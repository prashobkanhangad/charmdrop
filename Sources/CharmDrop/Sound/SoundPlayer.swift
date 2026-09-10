import AVFoundation
import Foundation

/// Plays a named short sound effect.
///
/// Behind a protocol so rituals can be exercised without an audio device, and
/// so a future implementation (system sounds, user-supplied files) can be
/// swapped in.
protocol SoundPlaying: AnyObject {
    var isEnabled: Bool { get set }

    /// Fire-and-forget. Never blocks the caller and never throws: a charm's
    /// ritual must still run when audio is unavailable.
    func play(_ name: String)
}

/// Discards everything. Used when audio is not wanted at all.
final class SilentSoundPlayer: SoundPlaying {
    var isEnabled = false
    func play(_ name: String) {}
}

/// `AVAudioEngine`-backed effect player.
///
/// Deliberately quiet by default and off the main thread: buffer resolution,
/// synthesis and scheduling all happen on a private serial queue, so a ritual
/// that plays a sound never risks a frame.
final class SoundPlayer: SoundPlaying {

    /// Effects are ambient decoration, not alerts, so they sit well below
    /// system volume.
    private static let outputVolume: Float = 0.35

    /// The audio hardware is released after this much silence. Holding an
    /// engine open indefinitely keeps the audio subsystem awake and shows up on
    /// battery.
    private static let idleShutdownDelay: TimeInterval = 5

    private let queue = DispatchQueue(label: "\(Constants.App.bundleIdentifier).audio", qos: .userInitiated)
    private let format: AVAudioFormat

    /// Built on first playback, not at launch.
    ///
    /// Constructing an `AVAudioEngine` alone measurably costs idle CPU — it
    /// brings up internal audio threads before a single sound has been
    /// requested. For an app whose whole point is being invisible until poked,
    /// that was about three percent of a core for nothing.
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var connectedFormat: AVAudioFormat?

    /// Read from the caller's thread and written from the main thread, so it is
    /// lock-protected rather than assumed to be main-only.
    private let stateLock = NSLock()
    private var _isEnabled: Bool

    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private var shutdownWorkItem: DispatchWorkItem?

    var isEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isEnabled
        }
        set {
            stateLock.lock()
            _isEnabled = newValue
            stateLock.unlock()
            if !newValue {
                queue.async { [weak self] in self?.shutdownEngine() }
            }
        }
    }

    init(isEnabled: Bool = true) {
        _isEnabled = isEnabled
        // A standard non-interleaved float format keeps both the synthesiser
        // and any decoded file on the same footing.
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
            ?? AVAudioFormat()
    }

    deinit {
        playerNode?.stop()
        engine?.stop()
    }

    func play(_ name: String) {
        guard isEnabled else { return }

        queue.async { [weak self] in
            guard let self, self.isEnabled else { return }

            guard let buffer = self.buffer(named: name) else {
                Log.charms.notice("No sound available for \(name, privacy: .public)")
                return
            }

            guard let playerNode = self.startEngineIfNeeded(for: buffer.format) else { return }

            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !playerNode.isPlaying {
                playerNode.play()
            }
            self.scheduleIdleShutdown()
        }
    }

    // MARK: - Buffers

    /// Prefers a bundled audio file, falling back to synthesis.
    ///
    /// Same arrangement as the charm artwork: the app is complete without any
    /// bundled media, and drops in real assets the moment they exist without a
    /// code change.
    private func buffer(named name: String) -> AVAudioPCMBuffer? {
        if let cached = bufferCache[name] { return cached }

        let resolved = bundledBuffer(named: name) ?? ProceduralTone.tone(named: name)
            .flatMap { $0.render(format: format) }

        if let resolved {
            bufferCache[name] = resolved
        }
        return resolved
    }

    private func bundledBuffer(named name: String) -> AVAudioPCMBuffer? {
        let extensions = ["caf", "wav", "aiff", "aif", "m4a", "mp3"]
        for extensionName in extensions {
            guard let url = Bundle.main.url(forResource: name, withExtension: extensionName) else {
                continue
            }
            do {
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)
                ) else { continue }
                try file.read(into: buffer)
                Log.charms.info("Loaded bundled sound \(name, privacy: .public).\(extensionName, privacy: .public)")
                return buffer
            } catch {
                Log.charms.error(
                    "Failed to read sound \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return nil
    }

    // MARK: - Engine lifecycle

    /// Returns a running player node able to accept buffers in `bufferFormat`,
    /// building the engine on first use.
    private func startEngineIfNeeded(for bufferFormat: AVAudioFormat) -> AVAudioPlayerNode? {
        let engine: AVAudioEngine
        let playerNode: AVAudioPlayerNode

        if let existing = self.engine, let existingNode = self.playerNode {
            engine = existing
            playerNode = existingNode
        } else {
            engine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.mainMixerNode.outputVolume = Self.outputVolume
            self.engine = engine
            self.playerNode = playerNode
            Log.charms.info("Audio engine started on first playback")
        }

        // A player node only accepts buffers matching the format it was
        // connected with. The synthesised tone and a decoded file need not
        // agree, so the connection follows the buffer rather than the reverse.
        let isAlreadyConnected = connectedFormat.map { bufferFormat.isEqual($0) } ?? false
        if !isAlreadyConnected {
            if connectedFormat != nil {
                playerNode.stop()
                engine.disconnectNodeOutput(playerNode)
            }
            engine.connect(playerNode, to: engine.mainMixerNode, format: bufferFormat)
            connectedFormat = bufferFormat
        }

        guard !engine.isRunning else { return playerNode }

        do {
            try engine.start()
            return playerNode
        } catch {
            // No output device, or the device was taken away. Not fatal.
            Log.charms.error(
                "Could not start the audio engine: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func scheduleIdleShutdown() {
        shutdownWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.shutdownEngine()
        }
        shutdownWorkItem = item
        queue.asyncAfter(deadline: .now() + Self.idleShutdownDelay, execute: item)
    }

    /// Releases the engine entirely rather than merely pausing it, so an idle
    /// CharmDrop holds no audio resources at all. Synthesised buffers are
    /// cached, so restarting is cheap.
    private func shutdownEngine() {
        shutdownWorkItem?.cancel()
        shutdownWorkItem = nil
        guard let engine else { return }

        playerNode?.stop()
        engine.stop()
        self.playerNode = nil
        self.engine = nil
        connectedFormat = nil
    }
}

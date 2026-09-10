import AVFoundation
import Foundation

/// An additive-synthesis description of a struck metallic tone, and its
/// renderer.
///
/// This exists for the same reason the placeholder charm artwork does: the app
/// should be complete and audible without shipping any licensed media. A struck
/// bell is a good fit for additive synthesis — it is a handful of inharmonic
/// partials, each decaying at its own rate — so a convincing one costs a few
/// dozen lines rather than a sample library.
struct ProceduralTone {

    /// One decaying sine component.
    struct Partial {
        /// Frequency as a multiple of the fundamental. Bells are inharmonic, so
        /// these are deliberately not whole numbers.
        let ratio: Double
        let amplitude: Double
        /// Seconds for this partial to fall to 1/e of its starting amplitude.
        /// High partials decaying faster than low ones is what makes a strike
        /// sound like metal rather than an organ.
        let decay: Double
    }

    let fundamental: Double
    let duration: Double
    let partials: [Partial]

    /// Short attack ramp. Without it the buffer starts on a discontinuity and
    /// you hear a click instead of a strike.
    let attack: Double = 0.004

    // MARK: - Library

    static func tone(named name: String) -> ProceduralTone? {
        switch name {
        case "bell": return .templeBell
        default: return nil
        }
    }

    /// A small temple bell: a low hum with a bright, quickly-fading strike.
    static let templeBell = ProceduralTone(
        fundamental: 523,
        duration: 1.8,
        partials: [
            Partial(ratio: 0.50, amplitude: 0.34, decay: 1.30),
            Partial(ratio: 1.00, amplitude: 1.00, decay: 0.90),
            Partial(ratio: 2.02, amplitude: 0.62, decay: 0.55),
            Partial(ratio: 2.97, amplitude: 0.40, decay: 0.38),
            Partial(ratio: 4.13, amplitude: 0.26, decay: 0.24),
            Partial(ratio: 5.61, amplitude: 0.16, decay: 0.16),
            Partial(ratio: 6.84, amplitude: 0.09, decay: 0.11)
        ]
    )

    // MARK: - Rendering

    /// Renders the tone into a PCM buffer, or nil if a buffer cannot be
    /// allocated.
    func render(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0, duration > 0 else { return nil }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = frameCount

        let channelCount = Int(format.channelCount)
        let normalisation = partials.reduce(0) { $0 + $1.amplitude }
        guard normalisation > 0 else { return nil }

        // Precompute per-partial angular velocity to keep the inner loop tight.
        let angularVelocities = partials.map { 2 * Double.pi * fundamental * $0.ratio / sampleRate }

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate

            var sample = 0.0
            for (index, partial) in partials.enumerated() {
                let envelope = exp(-time / partial.decay)
                sample += partial.amplitude * envelope * sin(angularVelocities[index] * Double(frame))
            }
            sample /= normalisation

            // Attack ramp in, and a short ramp out so the buffer ends at zero.
            if time < attack {
                sample *= time / attack
            }
            let remaining = duration - time
            if remaining < 0.05 {
                sample *= remaining / 0.05
            }

            let value = Float(sample)
            for channel in 0..<channelCount {
                channels[channel][frame] = value
            }
        }

        return buffer
    }
}

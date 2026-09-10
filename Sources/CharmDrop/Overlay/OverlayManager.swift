import AppKit
import Combine

/// Creates, updates and destroys one overlay per target display, and owns the
/// single shared pointer poll.
///
/// This is the only type that knows both about `AppStateManager` and about
/// panels, which keeps AppKit out of the view layer and SwiftUI out of the
/// render path.
@MainActor
final class OverlayManager {

    private let appState: AppStateManager
    private let screenManager: ScreenManager
    private let renderer: CharmRenderer
    private let audio: SoundPlaying
    private let pointerTracker = MouseInteractionManager()

    private var controllers: [CGDirectDisplayID: CharmOverlayController] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var configuration: OverlayConfiguration

    init(
        appState: AppStateManager,
        screenManager: ScreenManager,
        renderer: CharmRenderer = CharmRenderer(),
        audio: SoundPlaying
    ) {
        self.appState = appState
        self.screenManager = screenManager
        self.renderer = renderer
        self.audio = audio
        self.configuration = appState.overlayConfiguration

        pointerTracker.onPointerMoved = { [weak self] location in
            self?.dispatchPointer(location)
        }

        appState.$overlayConfiguration
            .removeDuplicates()
            .sink { [weak self] configuration in
                self?.apply(configuration: configuration)
            }
            .store(in: &cancellables)

        appState.commands
            .sink { [weak self] command in
                self?.forward(command)
            }
            .store(in: &cancellables)

        screenManager.screensDidChange
            .sink { [weak self] in
                self?.synchronizeScreens()
            }
            .store(in: &cancellables)
    }

    /// Builds the initial overlays. Called once the app has finished launching
    /// so screens and the window server are ready.
    func start() {
        apply(configuration: appState.overlayConfiguration)
    }

    func stop() {
        pointerTracker.stop()
        for controller in controllers.values {
            controller.teardown()
        }
        controllers.removeAll()
    }

    // MARK: - Configuration

    private func apply(configuration newValue: OverlayConfiguration) {
        let previous = configuration
        configuration = newValue

        guard newValue.isVisible else {
            hideAll()
            return
        }

        if newValue.requiresPanelRebuild(comparedTo: previous) {
            Log.overlay.info("Rebuilding panels for changed window collection behavior")
            for controller in controllers.values { controller.teardown() }
            controllers.removeAll()
        }

        synchronizeScreens()

        for controller in controllers.values {
            controller.update(configuration: newValue)
        }

        if !pointerTracker.isTracking {
            pointerTracker.start()
        }
    }

    private func hideAll() {
        pointerTracker.stop()
        for controller in controllers.values {
            controller.hide()
        }
    }

    private func forward(_ command: OverlayCommand) {
        for controller in controllers.values {
            controller.perform(command)
        }
    }

    // MARK: - Screens

    /// Reconciles the set of live controllers with the set of target displays.
    /// Existing controllers are re-bound rather than recreated so a resolution
    /// change does not restart the simulation.
    private func synchronizeScreens() {
        guard configuration.isVisible else { return }

        let targets = screenManager.targetScreens(
            selection: appState.settings.screenSelection,
            selectedScreenNumber: appState.settings.selectedScreenNumber
        )

        var liveIdentifiers: Set<CGDirectDisplayID> = []

        for screen in targets {
            guard let identifier = screen.displayIdentifier else { continue }
            liveIdentifiers.insert(identifier)

            if let existing = controllers[identifier] {
                existing.update(screen: screen)
                existing.update(configuration: configuration)
                existing.show()
            } else {
                let controller = CharmOverlayController(
                    screen: screen,
                    configuration: configuration,
                    renderer: renderer,
                    audio: audio
                )
                controller.onRitualRequested = { [weak self] in
                    self?.appState.performRitual()
                }
                controllers[identifier] = controller
                controller.show()
            }
        }

        // Displays that went away, or that are no longer targeted.
        for (identifier, controller) in controllers where !liveIdentifiers.contains(identifier) {
            Log.overlay.info("Tearing down overlay for display \(identifier)")
            controller.teardown()
            controllers.removeValue(forKey: identifier)
        }
    }

    private func dispatchPointer(_ location: CGPoint) {
        for controller in controllers.values {
            controller.handlePointerMoved(globalLocation: location)
        }
    }

    // MARK: - Power management

    /// Called on wake. Timestamps from before the sleep are meaningless, so
    /// each controller restarts its clock rather than integrating the gap.
    func handleSystemWake() {
        Log.overlay.info("System woke; restarting overlay render loops")
        synchronizeScreens()
        for controller in controllers.values {
            controller.update(configuration: configuration)
        }
    }

    func handleSystemSleep() {
        Log.overlay.info("System sleeping; pausing overlay render loops")
        for controller in controllers.values {
            controller.hide()
        }
    }
}

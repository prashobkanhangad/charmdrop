import Combine
import Foundation

/// Composition root.
///
/// Every long-lived object is created here exactly once and injected, so there
/// are no singletons and no global mutable state. Views receive only the pieces
/// they need.
@MainActor
final class AppEnvironment {

    let settings: SettingsManager
    let catalog: CharmCatalogProviding
    let appState: AppStateManager
    let screenManager: ScreenManager
    let charmRenderer: CharmRenderer
    let overlayManager: OverlayManager
    let updateManager: UpdateManaging
    let soundPlayer: SoundPlaying
    let launchAtLogin: LaunchAtLoginManager

    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: SettingsManager = SettingsManager(),
        catalog: CharmCatalogProviding = BuiltInCharmCatalog(),
        updateManager: UpdateManaging = UnconfiguredUpdateManager(),
        soundPlayer: SoundPlaying? = nil,
        launchAtLoginBackend: LaunchAtLoginBackend = SMAppServiceBackend()
    ) {
        self.settings = settings
        self.catalog = catalog
        self.updateManager = updateManager
        self.launchAtLogin = LaunchAtLoginManager(
            settings: settings,
            backend: launchAtLoginBackend
        )
        self.screenManager = ScreenManager()
        self.charmRenderer = CharmRenderer()
        self.soundPlayer = soundPlayer ?? SoundPlayer(isEnabled: settings.soundEnabled)
        self.appState = AppStateManager(settings: settings, catalog: catalog)
        self.overlayManager = OverlayManager(
            appState: appState,
            screenManager: screenManager,
            renderer: charmRenderer,
            audio: self.soundPlayer
        )

        // The audio player is shared across every display's overlay, so its
        // enabled state is bound here rather than in each controller.
        settings.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.soundPlayer.isEnabled = self.settings.soundEnabled
            }
            .store(in: &cancellables)
    }

    /// Brings the overlay up. Deferred until the app has finished launching so
    /// the window server and display list are ready.
    func start() {
        Log.app.info("\(Constants.App.displayName, privacy: .public) starting")

        // The user may have removed the login item in System Settings while
        // the app was closed, so the preference is reconciled before any UI
        // that displays it can appear.
        launchAtLogin.synchronize()

        overlayManager.start()
    }

    func stop() {
        overlayManager.stop()
        Log.app.info("\(Constants.App.displayName, privacy: .public) stopped")
    }
}

import Combine
import CoreGraphics
import Foundation

/// One-shot instructions sent to the overlay. Anything that is a *state* change
/// travels through `OverlayConfiguration` instead.
enum OverlayCommand: Equatable {
    /// Run the current charm's ritual. Until the ritual engine lands this
    /// applies a horizontal impulse so the charm reacts visibly.
    case performRitual
    /// Return the rope to a straight, motionless hang.
    case reset
}

/// Central, observable application state and the single entry point for
/// commands coming from the menu bar, settings, shortcuts and deep links.
///
/// Keeping this layer between the UI and the overlay means no view ever holds a
/// reference to a panel or a physics engine.
@MainActor
final class AppStateManager: ObservableObject {

    let settings: SettingsManager
    let catalog: CharmCatalogProviding

    /// Latest derived overlay configuration. Recomputed only when it actually
    /// differs, so the 60/120Hz render path is never disturbed by redundant
    /// updates.
    @Published private(set) var overlayConfiguration: OverlayConfiguration

    let commands = PassthroughSubject<OverlayCommand, Never>()

    /// Set by the app layer. Kept as a closure so this type stays free of
    /// AppKit and SwiftUI, which is what makes it testable.
    var onOpenSettings: (() -> Void)?

    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsManager, catalog: CharmCatalogProviding = BuiltInCharmCatalog()) {
        self.settings = settings
        self.catalog = catalog
        self.overlayConfiguration = Self.makeConfiguration(settings: settings, catalog: catalog)

        settings.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshConfiguration() }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    var selectedCharm: Charm { overlayConfiguration.charm }
    var isCharmVisible: Bool { settings.showCharm }

    private func refreshConfiguration() {
        let next = Self.makeConfiguration(settings: settings, catalog: catalog)
        guard next != overlayConfiguration else { return }
        overlayConfiguration = next
    }

    private static func makeConfiguration(
        settings: SettingsManager,
        catalog: CharmCatalogProviding
    ) -> OverlayConfiguration {
        OverlayConfiguration(
            charm: catalog.resolve(id: settings.selectedCharmID),
            isVisible: settings.showCharm,
            charmScale: settings.charmScale,
            ropeLength: settings.ropeLength,
            ropeThickness: settings.ropeThickness,
            ropeOpacity: settings.ropeOpacity,
            anchorPosition: settings.anchorPosition,
            customAnchorFraction: settings.customAnchorFraction,
            showOnAllSpaces: settings.showOnAllSpaces,
            showInFullscreenApps: settings.showInFullscreenApps,
            flickStrength: settings.flickStrength,
            dragSensitivity: settings.dragSensitivity,
            ritualTrigger: settings.ritualTrigger,
            debugOverlayEnabled: settings.debugOverlayEnabled
        )
    }

    // MARK: - Commands

    func setCharmVisible(_ isVisible: Bool) {
        guard settings.showCharm != isVisible else { return }
        settings.showCharm = isVisible
        Log.app.info("Charm visibility set to \(isVisible, privacy: .public)")
    }

    func toggleCharmVisible() {
        setCharmVisible(!settings.showCharm)
    }

    func selectCharm(id: String) {
        guard let charm = catalog.charm(withID: id) else {
            Log.charms.notice("Ignoring unknown charm identifier \(id, privacy: .public)")
            return
        }
        guard settings.selectedCharmID != charm.id else { return }
        settings.selectedCharmID = charm.id
        Log.charms.info("Charm changed to \(charm.id, privacy: .public)")
    }

    func setAnchorPosition(_ position: AnchorPosition) {
        guard settings.anchorPosition != position else { return }
        settings.anchorPosition = position
    }

    func performRitual() {
        // A ritual on a hidden charm would be invisible, which reads as the
        // command having failed. Say so instead.
        guard settings.showCharm else {
            Log.charms.notice("Ritual requested while the charm is hidden; ignoring")
            return
        }
        Log.charms.info("Ritual performed for \(self.selectedCharm.id, privacy: .public)")
        commands.send(.performRitual)
    }

    func resetCharm() {
        Log.overlay.info("Charm position reset")
        commands.send(.reset)
    }

    // MARK: - Deep links

    /// Applies a `charmdrop://` URL. Returns false when the URL was not
    /// understood, so the caller can log it once rather than guessing.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard let action = DeepLink.action(for: url) else {
            Log.deepLinks.notice("Ignoring unrecognised URL \(url.absoluteString, privacy: .public)")
            return false
        }

        Log.deepLinks.info("Handling \(url.absoluteString, privacy: .public)")
        apply(action)
        return true
    }

    func apply(_ action: DeepLinkAction) {
        switch action {
        case .show:
            setCharmVisible(true)
        case .hide:
            setCharmVisible(false)
        case .toggleVisibility:
            toggleCharmVisible()
        case .performRitual:
            performRitual()
        case .reset:
            resetCharm()
        case .selectCharm(let id):
            selectCharm(id: id)
        case .openSettings:
            guard let onOpenSettings else {
                Log.deepLinks.error("No settings handler is installed")
                return
            }
            onOpenSettings()
        }
    }
}

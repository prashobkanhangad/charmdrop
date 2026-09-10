import Combine
import CoreGraphics
import Foundation

/// Where the rope is mounted along the top edge of the screen.
enum AnchorPosition: String, CaseIterable, Codable, Identifiable {
    case left
    case center
    case right
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .custom: return "Custom"
        }
    }

    /// Horizontal position as a fraction of screen width. Stored normalised so
    /// a resolution change or a move to another display keeps the charm in a
    /// sensible place.
    func fraction(custom: CGFloat) -> CGFloat {
        switch self {
        case .left: return 0.25
        case .center: return 0.5
        case .right: return 0.75
        case .custom: return custom.clamped(to: 0.02...0.98)
        }
    }
}

/// Which displays get an overlay.
enum ScreenSelection: String, CaseIterable, Codable, Identifiable {
    case main
    case specific
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .main: return "Main Display"
        case .specific: return "Specific Display"
        case .all: return "All Displays"
        }
    }
}

/// How the user invokes a charm's ritual.
enum RitualTrigger: String, CaseIterable, Codable, Identifiable {
    case singleClick
    case doubleClick
    case shortcutOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleClick: return "Single Click"
        case .doubleClick: return "Double Click"
        case .shortcutOnly: return "Keyboard Shortcut Only"
        }
    }
}

/// Owns every user preference and its persistence.
///
/// UI never talks to `UserDefaults` directly, and values are validated on read
/// so a corrupted or hand-edited defaults file cannot put the app into an
/// unusable state.
final class SettingsManager: ObservableObject {

    /// Fires after any preference has been written. Consumers rebuild derived
    /// configuration from this rather than observing individual properties.
    let didChange = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults
    private var isBatchUpdating = false

    // MARK: - General

    @Published var selectedCharmID: String { didSet { persist(.selectedCharmID, selectedCharmID) } }
    @Published var showCharm: Bool { didSet { persist(.showCharm, showCharm) } }
    @Published var launchAtLogin: Bool { didSet { persist(.launchAtLogin, launchAtLogin) } }
    @Published var showOnAllSpaces: Bool { didSet { persist(.showOnAllSpaces, showOnAllSpaces) } }
    @Published var showInFullscreenApps: Bool { didSet { persist(.showInFullscreenApps, showInFullscreenApps) } }

    // MARK: - Appearance

    @Published var charmScale: CGFloat { didSet { persist(.charmScale, Double(charmScale)) } }
    @Published var ropeLength: CGFloat { didSet { persist(.ropeLength, Double(ropeLength)) } }
    @Published var ropeThickness: CGFloat { didSet { persist(.ropeThickness, Double(ropeThickness)) } }
    @Published var ropeOpacity: CGFloat { didSet { persist(.ropeOpacity, Double(ropeOpacity)) } }
    @Published var anchorPosition: AnchorPosition { didSet { persist(.anchorPosition, anchorPosition.rawValue) } }
    @Published var customAnchorFraction: CGFloat { didSet { persist(.customAnchorFraction, Double(customAnchorFraction)) } }

    // MARK: - Screens

    @Published var screenSelection: ScreenSelection { didSet { persist(.screenSelection, screenSelection.rawValue) } }
    @Published var selectedScreenNumber: Int { didSet { persist(.selectedScreenNumber, selectedScreenNumber) } }

    // MARK: - Interaction

    @Published var soundEnabled: Bool { didSet { persist(.soundEnabled, soundEnabled) } }
    @Published var dragSensitivity: CGFloat { didSet { persist(.dragSensitivity, Double(dragSensitivity)) } }
    @Published var flickStrength: CGFloat { didSet { persist(.flickStrength, Double(flickStrength)) } }
    @Published var ritualTrigger: RitualTrigger { didSet { persist(.ritualTrigger, ritualTrigger.rawValue) } }

    // MARK: - Developer

    @Published var debugOverlayEnabled: Bool { didSet { persist(.debugOverlayEnabled, debugOverlayEnabled) } }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        selectedCharmID = Self.string(defaults, .selectedCharmID) ?? Fallback.charmID
        showCharm = Self.bool(defaults, .showCharm, default: true)
        launchAtLogin = Self.bool(defaults, .launchAtLogin, default: false)
        showOnAllSpaces = Self.bool(defaults, .showOnAllSpaces, default: true)
        showInFullscreenApps = Self.bool(defaults, .showInFullscreenApps, default: true)

        charmScale = Self.number(
            defaults, .charmScale,
            default: 1.0,
            in: Constants.CharmScale.minimum...Constants.CharmScale.maximum
        )
        ropeLength = Self.number(
            defaults, .ropeLength,
            default: PhysicsConfiguration.default.ropeLength,
            in: Constants.Rope.minimumLength...Constants.Rope.maximumLength
        )
        ropeThickness = Self.number(
            defaults, .ropeThickness,
            default: Constants.Rope.defaultThickness,
            in: 1...6
        )
        ropeOpacity = Self.number(
            defaults, .ropeOpacity,
            default: Constants.Rope.defaultOpacity,
            in: 0.2...1.0
        )
        anchorPosition = AnchorPosition(
            rawValue: Self.string(defaults, .anchorPosition) ?? ""
        ) ?? .center
        customAnchorFraction = Self.number(defaults, .customAnchorFraction, default: 0.5, in: 0.02...0.98)

        screenSelection = ScreenSelection(
            rawValue: Self.string(defaults, .screenSelection) ?? ""
        ) ?? .main
        selectedScreenNumber = defaults.integer(forKey: Key.selectedScreenNumber.rawValue)

        soundEnabled = Self.bool(defaults, .soundEnabled, default: true)
        dragSensitivity = Self.number(defaults, .dragSensitivity, default: 1.0, in: 0.3...2.0)
        flickStrength = Self.number(
            defaults, .flickStrength,
            default: 1.0,
            in: Constants.Interaction.minimumFlickStrength...Constants.Interaction.maximumFlickStrength
        )
        ritualTrigger = RitualTrigger(
            rawValue: Self.string(defaults, .ritualTrigger) ?? ""
        ) ?? .singleClick

        debugOverlayEnabled = Self.bool(defaults, .debugOverlayEnabled, default: false)
    }

    // MARK: - Reset

    /// Restores factory defaults in one batch so observers see a single change.
    func resetAll() {
        isBatchUpdating = true

        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }

        selectedCharmID = Fallback.charmID
        showCharm = true
        launchAtLogin = false
        showOnAllSpaces = true
        showInFullscreenApps = true

        charmScale = 1.0
        ropeLength = PhysicsConfiguration.default.ropeLength
        ropeThickness = Constants.Rope.defaultThickness
        ropeOpacity = Constants.Rope.defaultOpacity
        anchorPosition = .center
        customAnchorFraction = 0.5

        screenSelection = .main
        selectedScreenNumber = 0

        soundEnabled = true
        dragSensitivity = 1.0
        flickStrength = 1.0
        ritualTrigger = .singleClick

        debugOverlayEnabled = false

        isBatchUpdating = false
        Log.settings.info("All settings reset to defaults")
        didChange.send()
    }

    // MARK: - Persistence plumbing

    private enum Key: String, CaseIterable {
        case selectedCharmID
        case showCharm
        case launchAtLogin
        case showOnAllSpaces
        case showInFullscreenApps
        case charmScale
        case ropeLength
        case ropeThickness
        case ropeOpacity
        case anchorPosition
        case customAnchorFraction
        case screenSelection
        case selectedScreenNumber
        case soundEnabled
        case dragSensitivity
        case flickStrength
        case ritualTrigger
        case debugOverlayEnabled
    }

    private enum Fallback {
        static let charmID = "nimbu-mirchi"
    }

    private func persist(_ key: Key, _ value: Any) {
        defaults.set(value, forKey: key.rawValue)
        guard !isBatchUpdating else { return }
        didChange.send()
    }

    private static func string(_ defaults: UserDefaults, _ key: Key) -> String? {
        guard let value = defaults.string(forKey: key.rawValue), !value.isEmpty else { return nil }
        return value
    }

    private static func bool(_ defaults: UserDefaults, _ key: Key, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key.rawValue) != nil else { return fallback }
        return defaults.bool(forKey: key.rawValue)
    }

    /// Reads a numeric preference, substituting the default for missing,
    /// non-finite or out-of-range values.
    private static func number(
        _ defaults: UserDefaults,
        _ key: Key,
        default fallback: CGFloat,
        in range: ClosedRange<CGFloat>
    ) -> CGFloat {
        guard defaults.object(forKey: key.rawValue) != nil else { return fallback }
        let raw = CGFloat(defaults.double(forKey: key.rawValue))
        guard raw.isFinite else { return fallback }
        return raw.clamped(to: range)
    }
}

import Foundation
import ServiceManagement

/// What the system currently thinks about launching CharmDrop at login.
///
/// Deliberately richer than a `Bool`. macOS can hold the request pending user
/// approval, and an unsigned or badly-placed build cannot register at all —
/// both of which look identical to "off" unless the UI can say otherwise.
enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled

    /// Registered, but the user has to allow it in System Settings before it
    /// takes effect.
    case requiresApproval

    /// Registration is impossible in this build or location.
    case unavailable(reason: String)

    var isEnabled: Bool { self == .enabled }

    /// Whether the user should be offered a toggle at all.
    var isActionable: Bool {
        switch self {
        case .enabled, .disabled, .requiresApproval: return true
        case .unavailable: return false
        }
    }

    /// Short sentence for the Settings window, or nil when the plain toggle
    /// says everything.
    var explanation: String? {
        switch self {
        case .enabled, .disabled:
            return nil
        case .requiresApproval:
            return "Waiting for approval in System Settings › General › Login Items."
        case .unavailable(let reason):
            return reason
        }
    }
}

/// The registration mechanism, behind a protocol so the reconciliation logic
/// can be tested without touching the real login item database.
protocol LaunchAtLoginBackend: AnyObject {
    var systemStatus: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

/// `SMAppService`-backed implementation.
///
/// `SMAppService.mainApp` registers the running app itself, which needs no
/// helper target, no privileged helper and no login-item bundle — but it does
/// require a real, signed `.app`. Running the bare SPM executable is detected
/// and reported as unavailable rather than allowed to fail confusingly.
final class SMAppServiceBackend: LaunchAtLoginBackend {

    private let service = SMAppService.mainApp

    /// True when the process is running from an `.app` bundle rather than as a
    /// loose executable.
    private var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    var systemStatus: LaunchAtLoginStatus {
        Self.status(from: service.status, isRunningInAppBundle: isRunningInAppBundle)
    }

    /// Maps `SMAppService`'s status onto ours.
    ///
    /// Pure and static so every branch can be tested; the interesting one is
    /// `.notFound`.
    ///
    /// macOS reports `.notFound` for an app it has no login-item record of at
    /// all, which — measured on a signed build both inside and outside
    /// `/Applications` — is what a *never-registered* app reports. Treating
    /// that as "unavailable" and disabling the toggle would make Launch at
    /// Login permanently unreachable: the only way out of `.notFound` is to
    /// call `register()`, which a disabled toggle can never do. So it is
    /// offered as simply "off", and a registration that genuinely cannot
    /// succeed reports itself by throwing.
    static func status(
        from serviceStatus: SMAppService.Status,
        isRunningInAppBundle: Bool
    ) -> LaunchAtLoginStatus {
        guard isRunningInAppBundle else {
            return .unavailable(
                reason: "Launch at Login needs CharmDrop to run from an app bundle."
            )
        }

        switch serviceStatus {
        case .enabled:
            return .enabled
        case .notRegistered, .notFound:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        @unknown default:
            return .disabled
        }
    }

    func register() throws {
        guard isRunningInAppBundle else {
            throw LaunchAtLoginError.notInAppBundle
        }
        try service.register()
    }

    func unregister() throws {
        guard isRunningInAppBundle else {
            throw LaunchAtLoginError.notInAppBundle
        }
        try service.unregister()
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notInAppBundle

    var errorDescription: String? {
        switch self {
        case .notInAppBundle:
            return "CharmDrop is not running from an app bundle."
        }
    }
}

/// Keeps the persisted preference and the system's actual login-item state in
/// agreement.
///
/// **The system is the source of truth.** A user who removes CharmDrop under
/// System Settings › Login Items has changed their mind, and the app must agree
/// with them the next time it launches rather than silently re-registering or
/// showing a toggle that lies. `synchronize()` therefore copies the system
/// state into the preference, never the other way around.
final class LaunchAtLoginManager: ObservableObject {

    @Published private(set) var status: LaunchAtLoginStatus

    private let settings: SettingsManager
    private let backend: LaunchAtLoginBackend

    init(settings: SettingsManager, backend: LaunchAtLoginBackend = SMAppServiceBackend()) {
        self.settings = settings
        self.backend = backend
        self.status = backend.systemStatus
    }

    var isEnabled: Bool { status.isEnabled }

    /// Reconciles the persisted preference with reality. Call at launch.
    func synchronize() {
        status = backend.systemStatus

        // An unavailable backend says nothing about intent, so the stored
        // preference is left alone; the app may be running from a bundle again
        // next time.
        guard case .unavailable = status else {
            let systemSaysEnabled = status.isEnabled
            if settings.launchAtLogin != systemSaysEnabled {
                Log.app.info(
                    "Login item state changed outside the app; preference now \(systemSaysEnabled, privacy: .public)"
                )
                settings.launchAtLogin = systemSaysEnabled
            }
            return
        }

        Log.app.notice("Launch at Login unavailable: \(self.status.explanation ?? "", privacy: .public)")
    }

    /// Registers or unregisters the login item, then re-reads the system state
    /// so the UI reflects what actually happened rather than what was asked.
    func setEnabled(_ enabled: Bool) {
        guard status.isActionable else {
            Log.app.notice("Ignoring Launch at Login change; unavailable in this build")
            return
        }

        // `.requiresApproval` already counts as registered, so re-registering
        // would be a no-op that some macOS versions report as an error.
        let isAlreadyRegistered = status == .enabled || status == .requiresApproval
        guard enabled != isAlreadyRegistered else {
            synchronize()
            return
        }

        do {
            if enabled {
                try backend.register()
                Log.app.info("Registered CharmDrop as a login item")
            } else {
                try backend.unregister()
                Log.app.info("Removed CharmDrop from login items")
            }
        } catch {
            // Common causes: an unsigned build, or the app sitting somewhere
            // macOS will not trust. Surfacing the message beats a toggle that
            // springs back with no explanation.
            let message = error.localizedDescription
            Log.app.error("Launch at Login change failed: \(message, privacy: .public)")
            status = .unavailable(reason: "macOS refused the change: \(message)")
            settings.launchAtLogin = false
            return
        }

        status = backend.systemStatus
        settings.launchAtLogin = status.isEnabled || status == .requiresApproval
    }

    /// Deep link to the Login Items pane, for when approval is pending.
    static var loginItemsSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }
}

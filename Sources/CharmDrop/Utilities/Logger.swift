import Foundation
import OSLog

/// Thin wrapper over `os.Logger` so call sites stay short and every subsystem
/// string is declared once. Logs are local only; nothing is ever transmitted.
enum Log {

    private static let subsystem = Constants.App.bundleIdentifier

    static let app = Logger(subsystem: subsystem, category: "app")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let physics = Logger(subsystem: subsystem, category: "physics")
    static let charms = Logger(subsystem: subsystem, category: "charms")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let screens = Logger(subsystem: subsystem, category: "screens")
    static let deepLinks = Logger(subsystem: subsystem, category: "deeplinks")
}

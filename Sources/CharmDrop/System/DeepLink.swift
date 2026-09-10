import Foundation

/// Something a `charmdrop://` URL can ask the app to do.
enum DeepLinkAction: Equatable {
    case show
    case hide
    case toggleVisibility
    case performRitual
    case reset
    case selectCharm(id: String)
    case openSettings
}

/// Parses `charmdrop://` URLs.
///
/// Pure and free of app state on purpose: a URL arriving from outside the
/// process is untrusted input, and the place where untrusted input is
/// interpreted is exactly the place worth testing exhaustively. Nothing here
/// touches the overlay, so a malformed link cannot do anything but be rejected.
enum DeepLink {

    /// Supported commands, as they appear in a URL.
    enum Command: String, CaseIterable {
        case show
        case hide
        case toggle
        case ritual
        case reset
        case charm
        case settings
    }

    /// Returns the action for `url`, or nil if it is not a valid CharmDrop
    /// link. Unknown commands are rejected rather than guessed at.
    static func action(for url: URL) -> DeepLinkAction? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == Constants.App.urlScheme
        else { return nil }

        let segments = segments(of: url)
        guard let rawCommand = segments.first else { return nil }
        guard let command = Command(rawValue: rawCommand.lowercased()) else { return nil }

        let argument = segments.count > 1 ? segments[1] : nil

        switch command {
        case .show:
            return argument == nil ? .show : nil
        case .hide:
            return argument == nil ? .hide : nil
        case .toggle:
            return argument == nil ? .toggleVisibility : nil
        case .ritual:
            return argument == nil ? .performRitual : nil
        case .reset:
            return argument == nil ? .reset : nil
        case .settings:
            return argument == nil ? .openSettings : nil
        case .charm:
            // A charm link is meaningless without an identifier. Validity of
            // the identifier itself is the catalog's job.
            guard let argument, !argument.isEmpty else { return nil }
            return .selectCharm(id: argument.lowercased())
        }
    }

    /// Splits a URL into command and argument.
    ///
    /// Both `charmdrop://charm/diya` (host + path) and `charmdrop:charm/diya`
    /// (path only) are accepted, because which one a shell, a browser or a
    /// script produces is not something a user should have to think about.
    private static func segments(of url: URL) -> [String] {
        var segments: [String] = []

        if let host = url.host, !host.isEmpty {
            segments.append(host)
        }

        let pathSegments = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        segments.append(contentsOf: pathSegments)

        return segments
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Every supported URL, for documentation and the menu bar's help text.
    static var examples: [String] {
        [
            "\(Constants.App.urlScheme)://show",
            "\(Constants.App.urlScheme)://hide",
            "\(Constants.App.urlScheme)://toggle",
            "\(Constants.App.urlScheme)://ritual",
            "\(Constants.App.urlScheme)://reset",
            "\(Constants.App.urlScheme)://charm/<id>",
            "\(Constants.App.urlScheme)://settings"
        ]
    }
}

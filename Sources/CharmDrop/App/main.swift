import Foundation

/// Process entry point.
///
/// Command-line modes are handled before SwiftUI starts, because once
/// `App.main()` runs it never returns. `--self-check` exists so the physics and
/// settings invariants can be verified in environments without an Xcode test
/// runner (for example a machine with only the Command Line Tools installed).
if CommandLine.arguments.contains("--self-check") {
    exit(SelfCheck.runAllAndReport() ? EXIT_SUCCESS : EXIT_FAILURE)
}

CharmDropApp.main()

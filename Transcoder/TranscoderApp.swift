import SwiftUI

/// Decides, before anything else runs, whether this launch is the app or only
/// the host for the unit tests. Hosting tests, the app starts with no window,
/// no view model and no update check, so a test run never reads or writes the
/// real settings.
@main
enum AppLauncher {
    static func main() {
        if isHostingTests {
            TestHostApp.main()
        } else if Snapshot.directory(in: CommandLine.arguments) != nil {
            SnapshotApp.main()
        } else {
            TranscoderApp.main()
        }
    }

    /// XCTest is already loaded when main() runs in a test host — Swift
    /// Testing's included — and is never linked into the app itself.
    nonisolated static let isHostingTests =
        NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
}

private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}

extension UserDefaults {
    /// Where the app keeps what it stores in defaults: its own domain, except in
    /// a test run or a `--snapshot` run, where that would be the developer's
    /// real settings. Those get a scratch suite named by a path in the
    /// temporary folder, which keeps it out of ~/Library/Preferences. Nothing
    /// in the app names `.standard`.
    nonisolated static let app: UserDefaults = {
        let scratch = AppLauncher.isHostingTests
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("io.github.sevmorris.Transcoder.tests").path
            : snapshotSuitePath
        return scratch.map { UserDefaults(suiteName: $0)! } ?? .standard
    }()

    /// The scratch suite of a `--snapshot` run, and nil in any other.
    nonisolated static let snapshotSuitePath: String? =
        !AppLauncher.isHostingTests && Snapshot.directory(in: CommandLine.arguments) != nil
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("io.github.sevmorris.Transcoder.snapshot").path
            : nil
}

struct TranscoderApp: App {
    @State private var viewModel = ContentViewModel()

    init() {
        Task { await checkForUpdates(silent: true) }
    }

    var body: some Scene {
        Window("Transcoder", id: "main") {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 740, minHeight: 480)
                // As in WaxOnWaxOff and ClipHack: a quit during a batch stops
                // FFmpeg, which would otherwise finish the file on its own.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.cancelForQuit()
                }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button(viewModel.showSettings ? "Hide Settings" : "Show Settings") {
                    withAnimation { viewModel.showSettings.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") { viewModel.chooseInputs() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Transcoder Help") { viewModel.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
                Button("Check for Updates…") { Task { await checkForUpdates() } }
                Divider()
                Button("Report an Issue…") {
                    if let url = URL(string: "https://github.com/sevmorris/Transcoder/issues/new"),
                       !NSWorkspace.shared.open(url) {
                        viewModel.errorMessage = "Could not open github.com/sevmorris/Transcoder/issues."
                    }
                }
            }
        }
    }
}

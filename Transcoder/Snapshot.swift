import AppKit
import SwiftUI

/// `Transcoder --snapshot <directory>`: shows the window in each state the
/// manual pictures, from fixed sample rows, captures it into PNGs in the
/// directory, and quits. It is how docs/screenshots/ is made: a picture of a full queue or
/// of a batch half done would otherwise need real files, the Open panel and a
/// conversion stopped at the right moment.
///
/// Nothing is converted and nothing is read: the rows are made up, and each
/// shot sets their status itself. The view model keeps its settings in
/// `UserDefaults.app`, which in a snapshot run is a scratch suite, so the
/// formats chosen for the shots never reach the real settings.
enum Snapshot {
    nonisolated static func directory(in arguments: [String]) -> String? {
        guard let flag = arguments.firstIndex(of: "--snapshot"),
              flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }

    /// The window's width in points, and its height, title bar included.
    /// The window goes no shorter than 532 (480 of content under the
    /// toolbar); 560 shows the whole settings column, Opus's included, and
    /// the empty queue needs 640 to show its Add Files… button.
    static let windowWidth = 900
    static let height = 560
    /// The manual's pictures are 2x. The window server captures at the
    /// display's scale, so a run on a 1x display is refused, not shrunk.
    static let scale = 2
    /// The settings shots are the window's right-hand 280 pt: the settings
    /// column and the end of the toolbar.
    static let panelWidth = 280

    enum Crop { case window, panel }

    struct Shot {
        let name: String
        let format: OutputFormat
        let rows: [(String, QueueItem.Status)]
        var running = false
        var crop = Crop.window
        var height = Snapshot.height
    }

    static let folder = URL(fileURLWithPath: "/Users/Shared/Recordings", isDirectory: true)

    static let sources = [
        "Voicemail Greeting.aiff",
        "Live Set (full).flac",
        "Rehearsal Take 3.m4a",
        "Back Room Radio — Episode 12.mp3",
        "Harbour at Dawn.wav",
    ]

    static func output(_ source: String, _ format: OutputFormat) -> QueueItem.Status {
        let name = (source as NSString).deletingPathExtension + "." + format.fileExtension
        return .done(folder.appendingPathComponent(name))
    }

    static let failure = ProcessingError.ffmpegFailed(
        code: 183, message: "Error during demuxing: Invalid data found when processing input"
    ).localizedDescription

    static let shots: [Shot] = [
        Shot(name: "tc-idle.png", format: .mp3, rows: [], height: 640),
        Shot(name: "tc-queue.png", format: .mp3, rows: sources.map { ($0, .pending) }),
        Shot(name: "tc-converting.png", format: .mp3, rows: [
            (sources[0], output(sources[0], .mp3)),
            (sources[1], .failed(failure)),
            (sources[2], .converting(0.42)),
            (sources[3], .pending),
            (sources[4], .pending),
        ], running: true),
        Shot(name: "tc-done.png", format: .mp3, rows: sources.map { ($0, output($0, .mp3)) }),
        // With rows behind them, so the empty queue's scroller stays out of the crop.
        Shot(name: "tc-wav-panel.png", format: .wav, rows: sources.map { ($0, .pending) }, crop: .panel),
        Shot(name: "tc-opus-panel.png", format: .opus, rows: sources.map { ($0, .pending) }, crop: .panel),
    ]

    /// Draws every shot and returns whether each was written.
    static func run(to directory: String) async -> Bool {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            say("cannot make \(dir.path): \(error.localizedDescription)")
            return false
        }
        defer { removeScratchSuite() }

        // The pictures are of the dark window, as the manual's always were.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let vm = ContentViewModel(store: .app)
        vm.settings = TranscoderSettings()
        vm.showSettings = true

        let window = makeWindow(vm)
        window.center()
        window.makeKeyAndOrderFront(nil)

        var ok = true
        for shot in shots {
            vm.isRunning = false
            vm.settings.format = shot.format
            vm.items = shot.rows.map { name, status in
                let item = QueueItem(source: folder.appendingPathComponent(name))
                item.status = status
                return item
            }
            vm.isRunning = shot.running
            let size = NSSize(width: windowWidth, height: shot.height)
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
            let active = await activate(window)
            await settle(window)

            let url = dir.appendingPathComponent(shot.name)
            if !active || !NSApp.isActive || !window.isKeyWindow {
                say("could not capture \(shot.name): Transcoder is not the active app, so the window "
                    + "would be drawn inactive. Leave the keyboard and mouse alone during the run.")
                ok = false
            } else if let problem = capture(window, shot, to: url) {
                say("could not capture \(shot.name): \(problem)")
                ok = false
            } else {
                say("wrote \(url.path)")
            }
        }
        vm.isRunning = false
        window.close()
        return ok
    }

    /// The window as the app's Window scene makes it — title, toolbar and
    /// all — but with no frame autosave name, so its size is never written to
    /// the real domain.
    private static func makeWindow(_ vm: ContentViewModel) -> NSWindow {
        let root = ContentView()
            .environment(vm)
            .frame(minWidth: 740, minHeight: 480)
        let controller = NSHostingController(rootView: root)
        controller.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: controller)
        window.title = "Transcoder"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("")
        window.isRestorable = false
        return window
    }

    /// Makes Transcoder the active app and the window key, so it is drawn as
    /// a window in use. macOS may decline while someone is using another
    /// app, so it asks again for up to 10 s.
    private static func activate(_ window: NSWindow) async -> Bool {
        for _ in 0..<50 {
            if NSApp.isActive, window.isKeyWindow { return true }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// SwiftUI lays the window out over more than one pass: wait until it
    /// has drawn the same picture twice running. The converting shot's
    /// spinner never keeps still, so that one waits the full 4 s.
    private static func settle(_ window: NSWindow) async {
        try? await Task.sleep(for: .milliseconds(500))
        var last = render(window)?.tiffRepresentation
        var steady = 0
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(250))
            let now = render(window)?.tiffRepresentation
            steady = now == last ? steady + 1 : 0
            last = now
            if steady == 2 { return }
        }
    }

    /// What the view draws of the window by itself: enough to tell when the
    /// layout has stopped changing, though not a picture of the window, since
    /// it leaves out the glass of the window's background and toolbar.
    private static func render(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// The window as the window server composites it, which is the only
    /// picture with the glass in it: `screencapture -l`, without the shadow,
    /// so the corners are transparent as on screen. It needs the Screen
    /// Recording permission, which macOS asks the app the run was started
    /// from for (Terminal, say). The settings shots are cropped to the right
    /// of the window. Returns what went wrong, or nil.
    private static func capture(_ window: NSWindow, _ shot: Shot, to url: URL) -> String? {
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        tool.arguments = ["-x", "-o", "-t", "png", "-l", String(window.windowNumber), url.path]
        do { try tool.run() } catch { return error.localizedDescription }
        tool.waitUntilExit()
        guard tool.terminationStatus == 0,
              let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data), let image = rep.cgImage else {
            return "screencapture wrote no picture (does the app you ran this from have Screen Recording?)"
        }
        let width = windowWidth * scale, height = shot.height * scale
        guard image.width == width, image.height == height else {
            return "it is \(image.width)×\(image.height) px, not \(width)×\(height): run it on a 2x display"
        }
        guard shot.crop == .panel else { return nil }
        let panel = panelWidth * scale
        guard let cropped = image.cropping(to: CGRect(x: width - panel, y: 0, width: panel, height: height)) else {
            return "could not crop it"
        }
        let out = NSBitmapImageRep(cgImage: cropped)
        out.size = NSSize(width: panelWidth, height: shot.height)
        guard let png = out.representation(using: .png, properties: [:]),
              (try? png.write(to: url)) != nil else { return "could not write the crop" }
        return nil
    }

    /// The scratch suite's file, so a run leaves nothing in the temporary
    /// folder for the next one to start from.
    private static func removeScratchSuite() {
        guard let path = UserDefaults.snapshotSuitePath else { return }
        UserDefaults.app.removePersistentDomain(forName: path)
        try? FileManager.default.removeItem(atPath: path + ".plist")
    }

    private static func say(_ text: String) {
        FileHandle.standardError.write(Data("transcoder: \(text)\n".utf8))
    }
}

/// The app a snapshot run launches instead of TranscoderApp: no window of its
/// own, no update check, and no view model but the snapshot's.
struct SnapshotApp: App {
    @NSApplicationDelegateAdaptor(SnapshotDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let directory = Snapshot.directory(in: CommandLine.arguments) else { return }
        Task {
            let ok = await Snapshot.run(to: directory)
            exit(ok ? 0 : 1)
        }
    }
}

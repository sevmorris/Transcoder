import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
final class ContentViewModel {
    var items: [QueueItem] = []
    var settings: TranscoderSettings { didSet { settings.save(to: store) } }
    var isRunning = false
    var showHelp = false
    var errorMessage: String?

    private let store: UserDefaults
    private let converter: any Converting
    /// The running batch. Internal so the tests can await its end.
    private(set) var batch: Task<Void, Never>?

    init(store: UserDefaults = .app, converter: any Converting = Converter()) {
        self.store = store
        self.converter = converter
        self.settings = TranscoderSettings.load(from: store)
    }

    var preset: Preset {
        get { settings.preset(for: settings.format) }
        set { settings.presets[settings.format] = newValue }
    }

    var outputFolder: URL? { settings.outputFolderPath.map { URL(fileURLWithPath: $0) } }

    var hasPending: Bool { items.contains { $0.status == .pending } }

    // MARK: Queue

    /// Adds files, and the media files inside folders, to the end of the
    /// queue. A file already in the queue, by any path to it, is not added
    /// again. Allowed during a batch: the new rows wait for the next one.
    func add(_ urls: [URL]) {
        var known = Set(items.map { Self.identity($0.source) })
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let files = isDir.boolValue ? Self.mediaFiles(in: url) : (Self.isMedia(url) ? [url] : [])
            for file in files where known.insert(Self.identity(file)).inserted {
                items.append(QueueItem(source: file))
            }
        }
    }

    private nonisolated static func identity(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Extensions macOS has no audio or video type for unless another app
    /// declares one (VLC declares the second row; without it macOS calls .ape
    /// a StuffIt archive), all of which the bundled FFmpeg decodes: DSD (.dsf,
    /// .dff), WebM audio, TAK, Shorten, RF64, WavPack, Monkey's Audio, TTA,
    /// Musepack and Matroska.
    nonisolated static let extraExtensions: Set<String> = [
        "dsf", "dff", "weba", "tak", "shn", "rf64",
        "wv", "ape", "tta", "mpc", "mka", "mkv",
    ]

    nonisolated static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if extraExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    /// What the open panel offers: the same files `isMedia` accepts.
    nonisolated static var openPanelTypes: [UTType] {
        [.audio, .movie, .audiovisualContent]
            + extraExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    private static func mediaFiles(in folder: URL) -> [URL] {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])
        return (walker?.allObjects as? [URL] ?? []).filter(isMedia).sorted { $0.path < $1.path }
    }

    /// No row leaves the queue during a batch: the batch holds the rows it
    /// started with, so a waiting row removed now would still be converted.
    func remove(_ item: QueueItem) {
        guard !isRunning else { return }
        items.removeAll { $0.id == item.id }
    }

    func clearFinished() {
        guard !isRunning else { return }
        items.removeAll { $0.isFinished }
    }

    var hasFinished: Bool { items.contains(where: \.isFinished) }

    /// Puts a completed, failed or cancelled row back to Waiting, for the next
    /// Convert. Its new output gets the next free name, as any output does.
    func convertAgain(_ item: QueueItem) {
        guard !isRunning, item.isFinished else { return }
        item.status = .pending
    }

    /// Convert Again for every finished row.
    func resetFinished() {
        guard !isRunning else { return }
        for item in items where item.isFinished { item.status = .pending }
    }

    // MARK: Converting

    func start() {
        guard !isRunning, hasPending else { return }
        isRunning = true
        BatchActivity.set(self, running: true)
        let format = settings.format
        let preset = self.preset
        let folder = outputFolder
        // The rows waiting now are the batch. Rows added during it are not
        // part of it, and still wait after a Cancel.
        let rows = items.filter { $0.status == .pending }
        batch = Task {
            for item in rows {
                if Task.isCancelled { break }
                await convert(item, format: format, preset: preset, folder: folder)
            }
            for item in rows where item.status == .pending && Task.isCancelled { item.status = .cancelled }
            isRunning = false
            BatchActivity.set(self, running: false)
        }
    }

    func cancel() { batch?.cancel() }

    private func convert(_ item: QueueItem, format: OutputFormat, preset: Preset, folder: URL?) async {
        let destination = folder ?? item.source.deletingLastPathComponent()
        let output = ArgumentBuilder.uniqueOutputURL(for: item.source, format: format, in: destination)
        item.status = .converting(0)
        do {
            try await converter.convert(input: item.source, output: output, format: format, preset: preset) { fraction in
                Task { @MainActor in
                    if case .converting = item.status { item.status = .converting(fraction) }
                }
            }
            item.status = .done(output)
        } catch is CancellationError {
            item.status = .cancelled
        } catch {
            item.status = .failed(error.localizedDescription)
        }
    }

    // MARK: Finder

    func reveal(_ item: QueueItem) {
        if let url = item.outputURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func revealAll() {
        let urls = items.compactMap(\.outputURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = Self.openPanelTypes
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { settings.outputFolderPath = url.path }
    }
}

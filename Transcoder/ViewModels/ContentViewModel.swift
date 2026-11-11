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
    private let converter: Converter
    private var batch: Task<Void, Never>?

    init(store: UserDefaults = .app, converter: Converter = Converter()) {
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

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.source))
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                add(Self.mediaFiles(in: url))
            } else if !known.contains(url), Self.isMedia(url) {
                items.append(QueueItem(source: url))
            }
        }
    }

    nonisolated static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    private static func mediaFiles(in folder: URL) -> [URL] {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])
        return (walker?.allObjects as? [URL] ?? []).filter(isMedia).sorted { $0.path < $1.path }
    }

    func remove(_ item: QueueItem) {
        guard !isActive(item) else { return }
        items.removeAll { $0.id == item.id }
    }

    func clearFinished() { items.removeAll { $0.isFinished } }

    func resetFinished() {
        for item in items where item.isFinished { item.status = .pending }
    }

    private func isActive(_ item: QueueItem) -> Bool {
        if case .converting = item.status { return true }
        return false
    }

    // MARK: Converting

    func start() {
        guard !isRunning, hasPending else { return }
        isRunning = true
        BatchActivity.set(self, running: true)
        let format = settings.format
        let preset = self.preset
        let folder = outputFolder
        batch = Task {
            for item in items where item.status == .pending {
                if Task.isCancelled { break }
                await convert(item, format: format, preset: preset, folder: folder)
            }
            for item in items where item.status == .pending && Task.isCancelled { item.status = .cancelled }
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
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
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

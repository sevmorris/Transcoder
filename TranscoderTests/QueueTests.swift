import Testing
import Foundation
@testable import Transcoder

/// The queue rules of `ContentViewModel`, with a stand-in converter so no
/// FFmpeg runs. Each test has its own temporary folder, holding the files it
/// queues and the scratch settings suite, deleted afterwards.
@MainActor
@Suite("Queue", .serialized)
struct QueueTests {

    /// A converter that records what it was asked to convert, writes an empty
    /// output file, and can be held shut to keep a batch running.
    actor FakeConverter: Converting {
        private(set) var inputs: [URL] = []
        private var isOpen: Bool
        private let failing: Set<String>
        private let passing: Set<String>

        /// `passing` names files that go through even while it is held shut.
        init(open: Bool = true, failing: Set<String> = [], passing: Set<String> = []) {
            isOpen = open
            self.failing = failing
            self.passing = passing
        }

        func open() { isOpen = true }

        func convert(input: URL, output: URL, format: OutputFormat, preset: Preset,
                     progress: @escaping @Sendable (Double) -> Void) async throws {
            inputs.append(input)
            while !isOpen && !passing.contains(input.lastPathComponent) {
                try await Task.sleep(for: .milliseconds(5))
            }
            if failing.contains(input.lastPathComponent) { throw ProcessingError.noAudioStream }
            FileManager.default.createFile(atPath: output.path, contents: Data())
            progress(1)
        }
    }

    final class Scratch {
        let folder: URL
        let store: UserDefaults

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("TranscoderQueue-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            store = UserDefaults(suiteName: folder.appendingPathComponent("suite").path)!
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        @discardableResult
        func file(_ relative: String) throws -> URL {
            let url = folder.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return url
        }
    }

    func names(_ vm: ContentViewModel) -> [String] { vm.items.map(\.source.lastPathComponent) }

    /// Waits, briefly, for something a batch does on its own schedule.
    func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting")
    }

    func finish(_ vm: ContentViewModel) async { await vm.batch?.value }

    // MARK: Adding

    @Test("Adds media files in the order given and ignores the rest")
    func addsMedia() throws {
        let s = try Scratch()
        let vm = ContentViewModel(store: s.store, converter: FakeConverter())
        let files = try ["b.wav", "notes.txt", "a.mp3", "c.dsf", "d.MKV", "film.mov"].map { try s.file($0) }
        vm.add(files + [s.folder.appendingPathComponent("gone.mp3")])
        #expect(names(vm) == ["b.wav", "a.mp3", "c.dsf", "d.MKV", "film.mov"])
        #expect(vm.items.allSatisfy { $0.status == .pending })
    }

    @Test("Extensions macOS has no type for are accepted when FFmpeg decodes them")
    func extraExtensions() {
        for ext in ["dsf", "dff", "weba", "tak", "shn", "rf64", "wv", "ape", "tta", "mpc", "mka", "mkv", "DSF"] {
            #expect(ContentViewModel.isMedia(URL(fileURLWithPath: "/x/a.\(ext)")), "\(ext)")
        }
        for ext in ["txt", "png", "zip", ""] {
            #expect(!ContentViewModel.isMedia(URL(fileURLWithPath: "/x/a.\(ext)")), "\(ext)")
        }
        #expect(ContentViewModel.openPanelTypes.count == 3 + ContentViewModel.extraExtensions.count)
    }

    @Test("A folder adds its media files, in subfolders too, sorted by path, skipping hidden ones")
    func addsFolder() throws {
        let s = try Scratch()
        let vm = ContentViewModel(store: s.store, converter: FakeConverter())
        try s.file("in/sub/z.flac")
        try s.file("in/b.m4a")
        try s.file("in/a.aiff")
        try s.file("in/.hidden.mp3")
        try s.file("in/readme.txt")
        vm.add([s.folder.appendingPathComponent("in")])
        #expect(names(vm) == ["a.aiff", "b.m4a", "z.flac"])
    }

    @Test("The same file is queued once, however it is added")
    func duplicates() throws {
        let s = try Scratch()
        let vm = ContentViewModel(store: s.store, converter: FakeConverter())
        let a = try s.file("in/a.mp3")
        vm.add([a, a])
        vm.add([a])
        vm.add([s.folder.appendingPathComponent("in/./a.mp3")])
        let link = s.folder.appendingPathComponent("link.mp3")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        vm.add([link])
        vm.add([s.folder.appendingPathComponent("in")])
        #expect(names(vm) == ["a.mp3"])
    }

    // MARK: During a batch

    @Test("Nothing leaves the queue during a batch, and files added during it wait")
    func noRemovalDuringBatch() async throws {
        let s = try Scratch()
        let fake = FakeConverter(open: false)
        let vm = ContentViewModel(store: s.store, converter: fake)
        let first = try s.file("first.wav"), second = try s.file("second.wav")
        vm.add([first, second])
        vm.start()
        #expect(vm.isRunning)
        try await eventually { await fake.inputs.count == 1 }

        vm.remove(vm.items[1])          // waiting
        vm.remove(vm.items[0])          // converting
        vm.add([try s.file("late.wav")])
        #expect(names(vm) == ["first.wav", "second.wav", "late.wav"])

        await fake.open()
        await finish(vm)
        #expect(!vm.isRunning)
        #expect(await fake.inputs == [first, second])
        #expect(vm.items[0].outputURL != nil && vm.items[1].outputURL != nil)
        #expect(vm.items[2].status == .pending)

        vm.remove(vm.items[2])
        #expect(names(vm) == ["first.wav", "second.wav"])
    }

    @Test("Cancel stops the batch's rows and leaves rows added during it waiting")
    func cancel() async throws {
        let s = try Scratch()
        let fake = FakeConverter(open: false)
        let vm = ContentViewModel(store: s.store, converter: fake)
        vm.add([try s.file("a.wav"), try s.file("b.wav")])
        vm.start()
        try await eventually { await fake.inputs.count == 1 }
        vm.add([try s.file("c.wav")])
        vm.cancel()
        await finish(vm)
        #expect(vm.items.map(\.status) == [.cancelled, .cancelled, .pending])
        #expect(await fake.inputs.count == 1)
    }

    // MARK: Finished rows

    @Test("Convert Again and Clear Finished act on finished rows, and not during a batch")
    func convertAgain() async throws {
        let s = try Scratch()
        let fake = FakeConverter(failing: ["bad.wav"])
        let vm = ContentViewModel(store: s.store, converter: fake)
        vm.add([try s.file("good.wav"), try s.file("bad.wav"), try s.file("other.wav")])
        vm.start()
        await finish(vm)
        let (good, bad, other) = (vm.items[0], vm.items[1], vm.items[2])
        #expect(good.outputURL?.lastPathComponent == "good.mp3")
        #expect(bad.status == .failed(ProcessingError.noAudioStream.localizedDescription))

        vm.convertAgain(bad)
        #expect(bad.status == .pending)
        vm.convertAgain(bad)            // already waiting: no change
        #expect(bad.status == .pending)

        // A row converted again never overwrites its earlier output.
        vm.convertAgain(good)
        vm.start()
        await finish(vm)
        #expect(good.outputURL?.lastPathComponent == "good 2.mp3")
        #expect(other.outputURL?.lastPathComponent == "other.mp3")
        #expect(await fake.inputs.count == 5)

        vm.resetFinished()
        #expect(vm.items.allSatisfy { $0.status == .pending })
    }

    @Test("Convert Again, Convert Again for all, and Clear Finished do nothing during a batch")
    func finishedRowsDuringBatch() async throws {
        let s = try Scratch()
        let fake = FakeConverter(open: false, passing: ["x.wav"])
        let vm = ContentViewModel(store: s.store, converter: fake)
        vm.add([try s.file("x.wav"), try s.file("y.wav")])
        vm.start()
        try await eventually { await fake.inputs.count == 2 }
        // x is done and y is converting, so the batch is still running.
        #expect(vm.isRunning && vm.items[0].isFinished && vm.hasFinished)

        vm.convertAgain(vm.items[0])
        vm.resetFinished()
        vm.clearFinished()
        #expect(names(vm) == ["x.wav", "y.wav"])
        #expect(vm.items[0].outputURL != nil)

        await fake.open()
        await finish(vm)
        vm.clearFinished()
        #expect(vm.items.isEmpty)
    }
}

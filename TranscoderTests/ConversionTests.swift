import Testing
import Foundation
@testable import Transcoder

/// Runs the bundled FFmpeg end to end: a tagged, cover-carrying sample goes to
/// every format, and the output is probed for its codec, tags and artwork.
/// Everything lives in a temporary folder that is deleted afterwards.
@Suite("Conversion", .serialized)
struct ConversionTests {
    let converter = Converter()
    let ffmpeg = Bundle.main.resourceURL!.appendingPathComponent("ffmpeg").path

    func run(_ args: [String]) async throws {
        let (status, err) = try await FFmpegProcess.launch(exe: ffmpeg, args: args, capture: .stderr, timeoutSeconds: 60)
        #expect(status == 0, "\(err)")
    }

    /// A 3-second tagged MP3 with a PNG cover.
    func makeSample(in folder: URL) async throws -> URL {
        let cover = folder.appendingPathComponent("cover.png")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "color=c=red:s=64x64:d=1", "-frames:v", "1", cover.path])
        let sample = folder.appendingPathComponent("sample.mp3")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3:sample_rate=44100",
                       "-i", cover.path, "-map", "0:a", "-map", "1:v", "-ac", "2", "-c:a", "libmp3lame", "-b:a", "192k",
                       "-c:v", "copy", "-disposition:v:0", "attached_pic", "-id3v2_version", "3",
                       "-metadata", "title=Test Tone", "-metadata", "artist=Transcoder",
                       "-metadata", "album=Fixtures", sample.path])
        return sample
    }

    func tags(of url: URL) async throws -> [String: String] {
        let probe = Bundle.main.resourceURL!.appendingPathComponent("ffprobe").path
        let (_, out) = try await FFmpegProcess.launch(
            exe: probe, args: ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path],
            capture: .stdout, timeoutSeconds: 30)
        struct Root: Decodable {
            struct S: Decodable { var tags: [String: String]? }
            struct F: Decodable { var tags: [String: String]? }
            var streams: [S]; var format: F
        }
        let root = try JSONDecoder().decode(Root.self, from: Data(out.utf8))
        var all: [String: String] = [:]
        for dict in [root.format.tags ?? [:]] + root.streams.map({ $0.tags ?? [:] }) {
            for (k, v) in dict { all[k.lowercased()] = v }
        }
        return all
    }

    @Test("Every format converts with tags, and artwork where the container holds it",
          arguments: OutputFormat.allCases)
    func converts(format: OutputFormat) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TranscoderConv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sample = try await makeSample(in: folder)
        let output = ArgumentBuilder.uniqueOutputURL(for: sample, format: format, in: folder)
        let fractions = FractionLog()
        try await converter.convert(input: sample, output: output, format: format,
                                    preset: .defaults(for: format)) { fractions.append($0) }

        let info = try await converter.probe(output)
        #expect((info.duration ?? 0) > 2.5)
        #expect((info.coverStreamIndex != nil) == format.carriesArtwork)
        if format == .opus { #expect(info.sampleRate == 48000) }

        let t = try await tags(of: output)
        #expect(t["title"] == "Test Tone")
        #expect(t["artist"] == "Transcoder")
        #expect(t["album"] == "Fixtures")
        #expect(fractions.last == 1)
    }

    @Test("A file with no audio fails cleanly and leaves nothing behind")
    func noAudio() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TranscoderConv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("still.png")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "color=c=blue:s=32x32:d=1", "-frames:v", "1", png.path])
        let output = folder.appendingPathComponent("still.mp3")
        await #expect(throws: ProcessingError.noAudioStream) {
            try await converter.convert(input: png, output: output, format: .mp3, preset: .defaults(for: .mp3)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TranscoderConv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("Cancelling a conversion deletes the partly written output")
    func cancelLeavesNothing() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // 20 minutes at 8 kHz is small to write, and resampling it to a
        // 48 kHz, 320 kbps MP3 takes seconds, long enough to cancel mid-run.
        let source = folder.appendingPathComponent("long.wav")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1200:sample_rate=8000",
                       "-c:a", "pcm_s16le", source.path])
        let output = folder.appendingPathComponent("long.mp3")
        let fractions = FractionLog()
        let converter = self.converter
        let task = Task {
            try await converter.convert(input: source, output: output, format: .mp3,
                                        preset: Preset(bitrateKbps: 320, sampleRate: 48000)) { fractions.append($0) }
        }
        for _ in 0..<600 where (fractions.last ?? 0) <= 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect((fractions.last ?? 0) > 0 && (fractions.last ?? 1) < 1, "the conversion should be under way")
        #expect(FileManager.default.fileExists(atPath: output.path), "a partial output should exist mid-run")
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test("Tags kept on the audio stream (Ogg Opus) come across", arguments: OutputFormat.allCases)
    func streamTags(format: OutputFormat) async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("tagged.opus")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
                       "-c:a", "libopus", "-b:a", "64k", "-metadata", "title=Stream Tags",
                       "-metadata", "artist=Transcoder", "-f", "opus", source.path])
        #expect(try await converter.probe(source).tagsOnStream)

        let output = ArgumentBuilder.uniqueOutputURL(for: source, format: format, in: folder)
        try await converter.convert(input: source, output: output, format: format, preset: .defaults(for: format)) { _ in }
        let t = try await tags(of: output)
        #expect(t["title"] == "Stream Tags")
        #expect(t["artist"] == "Transcoder")
    }

    @Test("A cover that is neither JPEG nor PNG arrives as JPEG",
          arguments: OutputFormat.allCases.filter(\.carriesArtwork))
    func bmpCover(format: OutputFormat) async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cover = folder.appendingPathComponent("cover.bmp")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "color=c=green:s=64x64:d=1", "-frames:v", "1", cover.path])
        let source = folder.appendingPathComponent("bmp.mp3")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-i", cover.path,
                       "-map", "0:a", "-map", "1:v", "-c:a", "libmp3lame", "-c:v", "copy",
                       "-disposition:v:0", "attached_pic", "-id3v2_version", "3", source.path])
        #expect(try await converter.probe(source).coverCodec == "bmp")

        let output = ArgumentBuilder.uniqueOutputURL(for: source, format: format, in: folder)
        try await converter.convert(input: source, output: output, format: format, preset: .defaults(for: format)) { _ in }
        #expect(try await converter.probe(output).coverCodec == "mjpeg")
    }

    @Test("A 5.1 source stays 5.1, except MP3 and Opus, which fold it to stereo",
          arguments: OutputFormat.allCases)
    func surround(format: OutputFormat) async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("surround.flac")
        try await run(["-hide_banner", "-y", "-f", "lavfi", "-i",
                       "aevalsrc=sin(440*2*PI*t)|sin(550*2*PI*t)|sin(660*2*PI*t)|sin(110*2*PI*t)|sin(770*2*PI*t)|sin(880*2*PI*t):c=5.1:s=48000:d=3",
                       source.path])
        #expect(try await converter.probe(source).channels == 6)

        let output = ArgumentBuilder.uniqueOutputURL(for: source, format: format, in: folder)
        try await converter.convert(input: source, output: output, format: format, preset: .defaults(for: format)) { _ in }
        let info = try await converter.probe(output)
        #expect(info.channels == ([.mp3, .opus].contains(format) ? 2 : 6))
        #expect((info.duration ?? 0) > 2.5)
    }

    @Test("A file ffprobe cannot read fails with ffprobe's own reason")
    func probeReason() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let junk = folder.appendingPathComponent("junk.mp3")
        try Data("not audio at all".utf8).write(to: junk)
        await #expect(throws: ProcessingError.ffprobeFailed("Invalid data found when processing input")) {
            try await converter.probe(junk)
        }
    }

    @Test("An output folder that is gone fails with a message that names it, before FFmpeg runs")
    func missingOutputFolder() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sample = try await makeSample(in: folder)
        let gone = folder.appendingPathComponent("Unmounted Drive/Out")
        let output = gone.appendingPathComponent("sample.flac")
        await #expect(throws: ProcessingError.outputFolderMissing(gone.path)) {
            try await converter.convert(input: sample, output: output, format: .flac, preset: .defaults(for: .flac)) { _ in }
        }
        #expect(ProcessingError.outputFolderMissing(gone.path).localizedDescription.contains(gone.path))
    }
}

final class FractionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func append(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}

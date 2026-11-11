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
}

final class FractionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func append(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}

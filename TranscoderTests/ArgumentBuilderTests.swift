import Testing
import Foundation
@testable import Transcoder

@Suite("ArgumentBuilder")
struct ArgumentBuilderTests {
    let input = URL(fileURLWithPath: "/in/song.flac")
    let output = URL(fileURLWithPath: "/out/song.mp3")
    let source = SourceInfo(duration: 10, audioStreamIndex: 0, channels: 2, sampleRate: 44100,
                            coverStreamIndex: 1, coverCodec: "mjpeg", tagsOnStream: false)

    func args(_ format: OutputFormat, _ preset: Preset? = nil, source: SourceInfo? = nil) -> [String] {
        ArgumentBuilder.arguments(input: input, output: output, format: format,
                                  preset: preset ?? .defaults(for: format), source: source ?? self.source)
    }

    func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }

    @Test("Each format picks its encoder", arguments: [
        (OutputFormat.mp3, "libmp3lame"), (.aac, "aac"), (.alac, "alac"), (.flac, "flac"),
        (.wav, "pcm_s24le"), (.aiff, "pcm_s24be"), (.opus, "libopus"),
    ])
    func encoder(format: OutputFormat, codec: String) {
        #expect(value(after: "-c:a", in: args(format)) == codec)
    }

    @Test("Lossy formats take the preset's bitrate")
    func bitrate() {
        #expect(value(after: "-b:a", in: args(.mp3, Preset(bitrateKbps: 192))) == "192k")
        #expect(value(after: "-b:a", in: args(.aac)) == "256k")
        #expect(value(after: "-b:a", in: args(.flac)) == nil)
    }

    @Test("Bit depth chooses the sample format")
    func bitDepth() {
        #expect(value(after: "-c:a", in: args(.wav, Preset(bitDepth: 16))) == "pcm_s16le")
        #expect(value(after: "-c:a", in: args(.wav, Preset(bitDepth: 32))) == "pcm_f32le")
        #expect(value(after: "-sample_fmt", in: args(.flac, Preset(bitDepth: 16))) == "s16")
        #expect(value(after: "-bits_per_raw_sample", in: args(.alac, Preset(bitDepth: 24))) == "24")
    }

    @Test("Same-as-source leaves rate and channels alone")
    func sourceRate() {
        let a = args(.mp3)
        #expect(!a.contains("-ar") && !a.contains("-ac"))
        let b = args(.mp3, Preset(bitrateKbps: 128, sampleRate: 44100, channels: 1))
        #expect(value(after: "-ar", in: b) == "44100")
        #expect(value(after: "-ac", in: b) == "1")
    }

    @Test("Opus is 48 kHz and folds surround to stereo")
    func opus() {
        let surround = SourceInfo(duration: 1, audioStreamIndex: 0, channels: 6, sampleRate: 44100,
                                  coverStreamIndex: nil, coverCodec: nil, tagsOnStream: false)
        let a = args(.opus, source: surround)
        #expect(value(after: "-ar", in: a) == "48000")
        #expect(!a.contains("-strict"))
        #expect(value(after: "-ac", in: a) == "2")
    }

    @Test("Cover art is mapped only where the container holds it")
    func artwork() {
        #expect(args(.mp3).contains("0:1"))
        #expect(value(after: "-disposition:v:0", in: args(.flac)) == "attached_pic")
        #expect(!args(.wav).contains("0:1"))
        #expect(!args(.opus).contains("-c:v"))
    }

    @Test("A cover that is neither JPEG nor PNG is re-encoded")
    func coverCodec() {
        var bmp = source; bmp.coverCodec = "bmp"
        #expect(value(after: "-c:v", in: args(.mp3, source: bmp)) == "mjpeg")
        #expect(value(after: "-c:v", in: args(.mp3)) == "copy")
    }

    @Test("Tags come from the stream when the source keeps them there")
    func streamTags() {
        var ogg = source; ogg.tagsOnStream = true; ogg.audioStreamIndex = 0
        #expect(value(after: "-map_metadata", in: args(.mp3, source: ogg)) == "0:s:0")
        #expect(value(after: "-map_metadata", in: args(.mp3)) == "0")
    }

    @Test("The output path is last and the input follows -i")
    func paths() {
        let a = args(.mp3)
        #expect(a.last == output.path)
        #expect(value(after: "-i", in: a) == input.path)
    }

    @Test("Output names never overwrite")
    func uniqueNames() {
        let folder = URL(fileURLWithPath: "/out")
        let taken: Set<String> = ["/out/song.mp3", "/out/song 2.mp3"]
        let url = ArgumentBuilder.uniqueOutputURL(for: input, format: .mp3, in: folder) { taken.contains($0.path) }
        #expect(url.lastPathComponent == "song 3.mp3")
        let m4a = ArgumentBuilder.uniqueOutputURL(for: input, format: .alac, in: folder) { _ in false }
        #expect(m4a.lastPathComponent == "song.m4a")
    }

    @Test("WAV turns into RF64 past 4 GB rather than write a broken file")
    func wavRF64() {
        for depth in [16, 24, 32] {
            #expect(value(after: "-rf64", in: args(.wav, Preset(bitDepth: depth))) == "auto")
        }
        #expect(!args(.aiff).contains("-rf64"))
        #expect(!args(.flac).contains("-rf64"))
    }

    @Test("Progress reads the last out_time_us")
    func progress() {
        let text = "out_time_us=1000000\nprogress=continue\nout_time_us=2500000\nprogress=continue\n"
        #expect(ArgumentBuilder.progressSeconds(in: text) == 2.5)
        #expect(ArgumentBuilder.progressSeconds(in: "progress=continue") == nil)
        #expect(ArgumentBuilder.progressSeconds(in: "out_time_us=N/A") == nil)
    }
}

@Suite("SourceInfo")
struct SourceInfoTests {
    @Test("Finds the audio stream and an attached cover")
    func parsesCover() throws {
        let json = """
        {"streams":[{"index":0,"codec_type":"video","codec_name":"h264","disposition":{"attached_pic":0}},
                    {"index":1,"codec_type":"audio","codec_name":"aac","channels":2,"sample_rate":"48000"},
                    {"index":2,"codec_type":"video","codec_name":"png","disposition":{"attached_pic":1}}],
         "format":{"duration":"12.5","tags":{"title":"T","major_brand":"isom"}}}
        """
        let info = try SourceInfo.parse(Data(json.utf8))
        #expect(info.audioStreamIndex == 1)
        #expect(info.coverStreamIndex == 2)
        #expect(info.coverCodec == "png")
        #expect(info.duration == 12.5)
        #expect(info.sampleRate == 48000)
        #expect(!info.tagsOnStream)
    }

    @Test("Notices tags kept on the audio stream")
    func streamTags() throws {
        let json = """
        {"streams":[{"index":0,"codec_type":"audio","channels":1,"sample_rate":"48000","tags":{"TITLE":"x","encoder":"Lavf"}}],
         "format":{"tags":{"encoder":"Lavf"}}}
        """
        #expect(try SourceInfo.parse(Data(json.utf8)).tagsOnStream)
    }

    @Test("No audio is an error")
    func noAudio() {
        #expect(throws: ProcessingError.noAudioStream) {
            try SourceInfo.parse(Data(#"{"streams":[{"index":0,"codec_type":"video"}]}"#.utf8))
        }
    }
}

@Suite("AIFFLimit")
struct AIFFLimitTests {
    /// 8 channels of 24-bit at 192 kHz: 4,608,000 bytes a second, so 932 s
    /// fits in an AIFF (measured: FFmpeg writes a good 4,294,656,126-byte file)
    /// and 933 s does not.
    func surround(seconds: Double?) -> SourceInfo {
        SourceInfo(duration: seconds, audioStreamIndex: 0, channels: 8, sampleRate: 192_000,
                   coverStreamIndex: nil, coverCodec: nil, tagsOnStream: false)
    }

    @Test("The estimate is duration × rate × channels × bytes per sample")
    func estimate() {
        #expect(AIFFLimit.estimatedAudioBytes(preset: Preset(bitDepth: 24), source: surround(seconds: 932)) == 4_294_656_000)
        #expect(AIFFLimit.estimatedAudioBytes(preset: Preset(bitDepth: 16), source: surround(seconds: 932)) == 2_863_104_000)
        // The preset's rate and channels win over the source's.
        #expect(AIFFLimit.estimatedAudioBytes(preset: Preset(sampleRate: 48_000, channels: 2, bitDepth: 24),
                                              source: surround(seconds: 10)) == 2_880_000)
        #expect(AIFFLimit.estimatedAudioBytes(preset: Preset(bitDepth: 24), source: surround(seconds: nil)) == nil)
    }

    @Test("A conversion past 4 GB is refused before it starts")
    func refusesBeforehand() {
        let preset = Preset(bitDepth: 24)
        #expect(!AIFFLimit.wouldOverflow(preset: preset, source: surround(seconds: 932)))
        #expect(AIFFLimit.wouldOverflow(preset: preset, source: surround(seconds: 933)))
        #expect(AIFFLimit.wouldOverflow(preset: preset, source: surround(seconds: 960)))
        #expect(!AIFFLimit.wouldOverflow(preset: Preset(bitDepth: 16), source: surround(seconds: 960)))
        #expect(!AIFFLimit.wouldOverflow(preset: Preset(channels: 2, bitDepth: 24), source: surround(seconds: 960)))
        // Unknown length: left to the check on the written file.
        #expect(!AIFFLimit.wouldOverflow(preset: preset, source: surround(seconds: nil)))
    }

    @Test("A written file larger than its FORM header can say is caught")
    func catchesAfterwards() {
        #expect(!AIFFLimit.overflowed(fileSize: 4_294_656_126))  // 932 s, measured
        #expect(AIFFLimit.overflowed(fileSize: 4_423_680_126))   // 960 s, measured: reads as 27.9 s
        #expect(!AIFFLimit.overflowed(fileSize: AIFFLimit.maxFileSize))
        #expect(AIFFLimit.overflowed(fileSize: AIFFLimit.maxFileSize + 1))
    }
}

@Suite("Converter rules")
struct ConverterRuleTests {
    @Test("The time limit is four times the length, at least ten minutes, a day when unknown")
    func timeLimit() {
        #expect(Converter.timeLimit(duration: 10) == 600)
        #expect(Converter.timeLimit(duration: 3600) == 14_400)
        #expect(Converter.timeLimit(duration: nil) == 86_400)
        #expect(Converter.timeLimit(duration: 0) == 86_400)
    }

    @Test("A failed probe gives ffprobe's own reason, without the path")
    func probeReason() {
        let path = "/in/junk.mp3"
        let stderr = "[mp3 @ 0x1] Failed to find two consecutive MPEG audio frames.\n/in/junk.mp3: Invalid data found when processing input\n"
        #expect(Converter.probeFailureReason(stderr: stderr, path: path, status: 1) == "Invalid data found when processing input")
        #expect(Converter.probeFailureReason(stderr: "other: No such file or directory", path: path, status: 1)
                == "other: No such file or directory")
        #expect(Converter.probeFailureReason(stderr: "\n  \n", path: path, status: 1) == "ffprobe exit 1")
    }
}

@Suite("TranscoderSettings")
struct SettingsTests {
    /// Exactly what 0.1.0 writes, from its synthesized encoder: the presets
    /// dictionary is an array of alternating keys and values, because
    /// OutputFormat is not CodingKeyRepresentable, and slashes are escaped.
    static let saved010 = #"{"outputFolderPath":"\/Volumes\/Out","format":"flac","presets":["flac",{"sampleRate":96000,"bitDepth":16},"mp3",{"bitrateKbps":192}]}"#

    func decode(_ json: String) throws -> TranscoderSettings {
        try JSONDecoder().decode(TranscoderSettings.self, from: Data(json.utf8))
    }

    @Test("What 0.1.0 saved loads unchanged")
    func loads010() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TranscoderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(UserDefaults(suiteName: folder.appendingPathComponent("suite").path))
        store.set(Data(Self.saved010.utf8), forKey: TranscoderSettings.key)

        let s = TranscoderSettings.load(from: store)
        #expect(s.format == .flac)
        #expect(s.outputFolderPath == "/Volumes/Out")
        #expect(s.presets == [.flac: Preset(sampleRate: 96000, bitDepth: 16), .mp3: Preset(bitrateKbps: 192)])
        #expect(try decode(#"{"format":"mp3","presets":[]}"#) == TranscoderSettings())
    }

    @Test("A missing field keeps its default and loses nothing else")
    func missingField() throws {
        let s = try decode(#"{"format":"wav","presets":["wav",{"bitDepth":32}]}"#)
        #expect(s.format == .wav)
        #expect(s.presets[.wav] == Preset(bitDepth: 32))
        #expect(s.outputFolderPath == nil)
        #expect(try decode(#"{"outputFolderPath":"/x"}"#).format == .mp3)
        #expect(try decode("{}") == TranscoderSettings())
    }

    @Test("An unknown key is ignored")
    func unknownKey() throws {
        let s = try decode(#"{"format":"aac","presets":["aac",{"bitrateKbps":128}],"theme":"dark","future":{"a":[1,2]}}"#)
        #expect(s.format == .aac)
        #expect(s.presets[.aac] == Preset(bitrateKbps: 128))
    }

    @Test("An unknown format costs only its own preset; an unknown chosen format falls back to MP3")
    func unknownFormat() throws {
        let s = try decode(#"{"format":"wma","outputFolderPath":"/x","presets":["wma",{"bitrateKbps":128},"flac",{"bitDepth":16}]}"#)
        #expect(s.format == .mp3)
        #expect(s.outputFolderPath == "/x")
        #expect(s.presets == [.flac: Preset(bitDepth: 16)])
    }

    @Test("A preset this version cannot read is dropped, and the rest kept")
    func unreadablePreset() throws {
        let s = try decode(#"{"format":"opus","presets":["mp3",{"bitrateKbps":"loud"},"aac",{"bitrateKbps":128},"opus",null]}"#)
        #expect(s.format == .opus)
        #expect(s.presets == [.aac: Preset(bitrateKbps: 128)])
        // A presets value that is not an array at all loses only the presets.
        #expect(try decode(#"{"format":"flac","presets":{"flac":{"bitDepth":16}}}"#).format == .flac)
    }

    @Test("What this version writes is the shape 0.1.0 reads")
    func writes010Shape() throws {
        /// 0.1.0's TranscoderSettings, with its synthesized decoder.
        struct Settings010: Decodable {
            var format: OutputFormat
            var presets: [OutputFormat: Preset]
            var outputFolderPath: String?
        }
        var s = TranscoderSettings()
        s.format = .alac
        s.presets[.alac] = Preset(sampleRate: 48000, bitDepth: 16)
        s.outputFolderPath = "/Volumes/Out"
        let data = try JSONEncoder().encode(s)
        let old = try JSONDecoder().decode(Settings010.self, from: data)
        #expect(old.format == .alac)
        #expect(old.presets == s.presets)
        #expect(old.outputFolderPath == "/Volumes/Out")
        #expect(try JSONDecoder().decode(TranscoderSettings.self, from: data) == s)
    }

    @Test("Round-trips through a scratch store, never the real domain")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TranscoderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(UserDefaults(suiteName: folder.appendingPathComponent("suite").path))

        #expect(TranscoderSettings.load(from: store) == TranscoderSettings())
        var s = TranscoderSettings()
        s.format = .flac
        s.presets[.flac] = Preset(sampleRate: 96000, bitDepth: 16)
        s.outputFolderPath = "/tmp/x"
        s.save(to: store)
        let loaded = TranscoderSettings.load(from: store)
        #expect(loaded == s)
        #expect(loaded.preset(for: .mp3) == .defaults(for: .mp3))
    }

    @Test("The app's store is not .standard under tests")
    func isolated() {
        #expect(UserDefaults.app !== UserDefaults.standard)
    }
}

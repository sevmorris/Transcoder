import Foundation

/// What ffprobe reports about an input, reduced to what a conversion needs.
nonisolated struct SourceInfo: Equatable, Sendable {
    var duration: Double?
    var audioStreamIndex: Int
    var channels: Int
    var sampleRate: Int
    /// The stream index of an attached cover picture, if there is one.
    var coverStreamIndex: Int?
    var coverCodec: String?
    /// True when the tags live on the audio stream rather than the container
    /// (Ogg and Opus keep their Vorbis comments there).
    var tagsOnStream: Bool

    /// Parses `ffprobe -show_format -show_streams -of json`.
    static func parse(_ json: Data) throws -> SourceInfo {
        struct Root: Decodable { var streams: [Stream]?; var format: Format? }
        struct Stream: Decodable {
            var index: Int
            var codec_type: String?
            var codec_name: String?
            var channels: Int?
            var sample_rate: String?
            var disposition: [String: Int]?
            var tags: [String: String]?
        }
        struct Format: Decodable { var duration: String?; var tags: [String: String]? }

        let root: Root
        do { root = try JSONDecoder().decode(Root.self, from: json) } catch {
            throw ProcessingError.ffprobeFailed("unreadable ffprobe output")
        }
        let streams = root.streams ?? []
        guard let audio = streams.first(where: { $0.codec_type == "audio" }) else {
            throw ProcessingError.noAudioStream
        }
        let cover = streams.first { $0.codec_type == "video" && $0.disposition?["attached_pic"] == 1 }
        let formatTags = (root.format?.tags ?? [:]).filter { !$0.key.lowercased().hasPrefix("encoder") && $0.key.lowercased() != "major_brand" && $0.key.lowercased() != "minor_version" && $0.key.lowercased() != "compatible_brands" }
        let streamTags = (audio.tags ?? [:]).filter { !["encoder", "handler_name", "vendor_id", "language"].contains($0.key.lowercased()) }
        return SourceInfo(
            duration: root.format?.duration.flatMap(Double.init),
            audioStreamIndex: audio.index,
            channels: audio.channels ?? 2,
            sampleRate: audio.sample_rate.flatMap(Int.init) ?? 44100,
            coverStreamIndex: cover?.index,
            coverCodec: cover?.codec_name,
            tagsOnStream: formatTags.isEmpty && !streamTags.isEmpty)
    }
}

import Foundation

/// An output format Transcoder writes. Audio only: video streams in the source
/// are never carried over, except a cover picture where the container holds one.
nonisolated enum OutputFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case mp3, aac, alac, flac, wav, aiff, opus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp3: "MP3"
        case .aac: "AAC (M4A)"
        case .alac: "Apple Lossless (M4A)"
        case .flac: "FLAC"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .opus: "Opus (OGG)"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp3: "mp3"
        case .aac, .alac: "m4a"
        case .flac: "flac"
        case .wav: "wav"
        case .aiff: "aiff"
        case .opus: "opus"
        }
    }

    var isLossy: Bool { [.mp3, .aac, .opus].contains(self) }

    /// Bitrates offered for a lossy format, in kbps.
    var bitrates: [Int] {
        switch self {
        case .mp3: [96, 128, 160, 192, 224, 256, 320]
        case .aac: [96, 128, 160, 192, 256, 320]
        case .opus: [48, 64, 96, 128, 160, 192, 256]
        default: []
        }
    }

    /// Bit depths offered for a lossless format.
    var bitDepths: [Int] {
        switch self {
        case .wav: [16, 24, 32]
        case .aiff, .flac, .alac: [16, 24]
        default: []
        }
    }

    /// Sample rates offered; an empty list means the format fixes it (Opus is
    /// always 48 kHz).
    var sampleRates: [Int] {
        switch self {
        case .opus: []
        case .mp3: [32000, 44100, 48000]
        default: [44100, 48000, 88200, 96000]
        }
    }

    /// Whether the container can carry a cover picture through FFmpeg.
    /// WAV has nowhere standard to put one, and FFmpeg's Ogg muxer writes no
    /// METADATA_BLOCK_PICTURE, so those two keep tags but lose artwork.
    var carriesArtwork: Bool { ![.wav, .opus].contains(self) }
}

/// The settings one format converts with. A nil field means "same as the source".
nonisolated struct Preset: Codable, Equatable, Sendable {
    var bitrateKbps: Int?
    var sampleRate: Int?
    var channels: Int?
    var bitDepth: Int?

    static func defaults(for format: OutputFormat) -> Preset {
        switch format {
        case .mp3: Preset(bitrateKbps: 320)
        case .aac: Preset(bitrateKbps: 256)
        case .opus: Preset(bitrateKbps: 128)
        case .wav, .aiff, .flac, .alac: Preset(bitDepth: 24)
        }
    }
}

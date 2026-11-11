import Foundation

/// AIFF keeps its sizes in 32-bit fields, and FFmpeg's AIFF muxer has no
/// 64-bit form to fall back on (WAV has RF64; AIFF has nothing). Past 4 GB it
/// writes sizes that have wrapped round, exits 0, and the file reads as a few
/// seconds of audio. So Transcoder refuses such a conversion before it starts,
/// when the length is known, and checks the written file afterwards in case the
/// estimate was short.
nonisolated enum AIFFLimit {
    /// The FORM chunk's size field counts every byte after its first eight.
    static let maxFileSize: Int64 = Int64(UInt32.max) + 8

    /// Room for the header chunks and an ID3 tag without a cover, so an
    /// estimate just under the limit is not refused for a few bytes. A large
    /// cover can still push a file over; the check afterwards catches that.
    static let headerAllowance: Int64 = 64 * 1024

    /// The sample data an AIFF of `source` at `preset` would hold, or nil when
    /// the source's length is unknown.
    static func estimatedAudioBytes(preset: Preset, source: SourceInfo) -> Int64? {
        guard let duration = source.duration, duration > 0 else { return nil }
        let rate = ArgumentBuilder.sampleRate(format: .aiff, preset: preset) ?? source.sampleRate
        let channels = ArgumentBuilder.channels(format: .aiff, preset: preset, source: source) ?? source.channels
        let bytesPerSample = preset.bitDepth == 16 ? 2 : 3
        return Int64((duration * Double(rate * channels * bytesPerSample)).rounded(.up))
    }

    /// True when the conversion cannot fit in an AIFF file.
    static func wouldOverflow(preset: Preset, source: SourceInfo) -> Bool {
        guard let bytes = estimatedAudioBytes(preset: preset, source: source) else { return false }
        return bytes + headerAllowance > maxFileSize
    }

    /// True when a written file is too large for its own FORM header.
    static func overflowed(fileSize: Int64) -> Bool { fileSize > maxFileSize }
}

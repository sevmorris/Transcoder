import Foundation

/// Builds the ffmpeg command line for one conversion. Pure, so the tests can
/// check every format's arguments without running FFmpeg.
nonisolated enum ArgumentBuilder {

    static func arguments(input: URL, output: URL, format: OutputFormat, preset: Preset,
                          source: SourceInfo, progressFile: URL? = nil) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y", "-i", input.path]
        if let progressFile { args += ["-progress", progressFile.path, "-nostats"] }

        // Audio: the first audio stream only. Video is never carried, except
        // an attached cover picture where the container can hold one.
        args += ["-map", "0:\(source.audioStreamIndex)"]
        let cover = format.carriesArtwork ? source.coverStreamIndex : nil
        if let cover { args += ["-map", "0:\(cover)"] }

        // Tags: from the container, or from the audio stream when that is where
        // the source keeps them (Ogg, Opus). Chapters are not carried.
        args += ["-map_metadata", source.tagsOnStream ? "0:s:\(source.audioStreamIndex)" : "0",
                 "-map_chapters", "-1"]

        args += codecArguments(format: format, preset: preset, source: source)

        if let rate = sampleRate(format: format, preset: preset) { args += ["-ar", String(rate)] }
        if let channels = channels(format: format, preset: preset, source: source) {
            args += ["-ac", String(channels)]
        }

        if cover != nil {
            let copyable = ["mjpeg", "png"].contains(source.coverCodec ?? "")
            args += ["-c:v", copyable ? "copy" : "mjpeg", "-disposition:v:0", "attached_pic"]
        }

        args += containerArguments(format: format)
        args.append(output.path)
        return args
    }

    static func codecArguments(format: OutputFormat, preset: Preset, source: SourceInfo) -> [String] {
        let depth = preset.bitDepth
        switch format {
        case .mp3:
            return ["-c:a", "libmp3lame", "-b:a", "\(preset.bitrateKbps ?? 320)k"]
        case .aac:
            return ["-c:a", "aac", "-b:a", "\(preset.bitrateKbps ?? 256)k"]
        case .opus:
            // FFmpeg's own Opus encoder is still marked experimental.
            return ["-c:a", "opus", "-strict", "-2", "-b:a", "\(preset.bitrateKbps ?? 128)k"]
        case .wav:
            switch depth {
            case 16: return ["-c:a", "pcm_s16le"]
            case 32: return ["-c:a", "pcm_f32le"]
            default: return ["-c:a", "pcm_s24le"]
            }
        case .aiff:
            return ["-c:a", depth == 16 ? "pcm_s16be" : "pcm_s24be"]
        case .flac:
            return depth == 16 ? ["-c:a", "flac", "-sample_fmt", "s16"]
                : ["-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
        case .alac:
            return depth == 16 ? ["-c:a", "alac", "-sample_fmt", "s16p"]
                : ["-c:a", "alac", "-sample_fmt", "s32p", "-bits_per_raw_sample", "24"]
        }
    }

    static func sampleRate(format: OutputFormat, preset: Preset) -> Int? {
        if format == .opus { return 48000 }
        return preset.sampleRate
    }

    /// Opus here is mono or stereo; a surround source is folded down.
    static func channels(format: OutputFormat, preset: Preset, source: SourceInfo) -> Int? {
        if format == .opus, preset.channels == nil, source.channels > 2 { return 2 }
        return preset.channels
    }

    static func containerArguments(format: OutputFormat) -> [String] {
        switch format {
        case .mp3: ["-id3v2_version", "3", "-write_id3v1", "1"]
        case .aiff: ["-write_id3v2", "1"]
        case .aac, .alac: ["-f", "ipod", "-movflags", "+faststart"]
        case .opus: ["-f", "opus"]
        case .flac, .wav: []
        }
    }

    /// `name.ext` in `folder`, or `name 2.ext`, `name 3.ext`… so nothing is
    /// overwritten — the source included, when it is already that format.
    static func uniqueOutputURL(for source: URL, format: OutputFormat, in folder: URL,
                                exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var n = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(format.fileExtension)
            n += 1
        }
        return candidate
    }

    /// Reads the latest `out_time_us` from an ffmpeg -progress file.
    static func progressSeconds(in text: String) -> Double? {
        for line in text.split(separator: "\n").reversed() where line.hasPrefix("out_time_us=") {
            if let us = Double(line.dropFirst("out_time_us=".count)) { return max(0, us / 1_000_000) }
        }
        return nil
    }
}

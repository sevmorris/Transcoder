import Foundation

/// What the queue needs from a converter. `Converter` is the real one; the
/// tests give `ContentViewModel` a stand-in so the queue rules can be checked
/// without running FFmpeg.
nonisolated protocol Converting: Sendable {
    func convert(input: URL, output: URL, format: OutputFormat, preset: Preset,
                 progress: @escaping @Sendable (Double) -> Void) async throws
}

/// Runs ffprobe and ffmpeg for one file at a time. The process itself is
/// FFmpegProcess's job; this decides what to run and reports progress.
actor Converter: Converting {
    let ffmpeg: String
    let ffprobe: String

    init(ffmpeg: String? = nil, ffprobe: String? = nil) {
        let resources = Bundle.main.resourceURL
        self.ffmpeg = ffmpeg ?? resources?.appendingPathComponent("ffmpeg").path ?? "ffmpeg"
        self.ffprobe = ffprobe ?? resources?.appendingPathComponent("ffprobe").path ?? "ffprobe"
    }

    func probe(_ url: URL) async throws -> SourceInfo {
        let args = ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path]
        let (status, output) = try await FFmpegProcess.launch(
            exe: ffprobe, args: args, capture: .stdout, timeoutSeconds: 60)
        guard status == 0 else {
            // FFmpegProcess captures one stream, and the JSON is on stdout, so
            // ffprobe's own reason is fetched with a second run, on failure only.
            let stderr = (try? await FFmpegProcess.launch(
                exe: ffprobe, args: args, capture: .stderr, timeoutSeconds: 60))?.1 ?? ""
            throw ProcessingError.ffprobeFailed(Self.probeFailureReason(stderr: stderr, path: url.path, status: status))
        }
        return try SourceInfo.parse(Data(output.utf8))
    }

    /// ffprobe's last line of complaint, without the path it starts with, or
    /// the exit status when it said nothing.
    nonisolated static func probeFailureReason(stderr: String, path: String, status: Int32) -> String {
        guard let line = stderr.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }) else { return "ffprobe exit \(status)" }
        return line.hasPrefix(path + ": ") ? String(line.dropFirst(path.count + 2)) : line
    }

    /// How long one run may take. It is there to catch a hung process, not a
    /// slow one: four times the length, at least ten minutes, and a whole day
    /// when the container gives no length to go by.
    nonisolated static func timeLimit(duration: Double?) -> Int {
        guard let duration, duration > 0 else { return 24 * 3600 }
        return max(600, Int(duration * 4))
    }

    /// Converts `input` to `output`, calling `progress` with 0…1 as it goes.
    func convert(input: URL, output: URL, format: OutputFormat, preset: Preset,
                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = output.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProcessingError.outputFolderMissing(folder.path)
        }

        let info = try await probe(input)
        if format == .aiff, AIFFLimit.wouldOverflow(preset: preset, source: info) {
            throw ProcessingError.tooLargeForAIFF
        }
        let progressFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcoder-progress-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: progressFile) }

        let args = ArgumentBuilder.arguments(input: input, output: output, format: format,
                                             preset: preset, source: info, progressFile: progressFile)

        let poller = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let duration = info.duration, duration > 0,
                      let text = try? String(contentsOf: progressFile, encoding: .utf8),
                      let seconds = ArgumentBuilder.progressSeconds(in: text) else { continue }
                progress(min(1, seconds / duration))
            }
        }
        defer { poller.cancel() }

        do {
            let (status, stderr) = try await FFmpegProcess.launch(
                exe: ffmpeg, args: args, capture: .stderr, timeoutSeconds: Self.timeLimit(duration: info.duration))
            guard status == 0 else {
                try? FileManager.default.removeItem(at: output)
                throw ProcessingError.ffmpegFailed(code: status, message: stderr)
            }
        } catch {
            // A cancelled or failed run leaves no half-written file behind.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        guard FileManager.default.fileExists(atPath: output.path) else { throw ProcessingError.outputMissing }
        // The estimate above cannot know the length of a source whose
        // container gives none, nor the size of a large cover.
        if format == .aiff,
           let size = ((try? FileManager.default.attributesOfItem(atPath: output.path))?[.size] as? NSNumber)?.int64Value,
           AIFFLimit.overflowed(fileSize: size) {
            try? FileManager.default.removeItem(at: output)
            throw ProcessingError.tooLargeForAIFF
        }
        progress(1)
    }
}

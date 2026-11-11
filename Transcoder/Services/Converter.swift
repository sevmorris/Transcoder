import Foundation

/// Runs ffprobe and ffmpeg for one file at a time. The process itself is
/// FFmpegProcess's job; this decides what to run and reports progress.
actor Converter {
    let ffmpeg: String
    let ffprobe: String

    init(ffmpeg: String? = nil, ffprobe: String? = nil) {
        let resources = Bundle.main.resourceURL
        self.ffmpeg = ffmpeg ?? resources?.appendingPathComponent("ffmpeg").path ?? "ffmpeg"
        self.ffprobe = ffprobe ?? resources?.appendingPathComponent("ffprobe").path ?? "ffprobe"
    }

    func probe(_ url: URL) async throws -> SourceInfo {
        let (status, output) = try await FFmpegProcess.launch(
            exe: ffprobe,
            args: ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path],
            capture: .stdout, timeoutSeconds: 60)
        guard status == 0 else { throw ProcessingError.ffprobeFailed("ffprobe exit \(status)") }
        return try SourceInfo.parse(Data(output.utf8))
    }

    /// Converts `input` to `output`, calling `progress` with 0…1 as it goes.
    func convert(input: URL, output: URL, format: OutputFormat, preset: Preset,
                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let info = try await probe(input)
        let progressFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcoder-progress-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: progressFile) }

        let args = ArgumentBuilder.arguments(input: input, output: output, format: format,
                                             preset: preset, source: info, progressFile: progressFile)
        // Generous: a long file at a slow setting, on a busy Mac.
        let timeout = max(600, Int((info.duration ?? 0) * 4))

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
                exe: ffmpeg, args: args, capture: .stderr, timeoutSeconds: timeout)
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
        progress(1)
    }
}

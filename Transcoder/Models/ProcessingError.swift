import Foundation

/// Errors a conversion can end in. `ffmpegNotFound` and
/// `ffmpegFailed(code:message:)` are the contract FFmpegProcess.swift (shared
/// verbatim) expects this module to define.
nonisolated enum ProcessingError: LocalizedError, Equatable {
    case ffmpegNotFound
    case ffmpegFailed(code: Int32, message: String)
    case ffprobeFailed(String)
    case noAudioStream
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "The bundled FFmpeg is missing. Reinstall Transcoder."
        case .ffmpegFailed(let code, let message):
            let tail = message.split(separator: "\n").suffix(3).joined(separator: " ")
            return tail.isEmpty ? "FFmpeg failed (exit \(code))." : "FFmpeg failed (exit \(code)): \(tail)"
        case .ffprobeFailed(let message):
            return "Could not read the file: \(message)"
        case .noAudioStream:
            return "The file has no audio."
        case .outputMissing:
            return "FFmpeg finished but wrote no file."
        }
    }
}

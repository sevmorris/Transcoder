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
    case outputFolderMissing(String)
    case tooLargeForAIFF

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
        case .outputFolderMissing(let path):
            return "The output folder is not available: \(path). Connect its drive, or choose another folder."
        case .tooLargeForAIFF:
            return "Too large for AIFF: the file would pass 4 GB, the most AIFF can hold. Choose WAV, FLAC or Apple Lossless, or a lower sample rate, bit depth or channel count."
        }
    }
}

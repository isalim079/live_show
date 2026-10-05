import Foundation

/// Strongly typed errors across the LiveWallpaper domain.
/// Adheres to Section 24 of the specification.
public enum WallpaperError: LocalizedError, Sendable, Equatable {
    case fileMissing(path: String)
    case accessDenied(path: String)
    case unsupportedMedia(reason: String)
    case corruptMedia(reason: String)
    case playbackFailed(reason: String)
    case displayUnavailable(identifier: String)
    case persistenceFailed(reason: String)
    case internalError(reason: String)

    public var errorDescription: String? {
        switch self {
        case .fileMissing(let path):
            return "Video file not found at path: \(path)"
        case .accessDenied:
            return "Permission to read the video file was denied."
        case .unsupportedMedia(let reason):
            return "Unsupported media: \(reason)"
        case .corruptMedia(let reason):
            return "Corrupt media file: \(reason)"
        case .playbackFailed(let reason):
            return "Playback error: \(reason)"
        case .displayUnavailable(let identifier):
            return "Display \(identifier) is currently unavailable."
        case .persistenceFailed(let reason):
            return "Failed to save or restore configuration: \(reason)"
        case .internalError(let reason):
            return "Internal error: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .fileMissing, .accessDenied:
            return "Verify the file exists and select it again using the Import button."
        case .unsupportedMedia:
            return "Use an H.264 or HEVC encoded MP4 or MOV video file."
        case .corruptMedia, .playbackFailed:
            return "Try re-encoding the video or choosing a different video file."
        case .displayUnavailable:
            return "Ensure the display is connected and powered on."
        case .persistenceFailed:
            return "Check available disk space in your home directory."
        case .internalError:
            return "Restart LiveWallpaper or check the Diagnostics window."
        }
    }
}

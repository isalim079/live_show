import Foundation

/// Core domain model representing a wallpaper item in the user's library.
/// Adheres to Section 6 & 14 of the specification.
public struct Wallpaper: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var fileURL: URL
    public var bookmarkData: Data?
    public var title: String
    public var duration: TimeInterval?
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var fileSize: Int64
    public var createdAt: Date
    public var updatedAt: Date
    public var lastPlayedAt: Date?
    public var isAvailable: Bool
    public var thumbnailPath: String?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        bookmarkData: Data? = nil,
        title: String? = nil,
        duration: TimeInterval? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        fileSize: Int64 = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        isAvailable: Bool = true,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.title = title ?? fileURL.deletingPathExtension().lastPathComponent
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastPlayedAt = lastPlayedAt
        self.isAvailable = isAvailable
        self.thumbnailPath = thumbnailPath
    }

    /// User-friendly resolution string (e.g. "4K UHD", "1080p", "1440p")
    public var resolutionLabel: String {
        guard let width = width, let height = height else { return "Unknown" }
        if width >= 3840 || height >= 2160 {
            return "4K"
        } else if width >= 2560 || height >= 1440 {
            return "2K / 1440p"
        } else if width >= 1920 || height >= 1080 {
            return "1080p"
        } else if width >= 1280 || height >= 720 {
            return "720p"
        } else {
            return "\(width)x\(height)"
        }
    }

    /// User-friendly duration string (e.g. "00:30", "02:15")
    public var formattedDuration: String {
        guard let duration = duration, duration > 0 else { return "00:00" }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remMinutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Formatted file size string (e.g. "12.4 MB")
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

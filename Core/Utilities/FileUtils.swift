import Foundation

public enum FileUtils {
    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Returns the app support directory for storing library and settings.
    public static var appSupportDirectory: URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("com.livewallpaper.app", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Returns the caches directory for storing video thumbnails.
    public static var thumbnailsDirectory: URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("com.livewallpaper.app/thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Returns the directory for permanently storing imported wallpaper video files.
    public static var wallpapersDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Checks if a file exists and is readable at the given URL.
    public static func isFileReadable(at url: URL) -> Bool {
        let path = url.path
        return FileManager.default.fileExists(atPath: path) && FileManager.default.isReadableFile(atPath: path)
    }

    /// Returns the file size in bytes.
    public static func fileSize(at url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        } catch {
            return 0
        }
    }

    /// Checks if the file extension is supported.
    public static func isSupportedVideoFormat(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}

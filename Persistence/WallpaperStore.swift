import Foundation
import AppKit
import Combine

/// Schema for serializing user library metadata.
public struct LibraryData: Codable, Sendable {
    public var version: Int = 1
    public var wallpapers: [Wallpaper] = []
    public var assignments: [String: WallpaperAssignment] = [:]

    public init(version: Int = 1, wallpapers: [Wallpaper] = [], assignments: [String: WallpaperAssignment] = [:]) {
        self.version = version
        self.wallpapers = wallpapers
        self.assignments = assignments
    }
}

/// Thread-safe persistence store for wallpapers, display assignments, and settings.
/// Adheres to Section 14, 25, and 26 of the specification.
@MainActor
public final class WallpaperStore: ObservableObject {
    @Published public private(set) var wallpapers: [Wallpaper] = []
    @Published public private(set) var assignments: [String: WallpaperAssignment] = [:]
    @Published public var settings: LiveWallpaperSettings = .default {
        didSet { saveSettings() }
    }

    private let libraryURL: URL
    private let settingsURL: URL
    private let backupLibraryURL: URL

    public init() {
        let appSupport = FileUtils.appSupportDirectory
        self.libraryURL = appSupport.appendingPathComponent("library.json")
        self.settingsURL = appSupport.appendingPathComponent("settings.json")
        self.backupLibraryURL = appSupport.appendingPathComponent("library.json.bak")

        loadSettings()
        loadLibrary()
    }

    // MARK: - Library Loading & Saving
    private func loadLibrary() {
        let fileManager = FileManager.default
        let urlToRead: URL

        if fileManager.fileExists(atPath: libraryURL.path) {
            urlToRead = libraryURL
        } else if fileManager.fileExists(atPath: backupLibraryURL.path) {
            AppLogger.persistence.warning("Primary library.json missing, restoring from backup.")
            urlToRead = backupLibraryURL
        } else {
            // First run, empty library
            self.wallpapers = []
            self.assignments = [:]
            seedDefaultSampleWallpaperIfAvailable()
            return
        }

        do {
            let data = try Data(contentsOf: urlToRead)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(LibraryData.self, from: data)
            self.wallpapers = decoded.wallpapers
            self.assignments = decoded.assignments
            AppLogger.persistence.info("Successfully loaded library with \(self.wallpapers.count) wallpaper(s).")
        } catch {
            AppLogger.persistence.error("Failed to decode library: \(error.localizedDescription). Attempting backup.")
            if urlToRead != backupLibraryURL && fileManager.fileExists(atPath: backupLibraryURL.path) {
                if let backupData = try? Data(contentsOf: backupLibraryURL),
                   let decoded = try? JSONDecoder().decode(LibraryData.self, from: backupData) {
                    self.wallpapers = decoded.wallpapers
                    self.assignments = decoded.assignments
                    return
                }
            }
            self.wallpapers = []
            self.assignments = [:]
        }
    }

    public func saveLibrary() {
        let dataToSave = LibraryData(
            version: 1,
            wallpapers: self.wallpapers,
            assignments: self.assignments
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(dataToSave)

            // Write backup first
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                try? FileManager.default.copyItem(at: libraryURL, to: backupLibraryURL)
            }

            try encoded.write(to: libraryURL, options: .atomic)
            AppLogger.persistence.info("Saved library successfully (\(encoded.count) bytes).")
        } catch {
            AppLogger.persistence.error("Failed to save library: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings Loading & Saving
    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            self.settings = .default
            return
        }

        do {
            let data = try Data(contentsOf: settingsURL)
            let decoded = try JSONDecoder().decode(LiveWallpaperSettings.self, from: data)
            self.settings = decoded
        } catch {
            AppLogger.persistence.warning("Could not read settings: \(error.localizedDescription), using defaults.")
            self.settings = .default
        }
    }

    public func saveSettings() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let encoded = try encoder.encode(self.settings)
            try encoded.write(to: settingsURL, options: .atomic)
        } catch {
            AppLogger.persistence.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Wallpaper Actions
    /// Imports a video from a file URL, extracting metadata and generating a thumbnail.
    public func importVideo(from url: URL) async throws -> Wallpaper {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // 1. Validate
        let metadata = try await MediaValidator.validate(url: url)

        let id = UUID()
        let fileExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let destinationURL = FileUtils.wallpapersDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        // Copy video file into the app's internal storage so it is permanently accessible
        // across restarts/reboots without relying on fragile external bookmarks.
        let fileManager = FileManager.default
        var finalURL = url
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            finalURL = destinationURL
            AppLogger.wallpaper.info("Successfully copied imported video to internal storage: \(destinationURL.path)")
        } catch {
            AppLogger.wallpaper.warning("Could not copy video to internal storage (\(error.localizedDescription)), using source URL")
        }

        // 2. Create security-scoped bookmark
        let bookmarkData = try? SecurityScopedBookmarkManager.shared.createBookmark(for: finalURL)
        let fileSize = FileUtils.fileSize(at: finalURL)

        // 3. Generate thumbnail asynchronously
        let thumbPath = await ThumbnailGenerator.generateThumbnail(for: finalURL, id: id)

        let wallpaper = Wallpaper(
            id: id,
            fileURL: finalURL,
            bookmarkData: bookmarkData,
            title: url.deletingPathExtension().lastPathComponent,
            duration: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            frameRate: metadata.frameRate,
            fileSize: fileSize,
            createdAt: Date(),
            updatedAt: Date(),
            lastPlayedAt: nil,
            isAvailable: true,
            thumbnailPath: thumbPath
        )

        objectWillChange.send()
        self.wallpapers.insert(wallpaper, at: 0)
        saveLibrary()

        AppLogger.wallpaper.info("Imported wallpaper: \(wallpaper.title) (\(wallpaper.resolutionLabel))")
        return wallpaper
    }

    public func removeWallpaper(id: UUID) {
        objectWillChange.send()
        wallpapers.removeAll(where: { $0.id == id })

        // Clear assignments using this wallpaper and stop playback
        for (dispID, assignment) in assignments where assignment.wallpaperID == id {
            assignments.removeValue(forKey: dispID)
            AppState.shared.wallpaperManager.activeSessions[dispID]?.stop()
        }

        // Remove cached thumbnail file if present
        let thumbFile = FileUtils.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).jpg")
        try? FileManager.default.removeItem(at: thumbFile)

        // Remove internally stored video file if present
        let extCandidates = ["mp4", "mov", "m4v"]
        for ext in extCandidates {
            let videoFile = FileUtils.wallpapersDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
            try? FileManager.default.removeItem(at: videoFile)
        }

        saveLibrary()
        AppLogger.wallpaper.info("Removed wallpaper ID: \(id.uuidString)")
    }

    public func setAssignment(wallpaperID: UUID, forDisplayID displayID: String, displayName: String, scalingMode: ScalingMode) {
        let assignment = WallpaperAssignment(
            wallpaperID: wallpaperID,
            displayStableIdentifier: displayID,
            displayName: displayName,
            scalingMode: scalingMode,
            updatedAt: Date()
        )
        self.assignments[displayID] = assignment

        if let index = wallpapers.firstIndex(where: { $0.id == wallpaperID }) {
            wallpapers[index].lastPlayedAt = Date()
        }

        saveLibrary()
    }

    /// Looks up an assignment by display ID, display name, or falls back to the most recent assignment.
    public func assignment(for displayID: String, displayName: String? = nil) -> WallpaperAssignment? {
        // 1. Direct match on displayID
        if let direct = assignments[displayID] {
            return direct
        }

        // 2. Match by display name if display ID shifted across reboots
        if let name = displayName, !name.isEmpty,
           let nameMatch = assignments.values.first(where: { $0.displayName == name }) {
            AppLogger.wallpaper.info("Remapped display assignment by name '\(name)' to display ID \(displayID)")
            return nameMatch
        }

        // 3. Fallback: if user previously had any assignment, reuse the latest one
        if let latest = assignments.values.max(by: { $0.updatedAt < $1.updatedAt }) {
            AppLogger.wallpaper.info("Reusing previous wallpaper assignment for display ID \(displayID)")
            return latest
        }

        return nil
    }

    /// Resolves the accessible URL for a wallpaper, using internal storage, bookmark, or original path.
    public func resolveURL(for wallpaper: Wallpaper) -> URL? {
        let fileManager = FileManager.default
        let ext = wallpaper.fileURL.pathExtension.isEmpty ? "mp4" : wallpaper.fileURL.pathExtension
        let internalURL = FileUtils.wallpapersDirectory.appendingPathComponent("\(wallpaper.id.uuidString).\(ext)")

        // 1. Priority: check internal storage
        if fileManager.fileExists(atPath: internalURL.path) {
            return internalURL
        }

        // 2. Direct path check with automatic migration to internal storage
        if fileManager.fileExists(atPath: wallpaper.fileURL.path) && fileManager.isReadableFile(atPath: wallpaper.fileURL.path) {
            SecurityScopedBookmarkManager.shared.startAccessing(url: wallpaper.fileURL)
            try? fileManager.copyItem(at: wallpaper.fileURL, to: internalURL)
            if fileManager.fileExists(atPath: internalURL.path) {
                return internalURL
            }
            return wallpaper.fileURL
        }

        // 3. Security-scoped bookmark resolution
        if let bookmarkData = wallpaper.bookmarkData {
            do {
                let resolved = try SecurityScopedBookmarkManager.shared.resolveBookmark(data: bookmarkData) { [weak self] newBookmark in
                    self?.updateBookmark(for: wallpaper.id, newBookmark: newBookmark)
                }
                if fileManager.fileExists(atPath: resolved.path) {
                    try? fileManager.copyItem(at: resolved, to: internalURL)
                    if fileManager.fileExists(atPath: internalURL.path) {
                        return internalURL
                    }
                    return resolved
                }
            } catch {
                AppLogger.persistence.warning("Bookmark resolution failed: \(error.localizedDescription). Trying direct path.")
            }
        }

        // 4. SampleAmbient fallback
        if wallpaper.fileURL.lastPathComponent == "SampleAmbient.mp4" {
            if let bundleSample = Bundle.main.url(forResource: "SampleAmbient", withExtension: "mp4") {
                return bundleSample
            }
        }

        return nil
    }

    private func updateBookmark(for id: UUID, newBookmark: Data) {
        if let index = wallpapers.firstIndex(where: { $0.id == id }) {
            wallpapers[index].bookmarkData = newBookmark
            saveLibrary()
        }
    }

    private func seedDefaultSampleWallpaperIfAvailable() {
        var sampleURL: URL? = Bundle.main.url(forResource: "SampleAmbient", withExtension: "mp4")
        if sampleURL == nil {
            let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/SampleAmbient.mp4")
            if FileManager.default.fileExists(atPath: devPath.path) {
                sampleURL = devPath
            }
        }

        if let sampleURL = sampleURL {
            Task { @MainActor in
                do {
                    let wallpaper = try await self.importVideo(from: sampleURL)
                    for (index, screen) in NSScreen.screens.enumerated() {
                        let displayID: String
                        if let cgID = DisplayDescriptor.cgDisplayID(from: screen) {
                            displayID = String(cgID)
                        } else {
                            displayID = String(index)
                        }
                        self.setAssignment(
                            wallpaperID: wallpaper.id,
                            forDisplayID: displayID,
                            displayName: screen.localizedName,
                            scalingMode: .fill
                        )
                    }
                    AppState.shared.wallpaperManager.reconcile()
                } catch {
                    AppLogger.wallpaper.error("Could not import default wallpaper: \(error.localizedDescription)")
                }
            }
        }
    }
}

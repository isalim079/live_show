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

        // 2. Create security-scoped bookmark
        let bookmarkData = try? SecurityScopedBookmarkManager.shared.createBookmark(for: url)

        let id = UUID()
        let fileSize = FileUtils.fileSize(at: url)

        // 3. Generate thumbnail asynchronously
        let thumbPath = await ThumbnailGenerator.generateThumbnail(for: url, id: id)

        let wallpaper = Wallpaper(
            id: id,
            fileURL: url,
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

    /// Resolves the accessible URL for a wallpaper, using bookmark or falling back to fileURL.
    public func resolveURL(for wallpaper: Wallpaper) -> URL? {
        if let bookmarkData = wallpaper.bookmarkData {
            do {
                let resolved = try SecurityScopedBookmarkManager.shared.resolveBookmark(data: bookmarkData) { [weak self] newBookmark in
                    self?.updateBookmark(for: wallpaper.id, newBookmark: newBookmark)
                }
                return resolved
            } catch {
                AppLogger.persistence.warning("Bookmark resolution failed: \(error.localizedDescription). Trying direct path.")
            }
        }

        // Direct path fallback
        if FileManager.default.fileExists(atPath: wallpaper.fileURL.path) {
            SecurityScopedBookmarkManager.shared.startAccessing(url: wallpaper.fileURL)
            return wallpaper.fileURL
        }

        // If it's SampleAmbient, fallback to bundle resource
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
                        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
                        let displayID = String(screen.deviceDescription[screenNumberKey] as? CGDirectDisplayID ?? CGDirectDisplayID(index))
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

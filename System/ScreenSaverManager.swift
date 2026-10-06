import Foundation
import AppKit

/// Manages installation and system settings integration for the macOS Screen Saver plugin.
@MainActor
public final class ScreenSaverManager: ObservableObject {
    public static let shared = ScreenSaverManager()

    @Published public private(set) var isInstalled: Bool = false

    public var destinationURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Screen Savers/LiveWallpaper.saver")
    }

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        self.isInstalled = FileManager.default.fileExists(atPath: destinationURL.path)
    }

    /// Installs or updates the Screen Saver bundle in ~/Library/Screen Savers/
    @discardableResult
    public func installScreenSaver() -> Bool {
        let fileManager = FileManager.default
        let screensaversDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers")

        do {
            if !fileManager.fileExists(atPath: screensaversDir.path) {
                try fileManager.createDirectory(at: screensaversDir, withIntermediateDirectories: true)
            }

            // Look for bundled .saver in the app bundle
            guard let bundleSaverURL = Bundle.main.url(forResource: "LiveWallpaper", withExtension: "saver") else {
                AppLogger.wallpaper.warning("LiveWallpaper.saver not found in app bundle.")
                checkStatus()
                return false
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: bundleSaverURL, to: destinationURL)

            // CRITICAL: Strip quarantine and provenance extended attributes.
            // macOS adds com.apple.quarantine / com.apple.provenance when files are
            // copied from external volumes. These cause Gatekeeper to reject the
            // .saver bundle, preventing ScreenSaverEngine from loading it on
            // the lock screen entirely (no error shown — just silence).
            stripExtendedAttributes(at: destinationURL)

            AppLogger.wallpaper.info("Installed LiveWallpaper.saver to \(self.destinationURL.path)")
            registerAsSystemScreenSaver()
            checkStatus()
            return true

        } catch {
            AppLogger.wallpaper.error("Failed to install screen saver: \(error.localizedDescription)")
        }

        checkStatus()
        return false
    }

    /// Recursively strips extended attributes (quarantine, provenance, etc.) from a path.
    private func stripExtendedAttributes(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-rc", url.path]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            AppLogger.wallpaper.info("Stripped xattrs from \(url.lastPathComponent)")
        }
    }

    /// Opens macOS System Settings Screen Saver / Lock Screen preferences pane.
    public func openScreenSaverSettings() {
        let urlsToTry = [
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        ]
        for urlStr in urlsToTry {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let settingsApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settingsApp, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Registers LiveWallpaper as the active screen saver in macOS preferences.
    public func registerAsSystemScreenSaver() {
        let path = destinationURL.path

        // Write via `defaults` so cfprefsd picks it up correctly for the current host
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = [
            "-currentHost", "write", "com.apple.screensaver", "moduleDict",
            "-dict", "path", path, "moduleName", "LiveWallpaper", "type", "0"
        ]
        try? process.run()
        process.waitUntilExit()

        // Flush cfprefsd so the preference is committed before ScreenSaverEngine reads it
        let killPrefsd = Process()
        killPrefsd.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killPrefsd.arguments = ["cfprefsd"]
        try? killPrefsd.run()
        killPrefsd.waitUntilExit()

        AppLogger.wallpaper.info("Registered LiveWallpaper.saver as active screen saver.")

        // Apply macOS Sequoia+ lock screen fix
        forceScreensaverIntoWallpaperAgent()
    }

    /// On macOS Sequoia (v14+ / Darwin 23+), the lock screen is controlled by WallpaperAgent
    /// rather than ScreenSaverEngine. To ensure our screensaver plays on the lock screen,
    /// we must inject it into the 'Idle' slot of WallpaperAgent's Store/Index.plist.
    private func forceScreensaverIntoWallpaperAgent() {
        let indexURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper_index_edit.plist")

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            AppLogger.wallpaper.warning("WallpaperAgent Index.plist not found, skipping lock screen injection")
            return
        }

        // 1. Convert binary plist to XML (so we can safely serialize/deserialize with $null)
        let convertToXML = Process()
        convertToXML.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        convertToXML.arguments = ["-convert", "xml1", "-o", xmlURL.path, indexURL.path]
        try? convertToXML.run()
        convertToXML.waitUntilExit()

        guard convertToXML.terminationStatus == 0,
              let xmlData = try? Data(contentsOf: xmlURL),
              var plist = try? PropertyListSerialization.propertyList(from: xmlData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            AppLogger.wallpaper.error("Failed to read WallpaperAgent Index.plist as XML")
            return
        }

        // 2. Build the Configuration binary blob for the screen-saver provider
        let saverPath = destinationURL.path
        let configDict: [String: Any] = ["path": saverPath, "name": "LiveWallpaper"]
        guard let configData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else {
            return
        }

        // 3. Build the Idle choice dictionary
        // Note: We use "$null" for NSNull representation which works when writing back to XML plist
        let idleChoice: [String: Any] = [
            "Configuration": configData,
            "Files": [String](),
            "Provider": "com.apple.wallpaper.choice.screen-saver"
        ]

        let idleContent: [String: Any] = [
            "Choices": [idleChoice],
            "EncodedOptionValues": "$null",
            "Shuffle": "$null"
        ]

        let idleEntry: [String: Any] = [
            "Content": idleContent,
            "LastSet": Date(),
            "LastUse": Date()
        ]

        var updated = false

        // Update AllSpacesAndDisplays > Idle
        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces["Idle"] = idleEntry
            plist["AllSpacesAndDisplays"] = allSpaces
            updated = true
        }

        // Update SystemDefault > Idle if present
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Idle"] = idleEntry
            plist["SystemDefault"] = sysDefault
            updated = true
        }

        guard updated else {
            AppLogger.wallpaper.warning("Could not find Idle slots in Index.plist to patch")
            return
        }

        // 4. Write back to XML
        guard let outXMLData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            AppLogger.wallpaper.error("Failed to serialize modified Index.plist to XML")
            return
        }
        try? outXMLData.write(to: xmlURL, options: .atomic)

        // 5. Suspend WallpaperAgent to prevent race conditions while we write
        let suspendTask = Process()
        suspendTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        suspendTask.arguments = ["-STOP", "WallpaperAgent"]
        try? suspendTask.run()
        suspendTask.waitUntilExit()

        // 6. Convert patched XML back to Binary and overwrite Index.plist
        let convertToBinary = Process()
        convertToBinary.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        convertToBinary.arguments = ["-convert", "binary1", "-o", indexURL.path, xmlURL.path]
        try? convertToBinary.run()
        convertToBinary.waitUntilExit()

        // 7. Resume and HUP WallpaperAgent to apply changes
        let resumeTask = Process()
        resumeTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        resumeTask.arguments = ["-CONT", "WallpaperAgent"]
        try? resumeTask.run()
        resumeTask.waitUntilExit()

        let hupTask = Process()
        hupTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        hupTask.arguments = ["-HUP", "WallpaperAgent"]
        try? hupTask.run()
        hupTask.waitUntilExit()

        AppLogger.wallpaper.info("Successfully patched WallpaperAgent Index.plist for Lock Screen")
    }



    /// Writes the active wallpaper video URL to a well-known path in ~/Library/Screen Savers/
    /// so the .saver bundle (running in the restricted lock screen context) can find it.
    public func updateActiveWallpaperLink(videoURL: URL) {
        let screensaversDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers")
        let linkURL = screensaversDir.appendingPathComponent("ActiveWallpaper.mp4")

        do {
            // Remove existing link/file
            if FileManager.default.fileExists(atPath: linkURL.path) {
                try FileManager.default.removeItem(at: linkURL)
            }

            // Create a hard link — works within the same volume and is accessible
            // by ScreenSaverEngine without needing sandbox entitlements on the source.
            // Falls back to a copy if the source is on a different volume (external drive).
            do {
                try FileManager.default.linkItem(at: videoURL, to: linkURL)
                AppLogger.wallpaper.info("Created hard link: ActiveWallpaper.mp4 → \(videoURL.lastPathComponent)")
            } catch {
                // Hard link failed (cross-volume) — copy the file instead
                try FileManager.default.copyItem(at: videoURL, to: linkURL)
                AppLogger.wallpaper.info("Copied video to Screen Savers dir: \(videoURL.lastPathComponent)")
            }

            // Strip xattrs from the copied/linked file as well
            stripExtendedAttributes(at: linkURL)

        } catch {
            AppLogger.wallpaper.error("Failed to update ActiveWallpaper.mp4 link: \(error.localizedDescription)")
        }
    }
}

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

            // Look for bundled .saver in app bundle
            if let bundleSaverURL = Bundle.main.url(forResource: "LiveWallpaper", withExtension: "saver") {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: bundleSaverURL, to: destinationURL)
                AppLogger.wallpaper.info("Installed LiveWallpaper.saver from app bundle to \(self.destinationURL.path)")
                checkStatus()
                return true
            }
        } catch {
            AppLogger.wallpaper.error("Failed to install screen saver: \(error.localizedDescription)")
        }

        checkStatus()
        return false
    }

    /// Opens macOS System Settings Screen Saver / Lock Screen preferences pane.
    public func openScreenSaverSettings() {
        let urlsToTry = [
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        ]

        for urlStr in urlsToTry {
            if let url = URL(string: urlStr) {
                if NSWorkspace.shared.open(url) {
                    return
                }
            }
        }

        // Fallback: open System Settings app
        if let settingsApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settingsApp, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

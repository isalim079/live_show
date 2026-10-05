import Foundation
import AppKit

/// Application delegate managing system lifecycle and teardown.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.app.info("Application did finish launching.")
        AppState.shared.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        AppLogger.app.info("Application will terminate. Releasing wallpaper sessions.")
        AppState.shared.wallpaperManager.tearDownAll()
        SecurityScopedBookmarkManager.shared.stopAccessingAll()
        AppState.shared.store.saveLibrary()
        AppState.shared.store.saveSettings()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.openLibrary()
        }
        return true
    }
}

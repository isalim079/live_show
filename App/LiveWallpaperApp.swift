import SwiftUI
import LiveWallpaperLib

/// Main entry point for the LiveWallpaper macOS application.
/// Implements Section 4 and Section 17 of the specification.
@main
struct LiveWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("LiveWallpaper", systemImage: "sparkles.tv") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Window("LiveWallpaper Library", id: "library") {
            LibraryView()
        }
        .defaultSize(width: 800, height: 560)

        Settings {
            SettingsView()
        }
    }
}

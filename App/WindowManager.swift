import SwiftUI
import AppKit

/// Manages auxiliary windows (Library, Settings, Diagnostics) so they can be summoned
/// from MenuBarExtra or NSApplication menu without stealing focus improperly.
@MainActor
public final class WindowManager {
    public static let shared = WindowManager()

    private var libraryWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?

    private init() {}

    public func openLibrary() {
        if let win = libraryWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LibraryView()
        let win = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "LiveWallpaper Library"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: view)

        self.libraryWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let win = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "LiveWallpaper Settings"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: view)

        self.settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openDiagnostics() {
        if let win = diagnosticsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DiagnosticsView()
        let win = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "LiveWallpaper Diagnostics"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: view)

        self.diagnosticsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

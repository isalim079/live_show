import Foundation
import AppKit

/// Dedicated native borderless window pinned to the macOS desktop level.
/// Strictly implements Section 7 of the specification.
public final class WallpaperWindow: NSWindow {
    public var displayID: String

    public init(screen: NSScreen, displayID: String) {
        self.displayID = displayID

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureDesktopBehavior(screen: screen)
    }

    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.displayID = ""
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    private func configureDesktopBehavior(screen: NSScreen) {
        reassertDesktopBehavior(screen: screen)
    }

    /// Re-applies desktop level, collection behavior, and frame after lock/unlock or WindowServer churn.
    public func reassertDesktopBehavior(screen: NSScreen) {
        // Desktop window level: directly under desktop icons, above system wallpaper
        let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
        self.level = NSWindow.Level(rawValue: desktopLevel)

        // Behavioral attributes
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false

        // Collection behavior for Spaces, Mission Control, and Fullscreen modes
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        // Position accurately on screen
        self.setFrame(screen.frame, display: true)
    }

    // Never steal keyboard or key window status
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Re-anchors and resizes the window when the display geometry changes.
    public func updateGeometry(for screen: NSScreen) {
        self.setFrame(screen.frame, display: true)
    }
}

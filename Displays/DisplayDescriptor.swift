import Foundation
import AppKit

/// Immutable snapshot representing a physical or virtual display.
/// Adheres to Section 6 and Section 8 of the specification.
public struct DisplayDescriptor: Identifiable, Sendable, Hashable, Equatable {
    public let id: String
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let scaleFactor: CGFloat
    public let refreshRate: Double
    public let isBuiltIn: Bool
    public let isPrimary: Bool

    public init(
        id: String,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect,
        scaleFactor: CGFloat,
        refreshRate: Double,
        isBuiltIn: Bool,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scaleFactor = scaleFactor
        self.refreshRate = refreshRate
        self.isBuiltIn = isBuiltIn
        self.isPrimary = isPrimary
    }

    /// User-friendly label (e.g. "MacBook Pro Display (1728x1117 @ 120Hz)")
    public var detailedDescription: String {
        let width = Int(frame.width)
        let height = Int(frame.height)
        let hz = Int(round(refreshRate))
        return "\(name) (\(width)x\(height) @ \(hz)Hz)"
    }
}

extension DisplayDescriptor {
    /// Extracts a stable CGDirectDisplayID from NSScreen.deviceDescription.
    /// Prefer NSNumber.uint32Value — a direct CGDirectDisplayID cast often fails at runtime.
    @MainActor
    public static func cgDisplayID(from screen: NSScreen) -> CGDirectDisplayID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = screen.deviceDescription[screenNumberKey] else { return nil }

        let displayID: CGDirectDisplayID
        if let number = value as? NSNumber {
            displayID = CGDirectDisplayID(number.uint32Value)
        } else if let cast = value as? CGDirectDisplayID {
            displayID = cast
        } else {
            return nil
        }

        return displayID == 0 ? nil : displayID
    }

    /// Constructs a descriptor from an NSScreen instance. Returns nil when the screen ID is invalid.
    @MainActor
    public static func from(screen: NSScreen, isPrimary: Bool = false) -> DisplayDescriptor? {
        guard let displayID = cgDisplayID(from: screen) else {
            AppLogger.display.warning("Skipping NSScreen with invalid NSScreenNumber: \(screen.localizedName)")
            return nil
        }

        let id = String(displayID)
        let name = screen.localizedName
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0

        var refreshRate: Double = 60.0
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            refreshRate = mode.refreshRate
            if refreshRate == 0 {
                // ProMotion displays often report 0 or variable rate
                refreshRate = 120.0
            }
        }

        return DisplayDescriptor(
            id: id,
            name: name,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            scaleFactor: screen.backingScaleFactor,
            refreshRate: refreshRate,
            isBuiltIn: isBuiltIn,
            isPrimary: isPrimary
        )
    }
}

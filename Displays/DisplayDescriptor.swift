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
    /// Constructs a descriptor from an NSScreen instance.
    @MainActor
    public static func from(screen: NSScreen, isPrimary: Bool = false) -> DisplayDescriptor {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = screen.deviceDescription[screenNumberKey] as? CGDirectDisplayID ?? 0
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

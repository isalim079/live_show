import Foundation

/// Represents the assignment of a specific wallpaper to a specific display.
/// Adheres to Section 6 of the specification.
public struct WallpaperAssignment: Identifiable, Codable, Sendable, Hashable {
    public var id: String { displayStableIdentifier }
    public let wallpaperID: UUID
    public let displayStableIdentifier: String
    public var displayName: String
    public var scalingMode: ScalingMode
    public var updatedAt: Date

    public init(
        wallpaperID: UUID,
        displayStableIdentifier: String,
        displayName: String,
        scalingMode: ScalingMode = .fill,
        updatedAt: Date = Date()
    ) {
        self.wallpaperID = wallpaperID
        self.displayStableIdentifier = displayStableIdentifier
        self.displayName = displayName
        self.scalingMode = scalingMode
        self.updatedAt = updatedAt
    }
}

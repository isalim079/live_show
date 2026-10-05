import Foundation
import CoreMedia

/// Extracted technical metadata for a video asset.
public struct VideoMetadata: Sendable {
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let frameRate: Double
    public let hasVideoTrack: Bool
    public let hasAudioTrack: Bool
    public let codec: String

    public init(
        duration: TimeInterval,
        width: Int,
        height: Int,
        frameRate: Double,
        hasVideoTrack: Bool,
        hasAudioTrack: Bool,
        codec: String
    ) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hasVideoTrack = hasVideoTrack
        self.hasAudioTrack = hasAudioTrack
        self.codec = codec
    }
}

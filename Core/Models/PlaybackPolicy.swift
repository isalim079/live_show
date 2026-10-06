import Foundation

/// Video presentation scaling modes.
public enum ScalingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case fill = "Fill / Crop"
    case fit = "Fit / Letterbox"
    case stretch = "Stretch"

    public var id: String { rawValue }
}

/// Explicit playback state machine as defined in Section 21 of the specification.
public enum WallpaperPlaybackState: Sendable, Equatable {
    case stopped
    case loading
    case ready
    case playing
    case paused(reason: PauseReason)
    case failed(error: WallpaperError)

    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .loading: return "Loading..."
        case .ready: return "Ready"
        case .playing: return "Playing"
        case .paused(let reason): return "Paused (\(reason.description))"
        case .failed(let error): return "Failed: \(error.localizedDescription)"
        }
    }
}

/// Reasons why playback can be paused by policy or user.
public enum PauseReason: String, Codable, Sendable, CustomStringConvertible {
    case user = "User"
    case battery = "On Battery Power"
    case displaySleep = "Display Asleep"
    case screenLocked = "Screen Locked"
    case systemSleep = "System Asleep"
    case fullscreenApp = "Fullscreen App"
    case lowPowerMode = "Low Power Mode"

    public var description: String { rawValue }
}

/// System power source state.
public enum PowerSourceState: String, Codable, Sendable {
    case ac = "AC Power"
    case battery = "Battery"
    case unknown = "Unknown"
}

/// Persisted user settings.
public struct LiveWallpaperSettings: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var showMenuBarIcon: Bool
    public var loopVideo: Bool
    public var muteByDefault: Bool
    public var playbackSpeed: Float
    public var volume: Float
    public var pauseOnBattery: Bool
    public var pauseWhenDisplaySleeps: Bool
    public var pauseWhenScreenLocked: Bool
    public var pauseOnFullscreen: Bool
    public var defaultScalingMode: ScalingMode
    public var autoStartPlayback: Bool

    public static let `default` = LiveWallpaperSettings(
        launchAtLogin: false,
        showMenuBarIcon: true,
        loopVideo: true,
        muteByDefault: true,
        playbackSpeed: 1.0,
        volume: 0.0,
        pauseOnBattery: false,
        pauseWhenDisplaySleeps: true,
        pauseWhenScreenLocked: true,
        pauseOnFullscreen: false,
        defaultScalingMode: .fill,
        autoStartPlayback: true
    )
}

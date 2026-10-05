import Foundation

/// Central evaluation engine for deciding wallpaper playback action.
/// Adheres to Section 15 and Section 19 of the specification.
public enum WallpaperPolicy {
    public enum PolicyAction: Equatable {
        case play
        case pause(reason: PauseReason)
        case stop
    }

    public struct Input {
        public let userWantsPlay: Bool
        public let isSystemAsleep: Bool
        public let areScreensAsleep: Bool
        public let isScreenLocked: Bool
        public let powerSource: PowerSourceState
        public let isFullscreenAppActive: Bool
        public let settings: LiveWallpaperSettings

        public init(
            userWantsPlay: Bool,
            isSystemAsleep: Bool,
            areScreensAsleep: Bool,
            isScreenLocked: Bool,
            powerSource: PowerSourceState,
            isFullscreenAppActive: Bool,
            settings: LiveWallpaperSettings
        ) {
            self.userWantsPlay = userWantsPlay
            self.isSystemAsleep = isSystemAsleep
            self.areScreensAsleep = areScreensAsleep
            self.isScreenLocked = isScreenLocked
            self.powerSource = powerSource
            self.isFullscreenAppActive = isFullscreenAppActive
            self.settings = settings
        }
    }

    public static func evaluate(input: Input) -> PolicyAction {
        // 1. User stopped or paused playback
        guard input.userWantsPlay else {
            return .pause(reason: .user)
        }

        // 2. System asleep
        if input.isSystemAsleep {
            return .stop
        }

        // 3. Screens asleep
        if input.areScreensAsleep && input.settings.pauseWhenDisplaySleeps {
            return .pause(reason: .displaySleep)
        }

        // 4. Screen locked
        if input.isScreenLocked && input.settings.pauseWhenScreenLocked {
            return .pause(reason: .screenLocked)
        }

        // 5. Battery power
        if input.powerSource == .battery && input.settings.pauseOnBattery {
            return .pause(reason: .battery)
        }

        // 6. Fullscreen application
        if input.isFullscreenAppActive && input.settings.pauseOnFullscreen {
            return .pause(reason: .fullscreenApp)
        }

        return .play
    }
}

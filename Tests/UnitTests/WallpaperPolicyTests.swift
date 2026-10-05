import XCTest
@testable import LiveWallpaperLib

final class WallpaperPolicyTests: XCTestCase {
    func testNormalPlaybackWhenUserWantsPlayAndNoRestrictions() {
        let input = WallpaperPolicy.Input(
            userWantsPlay: true,
            isSystemAsleep: false,
            areScreensAsleep: false,
            isScreenLocked: false,
            powerSource: .ac,
            isFullscreenAppActive: false,
            settings: .default
        )

        let action = WallpaperPolicy.evaluate(input: input)
        XCTAssertEqual(action, .play)
    }

    func testPauseWhenUserExplicitlyPauses() {
        let input = WallpaperPolicy.Input(
            userWantsPlay: false,
            isSystemAsleep: false,
            areScreensAsleep: false,
            isScreenLocked: false,
            powerSource: .ac,
            isFullscreenAppActive: false,
            settings: .default
        )

        let action = WallpaperPolicy.evaluate(input: input)
        XCTAssertEqual(action, .pause(reason: .user))
    }

    func testStopWhenSystemSleeps() {
        let input = WallpaperPolicy.Input(
            userWantsPlay: true,
            isSystemAsleep: true,
            areScreensAsleep: true,
            isScreenLocked: false,
            powerSource: .ac,
            isFullscreenAppActive: false,
            settings: .default
        )

        let action = WallpaperPolicy.evaluate(input: input)
        XCTAssertEqual(action, .stop)
    }

    func testPauseWhenScreenLockedAndSettingEnabled() {
        var settings = LiveWallpaperSettings.default
        settings.pauseWhenScreenLocked = true

        let input = WallpaperPolicy.Input(
            userWantsPlay: true,
            isSystemAsleep: false,
            areScreensAsleep: false,
            isScreenLocked: true,
            powerSource: .ac,
            isFullscreenAppActive: false,
            settings: settings
        )

        let action = WallpaperPolicy.evaluate(input: input)
        XCTAssertEqual(action, .pause(reason: .screenLocked))
    }

    func testPauseWhenOnBatteryAndSettingEnabled() {
        var settings = LiveWallpaperSettings.default
        settings.pauseOnBattery = true

        let input = WallpaperPolicy.Input(
            userWantsPlay: true,
            isSystemAsleep: false,
            areScreensAsleep: false,
            isScreenLocked: false,
            powerSource: .battery,
            isFullscreenAppActive: false,
            settings: settings
        )

        let action = WallpaperPolicy.evaluate(input: input)
        XCTAssertEqual(action, .pause(reason: .battery))
    }

    func testContinuePlayingOnBatteryWhenSettingDisabled() {
        var settings = LiveWallpaperSettings.default
        settings.pauseOnBattery = false

        let input = WallpaperPolicy.Input(
            userWantsPlay: true,
            isSystemAsleep: false,
            areScreensAsleep: false,
            isScreenLocked: false,
            powerSource: .battery,
            isFullscreenAppActive: false,
            settings: settings
        )

        let action = WallpaperPolicy.evaluate(input: input)
        XCTAssertEqual(action, .play)
    }
}

import XCTest
@testable import LiveWallpaperLib

final class StateMachineTests: XCTestCase {
    func testWallpaperPlaybackStateProperties() {
        let playing = WallpaperPlaybackState.playing
        XCTAssertTrue(playing.isPlaying)
        XCTAssertFalse(playing.isPaused)
        XCTAssertEqual(playing.label, "Playing")

        let paused = WallpaperPlaybackState.paused(reason: .battery)
        XCTAssertFalse(paused.isPlaying)
        XCTAssertTrue(paused.isPaused)
        XCTAssertEqual(paused.label, "Paused (On Battery Power)")

        let stopped = WallpaperPlaybackState.stopped
        XCTAssertFalse(stopped.isPlaying)
        XCTAssertFalse(stopped.isPaused)
        XCTAssertEqual(stopped.label, "Stopped")
    }

    func testWallpaperResolutionLabels() {
        let wp4K = Wallpaper(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), width: 3840, height: 2160)
        XCTAssertEqual(wp4K.resolutionLabel, "4K")

        let wp1080p = Wallpaper(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), width: 1920, height: 1080)
        XCTAssertEqual(wp1080p.resolutionLabel, "1080p")

        let wp1440p = Wallpaper(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), width: 2560, height: 1440)
        XCTAssertEqual(wp1440p.resolutionLabel, "2K / 1440p")
    }

    func testFormattedDuration() {
        let wp = Wallpaper(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), duration: 75.0)
        XCTAssertEqual(wp.formattedDuration, "01:15")

        let wpLong = Wallpaper(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), duration: 3665.0)
        XCTAssertEqual(wpLong.formattedDuration, "1:01:05")
    }
}

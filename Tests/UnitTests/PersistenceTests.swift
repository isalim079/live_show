import XCTest
@testable import LiveWallpaperLib

final class PersistenceTests: XCTestCase {
    func testSerializationRoundTrip() throws {
        let id = UUID()
        let now = Date()
        let wallpaper = Wallpaper(
            id: id,
            fileURL: URL(fileURLWithPath: "/Users/test/video.mp4"),
            bookmarkData: nil,
            title: "Neon City",
            duration: 120.0,
            width: 3840,
            height: 2160,
            frameRate: 60.0,
            fileSize: 104857600,
            createdAt: now,
            updatedAt: now,
            lastPlayedAt: now,
            isAvailable: true,
            thumbnailPath: "/tmp/thumb.jpg"
        )

        let assignment = WallpaperAssignment(
            wallpaperID: id,
            displayStableIdentifier: "display-1",
            displayName: "Main Display",
            scalingMode: .fill,
            updatedAt: now
        )

        let library = LibraryData(
            version: 1,
            wallpapers: [wallpaper],
            assignments: ["display-1": assignment]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(library)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LibraryData.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.wallpapers.count, 1)
        XCTAssertEqual(decoded.wallpapers[0].title, "Neon City")
        XCTAssertEqual(decoded.wallpapers[0].width, 3840)
        XCTAssertEqual(decoded.wallpapers[0].height, 2160)
        XCTAssertEqual(decoded.assignments["display-1"]?.displayName, "Main Display")
    }

    func testDefaultSettings() {
        let settings = LiveWallpaperSettings.default
        XCTAssertTrue(settings.loopVideo)
        XCTAssertTrue(settings.muteByDefault)
        XCTAssertTrue(settings.pauseWhenDisplaySleeps)
        XCTAssertTrue(settings.pauseWhenScreenLocked)
        XCTAssertEqual(settings.defaultScalingMode, .fill)
    }

    @MainActor
    func testAssignmentFallbackAndRemapping() {
        let store = WallpaperStore()
        let id = UUID()
        let oldDisplayID = "1"
        let newDisplayID = "2"
        let displayName = "LG UltraFine"

        store.setAssignment(
            wallpaperID: id,
            forDisplayID: oldDisplayID,
            displayName: displayName,
            scalingMode: .fill
        )

        // 1. Direct match on old ID
        let directMatch = store.assignment(for: oldDisplayID)
        XCTAssertEqual(directMatch?.wallpaperID, id)

        // 2. Remap match by display name when ID shifted
        let nameMatch = store.assignment(for: newDisplayID, displayName: displayName)
        XCTAssertEqual(nameMatch?.wallpaperID, id)

        // 3. Fallback to latest assignment when neither ID nor name match
        let fallbackMatch = store.assignment(for: "999", displayName: "Unknown Screen")
        XCTAssertEqual(fallbackMatch?.wallpaperID, id)
    }
}

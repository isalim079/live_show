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
    func testAssignmentFallbackAndRemapping() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WallpaperStore(baseDirectory: tempDir)
        let id = UUID()
        let oldDisplayID = "test-disp-1"
        let newDisplayID = "test-disp-2"
        let displayName = "LG UltraFine Test Screen"

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
        let fallbackMatch = store.assignment(for: "unknown-disp-999", displayName: "Unknown Screen")
        XCTAssertNotNil(fallbackMatch)
    }

    @MainActor
    func testLockScreenWallpaperPersistenceAndClearance() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WallpaperStore(baseDirectory: tempDir)
        let lockID = UUID()

        // 1. Initial state
        XCTAssertNil(store.lockScreenWallpaperID)

        // 2. Set Lock Screen Wallpaper
        store.setLockScreenWallpaper(id: lockID)
        XCTAssertEqual(store.lockScreenWallpaperID, lockID)

        // 3. Round-trip serialization with lockScreenWallpaperID
        let library = LibraryData(
            version: 1,
            wallpapers: [],
            assignments: [:],
            lockScreenWallpaperID: lockID
        )
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(LibraryData.self, from: data)
        XCTAssertEqual(decoded.lockScreenWallpaperID, lockID)

        // 4. Backward compatibility: JSON without lockScreenWallpaperID
        let legacyJSON = "{\"version\":1,\"wallpapers\":[],\"assignments\":{}}".data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(LibraryData.self, from: legacyJSON)
        XCTAssertNil(legacyDecoded.lockScreenWallpaperID)

        // 5. Explicit clear
        store.clearLockScreenWallpaper()
        XCTAssertNil(store.lockScreenWallpaperID)

        // 6. Automatic clearance when removing wallpaper
        store.setLockScreenWallpaper(id: lockID)
        XCTAssertEqual(store.lockScreenWallpaperID, lockID)
        store.removeWallpaper(id: lockID)
        XCTAssertNil(store.lockScreenWallpaperID)
    }

    func testLockScreenReadinessCalculation() {
        // 1. Linked slot satisfies lock screen readiness
        var readiness = LockScreenReadiness(
            usesAerialPipeline: true,
            aerialAssetPresent: true,
            aerialVideoPresent: true,
            linkedProviderOK: true,
            linkedAssetOK: true,
            idleProviderOK: false,
            idleAssetOK: false,
            desktopProviderOK: false,
            desktopAssetOK: false,
            idleDetail: "Linked Aerial OK",
            aerialAssetID: "TEST-ASSET-1",
            saverInstalled: false,
            codesignOK: true,
            codesignDetail: "OK"
        )
        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.summary, "Ready (Home & Lock Screen)")

        // 2. Both Desktop + Idle matching also satisfies lock screen readiness
        readiness.linkedProviderOK = false
        readiness.linkedAssetOK = false
        readiness.idleProviderOK = true
        readiness.idleAssetOK = true
        readiness.desktopProviderOK = true
        readiness.desktopAssetOK = true
        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.summary, "Ready (Home & Lock Screen)")

        // 3. Mismatched or missing assets fail readiness
        readiness.idleAssetOK = false
        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.summary, "Needs attention")
    }
}

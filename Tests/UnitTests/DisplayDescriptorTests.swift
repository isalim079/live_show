import XCTest
@testable import LiveWallpaperLib

final class DisplayDescriptorTests: XCTestCase {
    func testDisplayDescriptorFormatting() {
        let descriptor = DisplayDescriptor(
            id: "12345",
            name: "Studio Display",
            frame: CGRect(x: 0, y: 0, width: 5120, height: 2880),
            visibleFrame: CGRect(x: 0, y: 0, width: 5120, height: 2855),
            scaleFactor: 2.0,
            refreshRate: 60.0,
            isBuiltIn: false,
            isPrimary: true
        )

        XCTAssertEqual(descriptor.id, "12345")
        XCTAssertEqual(descriptor.name, "Studio Display")
        XCTAssertTrue(descriptor.isPrimary)
        XCTAssertFalse(descriptor.isBuiltIn)
        XCTAssertEqual(descriptor.detailedDescription, "Studio Display (5120x2880 @ 60Hz)")
    }
}

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveWallpaper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LiveWallpaper", targets: ["LiveWallpaper"]),
        .library(name: "LiveWallpaperLib", targets: ["LiveWallpaperLib"])
    ],
    targets: [
        .target(
            name: "LiveWallpaperLib",
            path: ".",
            exclude: [
                "App/LiveWallpaperApp.swift",
                "Tests",
                "Scripts",
                "Resources",
                "ScreenSaver",
                "LiveWallpaper-macOS-Production-README.md",
                "liveShow_v1.0.0.dmg",
                "liveShow_v1.1.0.dmg",
                "liveShow_v1.3.0.dmg",
                "liveShow_windows_v1.1.0.zip",
                "liveShow_windows_v1.3.0.zip",
                "LiveWallpaper.dmg",
                "build",
                "README.md",
                "LICENSE"
            ],
            sources: [
                "App",
                "Core",
                "Displays",
                "System",
                "Video",
                "Wallpaper",
                "Persistence",
                "Features",
                "UI"
            ]
        ),
        .executableTarget(
            name: "LiveWallpaper",
            dependencies: ["LiveWallpaperLib"],
            path: "App",
            exclude: [
                "AppDelegate.swift",
                "AppState.swift",
                "WindowManager.swift"
            ],
            sources: [
                "LiveWallpaperApp.swift"
            ]
        ),
        .testTarget(
            name: "LiveWallpaperTests",
            dependencies: ["LiveWallpaperLib"],
            path: "Tests/UnitTests"
        )
    ]
)

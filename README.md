# LiveWallpaper for macOS

<p align="center">
  <img src="Resources/AppIcon.icns" alt="LiveWallpaper Icon" width="128" height="128" />
</p>

<p align="center">
  <strong>Production-grade, hardware-accelerated live video desktop wallpaper engine for macOS.</strong><br>
  Native Swift & SwiftUI • AVFoundation 60/120 FPS • Multi-Display Topology • Zero Background Battery Drain
</p>

---

## Overview

**LiveWallpaper** is a 100% native macOS application that turns any MP4, MOV, or M4V video into an animated desktop wallpaper. It renders directly behind your desktop icons with hardware-accelerated decoding, providing seamless 60 FPS (and up to 120 FPS ProMotion) playback while automatically managing power consumption.

Unlike web-wrapped or resource-heavy wallpaper tools, LiveWallpaper is engineered with low-level macOS system APIs (`AppKit`, `AVFoundation`, `ServiceManagement`, `IOKit`, and `Combine`), guaranteeing responsive performance, instant sleep/wake recovery, and minimal CPU/GPU usage.

---

## Key Features

- **Multi-Monitor Support**: Automatically detects connected displays, screen resolution changes, and monitor topology. Assign unique wallpapers to each screen or stretch across all displays with 1-click.
- **Buttery Smooth AVFoundation Playback**: Hardware-accelerated decoding (H.264, HEVC / H.265, and ProRes) using dedicated GPU media engines without taxing the CPU.
- **Smart Power Conservation**:
  - Automatically pauses playback when on Battery power (configurable).
  - Automatically pauses when displays go to sleep or screen is locked.
  - Automatically pauses when a fullscreen app or game is active.
  - Instant sleep/wake resume without video frame drops.
- **Desktop Z-Order Integration**: Window level is locked directly behind desktop icons and above the system background image (`desktopIconWindow - 1`), allowing full desktop click-through and normal desktop file interaction.
- **Start on Mac Boot**: Native launch-at-login toggle using Apple's modern `SMAppService` framework.
- **Library Management**:
  - **1-Click Apply**: Direct "Apply to Desktop" button on every card.
  - **Double-Click**: Double-click any wallpaper card to immediately apply.
  - **Active Status Indicator**: Visual green `● ACTIVE` badge on the wallpaper currently running on your desktop.
  - **Security-Scoped Bookmarks**: Sandboxed, zero-copy file referencing—imports external video files without duplicating multi-gigabyte media onto your boot drive.
  - **Asynchronous Thumbnails**: Background thumbnail generation using `AVAssetImageGenerator`.
- **Menu Bar Control Center**:
  - Global status indicator (Active / Paused).
  - Quick Play / Pause toggle.
  - Volume slider and 1-click mute toggle.
  - Connected displays overview and quick shortcut to Library (`⌘L`), Settings (`⌘,`), and Diagnostics.

---

## Installing & Using the DMG

### 1. Download & Mount the DMG
Locate the pre-built installer:
- **`LiveWallpaper.dmg`** in the repository root or download the release DMG from the releases page.
- Double-click `LiveWallpaper.dmg` to mount the disk image.

### 2. Install to Applications
- In the opened window, **drag `LiveWallpaper.app` into the `Applications` folder** shortcut.
- Unmount the DMG by right-clicking it in Finder and selecting **Eject**.

### 3. Launching for the First Time
1. Open **Applications** or launch **LiveWallpaper** from Spotlight (`⌘ Space`).
2. *Note on Gatekeeper (for ad-hoc / self-signed builds)*:
   If macOS displays a message saying *"LiveWallpaper cannot be opened because Apple cannot check it for malicious software"*:
   - Right-click (or Control-click) `LiveWallpaper.app` in `/Applications`.
   - Click **Open**.
   - Click **Open** again in the confirmation prompt. *(You only need to do this once).*

### 4. Setting Your Live Wallpaper
1. Click the **Sparkles TV icon** in your macOS Menu Bar (top right), or open the app to display the **Wallpaper Library** (`⌘L`).
2. Click **"Import Video..."** to select any MP4, MOV, or M4V video from your disk (or use the built-in ambient wallpaper).
3. Click the **"Apply"** button or **double-click the video card** to set it as your live desktop wallpaper!

---

## Building from Source

### Prerequisites
- macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later.
- Xcode 15.0+ or Command Line Tools (`xcode-select --install`).
- Swift 5.9+ compiler.

### 1. Build the Binary
Clone the repository and build using Swift Package Manager:

```bash
git clone https://github.com/your-username/live_show.git
cd live_show

# Compile debug build
swift build

# Or compile optimized release build
swift build -c release
```

### 2. Run the Unit Tests
Verify all 12 test suites covering policy evaluation, display topology, state machines, and persistence:

```bash
swift test
# or run the automated test script
./Scripts/test.sh
```

### 3. Build the Application Bundle (.app)
To package the binary into a signed macOS application bundle:

```bash
./Scripts/build.sh
```
The output bundle will be located at:
```text
build/Release/LiveWallpaper.app
```

### 4. Package and Sign the Release DMG
To generate a compressed, signed, and verified `.dmg` installer with an `/Applications` symlink and quick start guide:

```bash
./Scripts/package-dmg.sh
```
This produces:
- `build/LiveWallpaper-v1.0.0.dmg`
- `LiveWallpaper.dmg` (root convenience copy)

Both are automatically validated using `hdiutil verify` and signed with Hardened Runtime.

---

## Project Architecture

```text
live_show/
├── App/                          # App lifecycle and coordination
│   ├── LiveWallpaperApp.swift    # SwiftUI App entry point
│   ├── AppDelegate.swift         # NSApplicationDelegate lifecycle
│   ├── AppState.swift            # Central coordinator & Combine pipeline
│   └── WindowManager.swift       # Window routing (Library, Settings, Diagnostics)
├── Core/                         # Domain models, errors, utilities
│   ├── Models/                   # Wallpaper, WallpaperAssignment, PlaybackPolicy
│   ├── Utilities/                # FileUtils, SecurityScopedBookmarkManager
│   └── Logging/                  # Structured os.Logger subsystem
├── Displays/                     # Multi-monitor management
│   ├── DisplayDescriptor.swift   # Immutable monitor geometry snapshot
│   └── DisplayManager.swift      # CGDirectDisplay listener & reconciliation
├── Features/                     # Main user interface screens
│   ├── Library/                  # Wallpaper gallery grid, import, 1-click apply
│   ├── Settings/                 # User preferences & power management toggles
│   ├── Diagnostics/              # Real-time hardware, display, and policy inspection
│   └── WallpaperAssignment/      # Per-display assignment manager
├── Persistence/                  # Storage & serialization
│   └── WallpaperStore.swift      # JSON persistence & security-scoped bookmark store
├── Resources/                    # Assets and manifests
│   ├── Info.plist                # App bundle metadata
│   ├── LiveWallpaper.entitlements # Hardened Runtime & Sandbox entitlements
│   ├── AppIcon.icns              # Multi-resolution macOS application icon
│   └── SampleAmbient.mp4         # Bundled default 1080p 60fps ambient loop
├── Scripts/                      # Build, test, and packaging automation
│   ├── build.sh                  # SPM release compile & .app assembly
│   ├── test.sh                   # Unit test execution
│   ├── package-dmg.sh            # Compressed & signed DMG creation
│   └── verify-release.sh         # Security and bundle verification script
├── System/                       # OS event integration
│   ├── PowerStateMonitor.swift   # IOKit AC/Battery power state listener
│   ├── SleepWakeMonitor.swift    # NSWorkspace sleep/wake/lock notifications
│   ├── WorkspaceMonitor.swift    # Fullscreen application detector
│   └── LoginItemManager.swift    # SMAppService "Start on Boot" integration
├── Tests/UnitTests/              # 12 Automated Unit Tests
├── Video/                        # Video decoding & metadata pipeline
│   ├── VideoPlayer.swift         # AVPlayer wrapper with seamless looping
│   ├── MediaValidator.swift      # Asset inspector & codec validation
│   └── ThumbnailGenerator.swift  # Asynchronous thumbnail generator
└── Wallpaper/                    # Desktop window rendering layer
    ├── WallpaperWindow.swift     # Desktop-level pinned NSWindow
    ├── WallpaperContentView.swift# AVPlayerLayer hardware host view
    ├── WallpaperSession.swift    # Per-display playback controller
    ├── WallpaperPolicy.swift     # Smart play/pause state machine
    └── WallpaperManager.swift    # Multi-display session coordinator
```

---

## Supported Media Specifications

| Parameter | Recommended Specification |
| :--- | :--- |
| **Container Formats** | `.mp4`, `.mov`, `.m4v` |
| **Video Codecs** | H.264 (AVC), H.265 (HEVC), Apple ProRes |
| **Resolutions** | 1080p Full HD, 1440p Quad HD, 4K Ultra HD, 5K, 6K |
| **Framerate** | 24 FPS, 30 FPS, 60 FPS, up to 120 FPS ProMotion |
| **Audio** | AAC / PCM (muted by default to avoid desktop interruptions) |

---

## Troubleshooting & FAQ

#### Why does the video stop when I unplug my MacBook?
By default, LiveWallpaper enables smart battery conservation. If you want playback to continue while on battery power, open **Settings** (`⌘,`) and toggle off **"Pause when on Battery"**.

#### Can I have different videos on my MacBook screen and external monitor?
Yes! In the Wallpaper Library, click the display icon next to the Apply button on any wallpaper to assign that video specifically to an individual connected monitor.

#### How do I start the app automatically when my Mac starts?
Click the Menu Bar icon and toggle on **"Start on Mac Boot"**, or enable **"Launch at Login"** in the Settings window.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

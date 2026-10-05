# LiveWallpaper for macOS

Production-grade macOS live video wallpaper application.

The application turns local video files into animated desktop wallpapers while remaining lightweight, stable, secure, and respectful of macOS window management, power management, multiple displays, Spaces, and fullscreen usage.

The core implementation should be native macOS:

- Swift
- SwiftUI for application UI
- AppKit for desktop/window integration
- AVFoundation for video playback
- Core Animation and/or Metal where profiling justifies it
- SwiftData or SQLite for local library metadata
- ServiceManagement for login-item behavior
- Xcode for build, signing, testing, archive, and distribution

Do not build the wallpaper engine around Electron, React Native, or a web browser.

---

## 1. Product Goal

Build a polished macOS application that can:

1. Play local videos as desktop wallpapers.
2. Loop videos seamlessly.
3. Support multiple displays.
4. Allow a different wallpaper per display.
5. Restore wallpaper state after restart or display changes.
6. Start automatically at login when enabled.
7. Pause or reduce activity when appropriate for battery and system power usage.
8. Pause/stop during display sleep or lock.
9. Avoid stealing keyboard focus or normal window interaction.
10. Behave correctly with Spaces, Mission Control, Stage Manager, and fullscreen applications as far as supported by the macOS windowing model.
11. Recover gracefully from malformed, unsupported, or temporarily unavailable media.
12. Provide a clean menu-bar and settings experience.
13. Be distributed as a properly signed and notarized macOS application.

The application must remain useful even when the network is completely unavailable.

---

## 2. Product Principles

### Performance first

Video playback must use Apple's native media stack and hardware-accelerated paths where available.

Do not continuously poll the system when an event/notification is available.

Do not decode frames manually unless a measured product requirement requires it.

### Local-first

The basic product must work with local files.

No account is required for the core wallpaper functionality.

### Safe defaults

Default behavior should favor:

- Lower battery usage
- No unnecessary network activity
- No microphone/camera access
- No elevated privileges
- No unnecessary permissions
- Minimal background work

### Crash-resistant

A corrupt video, removed file, disconnected display, decoder failure, or unexpected media interruption must not crash the application.

### Observable

Important failures should be diagnosable through structured logs without exposing private user data.

---

# 3. Recommended Technology Stack

| Area | Technology |
|---|---|
| Language | Swift |
| UI | SwiftUI |
| Window/Desktop integration | AppKit |
| Video playback | AVFoundation |
| Video presentation | AVPlayerLayer or equivalent native rendering |
| GPU rendering | Core Animation / Metal when justified |
| Persistence | SwiftData or SQLite |
| User preferences | UserDefaults |
| Secure secrets | Keychain |
| Login/startup | ServiceManagement / SMAppService |
| Testing | XCTest + XCUITest |
| Build system | Xcode |
| Distribution | Developer ID + notarization or Mac App Store |
| CI | GitHub Actions or another CI provider running macOS |
| Minimum OS | Choose explicitly; macOS 13+ is a reasonable baseline if SMAppService-based login integration is required |

Apple documents `SMAppService` as the current API for registering login items and related helpers on macOS 13 and later.

References:
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/avfoundation
- https://developer.apple.com/documentation/appkit

---

# 4. High-Level Architecture

```text
                         +----------------------+
                         |      SwiftUI UI      |
                         |----------------------|
                         | Library              |
                         | Settings             |
                         | Wallpaper Picker     |
                         | Display Assignment   |
                         +----------+-----------+
                                    |
                                    v
                         +----------------------+
                         |   Application State  |
                         |----------------------|
                         | Preferences          |
                         | Selected Wallpapers  |
                         | Playback Policies     |
                         +----------+-----------+
                                    |
                                    v
                         +----------------------+
                         | Wallpaper Manager     |
                         |----------------------|
                         | Display lifecycle     |
                         | Wallpaper lifecycle   |
                         | Recovery              |
                         +----------+-----------+
                                    |
              +---------------------+---------------------+
              |                     |                     |
              v                     v                     v
      +---------------+     +---------------+     +---------------+
      | Display #1    |     | Display #2    |     | Display #N    |
      | WallpaperWnd  |     | WallpaperWnd  |     | WallpaperWnd  |
      +-------+-------+     +-------+-------+     +-------+-------+
              |                     |                     |
              v                     v                     v
      +---------------+     +---------------+     +---------------+
      | AVPlayer      |     | AVPlayer      |     | AVPlayer      |
      | AVPlayerItem  |     | AVPlayerItem  |     | AVPlayerItem  |
      +---------------+     +---------------+     +---------------+

                         +----------------------+
                         | System Integration   |
                         |----------------------|
                         | Power                |
                         | Sleep/Wake           |
                         | Lock/Unlock          |
                         | Display changes      |
                         | Space/window changes |
                         | Login Item           |
                         +----------------------+
```

The wallpaper engine must be independent from the SwiftUI settings UI.

The UI should control the engine through well-defined application services rather than manipulating `NSWindow` or `AVPlayer` objects directly.

---

# 5. Repository Structure

Recommended structure:

```text
LiveWallpaper/
├── App/
│   ├── LiveWallpaperApp.swift
│   ├── AppDelegate.swift
│   ├── AppState.swift
│   └── AppEnvironment.swift
│
├── Core/
│   ├── Models/
│   ├── Errors/
│   ├── Logging/
│   ├── Utilities/
│   └── Extensions/
│
├── Wallpaper/
│   ├── WallpaperManager.swift
│   ├── WallpaperSession.swift
│   ├── WallpaperWindow.swift
│   ├── WallpaperContentView.swift
│   ├── WallpaperRenderer.swift
│   └── WallpaperPolicy.swift
│
├── Video/
│   ├── VideoPlayer.swift
│   ├── VideoPlayerFactory.swift
│   ├── VideoAsset.swift
│   ├── VideoMetadata.swift
│   ├── MediaValidator.swift
│   └── ThumbnailGenerator.swift
│
├── Displays/
│   ├── DisplayManager.swift
│   ├── DisplayDescriptor.swift
│   └── DisplayObserver.swift
│
├── System/
│   ├── PowerStateMonitor.swift
│   ├── SleepWakeMonitor.swift
│   ├── LoginItemManager.swift
│   ├── WorkspaceMonitor.swift
│   └── FullscreenPolicy.swift
│
├── Persistence/
│   ├── WallpaperStore.swift
│   ├── WallpaperRepository.swift
│   └── PersistenceModels.swift
│
├── Features/
│   ├── Library/
│   ├── Settings/
│   ├── WallpaperAssignment/
│   └── Onboarding/
│
├── UI/
│   ├── MenuBar/
│   ├── Settings/
│   ├── Library/
│   └── Components/
│
├── Resources/
│   ├── Assets.xcassets
│   ├── Localizable.xcstrings
│   └── Preview Content/
│
├── Tests/
│   ├── UnitTests/
│   ├── IntegrationTests/
│   └── UITests/
│
└── Scripts/
    ├── build.sh
    ├── test.sh
    ├── archive.sh
    ├── notarize.sh
    └── verify-release.sh
```

---

# 6. Core Domain Model

Do not persist `NSScreen`, `NSWindow`, `AVPlayer`, or other runtime objects.

Persist identifiers and configuration instead.

Example model:

```swift
struct Wallpaper {
    let id: UUID
    let fileURL: URL
    let title: String
    let duration: TimeInterval?
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let fileSize: Int64
    let createdAt: Date
    let updatedAt: Date
}
```

Display assignments should be configuration data:

```swift
struct WallpaperAssignment {
    let wallpaperID: UUID
    let displayStableIdentifier: String
    let displayName: String
    let updatedAt: Date
}
```

Do not assume display ordering is stable.

Do not use "Display 1", "Display 2" as persistent identity.

Prefer a display identifier that can be mapped back to the current `NSScreen` where possible.

---

# 7. Wallpaper Window Requirements

The wallpaper window is the most macOS-specific component.

The window should:

- Have no normal title bar or controls.
- Match the target display's visible coordinate space.
- Not become the key application window.
- Not steal focus.
- Ignore mouse input when appropriate.
- Stay behind normal application windows.
- Be removed cleanly when its display disappears.
- Be recreated or resized when display geometry changes.
- Behave correctly across Spaces and supported window-management modes.
- Avoid appearing as a normal user-facing application window.

AppKit provides `NSWindow.Level` and `NSWindow.CollectionBehavior` for controlling window stacking and behavior within Spaces, Mission Control, Stage Manager, and fullscreen-related environments.

Do not hard-code private APIs.

Do not use undocumented window-server hacks.

References:
- https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
- https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.property

---

# 8. Display Management

The `DisplayManager` owns display lifecycle.

Required events:

```text
displayConnected
displayDisconnected
displayGeometryChanged
displayConfigurationChanged
```

When the display topology changes:

1. Read current displays.
2. Reconcile existing wallpaper sessions.
3. Preserve assignments where identity still matches.
4. Apply a safe fallback for newly connected displays.
5. Destroy sessions for removed displays.
6. Never crash because a display disappeared during playback.

Example lifecycle:

```text
Current displays
      |
      v
Diff with previous state
      |
      +---- Added ------> Create WallpaperSession
      |
      +---- Removed ----> Stop + destroy session
      |
      +---- Changed ----> Re-layout session
      |
      v
Persist new state
```

---

# 9. Video Playback Architecture

Each active display should have an isolated playback session.

```text
WallpaperSession
    |
    +-- AVPlayer
    +-- AVPlayerItem
    +-- AVPlayerLayer
    +-- PlaybackState
    +-- WallpaperPolicy
```

The session should own:

- Player setup
- Loading state
- Playback state
- Looping
- Retry behavior
- Media errors
- Cleanup
- Layer/frame updates

Avoid one global `AVPlayer` controlling every display.

---

# 10. Looping

The first production implementation can use a single item with end-of-playback handling.

For more advanced use cases, evaluate:

- `AVQueuePlayer`
- `AVPlayerLooper`

Do not restart playback by repeatedly constructing new players.

The loop implementation must avoid visible black frames or unnecessary decoder reinitialization.

---

# 11. Aspect Ratio and Scaling

Supported modes:

```text
Fill / Crop
Fit / Letterbox
Stretch (optional)
Original size (optional)
```

Default should be:

```text
Fill / Crop
```

No image stretching should occur unless explicitly requested.

4K videos should not be unnecessarily resized multiple times by the application.

---

# 12. Media Validation

Before activating a wallpaper:

1. Confirm the file exists.
2. Confirm the app can read it.
3. Load media metadata.
4. Detect duration.
5. Detect dimensions.
6. Detect nominal frame rate if available.
7. Detect whether the asset contains a playable video track.
8. Fail gracefully for unsupported/corrupt media.

Example failure:

```text
Wallpaper failed to load
    |
    +-- File missing
    +-- Permission denied
    +-- Unsupported codec
    +-- Corrupt asset
    +-- Decoder failure
```

The UI should show a useful error without exposing internal implementation details.

---

# 13. Importing Videos

The app should use a system file picker for explicit user selection.

Do not request broad filesystem access when a user-selected file URL is sufficient.

Store security-scoped bookmarks when persistent access to user-selected files is required.

On application restart:

```text
restore bookmark
      |
      +-- valid ------> use file
      |
      +-- stale ------> attempt repair
      |
      +-- unavailable -> mark wallpaper unavailable
```

Never silently copy multi-gigabyte videos without user intent.

---

# 14. Wallpaper Library

The library should store metadata rather than duplicating video files.

Recommended fields:

```text
id
path/bookmark
title
thumbnail
duration
width
height
frameRate
fileSize
createdAt
updatedAt
lastPlayedAt
isAvailable
```

Generate thumbnails asynchronously.

Do not block the main UI while scanning a large library.

---

# 15. Power Management

A production wallpaper app must not behave like an ordinary foreground video player.

Define a central playback policy:

```text
Power source
Screen state
System sleep state
Lock state
Fullscreen policy
User preference
Wallpaper state
          |
          v
      PlaybackPolicy
          |
          v
Play / Pause / Reduce activity / Stop
```

Example policy:

```text
AC power:
    Normal playback

Battery:
    User configurable:
      - Continue
      - Reduce frame rate
      - Pause

Display asleep:
    Stop/pause playback

System locked:
    Stop/pause playback

Wallpaper disabled:
    Stop playback
```

Avoid implementing power decisions independently in every component.

There must be one policy engine.

---

# 16. Startup / Login Item

Use Apple's ServiceManagement APIs rather than manually writing launch-agent files for normal app startup behavior.

For macOS 13+, `SMAppService` is the supported API for registering login items and related helpers.

The setting should be user-controlled:

```text
Launch at login: ON/OFF
```

The app must reflect the real registration/authorization state.

Do not assume that "enabled in our database" means macOS actually authorized the login item.

Reference:

https://developer.apple.com/documentation/servicemanagement/smappservice

---

# 17. Menu Bar Experience

The application should behave primarily as a menu-bar utility.

Recommended menu:

```text
LiveWallpaper

Current Wallpaper
    Pause
    Resume
    Change Wallpaper

Displays
    MacBook Display
    External Display

Playback
    Mute
    Volume
    Playback Speed

Library
    Open Library
    Import Video

Settings
    Open Settings

Support
    Diagnostics
    About

Quit
```

Keep the menu responsive even when large videos are loading.

---

# 18. Settings

Suggested settings:

### General

```text
Launch at login
Show menu bar icon
Start wallpaper automatically
```

### Playback

```text
Loop video
Mute by default
Playback speed
Battery behavior
Fullscreen behavior
```

### Display

```text
Wallpaper per display
Scaling mode
Default wallpaper
```

### Performance

```text
Pause on battery
Pause when display sleeps
Reduced-motion mode
```

Settings must be persisted atomically and loaded safely when the app starts.

---

# 19. Fullscreen Application Policy

This feature should be treated as a policy layer, not embedded directly into the player.

Possible behavior:

```text
Normal desktop:
    PLAY

Fullscreen application detected:
    PAUSE

Fullscreen application closed:
    RESUME
```

However, exact fullscreen detection can vary across macOS versions and application types.

Therefore:

- Keep this feature optional.
- Test it on real applications.
- Do not depend on undocumented APIs.
- Provide a user setting to disable the behavior.
- Never make fullscreen detection a reason for the entire wallpaper engine to fail.

---

# 20. Spaces / Mission Control / Stage Manager

This requires real-device testing.

Test:

```text
Desktop Space A
Desktop Space B
Mission Control
Stage Manager
Fullscreen app
App switching
Display disconnect/reconnect
Sleep/wake
Login/logout
```

The wallpaper window must not become a normal foreground application window.

Use documented AppKit collection behaviors where appropriate.

Do not assume a configuration that works on one macOS release will behave identically on every future release.

---

# 21. Application State Machine

Use explicit state instead of scattered booleans.

Example:

```text
        +---------+
        | Stopped |
        +----+----+
             |
             v
        +---------+
        | Loading |
        +----+----+
             |
             v
        +---------+
        | Playing |
        +----+----+
         |    |   \
         |    |    \
         v    v     v
      Paused Error  Stopped
         |
         v
      Playing
```

At minimum:

```swift
enum WallpaperPlaybackState {
    case stopped
    case loading
    case ready
    case playing
    case paused
    case failed
}
```

Do not represent this as:

```swift
isPlaying
isLoading
hasError
shouldPause
isReady
...
```

That approach quickly creates impossible combinations.

---

# 22. Concurrency Rules

The main thread must remain responsive.

Use structured concurrency where appropriate.

Recommended rule:

```text
MainActor:
    UI
    NSWindow manipulation
    UI state

Background:
    File scanning
    Metadata extraction
    Thumbnail generation
    Persistence work where appropriate
    Non-UI media preparation

AVFoundation:
    Native media pipeline
```

Never block the main thread on:

- File hashing
- Large folder scans
- Thumbnail generation
- Media metadata over a large library
- Network calls
- Long database migrations

---

# 23. Logging

Use Apple's unified logging system.

Recommended categories:

```text
app
wallpaper
video
display
power
persistence
login
ui
diagnostics
```

Examples:

```text
[display] Added display
[wallpaper] Created session
[video] Loading asset
[video] Playback failed
[power] Entering battery policy
```

Never log:

- User file contents
- Access tokens
- Passwords
- Keychain secrets
- Full security-scoped bookmark data
- Unnecessary personal information

Logs should be useful for diagnostics but safe for support sharing.

---

# 24. Error Handling

Create typed errors.

Example:

```swift
enum WallpaperError: Error {
    case fileMissing
    case accessDenied
    case unsupportedMedia
    case corruptMedia
    case playbackFailed
    case displayUnavailable
    case persistenceFailed
}
```

Every error should have:

- A technical log representation.
- A user-facing message.
- A recovery action where possible.

Example:

```text
Playback failed

"The selected wallpaper could not be played."

[Choose another video]
```

Do not show raw Swift errors or internal stack traces to users.

---

# 25. Recovery Strategy

The wallpaper engine should recover from:

- Display disconnect
- Display reconnect
- Sleep/wake
- Player failure
- File deletion
- File relocation
- Temporary decoding failure
- Settings corruption
- Unexpected application termination

Suggested recovery algorithm:

```text
Failure
  |
  v
Classify error
  |
  +-- temporary --> retry with backoff
  |
  +-- file issue -> mark unavailable
  |
  +-- display issue -> wait for display event
  |
  +-- unrecoverable -> stop session safely
```

Avoid infinite restart loops.

Use bounded retry counts.

---

# 26. Persistence Rules

Application startup should tolerate:

```text
Missing database
Corrupt database
Schema migration
Missing wallpaper file
Stale display assignment
```

If persistence fails:

- Preserve in-memory state.
- Show a diagnostic warning.
- Avoid deleting user data.
- Avoid silently resetting all settings.

Database migrations must be versioned.

---

# 27. Performance Targets

These are engineering targets, not guarantees.

### Startup

Target:

```text
Fast application launch
No large library scan on the main thread
```

### CPU

A static desktop wallpaper should not consume significant CPU when the media pipeline is healthy.

Measure real devices rather than relying on assumptions.

### Memory

Avoid:

- Loading full video files into memory.
- Keeping thumbnails at original resolution.
- Retaining players for displays that no longer exist.

### GPU

The app should make use of native video rendering.

Profile before introducing Metal.

Do not add a custom renderer simply because the app contains video.

---

# 28. Performance Test Matrix

Test at least:

```text
1080p / 30 FPS
1080p / 60 FPS
1440p / 60 FPS
4K / 30 FPS
4K / 60 FPS
```

And:

```text
1 display
2 displays
3+ displays where hardware permits
```

Test both:

```text
Apple Silicon
Intel Mac if supported
```

Test:

```text
AC power
Battery
Sleep/wake
Locked/unlocked
```

Measure:

```text
CPU
GPU
Memory
Frame drops
Startup latency
Video load latency
Playback stability
```

Use Instruments and Xcode's profiling tools.

Do not publish performance claims without measuring them.

---

# 29. Supported Media Strategy

Start with formats that AVFoundation reliably supports on the target macOS versions.

Do not promise universal codec support.

Recommended MVP:

```text
Video container:
    MP4 / MOV

Preferred codecs:
    H.264
    HEVC
```

Then test additional formats before advertising support.

If a format is not supported:

```text
Unsupported video

Please choose a compatible MP4 or MOV file.
```

Do not automatically invoke FFmpeg unless there is a clear product requirement.

Bundling an additional media stack increases:

- Application size
- CPU/memory complexity
- Licensing review
- Security surface
- Update complexity

---

# 30. Security

The application should follow least privilege.

Do not request:

```text
Administrator privileges
Root access
Camera
Microphone
Contacts
Location
```

unless a future product feature genuinely requires them.

Use the macOS sandbox where compatible with the application's architecture.

Use security-scoped bookmarks for persistent access to user-selected files when required.

Use Keychain only for secrets.

Do not store secrets in UserDefaults.

Reference:

https://developer.apple.com/documentation/security/

---

# 31. Hardened Runtime

The release build must use Hardened Runtime.

Do not enable runtime exceptions unless the application actually requires them.

Every exception should have a written reason in the project documentation.

Apple requires Hardened Runtime for apps submitted to the notarization service.

Reference:

https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime

---

# 32. Code Signing

Development:

```text
Apple Development certificate
```

Distribution outside the Mac App Store:

```text
Developer ID Application
```

Do not ship unsigned builds.

Release validation should include:

```bash
codesign --verify --deep --strict --verbose=2 MyApp.app
spctl --assess --type execute --verbose=4 MyApp.app
```

Exact commands may evolve with Apple's tooling; use the current Xcode toolchain.

---

# 33. Notarization

For direct distribution:

```text
Build
  |
  v
Archive
  |
  v
Sign with Developer ID
  |
  v
Create distribution artifact
  |
  v
Submit to Apple Notary Service
  |
  v
Wait for successful result
  |
  v
Staple ticket
  |
  v
Validate Gatekeeper
  |
  v
Publish
```

Apple recommends `notarytool`/current Xcode notarization workflows rather than the older `altool` workflow.

Reference:

https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution

---

# 34. CI/CD

Recommended pipeline:

```text
Pull Request
    |
    +--> Swift build
    +--> Unit tests
    +--> UI tests where practical
    +--> SwiftLint/static checks
    +--> Package validation
    |
    v
Main branch
    |
    +--> Release build
    +--> Code signing
    +--> Archive
    +--> Notarization
    +--> Gatekeeper validation
    +--> Create DMG/ZIP
    +--> Publish release
```

Secrets must never be committed.

Use CI secrets for:

```text
Apple signing credentials
App Store Connect API credentials if needed
Notarization credentials
Release signing assets
```

Prefer short-lived or API-based credentials where supported.

---

# 35. Testing Strategy

## Unit tests

Test:

```text
Playback policy
Display assignment
State transitions
Persistence migrations
Wallpaper selection
Error mapping
Settings validation
Retry logic
```

## Integration tests

Test:

```text
Import video
Create wallpaper session
Load player
Assign to display
Persist assignment
Restore assignment
Display changes
Sleep/wake behavior
```

## UI tests

Test:

```text
Open application
Open library
Import video
Select wallpaper
Change display assignment
Pause playback
Open settings
Enable/disable startup
Quit application
```

## Manual hardware tests

Required.

Automated tests are not enough for:

- Spaces
- Fullscreen behavior
- Display hot-plugging
- Sleep/wake
- GPU/video behavior
- Battery behavior
- Real-world 4K playback

---

# 36. Crash and Hang Testing

Before release, intentionally test:

```text
Delete active wallpaper file
Disconnect active external display
Reconnect display
Close laptop lid
Wake Mac
Lock screen
Unlock screen
Enter fullscreen app
Exit fullscreen
Corrupt wallpaper database
Provide huge video
Provide unsupported video
Terminate app during startup
Terminate app during persistence
Terminate app during playback
```

The expected outcome is graceful recovery, not a crash.

---

# 37. Diagnostics

Include a diagnostics screen that can display:

```text
Application version
Build number
macOS version
Architecture
Display count
Active wallpapers
Video resolution
Video frame rate
Playback state
Power state
Startup setting
Last playback error
```

Do not expose private filesystem information unnecessarily.

Provide:

```text
Copy diagnostics
```

for support.

---

# 38. Analytics and Privacy

Do not add analytics to the MVP unless there is a clear business requirement.

If analytics are eventually added:

- Make the behavior transparent.
- Avoid collecting wallpaper file names or paths.
- Do not upload video files.
- Do not upload personal filesystem information.
- Document collection in the privacy policy.
- Provide appropriate user controls where required.

---

# 39. MVP Scope

The first production-capable milestone should include:

```text
[ ] macOS app
[ ] SwiftUI settings/library UI
[ ] Menu bar app
[ ] Import local MP4/MOV
[ ] Thumbnail generation
[ ] AVPlayer playback
[ ] Looping
[ ] One wallpaper per display
[ ] Multi-monitor support
[ ] Display connect/disconnect recovery
[ ] Pause/resume
[ ] Scaling modes
[ ] Persist selected wallpaper
[ ] Launch at login
[ ] Sleep/wake handling
[ ] Battery policy
[ ] Structured logging
[ ] Error handling
[ ] Unit tests
[ ] Integration tests
[ ] Signed release
[ ] Notarized release
```

Do not add online wallpaper downloads to the MVP.

Do not add accounts to the MVP.

Do not add a server unless a real product requirement appears.

---

# 40. Post-MVP Features

Possible future features:

```text
[ ] Wallpaper playlists
[ ] Scheduled wallpaper changes
[ ] Multiple scenes
[ ] Online wallpaper marketplace
[ ] Download manager
[ ] Cloud synchronization
[ ] Favorites
[ ] Search
[ ] Tags
[ ] Wallpaper metadata editor
[ ] Audio-reactive wallpapers
[ ] Interactive wallpapers
[ ] Desktop/system-color integration
[ ] Remote control
```

Build these only after the local playback engine is stable.

---

# 41. Development Phases

## Phase 0 — Technical Spike

Goal:

```text
One video
One display
Native playback
Desktop wallpaper window
```

Success criteria:

- Video plays.
- Window remains behind normal apps.
- App does not steal focus.
- App can be stopped cleanly.

---

## Phase 1 — Wallpaper Engine

Implement:

```text
WallpaperManager
WallpaperSession
WallpaperWindow
VideoPlayer
DisplayManager
```

Add:

```text
Looping
Display resize
Display reconnect
Playback state
Error recovery
```

---

## Phase 2 — Application UI

Implement:

```text
Menu bar
Library
Settings
Import
Wallpaper assignment
```

---

## Phase 3 — System Integration

Implement:

```text
Login item
Sleep/wake
Power policy
Lock/unlock behavior
Fullscreen policy
Spaces testing
```

---

## Phase 4 — Performance

Measure:

```text
CPU
GPU
RAM
Startup
Frame drops
Multiple displays
4K
Battery usage
```

Optimize only based on profiling.

---

## Phase 5 — Production Hardening

Implement:

```text
Crash handling
Migration safety
Recovery paths
Diagnostics
Structured logs
Release automation
Code signing
Notarization
```

---

# 42. Definition of Done

A release is not production-ready until all of the following are true:

```text
[ ] No known crash in core wallpaper workflow
[ ] No known data-loss issue
[ ] Active wallpaper survives normal sleep/wake
[ ] Display reconnect works
[ ] Missing wallpaper file is handled
[ ] Unsupported media is handled
[ ] Multiple displays work
[ ] Settings persist
[ ] Login item state is correct
[ ] App does not unnecessarily steal focus
[ ] CPU/GPU/memory have been profiled
[ ] Battery behavior has been tested
[ ] Unit tests pass
[ ] Integration tests pass
[ ] UI smoke tests pass
[ ] Release build is signed
[ ] Hardened Runtime is enabled
[ ] Notarization succeeds
[ ] Gatekeeper assessment succeeds
[ ] Release artifact installs on a clean Mac
[ ] Upgrade from the previous release works
[ ] Uninstall leaves the expected user data state
```

---

# 43. Release Checklist

Before publishing:

```text
Version number updated
Build number updated

Changelog reviewed
Known issues reviewed

Debug logging disabled where appropriate
Test data removed
Development endpoints removed
Development entitlements removed
Unused permissions removed

Release archive created
Code signature verified
Hardened Runtime verified
Notarization successful
Ticket stapled
Gatekeeper validation successful

DMG/ZIP tested on a clean machine
Fresh install tested
Upgrade tested
Uninstall tested

Release notes published
```

---

# 44. Engineering Rules

1. Prefer documented Apple APIs.
2. Do not use private macOS APIs.
3. Keep wallpaper rendering separate from UI.
4. Keep all display lifecycle handling in one subsystem.
5. Keep playback policy centralized.
6. Never block the main thread with file or media operations.
7. Persist stable identifiers, not runtime framework objects.
8. Treat every external display as disposable.
9. Treat every media file as untrusted input.
10. Make all failure paths recoverable where practical.
11. Profile before optimizing.
12. Do not add dependencies without a concrete reason.
13. Avoid unnecessary background processes.
14. Minimize permissions.
15. Keep release signing and notarization automated.
16. Test on real Apple Silicon hardware.
17. Test multi-monitor behavior manually.
18. Test sleep/wake manually.
19. Never rely on a single macOS version's behavior for window-management edge cases.
20. Never advertise a feature until it has been tested on the supported macOS versions.

---

# 45. Suggested First Implementation Order

```text
1. Create native macOS Swift project
2. Build basic SwiftUI settings window
3. Implement DisplayManager
4. Implement WallpaperWindow
5. Implement VideoPlayer
6. Play one local video behind the desktop
7. Add looping
8. Add display-specific wallpaper sessions
9. Add import + security-scoped bookmark handling
10. Add persistence
11. Add menu bar
12. Add power/sleep policies
13. Add login item
14. Add recovery logic
15. Add tests
16. Profile performance
17. Add release signing
18. Add notarization
19. Test clean installation
20. Ship first stable release
```

---

# 46. Recommended MVP Architecture

```text
                    App
                     |
             +-------+-------+
             |               |
         SwiftUI          AppKit
             |               |
             |        WallpaperManager
             |               |
             |        +------+------+
             |        |             |
             |   DisplayManager   PowerManager
             |        |
             |   +----+----+
             |   |         |
             | Session   Session
             |   |         |
             | AVPlayer   AVPlayer
             |   |         |
             | Renderer  Renderer
             |
          Persistence
             |
        WallpaperStore
```

The key architectural rule is:

> The UI tells the wallpaper engine what the user wants. The wallpaper engine decides how to manage windows, displays, players, and recovery.

---

# 47. Product Name Placeholder

Until branding is decided, use:

```text
Product name: LiveWallpaper
Bundle identifier: com.yourcompany.livewallpaper
Repository: live-wallpaper-macos
```

Replace these before the first public release.

---

# 48. Official Apple References

Use Apple's documentation as the source of truth for API behavior.

AVFoundation:
https://developer.apple.com/documentation/avfoundation

AppKit:
https://developer.apple.com/documentation/appkit

NSWindow levels:
https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct

NSWindow collection behavior:
https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.property

ServiceManagement / SMAppService:
https://developer.apple.com/documentation/servicemanagement/smappservice

Hardened Runtime:
https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime

Notarization:
https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

Security:
https://developer.apple.com/documentation/security/

---

# 49. Final Engineering Objective

The application should feel like a native macOS utility, not a webpage playing a video in a fullscreen window.

The end result should be:

```text
Fast
Stable
Quiet
Native
Power-aware
Multi-display
Recoverable
Secure
Signed
Notarized
Maintainable
```

The wallpaper itself is the visible feature.

The real engineering challenge is making everything around it behave correctly:
window management, display lifecycle, media lifecycle, power lifecycle, persistence, recovery, security, and distribution.

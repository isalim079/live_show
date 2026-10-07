# Live Show for Windows 10 & 11 (v1.4.0)

High-performance live video wallpaper for Windows. Features per-monitor placement parity with macOS, dual-path shell embedding (supporting Windows 11 24H2+ raised desktop and classic WorkerW), PerMonitorV2 DPI awareness, crash logging, and a top-level Setup window.

## Share / install options

### A) Portable Single-File EXE / Zip
- Standalone portable executable: `liveShow_v1.4.0.exe`
- Portable archive: `liveShow_windows_v1.4.0.zip`

1. Double-click `liveShow_v1.4.0.exe` (or extract `liveShow_windows_v1.4.0.zip` and run).
2. If **SmartScreen** appears: Click **More info → Run anyway** (unsigned builds are normal without an enterprise Authenticode cert).
3. On first launch, the **Setup & Settings** window appears to let you choose your video, configure multi-monitor settings, and opt into starting with Windows.
4. Use the **system tray icon** (near the clock) for complete control:
   - **Setup & Settings…** — open setup and manage video paths
   - **Choose video…** — pick `.mp4`, `.mov`, `.mkv`, `.webm`, etc.
   - **Pause** / **Play**
   - **Apply to all monitors** / per-monitor assignments
   - **Retry desktop embed**
   - **Open logs folder** (`%AppData%\LiveShow\logs\`)
   - **Start with Windows** (opt-in toggle)
   - **Quit**

Settings are saved in `%AppData%\LiveShow\settings.json`.

### B) Installer (Start Menu + Desktop shortcut)

On a Windows PC with [Inno Setup 6](https://jrsoftware.org/isinfo.php):

```powershell
powershell -ExecutionPolicy Bypass -File windows\Scripts\build-release.ps1
# Then open windows\Scripts\LiveShow.iss in Inno Setup Compiler → Build
```

Installer output: `windows\Output\LiveShow_Setup.exe`

## Architecture & How It Works

1. **Top-Level Setup First:** On first run or when requested, a native top-level Setup window manages configuration before desktop attachment, preventing black screen or orphan states.
2. **Dual-Path Desktop Embedding (`DesktopHostService`):**
   - **Windows 11 24H2+ (Raised Desktop):** Attaches as a layered child window under Progman (`WS_EX_NOREDIRECTIONBITMAP`), z-ordered below `SHELLDLL_DefView`.
   - **Classic Windows 10/11:** Attaches to the sibling `WorkerW` spawned behind desktop icons via `0x052C`.
3. **Per-Monitor Host Geometry (`MonitorHost`):**
   - Creates an independent host per physical display with WorkerW-relative coordinate calculation, supporting negative coordinates and mixed DPI scales.
   - Automatically handles dynamic display connect/disconnect/resolution changes via `DisplayTopology`.
4. **Crash Reporting (`CrashLog`):**
   - Global exception handling intercepts UI dispatcher and background task errors, writing logs to `%AppData%\LiveShow\logs\` and alerting the user.

# Live Show for Windows 10 & 11

Portable live video wallpaper. The app attaches a WPF window to the desktop `WorkerW` layer (behind icons) and shows a **system tray** icon for control.

## Share / install options

### A) Portable zip (no install)

1. Unzip `liveShow_windows_v1.3.0.zip` (or copy `windows/Release_Build`).
2. Double-click `LiveWallpaper.exe`.
3. If **SmartScreen** appears: **More info → Run anyway** (unsigned builds are normal without an Authenticode cert).
4. Use the **tray icon** (near the clock):
   - **Choose video…** — pick `.mp4` / `.mov` / `.mkv` / etc.
   - **Pause** / **Play**
   - **Start with Windows** (optional)
   - **Quit**

Settings (last video path, play state) are saved in `%AppData%\LiveShow\settings.json`.

### B) Installer (Start Menu + Desktop shortcut)

On a Windows PC with [Inno Setup 6](https://jrsoftware.org/isinfo.php):

```powershell
powershell -ExecutionPolicy Bypass -File windows\Scripts\build-release.ps1
# Then open windows\Scripts\LiveShow.iss in Inno Setup Compiler → Build
```

Installer output: `windows\Output\LiveShow_Setup.exe`

## Build from source

**Requirements:** Windows 10/11 (recommended) or any OS with .NET 8 SDK + Windows targeting pack; Visual Studio 2022 / Rider optional.

```powershell
powershell -ExecutionPolicy Bypass -File windows\Scripts\build-release.ps1
```

Equivalent command:

```powershell
dotnet publish windows\LiveWallpaper\LiveWallpaper.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -o windows\Release_Build
```

## How it works

1. Find `Progman` and send `0x052C` to spawn a desktop `WorkerW`.
2. `SetParent` attaches the borderless WPF window to that `WorkerW`.
3. `MediaElement` plays the chosen video in a loop behind desktop icons.
4. Tray (`NotifyIcon`) keeps the app discoverable — there is no taskbar button.

## Notes

- This is a focused Windows portable build, not full macOS Live Show feature parity (library UI, lock screen, multi-monitor polish).
- Unsigned EXEs may trigger SmartScreen until a paid Authenticode certificate is used.

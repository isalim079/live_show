# LiveWallpaper for Windows 10 & 11

This is the Windows equivalent of the LiveWallpaper engine. It utilizes the undocumented `0x052C` message sent to `Progman` (Program Manager) to spawn a hidden `WorkerW` window directly behind the desktop icons. We then attach our native WPF window as a child of this `WorkerW` to seamlessly render video wallpapers on the desktop.

## How it Works

1. **Find "Progman"**: We locate the Windows Program Manager.
2. **SendMessageTimeout (0x052C)**: We send a specific message to spawn the background `WorkerW` behind the icons but above the desktop image.
3. **SetParent**: We use the Win32 API to attach our WPF Window containing a `MediaElement` into the newly created `WorkerW`.

## Requirements

- **OS**: Windows 10 or Windows 11
- **Framework**: .NET 8.0 SDK (or adjust `TargetFramework` in the `.csproj` to `net6.0-windows` / `net48`)
- **IDE**: Visual Studio 2022 (Recommended) or JetBrains Rider.

## Setup & Build

1. Open the `LiveWallpaper` folder on your Windows machine.
2. Open `LiveWallpaper.csproj` in Visual Studio (or double click it to generate a solution).
3. Before running, open `MainWindow.xaml.cs` and modify the video path:
   ```csharp
   VideoPlayer.Source = new Uri(@"C:\Path\To\Your\Video.mp4", UriKind.Absolute);
   ```
4. Click **Start** (F5) to run the app. Your desktop background will now be the video!

## Stopping the App

Since the window is rendering behind your desktop icons, it won't appear in the standard taskbar. 
To stop the wallpaper, open **Task Manager** (`Ctrl + Shift + Esc`), find `LiveWallpaper`, and click **End Task**.

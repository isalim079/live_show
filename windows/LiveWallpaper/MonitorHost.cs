using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace LiveWallpaper;

/// <summary>
/// Individual host window dedicated to a single physical monitor.
/// Mirrors macOS WallpaperSession / WallpaperWindow per NSScreen.
/// Translates monitor coordinates into WorkerW-relative space.
/// </summary>
public sealed class MonitorHost : Window
{
    public DisplayInfo Display { get; }
    public IVideoWallpaperPlayer Player { get; }
    private bool _isAttached;

    public MonitorHost(DisplayInfo display)
    {
        Display = display;
        Player = new NativeVideoPlayer();

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Background = System.Windows.Media.Brushes.Black;
        Title = $"Live Show — {display.DisplayName}";

        Content = Player.VisualElement;

        // Position window initially at monitor bounds
        Left = display.Left;
        Top = display.Top;
        Width = display.Width;
        Height = display.Height;
    }

    /// <summary>
    /// Parents this monitor host window to the desktop host (WorkerW or Progman)
    /// and positions it using WorkerW-relative coordinates.
    /// </summary>
    public void AttachAndPosition(DesktopHostService desktopService)
    {
        Show();

        var hwnd = new WindowInteropHelper(this).Handle;
        if (!_isAttached)
        {
            _isAttached = desktopService.AttachWindow(hwnd);
        }

        UpdateGeometry(desktopService.DesktopHostHandle);
    }

    public void UpdateGeometry(IntPtr hostHwnd)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero)
        {
            return;
        }

        int relLeft = Display.Left;
        int relTop = Display.Top;
        int width = Display.Width;
        int height = Display.Height;

        if (hostHwnd != IntPtr.Zero && Win32.GetWindowRect(hostHwnd, out var hostRect))
        {
            // Crucial: WorkerW client coordinates relative to virtual desktop
            relLeft = Display.Left - hostRect.Left;
            relTop = Display.Top - hostRect.Top;
        }

        Left = relLeft;
        Top = relTop;
        Width = width;
        Height = height;

        Win32.SetWindowPos(
            hwnd,
            Win32.HWND_BOTTOM,
            relLeft,
            relTop,
            width,
            height,
            Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW);

        CrashLog.LogInfo($"MonitorHost [{Display.DisplayName}]: Positioned at ({relLeft}, {relTop}) size {width}x{height}.");
    }

    public void LoadVideo(string path, bool autoPlay)
    {
        Player.Load(path, autoPlay);
    }

    public void Play() => Player.Play();
    public void Pause() => Player.Pause();
    public void Stop() => Player.Stop();

    public void CloseAndDispose()
    {
        try
        {
            Player.Stop();
            Player.Dispose();
            Close();
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "MonitorHost.CloseAndDispose");
        }
    }
}

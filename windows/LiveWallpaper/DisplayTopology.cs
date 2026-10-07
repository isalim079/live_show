using System.Runtime.InteropServices;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace LiveWallpaper;

public sealed class DisplayInfo
{
    public string DeviceName { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public Win32.RECT Bounds { get; init; }
    public bool IsPrimary { get; init; }
    public int Index { get; init; }

    public int Width => Bounds.Width;
    public int Height => Bounds.Height;
    public int Left => Bounds.Left;
    public int Top => Bounds.Top;

    public override string ToString() =>
        $"{DisplayName} ({Width}x{Height} at [{Left}, {Top}]){(IsPrimary ? " [Primary]" : "")}";
}

/// <summary>
/// Discovers connected display monitors and notifies on topology changes (connect, disconnect, resolution change).
/// Mirrors macOS DisplayManager.
/// </summary>
public sealed class DisplayTopology : IDisposable
{
    private readonly DispatcherTimer _debounceTimer;
    private bool _disposed;

    public event Action? TopologyChanged;

    public DisplayTopology(Dispatcher dispatcher)
    {
        _debounceTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(1500) // Allow display driver to settle
        };
        _debounceTimer.Tick += OnDebounceTimerTick;

        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
    {
        CrashLog.LogInfo("DisplayTopology: DisplaySettingsChanged detected from OS. Schedulng reconcile...");
        _debounceTimer.Stop();
        _debounceTimer.Start();
    }

    private void OnDebounceTimerTick(object? sender, EventArgs e)
    {
        _debounceTimer.Stop();
        CrashLog.LogInfo("DisplayTopology: Debounce timer fired. Triggering TopologyChanged.");
        TopologyChanged?.Invoke();
    }

    /// <summary>
    /// Enumerates all connected display devices and their virtual screen bounds.
    /// </summary>
    public static List<DisplayInfo> GetConnectedDisplays()
    {
        var result = new List<DisplayInfo>();
        var screens = Forms.Screen.AllScreens;

        for (int i = 0; i < screens.Length; i++)
        {
            var screen = screens[i];
            var bounds = new Win32.RECT
            {
                Left = screen.Bounds.Left,
                Top = screen.Bounds.Top,
                Right = screen.Bounds.Right,
                Bottom = screen.Bounds.Bottom,
            };

            var cleanName = screen.DeviceName
                .Replace(@"\\.\DISPLAY", "Display ")
                .Replace(@"\\.\", "");

            result.Add(new DisplayInfo
            {
                DeviceName = screen.DeviceName,
                DisplayName = string.IsNullOrWhiteSpace(cleanName) ? $"Monitor {i + 1}" : cleanName,
                Bounds = bounds,
                IsPrimary = screen.Primary,
                Index = i,
            });
        }

        return result;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _debounceTimer.Stop();
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
    }
}

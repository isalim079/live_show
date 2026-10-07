using System.Diagnostics;
using System.IO;
using System.Windows;
using Microsoft.Win32;

namespace LiveWallpaper;

public partial class MainWindow : Window
{
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly DesktopHostService _desktopService = new();
    private DisplayTopology? _displayTopology;
    private TrayController? _tray;
    private SetupWindow? _setupWindow;
    private readonly Dictionary<string, MonitorHost> _monitorHosts = new(StringComparer.OrdinalIgnoreCase);
    private bool _allowClose;

    public MainWindow()
    {
        InitializeComponent();
    }

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        CrashLog.LogInfo("MainWindow: Loaded. Initializing tray, topology, and desktop services...");

        SetupTray();
        SetupTopology();

        ApplyStartWithWindows(_settings.StartWithWindows);

        _setupWindow = new SetupWindow(
            _settings,
            onApplyVideo: (path, applyToAll) =>
            {
                if (applyToAll)
                {
                    _settings.SetVideoForAll(path);
                }
                ReconcileMonitorHosts();
            },
            onStartWithWindows: ApplyStartWithWindows);

        var displays = DisplayTopology.GetConnectedDisplays();
        _tray?.UpdateMonitorsList(displays);

        if (!string.IsNullOrWhiteSpace(_settings.VideoPath) && File.Exists(_settings.VideoPath))
        {
            ReconcileMonitorHosts();
        }
        else
        {
            _tray?.ShowBalloon("Live Show", "Welcome! Select a video to start your live wallpaper.");
            _setupWindow.Show();
            _setupWindow.Activate();
        }
    }

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        CleanupAll();
    }

    private void SetupTray()
    {
        var icon = LoadAppIcon();
        _tray = new TrayController(icon);
        _tray.SetPlaying(_settings.IsPlaying);
        _tray.SetApplyToAll(_settings.ApplyToAll);
        _tray.SetStartWithWindows(_settings.StartWithWindows);

        _tray.OpenSetupRequested += () =>
        {
            if (_setupWindow != null)
            {
                _setupWindow.RefreshUI();
                _setupWindow.Show();
                _setupWindow.Activate();
            }
        };

        _tray.ChooseVideoRequested += () => ChooseVideo(targetDevice: null);
        _tray.PausePlayRequested += TogglePausePlay;
        _tray.RetryEmbedRequested += () => ReconcileMonitorHosts(forceReattach: true);
        _tray.QuitRequested += QuitApp;

        _tray.ApplyToAllChanged += applyToAll =>
        {
            _settings.ApplyToAll = applyToAll;
            _settings.Save();
            ReconcileMonitorHosts();
        };

        _tray.AssignMonitorRequested += deviceName => ChooseVideo(targetDevice: deviceName);

        _tray.StartWithWindowsChanged += enabled =>
        {
            _settings.StartWithWindows = enabled;
            _settings.Save();
            ApplyStartWithWindows(enabled);
        };
    }

    private void SetupTopology()
    {
        _displayTopology = new DisplayTopology(Dispatcher);
        _displayTopology.TopologyChanged += () =>
        {
            CrashLog.LogInfo("MainWindow: Display topology change detected. Reconciling monitor hosts...");
            var displays = DisplayTopology.GetConnectedDisplays();
            _tray?.UpdateMonitorsList(displays);
            _setupWindow?.RefreshUI();
            ReconcileMonitorHosts();
        };
    }

    private void ReconcileMonitorHosts(bool forceReattach = false)
    {
        try
        {
            var currentDisplays = DisplayTopology.GetConnectedDisplays();
            var currentDeviceNames = new HashSet<string>(currentDisplays.Select(d => d.DeviceName), StringComparer.OrdinalIgnoreCase);

            // 1. Tear down hosts for monitors that have been disconnected
            var removedKeys = _monitorHosts.Keys.Where(k => !currentDeviceNames.Contains(k)).ToList();
            foreach (var key in removedKeys)
            {
                if (_monitorHosts.TryGetValue(key, out var host))
                {
                    CrashLog.LogInfo($"Tearing down host for disconnected display: {key}");
                    host.CloseAndDispose();
                    _monitorHosts.Remove(key);
                }
            }

            // 2. Create or re-position hosts for active displays
            foreach (var display in currentDisplays)
            {
                if (!_monitorHosts.TryGetValue(display.DeviceName, out var host) || forceReattach)
                {
                    if (host != null)
                    {
                        host.CloseAndDispose();
                        _monitorHosts.Remove(display.DeviceName);
                    }

                    CrashLog.LogInfo($"Creating monitor host for {display.DisplayName} ({display.DeviceName})...");
                    host = new MonitorHost(display);
                    _monitorHosts[display.DeviceName] = host;

                    host.AttachAndPosition(_desktopService);

                    var video = _settings.GetVideoForDisplay(display.DeviceName);
                    if (!string.IsNullOrWhiteSpace(video) && File.Exists(video))
                    {
                        host.LoadVideo(video, autoPlay: _settings.IsPlaying);
                    }
                }
                else
                {
                    // Existing host: update geometry relative to WorkerW/desktop host
                    host.UpdateGeometry(_desktopService.DesktopHostHandle);

                    var video = _settings.GetVideoForDisplay(display.DeviceName);
                    if (!string.IsNullOrWhiteSpace(video) && File.Exists(video) && host.Player.CurrentVideoPath != video)
                    {
                        host.LoadVideo(video, autoPlay: _settings.IsPlaying);
                    }
                }
            }

            _tray?.SetPlaying(_settings.IsPlaying);
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "MainWindow.ReconcileMonitorHosts");
        }
    }

    private void ChooseVideo(string? targetDevice)
    {
        var title = string.IsNullOrWhiteSpace(targetDevice)
            ? "Choose Live Wallpaper Video"
            : $"Choose Video for {targetDevice}";

        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = title,
            Filter = "Video files (*.mp4;*.mov;*.mkv;*.webm;*.avi)|*.mp4;*.mov;*.mkv;*.webm;*.avi|All files (*.*)|*.*",
            CheckFileExists = true,
        };

        if (dialog.ShowDialog() == true)
        {
            if (string.IsNullOrWhiteSpace(targetDevice) || _settings.ApplyToAll)
            {
                _settings.SetVideoForAll(dialog.FileName);
            }
            else
            {
                _settings.SetVideoForDisplay(targetDevice, dialog.FileName);
            }

            _settings.IsPlaying = true;
            _settings.Save();

            ReconcileMonitorHosts();
            _setupWindow?.RefreshUI();
        }
    }

    private void TogglePausePlay()
    {
        _settings.IsPlaying = !_settings.IsPlaying;
        _settings.Save();

        foreach (var host in _monitorHosts.Values)
        {
            if (_settings.IsPlaying)
            {
                host.Play();
            }
            else
            {
                host.Pause();
            }
        }

        _tray?.SetPlaying(_settings.IsPlaying);
    }

    private void QuitApp()
    {
        CrashLog.LogInfo("MainWindow: Quit requested. Shutting down Live Show...");
        _allowClose = true;
        CleanupAll();
        System.Windows.Application.Current.Shutdown();
    }

    private void CleanupAll()
    {
        foreach (var host in _monitorHosts.Values)
        {
            host.CloseAndDispose();
        }
        _monitorHosts.Clear();

        _displayTopology?.Dispose();
        _displayTopology = null;

        _tray?.Dispose();
        _tray = null;

        _setupWindow?.Close();
        _setupWindow = null;
    }

    private static void ApplyStartWithWindows(bool enabled)
    {
        try
        {
            const string appName = "LiveShow";
            string? exePath = Environment.ProcessPath
                ?? Process.GetCurrentProcess().MainModule?.FileName;
            if (string.IsNullOrEmpty(exePath))
            {
                return;
            }

            using var key = Registry.CurrentUser.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                writable: true);
            if (key == null)
            {
                return;
            }

            if (enabled)
            {
                key.SetValue(appName, "\"" + exePath + "\"");
                CrashLog.LogInfo("Registry Run key set for Live Show auto-start.");
            }
            else
            {
                key.DeleteValue(appName, throwOnMissingValue: false);
                key.DeleteValue("LiveWallpaperEngine", throwOnMissingValue: false);
                CrashLog.LogInfo("Registry Run key removed.");
            }
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "MainWindow.ApplyStartWithWindows");
        }
    }

    private static System.Drawing.Icon LoadAppIcon()
    {
        try
        {
            var exePath = Environment.ProcessPath
                ?? Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrEmpty(exePath))
            {
                var associated = System.Drawing.Icon.ExtractAssociatedIcon(exePath);
                if (associated != null)
                {
                    return associated;
                }
            }
        }
        catch
        {
            // Fall through
        }

        var assetPath = Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico");
        if (File.Exists(assetPath))
        {
            return new System.Drawing.Icon(assetPath);
        }

        return System.Drawing.SystemIcons.Application;
    }
}

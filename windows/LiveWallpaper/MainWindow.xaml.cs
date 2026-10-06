using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace LiveWallpaper;

public partial class MainWindow : Window
{
    private readonly AppSettings _settings = AppSettings.Load();
    private TrayController? _tray;
    private bool _isPlaying;
    private bool _allowClose;

    public MainWindow()
    {
        InitializeComponent();
    }

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        AttachToDesktopWorkerW();
        CoverVirtualScreen();
        SetupTray();

        ApplyStartWithWindows(_settings.StartWithWindows);

        if (!string.IsNullOrWhiteSpace(_settings.VideoPath) && File.Exists(_settings.VideoPath))
        {
            LoadVideo(_settings.VideoPath, autoPlay: _settings.IsPlaying);
        }
        else
        {
            _tray?.ShowBalloon("Live Show", "Choose a video from the tray icon to start.");
            // Prompt on first run so the app is usable without editing code.
            Dispatcher.BeginInvoke(new Action(() => ChooseVideo(promptIfCancel: false)));
        }
    }

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (!_allowClose)
        {
            // Closing the wallpaper window would leave a blank WorkerW child; hide instead.
            e.Cancel = true;
            Hide();
            return;
        }

        _tray?.Dispose();
        _tray = null;
    }

    private void SetupTray()
    {
        var icon = LoadAppIcon();
        _tray = new TrayController(icon);
        _tray.SetPlaying(_settings.IsPlaying);
        _tray.SetStartWithWindows(_settings.StartWithWindows);

        _tray.ChooseVideoRequested += () => ChooseVideo(promptIfCancel: true);
        _tray.PausePlayRequested += TogglePausePlay;
        _tray.QuitRequested += QuitApp;
        _tray.StartWithWindowsChanged += enabled =>
        {
            _settings.StartWithWindows = enabled;
            _settings.Save();
            ApplyStartWithWindows(enabled);
        };
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

    private void AttachToDesktopWorkerW()
    {
        IntPtr progman = Win32.FindWindow("Progman", null!);

        IntPtr result = IntPtr.Zero;
        Win32.SendMessageTimeout(
            progman,
            0x052C,
            IntPtr.Zero,
            IntPtr.Zero,
            Win32.SendMessageTimeoutFlags.SMTO_NORMAL,
            1000,
            out result);

        IntPtr workerw = IntPtr.Zero;
        Win32.EnumWindows((tophandle, _) =>
        {
            IntPtr shellView = Win32.FindWindowEx(tophandle, IntPtr.Zero, "SHELLDLL_DefView", null!);
            if (shellView != IntPtr.Zero)
            {
                workerw = Win32.FindWindowEx(IntPtr.Zero, tophandle, "WorkerW", null!);
            }

            return true;
        }, IntPtr.Zero);

        IntPtr windowHandle = new WindowInteropHelper(this).Handle;
        if (workerw != IntPtr.Zero)
        {
            Win32.SetParent(windowHandle, workerw);
        }
    }

    private void CoverVirtualScreen()
    {
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;
    }

    private void ChooseVideo(bool promptIfCancel)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Choose a video wallpaper",
            Filter = "Video files|*.mp4;*.mov;*.mkv;*.avi;*.wmv;*.webm|All files|*.*",
            CheckFileExists = true,
        };

        if (!string.IsNullOrWhiteSpace(_settings.VideoPath))
        {
            try
            {
                dialog.InitialDirectory = Path.GetDirectoryName(_settings.VideoPath);
                dialog.FileName = Path.GetFileName(_settings.VideoPath);
            }
            catch
            {
                // Ignore bad persisted paths
            }
        }

        if (dialog.ShowDialog() == true)
        {
            LoadVideo(dialog.FileName, autoPlay: true);
            return;
        }

        if (promptIfCancel && string.IsNullOrWhiteSpace(_settings.VideoPath))
        {
            _tray?.ShowBalloon("Live Show", "No video selected. Use Choose video… from the tray.");
        }
    }

    private void LoadVideo(string path, bool autoPlay)
    {
        if (!File.Exists(path))
        {
            Forms.MessageBox.Show(
                $"Video not found:\n{path}",
                "Live Show",
                Forms.MessageBoxButtons.OK,
                Forms.MessageBoxIcon.Warning);
            return;
        }

        try
        {
            VideoPlayer.Stop();
            VideoPlayer.Source = new Uri(path, UriKind.Absolute);
            PlaceholderText.Visibility = Visibility.Collapsed;

            _settings.VideoPath = path;
            _settings.IsPlaying = autoPlay;
            _settings.Save();

            if (autoPlay)
            {
                VideoPlayer.Play();
                _isPlaying = true;
            }
            else
            {
                VideoPlayer.Pause();
                _isPlaying = false;
            }

            _tray?.SetPlaying(_isPlaying);
        }
        catch (Exception ex)
        {
            Forms.MessageBox.Show(
                $"Could not play video:\n{ex.Message}",
                "Live Show",
                Forms.MessageBoxButtons.OK,
                Forms.MessageBoxIcon.Error);
        }
    }

    private void TogglePausePlay()
    {
        if (VideoPlayer.Source == null)
        {
            ChooseVideo(promptIfCancel: true);
            return;
        }

        if (_isPlaying)
        {
            VideoPlayer.Pause();
            _isPlaying = false;
        }
        else
        {
            VideoPlayer.Play();
            _isPlaying = true;
        }

        _settings.IsPlaying = _isPlaying;
        _settings.Save();
        _tray?.SetPlaying(_isPlaying);
    }

    private void QuitApp()
    {
        _allowClose = true;
        try
        {
            VideoPlayer.Stop();
        }
        catch
        {
            // Ignore
        }

        _tray?.Dispose();
        _tray = null;
        System.Windows.Application.Current.Shutdown();
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
            }
            else
            {
                key.DeleteValue(appName, throwOnMissingValue: false);
                // Remove legacy key from earlier prototype builds
                key.DeleteValue("LiveWallpaperEngine", throwOnMissingValue: false);
            }
        }
        catch
        {
            // Ignore permissions/registry errors
        }
    }

    private void VideoPlayer_MediaEnded(object sender, RoutedEventArgs e)
    {
        VideoPlayer.Position = TimeSpan.Zero;
        if (_isPlaying)
        {
            VideoPlayer.Play();
        }
    }

    private void VideoPlayer_MediaOpened(object sender, RoutedEventArgs e)
    {
        PlaceholderText.Visibility = Visibility.Collapsed;
    }

    private void VideoPlayer_MediaFailed(object sender, ExceptionRoutedEventArgs e)
    {
        PlaceholderText.Text = "Could not play this video.\nTry another file from the tray menu.";
        PlaceholderText.Visibility = Visibility.Visible;
        _tray?.ShowBalloon("Live Show", "Playback failed. Choose another video.");
    }
}

using System.IO;
using System.Windows;
using Microsoft.Win32;

namespace LiveWallpaper;

public partial class SetupWindow : Window
{
    private readonly AppSettings _settings;
    private readonly Action<string, bool> _onApplyVideo;
    private readonly Action<bool> _onStartWithWindows;

    public SetupWindow(
        AppSettings settings,
        Action<string, bool> onApplyVideo,
        Action<bool> onStartWithWindows)
    {
        _settings = settings;
        _onApplyVideo = onApplyVideo;
        _onStartWithWindows = onStartWithWindows;

        InitializeComponent();
        RefreshUI();
    }

    public void RefreshUI()
    {
        TxtVideoPath.Text = string.IsNullOrWhiteSpace(_settings.VideoPath)
            ? "No video selected"
            : _settings.VideoPath;

        var displays = DisplayTopology.GetConnectedDisplays();
        var displaySummary = displays.Count switch
        {
            0 => "No displays detected",
            1 => $"1 Monitor: {displays[0]}",
            _ => $"{displays.Count} Monitors detected:\n" + string.Join("\n", displays.Select(d => $"• {d}"))
        };
        TxtDisplays.Text = displaySummary;

        ChkApplyToAll.IsChecked = _settings.ApplyToAll;
        ChkStartWithWindows.IsChecked = _settings.StartWithWindows;
    }

    private void BtnBrowse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Choose Live Wallpaper Video",
            Filter = "Video files (*.mp4;*.mov;*.mkv;*.webm;*.avi)|*.mp4;*.mov;*.mkv;*.webm;*.avi|All files (*.*)|*.*",
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
                // Ignore invalid persisted directories
            }
        }

        if (dialog.ShowDialog(this) == true)
        {
            _settings.VideoPath = dialog.FileName;
            _settings.Save();
            RefreshUI();
        }
    }

    private void ChkApplyToAll_Changed(object sender, RoutedEventArgs e)
    {
        _settings.ApplyToAll = ChkApplyToAll.IsChecked == true;
        _settings.Save();
    }

    private void ChkStartWithWindows_Changed(object sender, RoutedEventArgs e)
    {
        var isChecked = ChkStartWithWindows.IsChecked == true;
        _settings.StartWithWindows = isChecked;
        _settings.Save();
        _onStartWithWindows?.Invoke(isChecked);
    }

    private void BtnApply_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_settings.VideoPath) || !File.Exists(_settings.VideoPath))
        {
            BtnBrowse_Click(sender, e);
            return;
        }

        _onApplyVideo?.Invoke(_settings.VideoPath, _settings.ApplyToAll);
        Hide();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e)
    {
        Hide();
    }

    private void BtnOpenLogs_Click(object sender, RoutedEventArgs e)
    {
        CrashLog.OpenLogFolder();
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // Keep process running in tray when user closes the setup window
        e.Cancel = true;
        Hide();
    }
}

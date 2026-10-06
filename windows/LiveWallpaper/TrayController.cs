using System.Drawing;
using System.Windows.Forms;

namespace LiveWallpaper;

/// <summary>
/// System tray shell so the hidden WorkerW wallpaper window stays discoverable.
/// </summary>
public sealed class TrayController : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _pausePlayItem;
    private readonly ToolStripMenuItem _startWithWindowsItem;
    private bool _disposed;

    public event Action? ChooseVideoRequested;
    public event Action? PausePlayRequested;
    public event Action? QuitRequested;
    public event Action<bool>? StartWithWindowsChanged;

    public TrayController(Icon icon)
    {
        _pausePlayItem = new ToolStripMenuItem("Pause", null, (_, _) => PausePlayRequested?.Invoke());
        _startWithWindowsItem = new ToolStripMenuItem("Start with Windows", null, OnStartWithWindowsClicked)
        {
            CheckOnClick = true,
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("Choose video…", null, (_, _) => ChooseVideoRequested?.Invoke()));
        menu.Items.Add(_pausePlayItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_startWithWindowsItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => QuitRequested?.Invoke()));

        _notifyIcon = new NotifyIcon
        {
            Icon = icon,
            Text = "Live Show",
            Visible = true,
            ContextMenuStrip = menu,
        };

        _notifyIcon.DoubleClick += (_, _) => ChooseVideoRequested?.Invoke();
    }

    public void SetPlaying(bool isPlaying)
    {
        _pausePlayItem.Text = isPlaying ? "Pause" : "Play";
    }

    public void SetStartWithWindows(bool enabled)
    {
        _startWithWindowsItem.Checked = enabled;
    }

    public void ShowBalloon(string title, string text)
    {
        try
        {
            _notifyIcon.BalloonTipTitle = title;
            _notifyIcon.BalloonTipText = text;
            _notifyIcon.ShowBalloonTip(3000);
        }
        catch
        {
            // Balloon tips are optional
        }
    }

    private void OnStartWithWindowsClicked(object? sender, EventArgs e)
    {
        StartWithWindowsChanged?.Invoke(_startWithWindowsItem.Checked);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }
}

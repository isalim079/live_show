using System.Drawing;
using System.Windows.Forms;

namespace LiveWallpaper;

/// <summary>
/// System tray controller providing full control plane: Setup window, video selection,
/// pause/play, multi-monitor configuration, retry embed, log access, and quit.
/// </summary>
public sealed class TrayController : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _pausePlayItem;
    private readonly ToolStripMenuItem _applyToAllItem;
    private readonly ToolStripMenuItem _monitorsSubmenu;
    private readonly ToolStripMenuItem _startWithWindowsItem;
    private bool _disposed;

    public event Action? OpenSetupRequested;
    public event Action? ChooseVideoRequested;
    public event Action? PausePlayRequested;
    public event Action? RetryEmbedRequested;
    public event Action? OpenLogsRequested;
    public event Action? QuitRequested;
    public event Action<bool>? ApplyToAllChanged;
    public event Action<string>? AssignMonitorRequested;
    public event Action<bool>? StartWithWindowsChanged;

    public TrayController(Icon icon)
    {
        _pausePlayItem = new ToolStripMenuItem("Pause", null, (_, _) => PausePlayRequested?.Invoke());

        _applyToAllItem = new ToolStripMenuItem("Apply to all monitors", null, (sender, _) =>
        {
            if (sender is ToolStripMenuItem item)
            {
                ApplyToAllChanged?.Invoke(item.Checked);
            }
        })
        {
            CheckOnClick = true,
            Checked = true,
        };

        _monitorsSubmenu = new ToolStripMenuItem("Monitors");

        _startWithWindowsItem = new ToolStripMenuItem("Start with Windows", null, (sender, _) =>
        {
            if (sender is ToolStripMenuItem item)
            {
                StartWithWindowsChanged?.Invoke(item.Checked);
            }
        })
        {
            CheckOnClick = true,
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("Setup & Settings…", null, (_, _) => OpenSetupRequested?.Invoke()));
        menu.Items.Add(new ToolStripMenuItem("Choose video…", null, (_, _) => ChooseVideoRequested?.Invoke()));
        menu.Items.Add(_pausePlayItem);
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(_applyToAllItem);
        menu.Items.Add(_monitorsSubmenu);
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem("Retry desktop embed", null, (_, _) => RetryEmbedRequested?.Invoke()));
        menu.Items.Add(new ToolStripMenuItem("Open logs folder", null, (_, _) =>
        {
            OpenLogsRequested?.Invoke();
            CrashLog.OpenLogFolder();
        }));
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

        _notifyIcon.DoubleClick += (_, _) => OpenSetupRequested?.Invoke();
    }

    public void SetPlaying(bool isPlaying)
    {
        _pausePlayItem.Text = isPlaying ? "Pause" : "Play";
    }

    public void SetApplyToAll(bool applyToAll)
    {
        _applyToAllItem.Checked = applyToAll;
    }

    public void SetStartWithWindows(bool enabled)
    {
        _startWithWindowsItem.Checked = enabled;
    }

    public void UpdateMonitorsList(IEnumerable<DisplayInfo> displays)
    {
        _monitorsSubmenu.DropDownItems.Clear();
        foreach (var d in displays)
        {
            var item = new ToolStripMenuItem($"{d.DisplayName} ({d.Width}x{d.Height})", null, (_, _) =>
            {
                AssignMonitorRequested?.Invoke(d.DeviceName);
            });
            _monitorsSubmenu.DropDownItems.Add(item);
        }
    }

    public void ShowBalloon(string title, string text, ToolTipIcon icon = ToolTipIcon.Info)
    {
        try
        {
            _notifyIcon.BalloonTipTitle = title;
            _notifyIcon.BalloonTipText = text;
            _notifyIcon.BalloonTipIcon = icon;
            _notifyIcon.ShowBalloonTip(3000);
        }
        catch
        {
            // Balloon notifications are best-effort
        }
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

using System.Diagnostics;
using System.Windows.Threading;

namespace LiveWallpaper;

public enum DesktopAttachState
{
    NotAttached,
    AttachedClassicWorkerW,
    AttachedRaisedDesktop,
    Fallback
}

/// <summary>
/// Dual-path desktop shell attachment service.
/// Supports both classic Windows 10/11 sibling WorkerW (0x052C)
/// and modern Windows 11 24H2+ raised desktop (layered child under Progman).
/// </summary>
public sealed class DesktopHostService
{
    public DesktopAttachState CurrentState { get; private set; } = DesktopAttachState.NotAttached;
    public IntPtr DesktopHostHandle { get; private set; } = IntPtr.Zero;

    public event Action<DesktopAttachState>? StateChanged;

    /// <summary>
    /// Attempts immediate desktop embed. Returns true if attached to a valid desktop host.
    /// </summary>
    public bool AttachWindow(IntPtr childHwnd)
    {
        if (childHwnd == IntPtr.Zero)
        {
            return false;
        }

        var (hostHwnd, state) = FindDesktopHost();

        if (hostHwnd != IntPtr.Zero && state != DesktopAttachState.Fallback)
        {
            try
            {
                // Ensure the child window has the appropriate styles for embedding
                var curStyle = (long)Win32.GetWindowLongPtr(childHwnd, Win32.GWL_STYLE);
                var newStyle = (curStyle & ~Win32.WS_POPUP) | Win32.WS_CHILD;
                Win32.SetWindowLongPtr(childHwnd, Win32.GWL_STYLE, (IntPtr)newStyle);

                var parentResult = Win32.SetParent(childHwnd, hostHwnd);
                if (parentResult != IntPtr.Zero)
                {
                    DesktopHostHandle = hostHwnd;
                    CurrentState = state;

                    if (state == DesktopAttachState.AttachedRaisedDesktop)
                    {
                        // On Win11 raised desktop, layered window attribute with alpha 0xFF is required
                        var curEx = (long)Win32.GetWindowLongPtr(childHwnd, Win32.GWL_EXSTYLE);
                        Win32.SetWindowLongPtr(childHwnd, Win32.GWL_EXSTYLE, (IntPtr)(curEx | Win32.WS_EX_LAYERED));
                        Win32.SetLayeredWindowAttributes(childHwnd, 0, 255, Win32.LWA_ALPHA);
                    }

                    // Position at the bottom of the z-order
                    Win32.SetWindowPos(
                        childHwnd,
                        Win32.HWND_BOTTOM,
                        0, 0, 0, 0,
                        Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW);

                    CrashLog.LogInfo($"Successfully embedded into desktop host 0x{hostHwnd:X} using {state}.");
                    StateChanged?.Invoke(CurrentState);
                    return true;
                }
            }
            catch (Exception ex)
            {
                CrashLog.LogException(ex, "DesktopHostService.AttachWindow");
            }
        }

        CurrentState = DesktopAttachState.Fallback;
        CrashLog.LogWarning("DesktopHostService: Could not attach to desktop; entering fallback mode.");
        StateChanged?.Invoke(CurrentState);
        return false;
    }

    /// <summary>
    /// Schedules multi-pass retries at 0.5s, 1.5s, and 3.0s if initial attach fails.
    /// </summary>
    public void AttachWithRetries(
        IntPtr childHwnd,
        Dispatcher dispatcher,
        Action<bool>? onComplete = null)
    {
        if (AttachWindow(childHwnd))
        {
            onComplete?.Invoke(true);
            return;
        }

        var delays = new[] { 500, 1500, 3000 };
        var attempt = 0;

        void ScheduleNext()
        {
            if (attempt >= delays.Length)
            {
                onComplete?.Invoke(false);
                return;
            }

            var delay = delays[attempt++];
            var timer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher)
            {
                Interval = TimeSpan.FromMilliseconds(delay)
            };

            timer.Tick += (sender, args) =>
            {
                timer.Stop();
                if (AttachWindow(childHwnd))
                {
                    onComplete?.Invoke(true);
                }
                else
                {
                    ScheduleNext();
                }
            };
            timer.Start();
        }

        ScheduleNext();
    }

    private static (IntPtr Host, DesktopAttachState State) FindDesktopHost()
    {
        IntPtr progman = Win32.FindWindow("Progman", null);
        if (progman == IntPtr.Zero)
        {
            return (IntPtr.Zero, DesktopAttachState.Fallback);
        }

        // Trigger WorkerW spawn via message 0x052C
        IntPtr result = IntPtr.Zero;
        Win32.SendMessageTimeout(
            progman,
            0x052C,
            new IntPtr(0x0000000D),
            new IntPtr(0),
            Win32.SendMessageTimeoutFlags.SMTO_NORMAL,
            1000,
            out result);

        // Check if Progman has raised desktop / no redirection bitmap (Win11 24H2+)
        var progmanExStyle = (long)Win32.GetWindowLongPtr(progman, Win32.GWL_EXSTYLE);
        bool isRaisedDesktop = (progmanExStyle & Win32.WS_EX_NOREDIRECTIONBITMAP) != 0;

        IntPtr workerW = IntPtr.Zero;
        IntPtr defViewParent = IntPtr.Zero;

        // Enumerate top-level windows to locate SHELLDLL_DefView and WorkerW
        Win32.EnumWindows((topHandle, _) =>
        {
            IntPtr shellView = Win32.FindWindowEx(topHandle, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (shellView != IntPtr.Zero)
            {
                defViewParent = topHandle;
                // Look for WorkerW immediately following this window
                workerW = Win32.FindWindowEx(IntPtr.Zero, topHandle, "WorkerW", null);
            }
            return true;
        }, IntPtr.Zero);

        // Path A: Win11 Raised desktop (DefView is directly inside Progman, or WorkerW is inside Progman)
        if (isRaisedDesktop || workerW == IntPtr.Zero)
        {
            // If Progman hosts DefView directly, Progman or its child is the host
            IntPtr progmanDefView = Win32.FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (progmanDefView != IntPtr.Zero || isRaisedDesktop)
            {
                CrashLog.LogInfo("DesktopHostService: Detected Windows 11 raised desktop mode.");
                return (progman, DesktopAttachState.AttachedRaisedDesktop);
            }
        }

        // Path B: Classic sibling WorkerW
        if (workerW != IntPtr.Zero)
        {
            CrashLog.LogInfo("DesktopHostService: Detected classic sibling WorkerW.");
            return (workerW, DesktopAttachState.AttachedClassicWorkerW);
        }

        // Fallback: If defViewParent is valid, attempt to use defViewParent
        if (defViewParent != IntPtr.Zero)
        {
            return (defViewParent, DesktopAttachState.AttachedClassicWorkerW);
        }

        return (progman, DesktopAttachState.AttachedClassicWorkerW);
    }
}

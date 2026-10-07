using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace LiveWallpaper;

public partial class App : System.Windows.Application
{
    private static bool _hasShownCrashDialog = false;

    protected override void OnStartup(StartupEventArgs e)
    {
        InstallGlobalExceptionHandlers();

        base.OnStartup(e);

        CrashLog.LogInfo("Live Show Windows application starting...");

        // Ensure WinForms visual styles for tray menus and message boxes look native.
        Forms.Application.EnableVisualStyles();
        Forms.Application.SetCompatibleTextRenderingDefault(false);
    }

    private void InstallGlobalExceptionHandlers()
    {
        // 1. Dispatcher / UI thread exceptions
        DispatcherUnhandledException += (sender, args) =>
        {
            CrashLog.LogException(args.Exception, "DispatcherUnhandledException");
            ShowCrashAlertOnce(args.Exception);
            args.Handled = true; // Prevent silent process death if recoverable
        };

        // 2. Non-UI / background thread exceptions
        AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
        {
            if (args.ExceptionObject is Exception ex)
            {
                CrashLog.LogException(ex, "AppDomain.CurrentDomain.UnhandledException");
                ShowCrashAlertOnce(ex);
            }
            else
            {
                CrashLog.LogError($"Unhandled non-exception object: {args.ExceptionObject}");
            }
        };

        // 3. Unobserved task exceptions
        TaskScheduler.UnobservedTaskException += (sender, args) =>
        {
            CrashLog.LogException(args.Exception, "TaskScheduler.UnobservedTaskException");
            args.SetObserved();
        };
    }

    private static void ShowCrashAlertOnce(Exception ex)
    {
        if (_hasShownCrashDialog)
        {
            return;
        }

        _hasShownCrashDialog = true;

        var logPath = CrashLog.CurrentLogPath;
        var message = $"Live Show encountered an unexpected error:\n\n{ex.Message}\n\n" +
                      $"Details have been written to:\n{logPath}\n\n" +
                      "Would you like to open the logs folder?";

        var result = Forms.MessageBox.Show(
            message,
            "Live Show — Error",
            Forms.MessageBoxButtons.YesNo,
            Forms.MessageBoxIcon.Error);

        if (result == Forms.DialogResult.Yes)
        {
            CrashLog.OpenLogFolder();
        }
    }
}

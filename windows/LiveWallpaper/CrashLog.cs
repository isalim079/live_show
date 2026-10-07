using System.Diagnostics;
using System.IO;

namespace LiveWallpaper;

/// <summary>
/// Thread-safe file logger for crash reporting and runtime diagnostics.
/// Writes to %AppData%\LiveShow\logs\crash-YYYYMMDD.log.
/// </summary>
public static class CrashLog
{
    private static readonly object FileLock = new();

    public static string LogDirectory =>
        Path.Combine(AppSettings.SettingsDirectory, "logs");

    public static string CurrentLogPath
    {
        get
        {
            var fileName = $"crash-{DateTime.UtcNow:yyyyMMdd}.log";
            return Path.Combine(LogDirectory, fileName);
        }
    }

    public static void LogInfo(string message)
    {
        WriteEntry("INFO", message);
    }

    public static void LogWarning(string message)
    {
        WriteEntry("WARN", message);
    }

    public static void LogError(string message)
    {
        WriteEntry("ERROR", message);
    }

    public static void LogException(Exception ex, string context = "")
    {
        var text = string.IsNullOrWhiteSpace(context)
            ? $"{ex.GetType().FullName}: {ex.Message}\n{ex.StackTrace}"
            : $"[{context}] {ex.GetType().FullName}: {ex.Message}\n{ex.StackTrace}";

        if (ex.InnerException != null)
        {
            text += $"\nInner Exception: {ex.InnerException.GetType().FullName}: {ex.InnerException.Message}\n{ex.InnerException.StackTrace}";
        }

        WriteEntry("EXCEPTION", text);
    }

    private static void WriteEntry(string level, string message)
    {
        try
        {
            lock (FileLock)
            {
                Directory.CreateDirectory(LogDirectory);
                var timestamp = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss.fff");
                var line = $"[{timestamp}] [{level}] {message}{Environment.NewLine}";
                File.AppendAllText(CurrentLogPath, line);
            }
        }
        catch
        {
            // Logging failure must never crash the process
        }
    }

    public static void OpenLogFolder()
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            Process.Start(new ProcessStartInfo
            {
                FileName = LogDirectory,
                UseShellExecute = true,
            });
        }
        catch
        {
            // Ignore explorer launch issues
        }
    }
}

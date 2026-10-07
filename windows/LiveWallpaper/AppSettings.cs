using System.IO;
using System.Text.Json;

namespace LiveWallpaper;

/// <summary>
/// Persists user preferences and multi-monitor assignments under %AppData%\LiveShow\settings.json.
/// </summary>
public sealed class AppSettings
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    public string? VideoPath { get; set; }
    public Dictionary<string, string> Assignments { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public bool ApplyToAll { get; set; } = true;
    public bool IsPlaying { get; set; } = true;
    public bool StartWithWindows { get; set; }

    public static string SettingsDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "LiveShow");

    public static string SettingsPath => Path.Combine(SettingsDirectory, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
                if (settings != null)
                {
                    settings.Assignments ??= new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    return settings;
                }
            }
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "AppSettings.Load");
        }

        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(SettingsDirectory);
            var json = JsonSerializer.Serialize(this, JsonOptions);
            File.WriteAllText(SettingsPath, json);
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "AppSettings.Save");
        }
    }

    public string? GetVideoForDisplay(string deviceName)
    {
        if (ApplyToAll)
        {
            return VideoPath;
        }

        if (Assignments.TryGetValue(deviceName, out var path) && !string.IsNullOrWhiteSpace(path))
        {
            return path;
        }

        return VideoPath;
    }

    public void SetVideoForDisplay(string deviceName, string path)
    {
        Assignments[deviceName] = path;
        Save();
    }

    public void SetVideoForAll(string path)
    {
        VideoPath = path;
        ApplyToAll = true;
        Save();
    }
}

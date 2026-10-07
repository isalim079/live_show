using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace LiveWallpaper;

public interface IVideoWallpaperPlayer : IDisposable
{
    bool IsPlaying { get; }
    string? CurrentVideoPath { get; }
    UIElement VisualElement { get; }

    void Load(string path, bool autoPlay);
    void Play();
    void Pause();
    void Stop();
    void SetMuted(bool muted);
}

/// <summary>
/// Native video wallpaper player wrapper.
/// Optimized for wallpaper playback: hardware acceleration, muted audio by default,
/// seamless loop, and resilient error recovery.
/// </summary>
public sealed class NativeVideoPlayer : IVideoWallpaperPlayer
{
    private readonly MediaElement _mediaElement;
    private readonly Grid _container;
    private bool _isPlaying;
    private string? _currentPath;
    private bool _disposed;

    public bool IsPlaying => _isPlaying;
    public string? CurrentVideoPath => _currentPath;
    public UIElement VisualElement => _container;

    public NativeVideoPlayer()
    {
        _mediaElement = new MediaElement
        {
            LoadedBehavior = MediaState.Manual,
            UnloadedBehavior = MediaState.Manual,
            Stretch = Stretch.UniformToFill,
            IsMuted = true, // Wallpaper playback must be muted by default
            Volume = 0.0,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Stretch,
            VerticalAlignment = System.Windows.VerticalAlignment.Stretch,
        };

        _mediaElement.MediaEnded += OnMediaEnded;
        _mediaElement.MediaFailed += OnMediaFailed;
        _mediaElement.MediaOpened += OnMediaOpened;

        _container = new Grid
        {
            Background = System.Windows.Media.Brushes.Black,
            ClipToBounds = true,
        };
        _container.Children.Add(_mediaElement);
    }

    private void OnMediaOpened(object? sender, RoutedEventArgs e)
    {
        CrashLog.LogInfo($"NativeVideoPlayer: Media opened successfully for '{Path.GetFileName(_currentPath)}'.");
    }

    private void OnMediaEnded(object? sender, RoutedEventArgs e)
    {
        // Seamless loop
        try
        {
            _mediaElement.Position = TimeSpan.Zero;
            if (_isPlaying)
            {
                _mediaElement.Play();
            }
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "NativeVideoPlayer.OnMediaEnded");
        }
    }

    private void OnMediaFailed(object? sender, ExceptionRoutedEventArgs e)
    {
        CrashLog.LogError($"NativeVideoPlayer: Playback failed for '{_currentPath}': {e.ErrorException?.Message}");
    }

    public void Load(string path, bool autoPlay)
    {
        if (!File.Exists(path))
        {
            CrashLog.LogWarning($"NativeVideoPlayer: Video file does not exist: {path}");
            return;
        }

        try
        {
            _currentPath = path;
            _isPlaying = autoPlay;

            _mediaElement.Stop();
            _mediaElement.Source = new Uri(path, UriKind.Absolute);

            if (autoPlay)
            {
                _mediaElement.Play();
            }
            else
            {
                _mediaElement.Pause();
            }
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, $"NativeVideoPlayer.Load({path})");
        }
    }

    public void Play()
    {
        if (_currentPath == null)
        {
            return;
        }

        try
        {
            _isPlaying = true;
            _mediaElement.Play();
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "NativeVideoPlayer.Play");
        }
    }

    public void Pause()
    {
        try
        {
            _isPlaying = false;
            _mediaElement.Pause();
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "NativeVideoPlayer.Pause");
        }
    }

    public void Stop()
    {
        try
        {
            _isPlaying = false;
            _mediaElement.Stop();
        }
        catch (Exception ex)
        {
            CrashLog.LogException(ex, "NativeVideoPlayer.Stop");
        }
    }

    public void SetMuted(bool muted)
    {
        _mediaElement.IsMuted = muted;
        if (!muted && _mediaElement.Volume <= 0.0)
        {
            _mediaElement.Volume = 0.5;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        try
        {
            _mediaElement.Stop();
            _mediaElement.Source = null;
            _mediaElement.MediaEnded -= OnMediaEnded;
            _mediaElement.MediaFailed -= OnMediaFailed;
            _mediaElement.MediaOpened -= OnMediaOpened;
            _container.Children.Clear();
        }
        catch
        {
            // Ignore teardown errors
        }
    }
}

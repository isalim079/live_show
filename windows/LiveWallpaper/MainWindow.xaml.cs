using System;
using System.Windows;
using System.Windows.Interop;

namespace LiveWallpaper
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            // Register app to auto-start on Windows boot
            SetAutoStart();

            // 1. Fetch Progman window
            IntPtr progman = Win32.FindWindow("Progman", null);

            // 2. Send message 0x052C to spawn WorkerW behind icons
            IntPtr result = IntPtr.Zero;
            Win32.SendMessageTimeout(progman, 0x052C, new IntPtr(0), IntPtr.Zero, Win32.SendMessageTimeoutFlags.SMTO_NORMAL, 1000, out result);

            // 3. Find the correct WorkerW
            IntPtr workerw = IntPtr.Zero;
            Win32.EnumWindows(new Win32.EnumWindowsProc((tophandle, topparamhandle) =>
            {
                IntPtr p = Win32.FindWindowEx(tophandle, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (p != IntPtr.Zero)
                {
                    // Gets the WorkerW Window after the current one.
                    workerw = Win32.FindWindowEx(IntPtr.Zero, tophandle, "WorkerW", null);
                }
                return true;
            }), IntPtr.Zero);

            // 4. Set this window as a child of the WorkerW
            IntPtr windowHandle = new WindowInteropHelper(this).Handle;
            if (workerw != IntPtr.Zero)
            {
                Win32.SetParent(windowHandle, workerw);
            }

            // 5. Maximize window to cover the screen
            this.Left = SystemParameters.VirtualScreenLeft;
            this.Top = SystemParameters.VirtualScreenTop;
            this.Width = SystemParameters.VirtualScreenWidth;
            this.Height = SystemParameters.VirtualScreenHeight;

            // --- HOW TO PLAY A VIDEO ---
            // Uncomment the lines below and provide a valid path to an MP4 file.
            // PlaceholderText.Visibility = Visibility.Collapsed;
            // VideoPlayer.Source = new Uri(@"C:\Path\To\Your\Video.mp4", UriKind.Absolute);
            // VideoPlayer.Play();
        }

        private void SetAutoStart()
        {
            try
            {
                string appName = "LiveWallpaperEngine";
                // Get the .exe path (in .NET 5+ this sometimes points to the .dll, so we ensure it's .exe)
                string exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;

                using (Microsoft.Win32.RegistryKey key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    key.SetValue(appName, "\"" + exePath + "\"");
                }
            }
            catch
            {
                // Ignore permissions/registry errors for now
            }
        }

        private void VideoPlayer_MediaEnded(object sender, RoutedEventArgs e)
        {
            // Loop the video seamlessly
            VideoPlayer.Position = TimeSpan.Zero;
            VideoPlayer.Play();
        }
    }
}

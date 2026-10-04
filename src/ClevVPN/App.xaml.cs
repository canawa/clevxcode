using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ClevVPN.Core.Services;
using ClevVPN.Helpers;

namespace ClevVPN;

public partial class App : Application
{
    private SingleInstanceService? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        HookCrashGuards();

        RenderOptions.ProcessRenderMode = System.Windows.Interop.RenderMode.Default;
        Timeline.DesiredFrameRateProperty.OverrideMetadata(
            typeof(Timeline),
            new FrameworkPropertyMetadata(60));

        LocalizationManager.Apply(LocalizationManager.ReadSavedLanguage());

        var urlScheme = UrlSchemeParser.FindInCommandLine()
            ?? UrlSchemeParser.FindInArguments(e.Args);

        var canRunWithoutElevation = UrlSchemeParser.CanRunWithoutElevation(urlScheme);

        if (!AdminElevationHelper.IsAdministrator() && !canRunWithoutElevation)
        {
            var forwarded = !string.IsNullOrWhiteSpace(urlScheme)
                ? SingleInstanceService.TryForwardToRunningInstance(urlScheme)
                : SingleInstanceService.TryForwardToRunningInstance(SingleInstanceService.ActivateMessage);

            if (forwarded)
            {
                Shutdown();
                return;
            }

            if (AdminElevationHelper.TryEnsureAdministrator())
            {
                Shutdown();
                return;
            }

            urlScheme = UrlSchemeParser.FindInCommandLine()
                ?? UrlSchemeParser.FindInArguments(e.Args);
        }

        var settings = AppSettings.Load();
        ThemeManager.Apply(ThemeManager.Parse(settings.Theme));

        ProtocolRegistrationHelper.EnsureRegistered();

        _singleInstance = SingleInstanceService.Create();

        if (!_singleInstance.IsPrimary)
        {
            if (!string.IsNullOrWhiteSpace(urlScheme))
                _singleInstance.TrySendToPrimary(urlScheme);
            else
                _singleInstance.TrySendToPrimary(SingleInstanceService.ActivateMessage);

            Shutdown();
            return;
        }

        base.OnStartup(e);
        PreloadServerEmojis();

        var mainWindow = new MainWindow();
        MainWindow = mainWindow;

        _singleInstance.StartListening(message =>
        {
            mainWindow.Dispatcher.BeginInvoke(() =>
            {
                try
                {
                    if (string.Equals(message, SingleInstanceService.ActivateMessage, StringComparison.Ordinal))
                    {
                        mainWindow.ActivateFromExternalRequest();
                        return;
                    }

                    mainWindow.HandleUrlScheme(message);
                }
                catch (Exception ex)
                {
                    WriteCrashLog("SingleInstance", ex);
                }
            });
        });

        var pendingUrlScheme = urlScheme;
        mainWindow.Loaded += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(pendingUrlScheme))
                mainWindow.HandleUrlScheme(pendingUrlScheme);
        };

        mainWindow.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    private void HookCrashGuards()
    {
        DispatcherUnhandledException += (_, args) =>
        {
            WriteCrashLog("UI", args.Exception);
            args.Handled = true;
        };

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            if (args.ExceptionObject is Exception ex)
                WriteCrashLog("AppDomain", ex);
        };

        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            WriteCrashLog("Task", args.Exception);
            args.SetObserved();
        };
    }

    private static void WriteCrashLog(string source, Exception ex)
    {
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "ClevVPN",
                "logs");
            Directory.CreateDirectory(dir);
            File.AppendAllText(
                Path.Combine(dir, "crash.log"),
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {source}: {ex}{Environment.NewLine}");
        }
        catch
        {
            // ignored
        }
    }

    private static void PreloadServerEmojis()
    {
        foreach (var emoji in new[] { "🦎", "🌱", "🤏", "🟢", "⚪", "⚫" })
            EmojiImageHelper.TryGetImage(emoji);
    }
}

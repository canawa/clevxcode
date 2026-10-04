using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using ClevVPN.Helpers;

namespace ClevVPN.Controls;

public enum ClevConnectState
{
    Off,
    Busy,
    On
}

/// <summary>
/// Windows port of macOS <c>ConnectButton</c> (Components.swift, size 150).
/// Animations: press 0.93 spring, comet −90→810° / 0.5s, ringFill 0→1 / 0.55s,
/// ConnectBurst rings + SF bolt.fill flash.
/// </summary>
public partial class ClevConnectButton : UserControl
{
    // Mac: size=150, ringSize=size+24=174
    private const double RingDiameter = 174;
    private const double FillStroke = 2;
    private const double CometStroke = 2.5;

    public static readonly DependencyProperty RingFillProperty =
        DependencyProperty.Register(
            nameof(RingFill),
            typeof(double),
            typeof(ClevConnectButton),
            new PropertyMetadata(0.0, OnRingFillChanged));

    private ClevConnectState _state = ClevConnectState.Off;
    private DateTime? _connectedAt;
    private string? _busyLabelOverride;
    private bool _wasOn;
    private DispatcherTimer? _burstHideTimer;
    private System.Threading.Timer? _sessionTimer;
    private Stopwatch? _sessionWatch;
    private TimeSpan _sessionBase;
    private int _displayedSeconds = -1;
    private double _lastFill = -1;
    private bool _pressed;

    public event EventHandler? Click;

    public double RingFill
    {
        get => (double)GetValue(RingFillProperty);
        set => SetValue(RingFillProperty, value);
    }

    public ClevConnectButton()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            ApplyCometDash();
            ApplyBusyDash();
            ApplyVisuals(animateTransition: false);
        };
        Unloaded += (_, _) => EnsureSessionTimer(false);
        LocalizationManager.LanguageChanged += (_, _) =>
            Dispatcher.Invoke(ApplyContent);
    }

    public void SetState(ClevConnectState state, string? busyLabel = null, DateTime? connectedAt = null)
    {
        var previous = _state;
        _state = state;
        _busyLabelOverride = busyLabel;

        if (state == ClevConnectState.On)
        {
            if (_sessionWatch is not { IsRunning: true })
            {
                var now = DateTime.UtcNow;
                if (connectedAt is DateTime started && (now - started).TotalSeconds >= 1)
                {
                    _connectedAt = started;
                    _sessionBase = now - started;
                }
                else
                {
                    _connectedAt = now;
                    _sessionBase = TimeSpan.Zero;
                }
            }

            EnsureSessionTimer(true);
        }
        else
        {
            _connectedAt = null;
            EnsureSessionTimer(false);
            SessionTimerText.Visibility = Visibility.Collapsed;
        }

        var becameOn = state == ClevConnectState.On && previous != ClevConnectState.On;
        var turnedOff = state == ClevConnectState.Off && previous == ClevConnectState.On;

        if (becameOn)
            PlayConnectAnimation();
        else if (turnedOff)
            PlayDisconnectAnimation();
        else
            ApplyVisuals(animateTransition: true);

        _wasOn = state == ClevConnectState.On;
        // Mac allows tap while busy only for ping-cancel; Windows disconnect path uses Busy too —
        // keep disabled during Busy like previous Windows behavior.
        IsEnabled = state != ClevConnectState.Busy;
    }

    public void SetConnectedAt(DateTime? connectedAt)
    {
        if (_sessionWatch is { IsRunning: true })
            return;

        _connectedAt = connectedAt;
        if (_state == ClevConnectState.On)
        {
            EnsureSessionTimer(connectedAt is not null);
            UpdateSessionTimer();
        }
    }

    private static void OnRingFillChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is ClevConnectButton button)
            button.ApplyFillDash((double)e.NewValue);
    }

    private void ApplyFillDash(double fill)
    {
        fill = Math.Clamp(fill, 0, 1);
        if (Math.Abs(fill - _lastFill) < 0.01)
            return;
        _lastFill = fill;
        FillRing.StrokeDashArray = DashForFraction(RingDiameter, FillStroke, fill);
        FillRing.Opacity = fill <= 0.001 ? 0 : 1;
        CometRing.Opacity = fill > 0.001 && fill < 0.999 && _state == ClevConnectState.On ? 1 : 0;
    }

    private void ApplyCometDash() =>
        CometRing.StrokeDashArray = DashForFraction(RingDiameter, CometStroke, 0.18);

    private void ApplyBusyDash() =>
        BusyRing.StrokeDashArray = DashForFraction(RingDiameter, CometStroke, 0.2);

    private static DoubleCollection DashForFraction(double diameter, double thickness, double fraction)
    {
        var circumference = Math.PI * diameter;
        var dash = Math.Max(0.0001, fraction * circumference / thickness);
        var gap = Math.Max(0.0001, circumference / thickness);
        return [dash, gap];
    }

    private void PlayConnectAnimation()
    {
        StopBusySpin();
        BusyRing.Opacity = 0;

        RingFill = 0;
        ApplyFillDash(0);
        CometRotate.Angle = -90;
        CometRing.Opacity = 1;
        ApplyCometDash();

        // Mac: withAnimation(.easeIn(duration: 0.5)) { cometAngle = -90 + 900 }
        var cometAnim = new DoubleAnimation(-90, 810, TimeSpan.FromSeconds(0.5))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn }
        };
        CometRotate.BeginAnimation(RotateTransform.AngleProperty, cometAnim);

        // Mac: withAnimation(.easeOut(duration: 0.55).delay(0.15)) { ringFill = 1 }
        var fillAnim = new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.55))
        {
            BeginTime = TimeSpan.FromSeconds(0.15),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        fillAnim.Completed += (_, _) =>
        {
            CometRing.Opacity = 0;
            CometRotate.BeginAnimation(RotateTransform.AngleProperty, null);
        };
        BeginAnimation(RingFillProperty, fillAnim);

        ApplyPlate(on: true, animate: true);
        ApplyContent();
        ApplyRimGlow(on: true);
        PlayBurst();
    }

    private void PlayDisconnectAnimation()
    {
        StopBurst();
        StopBusySpin();
        BusyRing.Opacity = 0;
        CometRing.Opacity = 0;
        CometRotate.BeginAnimation(RotateTransform.AngleProperty, null);

        var fillAnim = new DoubleAnimation(RingFill, 0, TimeSpan.FromSeconds(0.25))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        fillAnim.Completed += (_, _) =>
        {
            BeginAnimation(RingFillProperty, null);
            RingFill = 0;
            ApplyFillDash(0);
        };
        BeginAnimation(RingFillProperty, fillAnim);

        ApplyPlate(on: false, animate: true);
        ApplyContent();
        ApplyRimGlow(on: false);
    }

    private void ApplyVisuals(bool animateTransition)
    {
        switch (_state)
        {
            case ClevConnectState.On:
                StopBusySpin();
                BusyRing.Opacity = 0;
                BeginAnimation(RingFillProperty, null);
                RingFill = 1;
                ApplyFillDash(1);
                CometRing.Opacity = 0;
                ApplyPlate(on: true, animate: animateTransition);
                ApplyRimGlow(on: true);
                break;

            case ClevConnectState.Busy:
                BeginAnimation(RingFillProperty, null);
                RingFill = 0;
                ApplyFillDash(0);
                CometRing.Opacity = 0;
                ApplyPlate(on: false, animate: animateTransition);
                ApplyRimGlow(busy: true);
                StartBusySpin();
                break;

            default:
                StopBusySpin();
                BusyRing.Opacity = 0;
                if (!_wasOn)
                {
                    BeginAnimation(RingFillProperty, null);
                    RingFill = 0;
                    ApplyFillDash(0);
                }
                CometRing.Opacity = 0;
                ApplyPlate(on: false, animate: animateTransition);
                ApplyRimGlow(on: false);
                break;
        }

        ApplyContent();
    }

    private void ApplyContent()
    {
        switch (_state)
        {
            case ClevConnectState.On:
                // Mac: power black.opacity(0.75), label size*0.058 tracking(3), timer size*0.11 light
                SetPowerStroke(Color.FromArgb(0xBF, 0, 0, 0));
                ConnectLabel.Text = Track(LocalizationManager.Get("Loc.Connect.Connected"));
                ConnectLabel.FontSize = 8.7;
                ConnectLabel.FontWeight = FontWeights.Normal;
                ConnectLabel.Foreground = new SolidColorBrush(Color.FromArgb(0x73, 0, 0, 0));
                ConnectLabel.Margin = new Thickness(0, 7, 0, 0);
                SessionTimerText.Visibility = Visibility.Visible;
                SessionTimerText.FontWeight = FontWeights.Light;
                SessionTimerText.Foreground = new SolidColorBrush(Color.FromArgb(0xB3, 0, 0, 0));
                UpdateSessionTimer();
                break;

            case ClevConnectState.Busy:
                SetPowerStroke(Color.FromRgb(0xFA, 0xC3, 0x00));
                ConnectLabel.Text = string.IsNullOrWhiteSpace(_busyLabelOverride)
                    ? LocalizationManager.Get("Loc.Connect.Connecting")
                    : _busyLabelOverride!;
                ConnectLabel.FontSize = 11.25;
                ConnectLabel.FontWeight = FontWeights.Normal;
                ConnectLabel.Foreground = new SolidColorBrush(Color.FromRgb(0x9A, 0x9A, 0xA3));
                ConnectLabel.Margin = new Thickness(0, 6, 0, 0);
                SessionTimerText.Visibility = Visibility.Collapsed;
                break;

            default:
                var off = Color.FromRgb(0x9A, 0x9A, 0xA3);
                SetPowerStroke(off);
                ConnectLabel.Text = LocalizationManager.Get("Loc.Connect.Start");
                ConnectLabel.FontSize = 11.25;
                ConnectLabel.FontWeight = FontWeights.Normal;
                ConnectLabel.Foreground = new SolidColorBrush(off);
                ConnectLabel.Margin = new Thickness(0, 6, 0, 0);
                SessionTimerText.Visibility = Visibility.Collapsed;
                break;
        }
    }

    private static string Track(string text) =>
        string.Join('\u200A', text.ToCharArray());

    private void SetPowerStroke(Color color)
    {
        PowerIcon.Stroke = new SolidColorBrush(color);
        PowerIcon.Fill = Brushes.Transparent;
    }

    /// <summary>
    /// Mac <c>plateRadial</c>: RadialGradient([logoYellow #FAC300, logoAmber #E39A00],
    /// center (0.5, 0.42), startRadius d·0.05, endRadius d·0.6). Off: #24242E→#0C0C11.
    /// </summary>
    private void ApplyPlate(bool on, bool animate)
    {
        // Theme.logoYellow / Theme.logoAmber — exact Mac hex
        var c0 = on ? Color.FromRgb(0xFA, 0xC3, 0x00) : Color.FromRgb(0x24, 0x24, 0x2E);
        var cMid = c0; // solid first color through startRadius (0.05/0.6 ≈ 0.083)
        var c1 = on ? Color.FromRgb(0xE3, 0x9A, 0x00) : Color.FromRgb(0x0C, 0x0C, 0x11);
        // plateTopLight: on .white.opacity(0.3), off .white.opacity(0.10)
        var topLight = on ? Color.FromArgb(0x4D, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF);
        var plateGlow = on ? 0.85 : 0.0;

        PlateBrush.GradientOrigin = new Point(0.5, 0.42);
        PlateBrush.Center = new Point(0.5, 0.42);
        PlateBrush.RadiusX = 0.6;
        PlateBrush.RadiusY = 0.6;

        if (!animate)
        {
            PlateStop0.BeginAnimation(GradientStop.ColorProperty, null);
            PlateStopMid.BeginAnimation(GradientStop.ColorProperty, null);
            PlateStop1.BeginAnimation(GradientStop.ColorProperty, null);
            PlateTopLightStop.BeginAnimation(GradientStop.ColorProperty, null);
            PlateGlow.BeginAnimation(UIElement.OpacityProperty, null);
            PlateStop0.Color = c0;
            PlateStopMid.Color = cMid;
            PlateStopMid.Offset = on ? 0.083 : 0;
            PlateStop1.Color = c1;
            PlateTopLightStop.Color = topLight;
            PlateGlow.Opacity = plateGlow;
            return;
        }

        var duration = TimeSpan.FromSeconds(0.3);
        PlateStop0.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(c0, duration));
        PlateStopMid.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(cMid, duration));
        PlateStop1.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(c1, duration));
        PlateTopLightStop.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(topLight, duration));
        PlateGlow.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(plateGlow, duration));
        PlateStopMid.Offset = on ? 0.083 : 0;
    }

    private void ApplyRimGlow(bool on = false, bool busy = false)
    {
        // Mac: rim.shadow(glowColor) — on 0.35, busy 0.12 — soft broad radial
        double opacity = on ? 1.0 : busy ? 0.35 : 0;
        RimGlow.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(opacity, TimeSpan.FromMilliseconds(300)));
    }

    private void StartBusySpin()
    {
        StopBusySpin();
        ApplyBusyDash();
        BusyRing.Opacity = 1;
        BusyRotate.Angle = 0;

        // Mac busy: linear 0.5s/rev forever
        var spin = new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.5))
        {
            RepeatBehavior = RepeatBehavior.Forever
        };
        BusyRotate.BeginAnimation(RotateTransform.AngleProperty, spin, HandoffBehavior.SnapshotAndReplace);
    }

    private void StopBusySpin()
    {
        BusyRotate.BeginAnimation(RotateTransform.AngleProperty, null);
        BusyRotate.Angle = 0;
        BusyRing.Opacity = 0;
    }

    private void PlayBurst()
    {
        StopBurst();
        BurstLayer.Visibility = Visibility.Visible;
        BurstRing0.Opacity = 0.55;
        BurstRing1.Opacity = 0.55;
        BurstRing2.Opacity = 0.55;
        BurstRing0Scale.ScaleX = BurstRing0Scale.ScaleY = 1;
        BurstRing1Scale.ScaleX = BurstRing1Scale.ScaleY = 1;
        BurstRing2Scale.ScaleX = BurstRing2Scale.ScaleY = 1;
        BurstFlash.Opacity = 0.9;
        BurstFlashScale.ScaleX = BurstFlashScale.ScaleY = 0.5;
        BurstBolt.Opacity = 1;
        BurstBoltScale.ScaleX = BurstBoltScale.ScaleY = 0.5;

        AnimateBurstRing(BurstRing0, BurstRing0Scale, delay: 0);
        AnimateBurstRing(BurstRing1, BurstRing1Scale, delay: 0.18);
        AnimateBurstRing(BurstRing2, BurstRing2Scale, delay: 0.36);

        var flashScale = new DoubleAnimation(0.5, 1.5, TimeSpan.FromSeconds(0.4))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        var flashOpacity = new DoubleAnimation(0.9, 0, TimeSpan.FromSeconds(0.4))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        BurstFlashScale.BeginAnimation(ScaleTransform.ScaleXProperty, flashScale);
        BurstFlashScale.BeginAnimation(ScaleTransform.ScaleYProperty, flashScale.Clone());
        BurstFlash.BeginAnimation(OpacityProperty, flashOpacity);

        var boltScale = new DoubleAnimation(0.5, 1.35, TimeSpan.FromSeconds(0.45))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        var boltOpacity = new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.45))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        BurstBoltScale.BeginAnimation(ScaleTransform.ScaleXProperty, boltScale);
        BurstBoltScale.BeginAnimation(ScaleTransform.ScaleYProperty, boltScale.Clone());
        BurstBolt.BeginAnimation(UIElement.OpacityProperty, boltOpacity);

        _burstHideTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.3) };
        _burstHideTimer.Tick += (_, _) =>
        {
            _burstHideTimer?.Stop();
            _burstHideTimer = null;
            BurstLayer.Visibility = Visibility.Collapsed;
        };
        _burstHideTimer.Start();
    }

    private static void AnimateBurstRing(Ellipse ring, ScaleTransform scale, double delay)
    {
        var scaleAnim = new DoubleAnimation(1, 1.9, TimeSpan.FromSeconds(1.0))
        {
            BeginTime = TimeSpan.FromSeconds(delay),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        var opacityAnim = new DoubleAnimation(0.55, 0, TimeSpan.FromSeconds(1.0))
        {
            BeginTime = TimeSpan.FromSeconds(delay),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, scaleAnim);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, scaleAnim.Clone());
        ring.BeginAnimation(OpacityProperty, opacityAnim);
    }

    private void StopBurst()
    {
        _burstHideTimer?.Stop();
        _burstHideTimer = null;
        BurstLayer.Visibility = Visibility.Collapsed;
        BurstRing0.BeginAnimation(OpacityProperty, null);
        BurstRing1.BeginAnimation(OpacityProperty, null);
        BurstRing2.BeginAnimation(OpacityProperty, null);
        BurstFlash.BeginAnimation(OpacityProperty, null);
        BurstBolt.BeginAnimation(UIElement.OpacityProperty, null);
    }

    private void EnsureSessionTimer(bool enabled)
    {
        if (enabled)
        {
            if (_sessionWatch is { IsRunning: true })
            {
                UpdateSessionTimer();
                return;
            }

            _sessionWatch = Stopwatch.StartNew();
            _displayedSeconds = -1;
            UpdateSessionTimer();
            _sessionTimer?.Dispose();
            _sessionTimer = new System.Threading.Timer(
                static state => ((ClevConnectButton)state!).OnSessionThreadTick(),
                this,
                40,
                40);
            return;
        }

        _sessionTimer?.Dispose();
        _sessionTimer = null;
        _sessionWatch?.Stop();
        _sessionWatch = null;
        _sessionBase = TimeSpan.Zero;
        _displayedSeconds = -1;
    }

    private TimeSpan SessionElapsed =>
        _sessionBase + (_sessionWatch?.Elapsed ?? TimeSpan.Zero);

    private void OnSessionThreadTick()
    {
        if (_state != ClevConnectState.On || _sessionWatch is null)
            return;

        var total = Math.Max(0, (int)SessionElapsed.TotalSeconds);
        if (total == System.Threading.Volatile.Read(ref _displayedSeconds))
            return;

        try
        {
            Dispatcher.BeginInvoke(UpdateSessionTimer, DispatcherPriority.Send);
        }
        catch
        {
            // dispatcher shutting down
        }
    }

    private void UpdateSessionTimer()
    {
        if (_state != ClevConnectState.On)
            return;

        var total = Math.Max(0, (int)SessionElapsed.TotalSeconds);
        if (total == _displayedSeconds)
            return;

        _displayedSeconds = total;
        var h = total / 3600;
        var m = (total % 3600) / 60;
        var s = total % 60;
        SessionTimerText.Text = $"{h}:{m:D2}:{s:D2}";
    }

    private void HitTarget_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!IsEnabled)
            return;

        _pressed = true;
        HitTarget.CaptureMouse();
        AnimatePress(0.93);
    }

    private void HitTarget_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_pressed)
            return;

        _pressed = false;
        HitTarget.ReleaseMouseCapture();
        AnimatePress(1.0);

        if (HitTarget.IsMouseOver && IsEnabled)
            Click?.Invoke(this, EventArgs.Empty);
    }

    private void HitTarget_MouseLeave(object sender, MouseEventArgs e)
    {
        if (!_pressed)
            return;

        _pressed = false;
        HitTarget.ReleaseMouseCapture();
        AnimatePress(1.0);
    }

    /// <summary>Mac PressableButtonStyle: spring(response: 0.22, dampingFraction: 0.55) → 0.93.</summary>
    private void AnimatePress(double scale)
    {
        var anim = new DoubleAnimation(scale, TimeSpan.FromMilliseconds(220))
        {
            // Underdamped spring-ish bounce (dampingFraction 0.55)
            EasingFunction = new BackEase
            {
                EasingMode = scale < 1 ? EasingMode.EaseOut : EasingMode.EaseOut,
                Amplitude = 0.35
            }
        };
        PressScale.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
        PressScale.BeginAnimation(ScaleTransform.ScaleYProperty, anim.Clone());
    }
}

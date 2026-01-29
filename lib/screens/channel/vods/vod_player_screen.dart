import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/vod.dart';
import 'package:frosty/screens/channel/vods/vod_chat.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/theme.dart';
import 'package:frosty/utils.dart';
import 'package:frosty/utils/context_extensions.dart';
import 'package:frosty/widgets/draggable_divider.dart';
import 'package:frosty/widgets/profile_picture.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:simple_pip_mode/actions/pip_actions_layout.dart';
import 'package:simple_pip_mode/pip_widget.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Screen for playing VOD videos with custom overlay similar to live streams
class VodPlayerScreen extends StatefulWidget {
  final VideoTwitch video;

  const VodPlayerScreen({
    super.key,
    required this.video,
  });

  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen>
    with WidgetsBindingObserver {
  // GlobalKey to preserve WebView state across widget tree changes (e.g., PIP mode)
  final _webViewKey = GlobalKey();
  // GlobalKey to preserve VodChat state across orientation changes
  final _vodChatKey = GlobalKey();
  InAppWebViewController? _webViewController;
  bool _paused = true;
  bool _overlayVisible = true;
  bool _isLoaded = false;
  bool _isInPipMode = false;
  bool _showChat = true;

  // Seek state
  double _currentTime = 0;
  double _duration = 0;
  bool _isSeeking = false;
  Timer? _overlayTimer;
  Timer? _progressTimer;

  // Value notifiers for VOD chat
  late final ValueNotifier<double> _currentTimeNotifier;
  late final ValueNotifier<bool> _pausedNotifier;

  late final SettingsStore _settingsStore;
  late final TwitchApi _twitchApi;
  late final SimplePip _pip;

  // Cached player widget to prevent recreation on rebuilds
  late final Widget _player;

  // Background audio support
  bool _isForegroundServiceRunning = false;

  /// The video URL to use for the webview
  String get videoUrl =>
      'https://player.twitch.tv/?video=${widget.video.id}&parent=frosty&autoplay=true';

  /// InAppWebView settings for video playback
  InAppWebViewSettings get webViewSettings => InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
        disableContextMenu: true,
        useHybridComposition: !_settingsStore.useTextureRendering,
        allowsBackForwardNavigationGestures: false,
        iframeAllowFullscreen: true,
        allowBackgroundAudioPlaying: _settingsStore.backgroundAudioEnabled,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsStore = context.read<SettingsStore>();
    _twitchApi = context.read<TwitchApi>();
    _duration = widget.video.durationInSeconds.toDouble();
    _currentTimeNotifier = ValueNotifier(0);
    _pausedNotifier = ValueNotifier(true);
    _scheduleOverlayHide();

    // Initialize SimplePip with callbacks for PIP exit detection
    _pip = SimplePip(
      onPipExited: _onPipExited,
      onPipEntered: () {
        if (mounted) {
          setState(() => _isInPipMode = true);
        }
      },
    );

    // Initialize foreground task for background audio on Android
    if (Platform.isAndroid) {
      _initForegroundTask();
    }

    _initPlayer();
  }

  /// Callback for when PIP mode is exited on Android.
  /// This is called when user dismisses the PIP window.
  void _onPipExited() {
    if (mounted) {
      setState(() => _isInPipMode = false);
    }
    // Stop video if setting is enabled
    if (_settingsStore.stopVideoOnPipDismiss && !_paused) {
      _handlePausePlay();
    }
  }

  /// Initializes the foreground task for background audio playback.
  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'vod_background_audio_channel',
        channelName: 'VOD Background Audio',
        channelDescription: 'Playing VOD audio in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the foreground service for background audio playback.
  Future<void> _startForegroundService() async {
    if (_isForegroundServiceRunning) return;

    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        _isForegroundServiceRunning = true;
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: 'ReFrosty',
        notificationText: 'Playing VOD: ${widget.video.userName}',
        notificationIcon: null,
        callback: _vodBackgroundAudioCallback,
      );
      _isForegroundServiceRunning = true;
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
    }
  }

  /// Stops the foreground service.
  Future<void> _stopForegroundService() async {
    if (!_isForegroundServiceRunning) return;

    try {
      await FlutterForegroundTask.stopService();
      _isForegroundServiceRunning = false;
    } catch (e) {
      debugPrint('Failed to stop foreground service: $e');
    }
  }

  /// Manages background audio state based on playback state.
  void _updateBackgroundAudioState() {
    if (!Platform.isAndroid) return;

    if (_settingsStore.backgroundAudioEnabled && !_paused) {
      _startForegroundService();
      WakelockPlus.enable();
    } else if (_paused || !_settingsStore.backgroundAudioEnabled) {
      _stopForegroundService();
      if (_settingsStore.backgroundAudioEnabled) {
        WakelockPlus.disable();
      }
    }
  }

  /// Initialize the player widget once to prevent recreation on rebuilds
  void _initPlayer() {
    _player = InAppWebView(
      key: _webViewKey,
      initialUrlRequest: URLRequest(url: WebUri(videoUrl)),
      initialSettings: webViewSettings,
      onWebViewCreated: (controller) {
        _webViewController = controller;

        controller.addJavaScriptHandler(
          handlerName: 'VideoPause',
          callback: (args) {
            if (mounted) {
              setState(() => _paused = true);
              _pausedNotifier.value = true;
              _stopProgressTimer();
              if (Platform.isAndroid) _pip.setIsPlaying(false);
              _updateBackgroundAudioState();
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'VideoPlaying',
          callback: (args) {
            if (mounted) {
              setState(() => _paused = false);
              _pausedNotifier.value = false;
              _startProgressTimer();
              if (Platform.isAndroid) _pip.setIsPlaying(true);
              _updateBackgroundAudioState();
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'PipEntered',
          callback: (args) {
            if (mounted) {
              setState(() {
                _isInPipMode = true;
                _overlayVisible = true;
              });
              _overlayTimer?.cancel();
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'PipExited',
          callback: (args) {
            if (mounted) {
              setState(() => _isInPipMode = false);
              _scheduleOverlayHide();
            }
          },
        );
      },
      onLoadStop: (controller, url) async {
        if (url?.toString() == videoUrl) {
          await _initVideo();
          if (mounted) {
            setState(() => _isLoaded = true);
          }
        }
      },
    );
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (Platform.isAndroid) {
      final backgroundAudioEnabled = _settingsStore.backgroundAudioEnabled;

      // Handle background audio playback
      if (backgroundAudioEnabled && _webViewController != null) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) {
          // Keep WebView running in background for audio playback
          await _webViewController?.resume();
        }
      }

      // Check if auto-PIP is available (newer Android versions handle it automatically)
      final isAutoPipAvailable = await SimplePip.isAutoPipAvailable;

      // Only manually trigger PIP if auto-PIP is not available and background audio is disabled
      if (!isAutoPipAvailable &&
          state == AppLifecycleState.inactive &&
          !_paused &&
          _settingsStore.showVideo &&
          !backgroundAudioEnabled) {
        _requestPictureInPicture();
      }
    }
  }

  void _scheduleOverlayHide([Duration delay = const Duration(seconds: 5)]) {
    _overlayTimer?.cancel();
    if (_isInPipMode) {
      setState(() => _overlayVisible = true);
      return;
    }

    _overlayTimer = Timer(delay, () {
      if (_isInPipMode || _isSeeking) return;
      if (mounted) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  void _handleVideoTap() {
    if (_isInPipMode) {
      setState(() => _overlayVisible = true);
      return;
    }

    _overlayTimer?.cancel();

    if (_overlayVisible) {
      setState(() => _overlayVisible = false);
    } else {
      setState(() => _overlayVisible = true);
      _scheduleOverlayHide();
    }
  }

  void _handlePausePlay() {
    try {
      if (_paused) {
        _webViewController?.evaluateJavascript(
          source: 'document.querySelector("video")?.play();',
        );
      } else {
        _webViewController?.evaluateJavascript(
          source: 'document.querySelector("video")?.pause();',
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _seekTo(double seconds) {
    try {
      _webViewController?.evaluateJavascript(
        source: 'document.querySelector("video").currentTime = $seconds;',
      );
      setState(() => _currentTime = seconds);
      _currentTimeNotifier.value = seconds;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _seekRelative(double delta) {
    final newTime = (_currentTime + delta).clamp(0.0, _duration);
    _seekTo(newTime);
  }

  /// Handles screen rotation between portrait and landscape modes.
  Future<void> _handleRotation() async {
    if (!mounted) return;

    // Check current orientation using MediaQuery
    final isCurrentlyPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    debugPrint('VOD Player: Rotation pressed. Portrait=$isCurrentlyPortrait');

    if (isCurrentlyPortrait) {
      // Enter landscape mode - allow both orientations for flexibility
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      debugPrint('VOD Player: Set to landscape');
    } else {
      // Return to portrait
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      debugPrint('VOD Player: Set to portrait');
      // Then allow all orientations again after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        SystemChrome.setPreferredOrientations([]);
      });
    }
  }

  void _requestPictureInPicture() {
    try {
      if (Platform.isAndroid) {
        _pip.enterPipMode(autoEnter: true);
      } else if (Platform.isIOS) {
        _webViewController?.evaluateJavascript(
          source:
              'document.querySelector("video")?.requestPictureInPicture();',
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isSeeking && !_paused) {
        _updateProgress();
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _updateProgress() async {
    try {
      final result = await _webViewController?.evaluateJavascript(
        source: 'document.querySelector("video")?.currentTime || 0',
      );
      if (result != null && mounted && !_isSeeking) {
        final time = double.tryParse(result.toString()) ?? 0;
        setState(() => _currentTime = time);
        _currentTimeNotifier.value = time;
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _initVideo() async {
    try {
      await _webViewController?.evaluateJavascript(source: '''
        (async function() {
          const video = await new Promise((resolve) => {
            const checkVideo = () => {
              const v = document.querySelector("video");
              if (v) {
                resolve(v);
              } else {
                setTimeout(checkVideo, 100);
              }
            };
            checkVideo();
          });

          video.addEventListener("pause", () => {
            window.flutter_inappwebview.callHandler('VideoPause');
          });
          video.addEventListener("playing", () => {
            window.flutter_inappwebview.callHandler('VideoPlaying');
            video.muted = false;
            video.volume = 1.0;
          });
          video.addEventListener("enterpictureinpicture", () => {
            window.flutter_inappwebview.callHandler('PipEntered');
          });
          video.addEventListener("leavepictureinpicture", () => {
            window.flutter_inappwebview.callHandler('PipExited');
          });

          if (!video.paused) {
            window.flutter_inappwebview.callHandler('VideoPlaying');
            video.muted = false;
            video.volume = 1.0;
          }
        })();
      ''');

      // Hide default Twitch overlay - show only video
      await _webViewController?.evaluateJavascript(source: '''
        {
          if (!document.getElementById('frosty-vod-styles')) {
            const style = document.createElement('style');
            style.id = 'frosty-vod-styles';
            style.textContent = \`
              .top-bar,
              .player-controls,
              #channel-player-disclosures,
              [data-a-target="player-overlay-click-handler"],
              .video-player__overlay {
                display: none !important;
                visibility: hidden !important;
                pointer-events: none !important;
              }
            \`;
            document.head.appendChild(style);
          }
        }
      ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  String _formatTime(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final isLandscape = context.isLandscape;

    final surfaceColor = context.watch<FrostyThemes>().dark.colorScheme.onSurface;

    const iconShadow = [
      Shadow(
        offset: Offset(0, 1),
        blurRadius: 4,
        color: Color.fromRGBO(0, 0, 0, 0.3),
      ),
    ];

    const textShadow = [
      Shadow(
        offset: Offset(0, 1),
        blurRadius: 4,
        color: Color.fromRGBO(0, 0, 0, 0.3),
      ),
    ];

    // Use cached player widget to prevent recreation

    // Top gradient
    final topGradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black,
          Colors.black.withValues(alpha: 0.8),
          Colors.black.withValues(alpha: 0.5),
          Colors.black.withValues(alpha: 0.2),
          Colors.transparent,
        ],
      ),
    );

    // Bottom gradient
    final bottomGradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black,
          Colors.black.withValues(alpha: 0.8),
          Colors.black.withValues(alpha: 0.5),
          Colors.black.withValues(alpha: 0.2),
          Colors.transparent,
        ],
      ),
    );

    final backButton = IconButton(
      tooltip: 'Back',
      icon: Icon(
        Icons.adaptive.arrow_back_rounded,
        color: surfaceColor,
        shadows: iconShadow,
      ),
      onPressed: () {
        if (isLandscape) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
        }
        Navigator.of(context).pop();
      },
    );

    final rotateButton = Tooltip(
      message: context.isPortrait
          ? 'Enter landscape mode'
          : 'Exit landscape mode',
      preferBelow: false,
      child: IconButton(
        icon: Icon(
          Icons.screen_rotation_rounded,
          color: surfaceColor,
          shadows: iconShadow,
        ),
        onPressed: () {
          _handleRotation();
        },
      ),
    );

    final pipButton = Tooltip(
      message: _isInPipMode
          ? 'Exit picture-in-picture'
          : 'Enter picture-in-picture',
      preferBelow: false,
      child: IconButton(
        icon: Icon(
          _isInPipMode
              ? Icons.picture_in_picture_alt_outlined
              : Icons.picture_in_picture_alt_rounded,
          color: surfaceColor,
          shadows: iconShadow,
        ),
        onPressed: () {
          if (Platform.isIOS && _isInPipMode) {
            _webViewController?.evaluateJavascript(source: '''
              (function() {
                if (document.pictureInPictureElement) {
                  document.exitPictureInPicture();
                }
              })();
            ''');
          } else {
            _requestPictureInPicture();
          }
        },
      ),
    );

    // Seek bar widget
    Widget buildSeekBar() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(_currentTime),
                  style: TextStyle(
                    color: surfaceColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: textShadow,
                  ),
                ),
                Text(
                  _formatTime(_duration),
                  style: TextStyle(
                    color: surfaceColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: textShadow,
                  ),
                ),
              ],
            ),
          ),
          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _currentTime.clamp(0.0, _duration),
              min: 0,
              max: _duration > 0 ? _duration : 1,
              onChangeStart: (_) {
                setState(() => _isSeeking = true);
                _overlayTimer?.cancel();
              },
              onChanged: (value) {
                setState(() => _currentTime = value);
              },
              onChangeEnd: (value) {
                _seekTo(value);
                setState(() => _isSeeking = false);
                _scheduleOverlayHide();
              },
            ),
          ),
        ],
      );
    }

    // Overlay content
    Widget buildOverlay() {
      return GestureDetector(
        onTap: _handleVideoTap,
        behavior: HitTestBehavior.translucent,
        child: AnimatedOpacity(
          opacity: _overlayVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_overlayVisible,
            child: Stack(
              children: [
                // Top gradient
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 100,
                  child: Container(decoration: topGradient),
                ),
                // Bottom gradient
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 140,
                  child: Container(decoration: bottomGradient),
                ),
                // Top bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          backButton,
                          ProfilePicture(userLogin: video.userLogin, radius: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  getReadableName(video.userName, video.userLogin),
                                  style: TextStyle(
                                    color: surfaceColor,
                                    fontWeight: FontWeight.w600,
                                    shadows: textShadow,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  video.title.isNotEmpty
                                      ? video.title
                                      : 'Untitled Broadcast',
                                  style: TextStyle(
                                    color: surfaceColor.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    shadows: textShadow,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Center controls - with bottom padding to avoid seek bar overlap
                Positioned.fill(
                  // Add bottom padding to account for seek bar and bottom controls (~120px)
                  bottom: 120,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rewind 10s
                        IconButton(
                          iconSize: 40,
                          icon: Icon(
                            Icons.replay_10_rounded,
                            color: surfaceColor,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 3),
                                blurRadius: 8,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          onPressed: () => _seekRelative(-10),
                        ),
                        const SizedBox(width: 24),
                        // Play/Pause
                        IconButton(
                          iconSize: 64,
                          icon: Icon(
                            _paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            color: surfaceColor,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 3),
                                blurRadius: 8,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          onPressed: _handlePausePlay,
                        ),
                        const SizedBox(width: 24),
                        // Forward 10s
                        IconButton(
                          iconSize: 40,
                          icon: Icon(
                            Icons.forward_10_rounded,
                            color: surfaceColor,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 3),
                                blurRadius: 8,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          onPressed: () => _seekRelative(10),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom bar with seek and controls
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Seek bar
                        buildSeekBar(),
                        // Bottom controls row
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              // Video info
                              Expanded(
                                child: Row(
                                  spacing: 8,
                                  children: [
                                    // VOD type badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        video.videoType == VideoType.archive
                                            ? 'VOD'
                                            : video.videoType == VideoType.highlight
                                                ? 'Highlight'
                                                : 'Upload',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    // View count
                                    Row(
                                      spacing: 4,
                                      children: [
                                        Icon(
                                          Icons.visibility,
                                          size: 14,
                                          shadows: iconShadow,
                                          color: surfaceColor,
                                        ),
                                        Text(
                                          NumberFormat.compact()
                                              .format(video.viewCount),
                                          style: TextStyle(
                                            color: surfaceColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            shadows: textShadow,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Date
                                    Row(
                                      spacing: 4,
                                      children: [
                                        Icon(
                                          Icons.calendar_today,
                                          size: 12,
                                          shadows: iconShadow,
                                          color: surfaceColor,
                                        ),
                                        Text(
                                          DateFormat('dd.MM.yy').format(
                                            DateTime.parse(video.createdAt)
                                                .toLocal(),
                                          ),
                                          style: TextStyle(
                                            color: surfaceColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            shadows: textShadow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Right controls
                              // Chat toggle button
                              Tooltip(
                                message: _showChat ? 'Hide chat' : 'Show chat',
                                preferBelow: false,
                                child: IconButton(
                                  icon: Icon(
                                    _showChat
                                        ? Icons.chat_bubble_rounded
                                        : Icons.chat_bubble_outline_rounded,
                                    color: surfaceColor,
                                    shadows: iconShadow,
                                  ),
                                  onPressed: () {
                                    setState(() => _showChat = !_showChat);
                                    _scheduleOverlayHide();
                                  },
                                ),
                              ),
                              if (Platform.isAndroid || Platform.isIOS) pipButton,
                              if (!isIPad()) rotateButton,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Main video area with overlay
    Widget videoWithOverlay() {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Video - use cached player widget
          _player,
          // Loading indicator
          if (!_isLoaded)
            Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          // Overlay with tap handler (always present to handle taps on video area)
          if (_isLoaded) buildOverlay(),
        ],
      );
    }

    // Portrait layout
    Widget portraitLayout() {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Video with 16:9 aspect ratio
              AspectRatio(
                aspectRatio: 16 / 9,
                child: videoWithOverlay(),
              ),
              // Content below video
              Expanded(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: _showChat
                      ? VodChat(
                          key: _vodChatKey,
                          twitchApi: _twitchApi,
                          videoId: video.id,
                          channelId: video.userId,
                          currentTimeNotifier: _currentTimeNotifier,
                          pausedNotifier: _pausedNotifier,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title.isNotEmpty
                                    ? video.title
                                    : 'Untitled Broadcast',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  ProfilePicture(
                                    userLogin: video.userLogin,
                                    radius: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        video.userName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${NumberFormat.compact().format(video.viewCount)} views',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Info chips
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(
                                    avatar:
                                        const Icon(Icons.calendar_today, size: 16),
                                    label: Text(
                                      DateFormat('dd MMM yyyy, HH:mm').format(
                                        DateTime.parse(video.createdAt).toLocal(),
                                      ),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Chip(
                                    avatar: const Icon(Icons.timer, size: 16),
                                    label: Text(video.formattedDuration),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Chip(
                                    avatar: Icon(
                                      video.videoType == VideoType.archive
                                          ? Icons.live_tv
                                          : video.videoType == VideoType.highlight
                                              ? Icons.star
                                              : Icons.upload,
                                      size: 16,
                                    ),
                                    label: Text(
                                      video.videoType == VideoType.archive
                                          ? 'Past Broadcast'
                                          : video.videoType == VideoType.highlight
                                              ? 'Highlight'
                                              : 'Upload',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              if (video.description?.isNotEmpty == true) ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 8),
                                Text(video.description!),
                              ],
                              SizedBox(
                                height: MediaQuery.of(context).padding.bottom + 16,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Landscape layout
    Widget landscapeLayout() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      final chatWidth = _settingsStore.chatWidth;
      final totalWidth = MediaQuery.of(context).size.width;

      return Scaffold(
        backgroundColor: Colors.black,
        body: _showChat
            ? Row(
                children: [
                  // Video takes remaining space
                  Expanded(
                    child: videoWithOverlay(),
                  ),
                  // Draggable divider
                  DraggableDivider(
                    currentWidth: chatWidth,
                    minWidth: 0.15,
                    maxWidth: 0.5,
                    isResizableOnLeft: false,
                    onDrag: (newWidth) {
                      setState(() {
                        _settingsStore.chatWidth = newWidth;
                      });
                    },
                  ),
                  // Chat with configurable width
                  SizedBox(
                    width: totalWidth * chatWidth,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: VodChat(
                        key: _vodChatKey,
                        twitchApi: _twitchApi,
                        videoId: video.id,
                        channelId: video.userId,
                        currentTimeNotifier: _currentTimeNotifier,
                        pausedNotifier: _pausedNotifier,
                      ),
                    ),
                  ),
                ],
              )
            : videoWithOverlay(),
      );
    }

    final content = isLandscape ? landscapeLayout() : portraitLayout();

    // Wrap with PipWidget on Android
    if (Platform.isAndroid) {
      return PipWidget(
        pipLayout: PipActionsLayout.mediaOnlyPause,
        onPipAction: (_) => _handlePausePlay(),
        pipChild: _player,
        child: content,
      );
    }

    return content;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayTimer?.cancel();
    _progressTimer?.cancel();
    _currentTimeNotifier.dispose();
    _pausedNotifier.dispose();

    // Stop foreground service and disable wakelock when leaving VOD player
    if (Platform.isAndroid) {
      _stopForegroundService();
      if (_settingsStore.backgroundAudioEnabled) {
        WakelockPlus.disable();
      }
    }

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([]);
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    super.dispose();
  }
}

/// Callback for the foreground service - runs in isolate.
/// This is a no-op since we just need the service to keep the app alive.
@pragma('vm:entry-point')
void _vodBackgroundAudioCallback() {
  // The service just needs to run to keep the app process alive.
  // The actual audio playback happens in the WebView.
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/channel.dart';
import 'package:frosty/models/stream.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/utils/background_playback_callback.dart';
import 'package:frosty/utils/pip_callback.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

part 'video_store.g.dart';

class VideoStore = VideoStoreBase with _$VideoStore;

abstract class VideoStoreBase with Store {
  final TwitchApi twitchApi;

  /// The userlogin of the current channel.
  final String userLogin;

  /// The user ID of the current channel.
  final String userId;

  final AuthStore authStore;

  final SettingsStore settingsStore;

  /// The [SimplePip] instance used for initiating PiP on Android.
  late final SimplePip pip;

  /// Callback for when PIP mode is exited on Android.
  /// This is called when user dismisses the PIP window.
  void _onPipExited() {
    _isInPipMode = false;
    if (!_paused) {
      handlePausePlay();
      _paused = true;
      if (Platform.isAndroid && settingsStore.backgroundAudioEnabled) {
        _stopForegroundService("pipExited");
        WakelockPlus.disable();
      }
    }
  }

  var _firstTimeSettingQuality = true;

  /// The InAppWebView controller - set when webview is created
  InAppWebViewController? _webViewController;

  /// Getter for the webview controller
  InAppWebViewController? get webViewController => _webViewController;

  /// Dio instance for proxy requests
  final _dio = Dio();

  /// The timer that handles hiding the overlay automatically
  Timer? _overlayTimer;

  /// Tracks the pre-PiP overlay visibility so we can restore it on exit.
  bool _overlayWasVisibleBeforePip = true;

  /// The timer that handles periodic stream info updates
  Timer? _streamInfoTimer;

  /// Timer for periodic JavaScript state cleanup to prevent memory accumulation.
  Timer? _jsCleanupTimer;

  /// Tracks the last time stream info was updated to prevent double refresh
  DateTime? _lastStreamInfoUpdate;

  /// Disposes the overlay reactions.
  late final ReactionDisposer _disposeOverlayReaction;

  /// Disposes the video mode reaction for timer management.
  late final ReactionDisposer _disposeVideoModeReaction;

  ReactionDisposer? _disposeAndroidAutoPipReaction;

  /// Disposes the latency settings reaction.
  ReactionDisposer? _disposeLatencySettingsReaction;

  /// Disposes the background audio wakelock reaction.
  ReactionDisposer? _disposeBackgroundAudioReaction;

  /// Whether the foreground service is currently running.
  bool _isForegroundServiceRunning = false;

  /// If the video is currently paused.
  ///
  /// Does not pause or play the video, only used for rendering state of the overlay.
  @readonly
  var _paused = true;

  /// If the overlay is should be visible.
  @readonly
  var _overlayVisible = true;

  /// The current stream info, used for displaying relevant info on the overlay.
  @readonly
  StreamTwitch? _streamInfo;

  /// The offline channel info, used for displaying channel details when offline.
  @readonly
  Channel? _offlineChannelInfo;

  @readonly
  List<String> _availableStreamQualities = [];

  // The current stream quality index
  @readonly
  int _streamQualityIndex = 0;

  // The current stream quality string
  String get streamQuality =>
      _availableStreamQualities.elementAtOrNull(_streamQualityIndex) ?? 'Auto';

  @readonly
  String? _latency;

  /// Whether the app is currently in picture-in-picture mode (iOS only).
  /// On Android, this state is not tracked since there's no programmatic exit.
  @readonly
  var _isInPipMode = false;

  /// Whether audio compressor is currently active.
  @readonly
  var _audioCompressorActive = false;

  /// The video URL to use for the webview.
  String get videoUrl =>
      'https://player.twitch.tv/?channel=$userLogin&muted=false&parent=frosty';


  /// InAppWebView settings for video playback
  InAppWebViewSettings get webViewSettings => InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
        disableContextMenu: true,
        useHybridComposition: !settingsStore.useTextureRendering,
        allowsBackForwardNavigationGestures: false,
        iframeAllowFullscreen: true,
        allowBackgroundAudioPlaying: settingsStore.backgroundAudioEnabled,
      );

  VideoStoreBase({
    required this.userLogin,
    required this.userId,
    required this.twitchApi,
    required this.authStore,
    required this.settingsStore,
  }) {
    // Initialize SimplePip with callbacks for PIP exit detection
    debugPrint('[PIP] VideoStore: registering SimplePip callbacks (onPipExited, onPipEntered)');
    pip = SimplePip(
      onPipExited: () {
        debugPrint('[PIP] VideoStore: onPipExited invoked (native -> Dart)');
        _onPipExited();
      },
      onPipEntered: () {
        debugPrint('[PIP] VideoStore: onPipEntered invoked (native -> Dart)');
        _isInPipMode = true;
      },
    );
    PipCallbackRegistry.registerPipExitedFromNative((event) {
      if (event == 'dismissed') {
        _onPipExited();
      } else if (event == 'expanded') {
        _isInPipMode = false;
      }
    });

    // Reset chat delay to 0 if auto sync is already enabled to prevent starting with old values
    if (settingsStore.autoSyncChatDelay) {
      settingsStore.chatDelay = 0.0;
    }

    // Initialize the [_overlayTimer] to auto-hide the overlay after a delay (default 5 seconds).
    _scheduleOverlayHide();

    // Initialize a reaction that will reload the webview whenever the overlay is toggled.
    _disposeOverlayReaction = reaction(
      (_) => settingsStore.showOverlay,
      (_) => _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(videoUrl)),
      ),
    );

    // Initialize a reaction to manage stream info timer based on video mode
    _disposeVideoModeReaction = reaction((_) => settingsStore.showVideo, (
      showVideo,
    ) {
      if (showVideo) {
        // In video mode, stop the timer since overlay taps handle refreshing
        _stopStreamInfoTimer();
      } else {
        // In chat-only mode, start the timer for automatic updates
        _startStreamInfoTimer();
        // Ensure overlay timer is active for clean UI
        _scheduleOverlayHide();
      }
    });

    // Check initial state and start timer if already in chat-only mode
    if (!settingsStore.showVideo) {
      _startStreamInfoTimer();
      _scheduleOverlayHide();
    }

    // On Android, enable auto PiP mode (setAutoEnterEnabled) if the device supports it.
    if (Platform.isAndroid) {
      _disposeAndroidAutoPipReaction = autorun((_) async {
        if (settingsStore.showVideo && await SimplePip.isAutoPipAvailable) {
          pip.setAutoPipMode();
        } else {
          pip.setAutoPipMode(autoEnter: false);
        }
      });
    }

    updateStreamInfo();

    // Initialize periodic JavaScript cleanup timer (every 10 minutes)
    // This prevents memory accumulation during long viewing sessions
    _jsCleanupTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _performJsSoftReset(),
    );

    // Initialize background audio management with foreground service
    if (Platform.isAndroid) {
      _initForegroundTask();

      _disposeBackgroundAudioReaction = autorun((_) {
        if (settingsStore.backgroundAudioEnabled) {
          // Keep foreground service running while on stream with bg playback on
          _startForegroundService();
          WakelockPlus.enable();
        } else if (_isForegroundServiceRunning) {
          _stopForegroundService("_disposeBackgroundAudioReaction");
          WakelockPlus.disable();
        }
      });
    }

    // React to changes in latency-related settings mid-session
    // This handles the case where user toggles autoSyncChatDelay or showLatency
    // while already watching a stream
    _disposeLatencySettingsReaction = reaction(
      (_) => (settingsStore.showLatency, settingsStore.autoSyncChatDelay),
      (values) async {
        final (showLatency, autoSync) = values;
        // Only act if overlay is enabled (latency tracker only works with custom overlay)
        if (!settingsStore.showOverlay) return;

        if (showLatency || autoSync) {
          // Start tracker if either setting is now enabled
          // The init() method is idempotent - won't double-start if already running
          await _listenOnLatencyChanges();
        } else {
          // Stop tracker if both settings are now disabled
          try {
            _webViewController?.evaluateJavascript(
              source: 'window._latencyTracker?.stop()',
            );
          } catch (e) {
            debugPrint(e.toString());
          }
        }
      },
    );
  }

  /// Called when the InAppWebView is created
  void onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;

    // Add JavaScript handlers (equivalent to addJavaScriptChannel)
    controller.addJavaScriptHandler(
      handlerName: 'Latency',
      callback: (args) {
        if (args.isEmpty) return;
        final receivedLatency = args[0].toString();
        _latency = receivedLatency;

        if (!settingsStore.autoSyncChatDelay) return;

        // Parse latency from abbreviated format: "5s" -> 5.0
        final numericPart = receivedLatency.replaceAll(
          RegExp(r'[^0-9.]'),
          '',
        );
        final latencyAsDouble = double.tryParse(numericPart);

        if (latencyAsDouble != null) {
          settingsStore.chatDelay = latencyAsDouble;
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'StreamQualities',
      callback: (args) async {
        if (args.isEmpty) return;
        final data = jsonDecode(args[0].toString()) as List;
        _availableStreamQualities =
            data.map((item) => item as String).toList();
        if (_firstTimeSettingQuality) {
          _firstTimeSettingQuality = false;
          if (settingsStore.defaultToHighestQuality) {
            await _setStreamQualityIndex(1);
            return;
          }
          final prefs = await SharedPreferences.getInstance();
          final lastStreamQuality = prefs.getString('last_stream_quality');
          if (lastStreamQuality == null) return;
          setStreamQuality(lastStreamQuality);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'VideoPause',
      callback: (args) {
        _paused = true;
        if (Platform.isAndroid) pip.setIsPlaying(false);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'VideoPlaying',
      callback: (args) {
        _paused = false;
        if (Platform.isAndroid) pip.setIsPlaying(true);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'PipEntered',
      callback: (args) {
        debugPrint('[PIP] VideoStore: PipEntered (WebView JS handler)');
        _overlayWasVisibleBeforePip = _overlayVisible;
        _isInPipMode = true;
        _overlayTimer?.cancel();
        _overlayVisible = true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'PipExited',
      callback: (args) {
        debugPrint('[PIP] VideoStore: PipExited (WebView JS handler)');
        _isInPipMode = false;
        if (_overlayWasVisibleBeforePip) {
          _updateLatencyTrackerVisibility(true);
          _scheduleOverlayHide();
        } else {
          _overlayVisible = false;
          _updateLatencyTrackerVisibility(false);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'AudioCompressorState',
      callback: (args) {
        if (args.isEmpty) return;
        final isActive = args[0] == true || args[0] == 'true';
        _audioCompressorActive = isActive;
        settingsStore.audioCompressorEnabled = isActive;
      },
    );

  }

  /// Intercepts network requests to proxy usher URLs
  Future<WebResourceResponse?> shouldInterceptRequest(
    WebResourceRequest request,
  ) async {
    // Only intercept if proxy is enabled and a proxy is selected
    if (!settingsStore.usePlaylistProxy ||
        settingsStore.selectedProxyUrl.isEmpty) {
      return null;
    }

    final url = request.url.toString();

    // Intercept usher.ttvnw.net requests and proxy them
    if (url.contains('usher.ttvnw.net')) {
      try {
        final proxyUrl = '${settingsStore.selectedProxyUrl}/$url';

        final response = await _dio.get<List<int>>(
          proxyUrl,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (status) => status != null && status < 500,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'User-Agent': request.headers?['User-Agent'] ?? 'Frosty',
              'Accept':
                  request.headers?['Accept'] ??
                  'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
              'Origin': 'https://player.twitch.tv',
              'Referer': 'https://player.twitch.tv/',
            },
          ),
        );

        if (response.data != null) {
          var contentType = 'application/vnd.apple.mpegurl';
          final responseContentType =
              response.headers.value('content-type') ?? '';
          if (responseContentType.isNotEmpty) {
            contentType = responseContentType.split(';').first;
          }

          return WebResourceResponse(
            contentType: contentType,
            contentEncoding: 'utf-8',
            statusCode: response.statusCode ?? 200,
            reasonPhrase: 'OK',
            headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
              'Access-Control-Allow-Headers': '*',
              'Cache-Control': 'no-cache',
            },
            data: Uint8List.fromList(response.data!),
          );
        }
      } catch (e) {
        debugPrint('[Usher Proxy] Error: $e');
      }
    }

    return null;
  }

  /// Called when page starts loading
  void onLoadStart(InAppWebViewController controller, WebUri? url) {
    // No-op, required callback
  }

  /// Called when page finishes loading
  Future<void> onLoadStop(InAppWebViewController controller, WebUri? url) async {
    if (url?.toString() != videoUrl) return;

    // Safe evaluation of JavaScript boolean result
    final result = await controller.evaluateJavascript(
      source: 'window._injected ? true : false',
    );
    final injected =
        result is bool ? result : (result.toString().toLowerCase() == 'true');
    if (injected) return;

    await controller.evaluateJavascript(source: 'window._injected = true;');
    await initVideo();
    _acceptContentWarning();
  }

  @action
  Future<void> updateStreamQualities() async {
    try {
      await _webViewController?.evaluateJavascript(source: r'''
      _queuePromise(async () => {
        // Open the settings → quality submenu
        (await _asyncQuerySelector('[data-a-target="player-settings-button"]')).click();
        (await _asyncQuerySelector('[data-a-target="player-settings-menu-item-quality"]')).click();

        // Wait until at least one quality option is rendered
        await _asyncQuerySelector(
          '[data-a-target="player-settings-menu"] input[name="player-settings-submenu-quality-option"] + label'
        );

        // Grab every label, normalise whitespace, return as array
        const qualities = Array.from(
          document.querySelectorAll(
            '[data-a-target="player-settings-menu"] input[name="player-settings-submenu-quality-option"] + label'
          )
        ).map(l => l.textContent.replace(/\s+/g, ' ').trim());

        window.flutter_inappwebview.callHandler('StreamQualities', JSON.stringify(qualities));

        // Close the settings panel again
        (await _asyncQuerySelector('[data-a-target="player-settings-button"]')).click();
      });
    ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @action
  Future<void> setStreamQuality(String newStreamQuality) async {
    final indexOfStreamQuality = _availableStreamQualities.indexOf(
      newStreamQuality,
    );
    if (indexOfStreamQuality == -1) return;
    await _setStreamQualityIndex(indexOfStreamQuality);
  }

  @action
  Future<void> _setStreamQualityIndex(int newStreamQualityIndex) async {
    try {
      await _webViewController?.evaluateJavascript(source: '''
        _queuePromise(async () => {
          (await _asyncQuerySelector('[data-a-target="player-settings-button"]')).click();
          (await _asyncQuerySelector('[data-a-target="player-settings-menu-item-quality"]')).click();
          await _asyncQuerySelector('[data-a-target="player-settings-submenu-quality-option"] input');
          [...document.querySelectorAll('[data-a-target="player-settings-submenu-quality-option"] input')][$newStreamQualityIndex].click();
          (await _asyncQuerySelector('[data-a-target="player-settings-button"]')).click();
        });
      ''');
      _streamQualityIndex = newStreamQualityIndex;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Hides the default Twitch overlay elements using CSS injection.
  Future<void> _hideDefaultOverlay() async {
    try {
      await _webViewController?.evaluateJavascript(source: '''
        {
          if (!document.getElementById('frosty-overlay-styles')) {
            const style = document.createElement('style');
            style.id = 'frosty-overlay-styles';
            style.textContent = `
              .top-bar,
              .player-controls,
              #channel-player-disclosures,
              [data-a-target="player-overlay-preview-background"] {
                display: none !important;
                visibility: hidden !important;
                pointer-events: none !important;
              }
              /* Keep video stats in DOM but invisible for latency reading */
              [data-a-target="player-overlay-video-stats"] {
                opacity: 0 !important;
                pointer-events: none !important;
                position: absolute !important;
                z-index: -1 !important;
              }
            `;
            document.head.appendChild(style);
          }

          // Single one-time observer just to detect when player loads
          const observer = new MutationObserver((_, obs) => {
            if (document.querySelector('.video-player__overlay')) {
              obs.disconnect();
            }
          });
          observer.observe(document.body, { childList: true, subtree: true });

          // Safety timeout: disconnect observer if player never loads
          setTimeout(() => observer.disconnect(), 30000);
        }
      ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _acceptContentWarning() async {
    try {
      await _webViewController?.evaluateJavascript(source: '''
        {
          (async () => {
            const warningBtn = await _asyncQuerySelector('button[data-a-target*="content-classification-gate"]', 10000);

            if (warningBtn) {
              warningBtn.click();
            }
          })();
        }
      ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Sets up visibility-aware latency tracking.
  Future<void> _listenOnLatencyChanges() async {
    try {
      await _webViewController?.evaluateJavascript(source: r'''
        window._latencyTracker = {
          CYCLE_INTERVAL: 15000,  // Update every 15 seconds
          STATS_ACTIVE_TIME: 2000,
          INITIAL_RETRY_INTERVAL: 2000,
          MAX_INITIAL_RETRIES: 6,

          cycleCount: 0,
          hasInitialLatency: false,
          timeoutId: null,
          isRunning: false,
          overlayVisible: true,

          init() {
            if (this.isRunning) return;
            this.isRunning = true;
            this._cycle();
          },

          stop() {
            this.isRunning = false;
            if (this.timeoutId) {
              clearTimeout(this.timeoutId);
              this.timeoutId = null;
            }
          },

          setOverlayVisible(visible) {
            this.overlayVisible = visible;
            if (visible && this.isRunning && !this.timeoutId) {
              this._cycle();
            }
          },

          async _cycle() {
            const currentTimeoutId = this.timeoutId;
            this.timeoutId = null;
            if (currentTimeoutId) {
              clearTimeout(currentTimeoutId);
            }

            if (!this.isRunning) return;

            if (!this.overlayVisible) {
              this.timeoutId = setTimeout(() => this._cycle(), 5000);
              return;
            }

            this.cycleCount++;
            const cycleStart = Date.now();

            await this._enableStats();

            const waitTime = this.cycleCount === 1 ? 3000 : this.STATS_ACTIVE_TIME;
            await new Promise(resolve => setTimeout(resolve, waitTime));

            this._readLatency();
            await this._disableStats();

            const totalActiveTime = Date.now() - cycleStart;

            let nextInterval;
            if (!this.hasInitialLatency && this.cycleCount < this.MAX_INITIAL_RETRIES) {
              nextInterval = this.INITIAL_RETRY_INTERVAL;
            } else {
              nextInterval = this.CYCLE_INTERVAL - totalActiveTime;
            }

            this.timeoutId = setTimeout(() => this._cycle(), Math.max(nextInterval, 1000));
          },

          async _enableStats() {
            try {
              await _queuePromise(async () => {
                const settingsBtn = await _asyncQuerySelector('[data-a-target="player-settings-button"]');
                console.log('[Latency] Settings button:', settingsBtn ? 'found' : 'NOT FOUND');
                if (!settingsBtn) return;
                settingsBtn.click();

                const advancedItem = await _asyncQuerySelector('[data-a-target="player-settings-menu-item-advanced"]');
                console.log('[Latency] Advanced menu item:', advancedItem ? 'found' : 'NOT FOUND');
                if (!advancedItem) {
                  settingsBtn.click();
                  return;
                }
                advancedItem.click();

                const statsCheckbox = await _asyncQuerySelector('[data-a-target="player-settings-submenu-advanced-video-stats"] input');
                console.log('[Latency] Stats checkbox:', statsCheckbox ? 'found' : 'NOT FOUND', statsCheckbox?.checked ? '(checked)' : '(unchecked)');
                if (statsCheckbox && !statsCheckbox.checked) {
                  statsCheckbox.click();
                }

                settingsBtn.click();
              });
            } catch (error) {
              console.error('[Latency] _enableStats error:', error);
            }
          },

          async _disableStats() {
            try {
              await _queuePromise(async () => {
                const settingsBtn = await _asyncQuerySelector('[data-a-target="player-settings-button"]');
                if (!settingsBtn) return;
                settingsBtn.click();

                const advancedItem = await _asyncQuerySelector('[data-a-target="player-settings-menu-item-advanced"]');
                if (!advancedItem) {
                  settingsBtn.click();
                  return;
                }
                advancedItem.click();

                const statsCheckbox = await _asyncQuerySelector('[data-a-target="player-settings-submenu-advanced-video-stats"] input');
                if (statsCheckbox && statsCheckbox.checked) {
                  statsCheckbox.click();
                }

                settingsBtn.click();
              });
            } catch (error) {
              console.error('[Latency] _disableStats error:', error);
            }
          },

          _readLatency() {
            try {
              const statsOverlay = document.querySelector('[data-a-target="player-overlay-video-stats"]');
              if (!statsOverlay) {
                console.log('[Latency] Stats overlay not found');
                return;
              }

              // Debug: dump all rows to understand structure
              const allRows = statsOverlay.querySelectorAll('tr, [class*="stat-"]');
              console.log('[Latency] Found rows:', allRows.length);

              // Find the row that contains "Latency" or "Задержка" label
              let latencyValue = null;
              const allElements = statsOverlay.querySelectorAll('*');
              
              for (const el of allElements) {
                const text = el.textContent || '';
                
                // Look for the label that indicates latency
                if (/latency|задержка/i.test(text)) {
                  // Found a latency-related element, look for the value nearby
                  const parent = el.closest('tr') || el.parentElement?.parentElement || el.parentElement;
                  if (parent) {
                    const valueMatch = parent.textContent.match(/(\d+\.?\d*)\s*(sec|сек|seconds|секунд|с\.)/i);
                    if (valueMatch && parseFloat(valueMatch[1]) > 0) {
                      latencyValue = valueMatch[1];
                      console.log('[Latency] Found in row with label:', parent.textContent.substring(0, 100));
                      break;
                    }
                  }
                }
              }

              // Fallback: search for any reasonable latency value (> 0 and < 60 seconds)
              if (!latencyValue) {
                for (const el of allElements) {
                  const text = el.textContent || '';
                  const match = text.match(/^(\d+\.?\d*)\s*(sec|сек|seconds|секунд|с\.)$/i);
                  if (match) {
                    const value = parseFloat(match[1]);
                    // Latency is typically between 0.5 and 30 seconds
                    if (value > 0.1 && value < 60) {
                      latencyValue = match[1];
                      console.log('[Latency] Found by value pattern:', text);
                      break;
                    }
                  }
                }
              }

              if (latencyValue && parseFloat(latencyValue) > 0) {
                const rounded = Math.round(parseFloat(latencyValue));
                const latencyText = rounded + 's';
                this.hasInitialLatency = true;
                console.log('[Latency] Final value:', latencyText);

                if (window.flutter_inappwebview) {
                  window.flutter_inappwebview.callHandler('Latency', latencyText);
                }
              } else {
                // Debug: dump all text content from stats overlay
                const texts = [];
                statsOverlay.querySelectorAll('p, span, td').forEach(el => {
                  const t = el.textContent?.trim();
                  if (t && t.length < 50) texts.push(t);
                });
                console.log('[Latency] All stats texts:', JSON.stringify(texts.slice(0, 20)));
              }
            } catch (error) {
              console.error('[Latency] _readLatency error:', error);
            }
          }
        };

        window._latencyTracker.init();
      ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Initializes the audio compressor JavaScript module.
  Future<void> _initAudioCompressor() async {
    final shouldEnable = settingsStore.audioCompressorEnabled;
    try {
      await _webViewController?.evaluateJavascript(source: '''
        window._audioCompressor = {
          DEFAULTS: {
            threshold: -50,
            knee: 40,
            ratio: 12,
            attack: 0,
            release: 0.25,
          },
          
          context: null,
          source: null,
          compressor: null,
          isActive: false,
          videoElement: null,
          
          async init(video) {
            if (!window.AudioContext || !window.DynamicsCompressorNode) {
              console.log('[AudioCompressor] Web Audio API not supported');
              return false;
            }
            
            if (this.context) {
              console.log('[AudioCompressor] Already initialized');
              return this.isActive;
            }
            
            if (!video || video.paused || video.ended || video.currentTime === 0) {
              console.log('[AudioCompressor] Video not ready');
              return false;
            }
            
            try {
              console.log('[AudioCompressor] Creating AudioContext');
              this.context = new AudioContext();
              this.videoElement = video;
              
              if (this.context.state === 'suspended') {
                await this.context.resume();
              }
              
              this.source = new MediaElementAudioSourceNode(this.context, {
                mediaElement: video,
              });
              
              this.compressor = new DynamicsCompressorNode(this.context, {
                threshold: this.DEFAULTS.threshold,
                knee: this.DEFAULTS.knee,
                ratio: this.DEFAULTS.ratio,
                attack: this.DEFAULTS.attack,
                release: this.DEFAULTS.release,
              });
              
              // Start with direct connection
              this.source.connect(this.context.destination);
              console.log('[AudioCompressor] Initialized successfully');
              return true;
            } catch (err) {
              console.error('[AudioCompressor] Init failed:', err);
              return false;
            }
          },
          
          async enable() {
            const video = document.querySelector('video');
            if (!video) return false;
            
            if (!this.context) {
              const initResult = await this.init(video);
              if (!initResult) return false;
            }
            
            if (this.isActive) return true;
            
            try {
              if (this.context.state === 'suspended') {
                await this.context.resume();
              }
              
              this.source.disconnect(this.context.destination);
              this.source.connect(this.compressor);
              this.compressor.connect(this.context.destination);
              this.isActive = true;
              console.log('[AudioCompressor] Enabled');
              
              if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('AudioCompressorState', true);
              }
              return true;
            } catch (err) {
              console.error('[AudioCompressor] Enable failed:', err);
              return false;
            }
          },
          
          disable() {
            if (!this.context || !this.isActive) return false;
            
            try {
              this.source.disconnect(this.compressor);
              this.compressor.disconnect(this.context.destination);
              this.source.connect(this.context.destination);
              this.isActive = false;
              console.log('[AudioCompressor] Disabled');
              
              if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('AudioCompressorState', false);
              }
              return true;
            } catch (err) {
              console.error('[AudioCompressor] Disable failed:', err);
              return false;
            }
          },
          
          async toggle() {
            if (this.isActive) {
              return !this.disable();
            } else {
              return await this.enable();
            }
          },
          
          getState() {
            return this.isActive;
          }
        };
        
        // Auto-enable if setting was on
        if ($shouldEnable) {
          setTimeout(async () => {
            const video = document.querySelector('video');
            if (video && !video.paused) {
              await window._audioCompressor.enable();
            }
          }, 1000);
        }
      ''');
    } catch (e) {
      debugPrint('Audio compressor init error: $e');
    }
  }

  /// Toggles the audio compressor on/off.
  @action
  Future<void> toggleAudioCompressor() async {
    try {
      final result = await _webViewController?.evaluateJavascript(
        source: 'window._audioCompressor?.toggle()',
      );
      // State will be updated via AudioCompressorState handler
      debugPrint('Audio compressor toggle result: $result');
    } catch (e) {
      debugPrint('Audio compressor toggle error: $e');
    }
  }

  /// Updates the latency tracker's overlay visibility state.
  void _updateLatencyTrackerVisibility(bool visible) {
    if (!settingsStore.showLatency && !settingsStore.autoSyncChatDelay) return;

    if (settingsStore.autoSyncChatDelay) {
      try {
        _webViewController?.evaluateJavascript(
          source: 'window._latencyTracker?.setOverlayVisible(true)',
        );
      } catch (e) {
        debugPrint(e.toString());
      }
      return;
    }

    try {
      _webViewController?.evaluateJavascript(
        source: 'window._latencyTracker?.setOverlayVisible($visible)',
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Performs a soft reset of JavaScript state to prevent memory accumulation.
  void _performJsSoftReset() {
    try {
      _webViewController?.evaluateJavascript(source: '''
        if (window._promiseQueueLength === 0) {
          window._PROMISE_QUEUE = Promise.resolve();
          window._promiseQueueGen = (window._promiseQueueGen || 0) + 1;
        }
      ''');
    } catch (e) {
      debugPrint('JS soft reset error: $e');
    }
  }

  /// Initializes the video webview.
  @action
  Future<void> initVideo() async {
    final currentUrl = await _webViewController?.getUrl();
    if (currentUrl?.toString() == videoUrl) {
      try {
        await _webViewController?.evaluateJavascript(source: '''
          // Promise queue with length limit and generation tracking
          window._PROMISE_QUEUE = Promise.resolve();
          window._promiseQueueLength = 0;
          window._promiseQueueGen = 0;

          window._queuePromise = (method) => {
            window._promiseQueueLength++;

            if (window._promiseQueueLength > 30) {
              window._PROMISE_QUEUE = Promise.resolve();
              window._promiseQueueLength = 1;
              window._promiseQueueGen++;
            }

            const myGen = window._promiseQueueGen;

            window._PROMISE_QUEUE = window._PROMISE_QUEUE.then(async () => {
              try {
                await method();
              } catch (e) {
                console.warn('Queue promise error:', e);
              } finally {
                if (myGen === window._promiseQueueGen) {
                  window._promiseQueueLength--;
                }
              }
            });

            return window._PROMISE_QUEUE;
          };

          window._asyncQuerySelector = (selector, timeout = 30000) => new Promise((resolve) => {
            let element = document.querySelector(selector);
            if (element) {
              return resolve(element);
            }

            let timeoutId;
            const observer = new MutationObserver(() => {
              element = document.querySelector(selector);
              if (element) {
                observer.disconnect();
                clearTimeout(timeoutId);
                resolve(element);
              }
            });
            observer.observe(document.body, { childList: true, subtree: true });

            timeoutId = setTimeout(() => {
              observer.disconnect();
              resolve(undefined);
            }, timeout);
          });

          _queuePromise(async () => {
            const videoElement = await _asyncQuerySelector("video");

            if (!videoElement) {
              console.warn("Video element not found within timeout");
              return;
            }

            if (!videoElement._listenersAdded) {
              videoElement._listenersAdded = true;

              videoElement.addEventListener("pause", () => {
                window.flutter_inappwebview.callHandler('VideoPause', 'video paused');
                if (videoElement.textTracks && videoElement.textTracks.length > 0) {
                  videoElement.textTracks[0].mode = "hidden";
                }
              });
              videoElement.addEventListener("playing", () => {
                window.flutter_inappwebview.callHandler('VideoPlaying', 'video playing');
                videoElement.muted = false;
                videoElement.volume = 1.0;
                if (videoElement.textTracks && videoElement.textTracks.length > 0) {
                  videoElement.textTracks[0].mode = "hidden";
                }
              });

              videoElement.addEventListener("enterpictureinpicture", () => {
                window.flutter_inappwebview.callHandler('PipEntered', 'pip entered');
              });
              videoElement.addEventListener("leavepictureinpicture", () => {
                window.flutter_inappwebview.callHandler('PipExited', 'pip exited');
              });
            }

            if (!videoElement.paused) {
              window.flutter_inappwebview.callHandler('VideoPlaying', 'video playing');
              videoElement.muted = false;
              videoElement.volume = 1.0;
              if (videoElement.textTracks && videoElement.textTracks.length > 0) {
                videoElement.textTracks[0].mode = "hidden";
              }
            }
          });
        ''');
        if (settingsStore.showOverlay) {
          await _hideDefaultOverlay();
          if (settingsStore.showLatency || settingsStore.autoSyncChatDelay) {
            await _listenOnLatencyChanges();
          }
          await updateStreamQualities();
          await _initAudioCompressor();
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  /// Called whenever the video/overlay is tapped.
  @action
  void handleVideoTap() {
    if (_isInPipMode) {
      _overlayVisible = true;
      return;
    }

    _overlayTimer?.cancel();

    if (_overlayVisible) {
      _overlayVisible = false;
      _updateLatencyTrackerVisibility(false);
    } else {
      updateStreamInfo(forceUpdate: true);

      _overlayVisible = true;
      _updateLatencyTrackerVisibility(true);
      _scheduleOverlayHide();
    }
  }

  /// Starts the periodic stream info timer for chat-only mode.
  void _startStreamInfoTimer() {
    if (_streamInfoTimer?.isActive != true) {
      _streamInfoTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => updateStreamInfo(),
      );
    }
  }

  /// Stops the periodic stream info timer.
  void _stopStreamInfoTimer() {
    if (_streamInfoTimer?.isActive == true) {
      _streamInfoTimer?.cancel();
      _streamInfoTimer = null;
    }
  }

  void _scheduleOverlayHide([Duration delay = const Duration(seconds: 5)]) {
    _overlayTimer?.cancel();

    if (_isInPipMode) {
      _overlayVisible = true;
      return;
    }

    _overlayTimer = Timer(delay, () {
      if (_isInPipMode) return;

      runInAction(() {
        _overlayVisible = false;
      });
      _updateLatencyTrackerVisibility(false);
    });
  }

  /// Handles app resume event for immediate stream info refresh in chat-only mode.
  @action
  void handleAppResume() {
    if (!settingsStore.showVideo) {
      updateStreamInfo(forceUpdate: true);
    }
    // Re-start foreground service when returning to app if background audio is on
    if (Platform.isAndroid && settingsStore.backgroundAudioEnabled) {
      _startForegroundService();
      WakelockPlus.enable();
    }
  }

  /// Updates the stream info from the Twitch API.
  @action
  Future<void> updateStreamInfo({bool forceUpdate = false}) async {
    final now = DateTime.now();
    if (!forceUpdate && _lastStreamInfoUpdate != null) {
      final timeSinceLastUpdate = now.difference(_lastStreamInfoUpdate!);
      if (timeSinceLastUpdate.inSeconds < 5) {
        return;
      }
    }

    _lastStreamInfoUpdate = now;

    try {
      _streamInfo = await twitchApi.getStream(userLogin: userLogin);
      _offlineChannelInfo = null;
    } catch (e) {
      _overlayTimer?.cancel();
      _streamInfo = null;
      _paused = true;

      try {
        _offlineChannelInfo = await twitchApi.getChannel(userId: userId);
      } catch (channelError) {
        _offlineChannelInfo = null;
      }

      if (!settingsStore.showVideo) {
        _scheduleOverlayHide();
      }
    }
  }

  /// Handles the toggle overlay options.
  @action
  void handleToggleOverlay() {
    if (settingsStore.toggleableOverlay) {
      HapticFeedback.mediumImpact();

      settingsStore.showOverlay = !settingsStore.showOverlay;

      if (settingsStore.showOverlay) {
        _overlayVisible = true;
        _scheduleOverlayHide(const Duration(seconds: 3));
      }
    }
  }

  /// Refreshes the stream webview and updates the stream info.
  @action
  Future<void> handleRefresh() async {
    HapticFeedback.lightImpact();
    _paused = true;
    _firstTimeSettingQuality = true;
    _isInPipMode = false;

    try {
      _webViewController?.evaluateJavascript(
        source: 'window._latencyTracker?.stop()',
      );
    } catch (e) {
      // Ignore
    }

    await _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    await _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(videoUrl)),
    );

    updateStreamInfo();
  }

  /// Play or pause the video depending on the current state of [_paused].
  void handlePausePlay() {
    try {
      if (_paused) {
        _webViewController?.evaluateJavascript(
          source: 'document.getElementsByTagName("video")[0].play();',
        );
      } else {
        _webViewController?.evaluateJavascript(
          source: 'document.getElementsByTagName("video")[0].pause();',
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Initiate picture in picture if available.
  void requestPictureInPicture() {
    try {
      if (Platform.isAndroid) {
        pip.enterPipMode(autoEnter: true);
      } else if (Platform.isIOS) {
        _webViewController?.evaluateJavascript(
          source:
              'document.getElementsByTagName("video")[0].requestPictureInPicture();',
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Toggle picture-in-picture mode.
  @action
  void togglePictureInPicture() {
    try {
      if (Platform.isIOS && _isInPipMode) {
        _webViewController?.evaluateJavascript(source: '''
          (function() {
            if (document.pictureInPictureElement) {
              document.exitPictureInPicture();
            }
          })();
          ''');
      } else {
        requestPictureInPicture();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Initializes the foreground task for background audio playback.
  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'background_audio_channel',
        channelName: 'Background Audio',
        channelDescription: 'Playing stream audio in background',
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
        notificationText: 'Playing $userLogin stream',
        notificationIcon: null,
        notificationButtons: const [
          NotificationButton(id: 'pause', text: 'Pause'),
        ],
        callback: backgroundAudioTaskCallback,
      );
      _isForegroundServiceRunning = true;
      BackgroundPlaybackCallbackRegistry.register(_onNotificationPauseOrDismiss);
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
    }
  }

  /// Called when user taps Pause in notification or swipes notification away.
  void _onNotificationPauseOrDismiss() {
    if (_paused) return;
    handlePausePlay();
    _paused = true;
    if (Platform.isAndroid && settingsStore.backgroundAudioEnabled) {
      _stopForegroundService("notification");
      WakelockPlus.disable();
    }
  }

  /// Stops the foreground service.
  Future<void> _stopForegroundService(String reason) async {
    debugPrint(
      '[PIP] VideoStore: _stopForegroundService called, '
      '_isForegroundServiceRunning=$_isForegroundServiceRunning, reason=$reason',
    );
    if (!_isForegroundServiceRunning) return;

    BackgroundPlaybackCallbackRegistry.unregister();
    try {
      await FlutterForegroundTask.stopService();
      _isForegroundServiceRunning = false;
      debugPrint('[PIP] VideoStore: foreground service stopped');
    } catch (e) {
      debugPrint('[PIP] VideoStore: failed to stop foreground service: $e');
    }
  }

  @action
  void dispose() {
    PipCallbackRegistry.registerPipExitedFromNative(null);
    if (Platform.isAndroid) {
      SimplePip.isAutoPipAvailable.then((isAutoPipAvailable) {
        if (isAutoPipAvailable) pip.setAutoPipMode(autoEnter: false);
      });
    }

    _overlayTimer?.cancel();
    _streamInfoTimer?.cancel();
    _jsCleanupTimer?.cancel();

    _disposeOverlayReaction();
    _disposeVideoModeReaction();
    _disposeAndroidAutoPipReaction?.call();
    _disposeLatencySettingsReaction?.call();
    _disposeBackgroundAudioReaction?.call();

    // Stop foreground service and disable wakelock when leaving video screen
    if (Platform.isAndroid) {
      _stopForegroundService("dispose");
      if (settingsStore.backgroundAudioEnabled) {
        WakelockPlus.disable();
      }
    }

    try {
      _webViewController?.evaluateJavascript(
        source: 'window._latencyTracker?.stop()',
      );
    } catch (e) {
      // Ignore
    }

    _dio.close();
  }
}


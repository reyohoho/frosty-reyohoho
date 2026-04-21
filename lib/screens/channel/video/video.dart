import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/channel/video/video_store.dart';
import 'package:frosty/widgets/native_player/native_player_controller.dart';
import 'package:frosty/widgets/native_player/native_player_view.dart';
import 'package:simple_pip_mode/simple_pip.dart';

/// Renders the channel's live video.
///
/// Two backends are supported and picked at build time based on
/// `settingsStore.useNativePlayer`:
///  * WebView (default) — embeds `https://player.twitch.tv/` via flutter_inappwebview.
///  * Native (Android only) — spins up a Media3/ExoPlayer PlatformView with
///    a patched HLS playlist parser (`#EXT-X-TWITCH-PREFETCH` LL-HLS tags).
class Video extends StatefulWidget {
  final VideoStore videoStore;

  const Video({super.key, required this.videoStore});

  @override
  State<Video> createState() => _VideoState();
}

class _VideoState extends State<Video> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState lifecycleState) async {
    final controller = widget.videoStore.webViewController;
    final backgroundAudioEnabled = widget.videoStore.settingsStore.backgroundAudioEnabled;

    if (Platform.isAndroid) {
      // Handle background audio playback
      if (backgroundAudioEnabled && controller != null) {
        if (lifecycleState == AppLifecycleState.paused || lifecycleState == AppLifecycleState.hidden) {
          // Keep WebView running in background for audio playback
          await controller.resume();
        }
      }

      // Handle PiP mode
      if (!await SimplePip.isAutoPipAvailable &&
          lifecycleState == AppLifecycleState.inactive &&
          widget.videoStore.settingsStore.showVideo &&
          !backgroundAudioEnabled) {
        widget.videoStore.requestPictureInPicture();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.videoStore.settingsStore.showVideo) {
      return const SizedBox.shrink();
    }

    return Observer(
      builder: (context) {
        if (widget.videoStore.useNativePlayer) {
          return _NativeVideo(videoStore: widget.videoStore);
        }
        return _WebViewVideo(videoStore: widget.videoStore);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      widget.videoStore.webViewController
          ?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')))
          .catchError((_) {});
    } catch (_) {
      // WebView controller may already be disposed by platform
    }

    super.dispose();
  }
}

/// Legacy WebView-backed video implementation. Unchanged from before the
/// native-player option was introduced.
class _WebViewVideo extends StatelessWidget {
  final VideoStore videoStore;

  const _WebViewVideo({required this.videoStore});

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(videoStore.videoUrl)),
      initialSettings: videoStore.webViewSettings,
      onWebViewCreated: videoStore.onWebViewCreated,
      onLoadStart: videoStore.onLoadStart,
      onLoadStop: videoStore.onLoadStop,
      onConsoleMessage: (controller, consoleMessage) {
        // debugPrint('[WebView Console] ${consoleMessage.message}');
      },
      shouldInterceptRequest: (controller, request) async {
        return videoStore.shouldInterceptRequest(request);
      },
    );
  }
}

/// Native ExoPlayer-backed video implementation. On Android only.
class _NativeVideo extends StatefulWidget {
  final VideoStore videoStore;

  const _NativeVideo({required this.videoStore});

  @override
  State<_NativeVideo> createState() => _NativeVideoState();
}

class _NativeVideoState extends State<_NativeVideo> {
  late final NativePlayerController _controller;
  bool _bootstrapScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.videoStore.nativePlayerController;
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      // Shouldn't happen because VideoStore.useNativePlayer is gated on Android.
      return const ColoredBox(color: Colors.black);
    }
    return _PlatformViewBootstrapper(
      controller: _controller,
      onReady: _maybeBootstrap,
    );
  }

  void _maybeBootstrap() {
    if (_bootstrapScheduled) return;
    _bootstrapScheduled = true;
    // Defer to the next frame so the PlatformView is fully wired up before we
    // start firing commands on it.
    scheduleMicrotask(() async {
      if (!mounted) return;
      try {
        await widget.videoStore.reloadNativeStream();
      } catch (e) {
        debugPrint('[native_player] bootstrap failed: $e');
      }
    });
  }
}

/// Thin wrapper around [NativePlayerView] that fires [onReady] exactly once,
/// right after the native Android PlatformView has been attached.
class _PlatformViewBootstrapper extends StatefulWidget {
  final NativePlayerController controller;
  final VoidCallback onReady;

  const _PlatformViewBootstrapper({
    required this.controller,
    required this.onReady,
  });

  @override
  State<_PlatformViewBootstrapper> createState() => _PlatformViewBootstrapperState();
}

class _PlatformViewBootstrapperState extends State<_PlatformViewBootstrapper> {
  late final ReactionCheckTimer _timer;

  @override
  void initState() {
    super.initState();
    _timer = ReactionCheckTimer(
      isReady: () => widget.controller.isAttached,
      onReady: widget.onReady,
    )..start();
  }

  @override
  void dispose() {
    _timer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        NativePlayerView(controller: widget.controller),
        Observer(
          builder: (_) {
            if (!widget.controller.adActive) return const SizedBox.shrink();
            return const _AdOverlay();
          },
        ),
      ],
    );
  }
}

/// Shown while the native player is muting/blanking a Twitch-stitched ad.
class _AdOverlay extends StatelessWidget {
  const _AdOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white70,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Waiting for ads…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Twitch is stitching an ad into the stream. Video and audio are '
            'muted until it ends. Quality cannot be changed during an ad.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Tiny utility that polls a predicate every 50ms and fires a callback once,
/// the first time it flips to `true`. Kept private so we don't expose it from
/// the controller API.
class ReactionCheckTimer {
  ReactionCheckTimer({required this.isReady, required this.onReady});

  final bool Function() isReady;
  final VoidCallback onReady;

  Timer? _t;

  void start() {
    _t = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (isReady()) {
        t.cancel();
        _t = null;
        onReady();
      }
    });
  }

  void stop() {
    _t?.cancel();
    _t = null;
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:frosty/screens/channel/video/video_store.dart';
import 'package:simple_pip_mode/simple_pip.dart';

/// Creates an [InAppWebView] widget that shows a channel's video stream.
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
  Future<void> didChangeAppLifecycleState(
    AppLifecycleState lifecycleState,
  ) async {
    if (Platform.isAndroid &&
        !await SimplePip.isAutoPipAvailable &&
        lifecycleState == AppLifecycleState.inactive &&
        widget.videoStore.settingsStore.showVideo) {
      widget.videoStore.requestPictureInPicture();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.videoStore.settingsStore.showVideo) {
      return const SizedBox.shrink();
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(widget.videoStore.videoUrl),
      ),
      initialSettings: widget.videoStore.webViewSettings,
      onWebViewCreated: widget.videoStore.onWebViewCreated,
      onLoadStart: widget.videoStore.onLoadStart,
      onLoadStop: widget.videoStore.onLoadStop,
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('[WebView Console] ${consoleMessage.message}');
      },
      shouldInterceptRequest: (controller, request) async {
        return widget.videoStore.shouldInterceptRequest(request);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.videoStore.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );

    super.dispose();
  }
}

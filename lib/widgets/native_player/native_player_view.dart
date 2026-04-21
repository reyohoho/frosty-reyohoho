import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:frosty/widgets/native_player/native_player_controller.dart';

/// Wrapper around [AndroidView] that spins up the native ExoPlayer-backed
/// `NativePlayerView`.
///
/// * Uses hybrid composition so Flutter overlays (custom video overlay,
///   chat column, gestures) can be stacked on top of the video surface.
/// * Passes touch events through via a TLDR gesture arena config — the
///   native view itself does not show any controls (useController=false).
class NativePlayerView extends StatelessWidget {
  final NativePlayerController controller;
  final Map<String, Object?> creationParams;

  const NativePlayerView({
    super.key,
    required this.controller,
    this.creationParams = const {},
  });

  /// Id registered by [MainActivity.configureFlutterEngine].
  static const String _viewType = 'ru.refrosty/native_player';

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ColoredBox(color: Colors.black);
    }
    final gestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    };
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: gestureRecognizers,
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        )
          ..addOnPlatformViewCreatedListener((id) {
            controller.attach(id);
            params.onPlatformViewCreated(id);
          })
          ..create();
      },
    );
  }
}

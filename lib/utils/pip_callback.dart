import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registry for PIP exit callback. When Android fires onPictureInPictureModeChanged(false)
/// we receive "expanded" (returned to app) or "dismissed" (swiped away) and invoke the callback.
class PipCallbackRegistry {
  PipCallbackRegistry._();

  static void Function(String event)? _onPipExitedFromNative;

  /// Registers the callback: (event) where event is "expanded" or "dismissed".
  /// Pass [null] to unregister (e.g. on dispose).
  static void registerPipExitedFromNative(void Function(String event)? callback) {
    _onPipExitedFromNative = callback;
  }

  /// Called when we receive an event from native. Invokes the registered callback with the event.
  static void invokePipExitedFromNative(String event) {
    debugPrint('[PIP] PipCallbackRegistry: received "$event" from native');
    _onPipExitedFromNative?.call(event);
  }
}

const _pipEventChannel = EventChannel('ru.refrosty/pip');

/// Starts listening to PIP events from native (e.g. pip exited).
/// Call once from a widget that is mounted for the app lifetime.
void pipEventChannelListen() {
  if (!Platform.isAndroid) return;
  _pipEventChannel.receiveBroadcastStream().listen(
    (dynamic event) {
      if (event == 'expanded' || event == 'dismissed') {
        PipCallbackRegistry.invokePipExitedFromNative(event as String);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      debugPrint('[PIP] pipEventChannel error: $error');
    },
  );
}

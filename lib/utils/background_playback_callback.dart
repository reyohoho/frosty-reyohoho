import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Registry for foreground service notification actions (pause button, swipe dismiss).
/// VideoStore and VodPlayerScreen register when they start the service and unregister on stop.
class BackgroundPlaybackCallbackRegistry {
  BackgroundPlaybackCallbackRegistry._();

  static void Function()? _onPauseOrStop;

  /// Registers the callback for both pause button and notification dismiss.
  /// Pass [null] to unregister (e.g. when stopping the service).
  static void register(void Function()? callback) {
    _onPauseOrStop = callback;
  }

  /// Unregisters the callback.
  static void unregister() {
    _onPauseOrStop = null;
  }

  /// Called when the task sends data (pause button or dismissed). Invokes the registered callback.
  static void invoke(Object data) {
    if (data == 'pause' || data == 'dismissed') {
      _onPauseOrStop?.call();
    }
  }
}

/// Task handler for background audio notification: pause button and dismiss → send to main.
class _BackgroundAudioTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Service stays running until stopped; nothing to do here.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'pause') {
      FlutterForegroundTask.sendDataToMain('pause');
    }
  }

  @override
  void onNotificationDismissed() {
    FlutterForegroundTask.sendDataToMain('dismissed');
  }
}

/// Top-level callback run in the task isolate. Sets the TaskHandler so button/dismiss are handled.
@pragma('vm:entry-point')
void backgroundAudioTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_BackgroundAudioTaskHandler());
}

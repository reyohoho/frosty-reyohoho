import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('ru.refrosty/display_cutout');

/// Applies display-under-cutout mode on Android (landscape).
/// When [enabled] is true, the app draws under the display cutout (notch) on short edges.
/// No-op on iOS and when [enabled] is false on Android.
Future<void> applyDisplayUnderCutout(bool enabled) async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('setDisplayUnderCutout', enabled);
  } on PlatformException catch (e) {
    debugPrint('Display cutout: $e');
  }
}

import 'package:flutter/material.dart';

/// Global navigator key for [MaterialApp]. Kept in a small library so stores and
/// interceptors can show UI without importing [main.dart].
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

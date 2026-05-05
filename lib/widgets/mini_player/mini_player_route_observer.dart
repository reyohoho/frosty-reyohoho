import 'package:flutter/material.dart';

/// A [RouteObserver] dedicated to channel routes ([VideoChat]). The channel
/// screen subscribes via [RouteAware] in `initState` so it gets `didPush`,
/// `didPop`, `didPopNext`, `didPushNext` callbacks and can drive the global
/// [MiniPlayerStore] presentation accordingly.
///
/// We use a dedicated observer (instead of the bare `MaterialApp.navigatorObservers`)
/// so non-channel routes don't accidentally trigger mini-player transitions.
final RouteObserver<ModalRoute<void>> miniPlayerRouteObserver =
    RouteObserver<ModalRoute<void>>();

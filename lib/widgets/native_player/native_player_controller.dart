import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:frosty/apis/twitch_playlist_api.dart';
import 'package:mobx/mobx.dart';

part 'native_player_controller.g.dart';

/// Current Media3 playback state mirrored to Dart.
enum NativePlayerState { idle, buffering, ready, ended, unknown }

/// Descriptor of a single ABR variant reported by ExoPlayer, independent from
/// the master-playlist variants downloaded upfront.
@immutable
class NativeVariant {
  final int index;
  final int width;
  final int height;
  final int bitrate;
  final double? frameRate;
  final String? codecs;
  final String? label;

  const NativeVariant({
    required this.index,
    required this.width,
    required this.height,
    required this.bitrate,
    this.frameRate,
    this.codecs,
    this.label,
  });

  factory NativeVariant.fromMap(Map<dynamic, dynamic> map) => NativeVariant(
    index: (map['index'] as num?)?.toInt() ?? 0,
    width: (map['width'] as num?)?.toInt() ?? 0,
    height: (map['height'] as num?)?.toInt() ?? 0,
    bitrate: (map['bitrate'] as num?)?.toInt() ?? 0,
    frameRate: (map['frameRate'] as num?)?.toDouble(),
    codecs: map['codecs'] as String?,
    label: map['label'] as String?,
  );
}

/// MobX-backed bridge to a native [NativePlayerView] (PlatformView) Android
/// instance. Manages the per-viewId MethodChannel + EventChannel created by
/// `android/app/src/main/java/ru/refrosty/player/NativePlayerView.kt`.
class NativePlayerController = NativePlayerControllerBase with _$NativePlayerController;

abstract class NativePlayerControllerBase with Store {
  NativePlayerControllerBase();

  MethodChannel? _methodChannel;
  StreamSubscription<dynamic>? _eventSub;

  /// Latest reported playback state.
  @observable
  NativePlayerState state = NativePlayerState.idle;

  /// `true` when ExoPlayer is actively rendering frames (not buffering, paused).
  @observable
  bool isPlaying = false;

  /// Mirrors `ExoPlayer.playWhenReady`. The user pressed play but we may still
  /// be buffering.
  @observable
  bool playWhenReady = false;

  /// Most recent native error, if any.
  @observable
  String? lastError;

  /// Video surface size reported by ExoPlayer.
  @observable
  int videoWidth = 0;

  @observable
  int videoHeight = 0;

  /// ABR variants reported by ExoPlayer's current Tracks after preparation.
  /// Generally narrower than the master-playlist list, but still useful for
  /// the quality chooser to cross-reference.
  @observable
  ObservableList<NativeVariant> variants = ObservableList<NativeVariant>();

  /// Master-playlist variants fetched upfront via [TwitchPlaylistApi].
  /// These drive the quality UI the same way as the old WebView flow.
  @observable
  ObservableList<TwitchHlsVariant> masterVariants = ObservableList<TwitchHlsVariant>();

  /// Currently selected quality identifier. One of:
  ///   * `'auto'` — let ExoPlayer choose (clears all size/bitrate caps).
  ///   * `'audio_only'` — audio-only track (caps video size at 1x1 effectively).
  ///   * `'<groupId>'` — force a specific variant from [masterVariants].
  @observable
  String selectedQuality = 'auto';

  /// Current live latency in milliseconds, as derived from the active HLS
  /// media playlist's `#EXT-X-PROGRAM-DATE-TIME`. `null` if unknown.
  @observable
  int? latencyMs;

  /// `true` while the native player has detected a Twitch-stitched ad and
  /// is hiding video + muting audio (mirrors Xtra's `hideAds`). The UI can
  /// use this to show a "waiting for ads…" indicator.
  @observable
  bool adActive = false;

  /// Internal: whether the native MethodChannel has been wired up.
  bool get isAttached => _methodChannel != null;

  /// Called by [NativePlayerView.onPlatformViewCreated] once the native side
  /// exists. Binds the per-viewId channels.
  void attach(int viewId) {
    if (_methodChannel != null) return;
    _methodChannel = MethodChannel('ru.refrosty/native_player/$viewId');
    final events = EventChannel('ru.refrosty/native_player/events/$viewId');
    _eventSub = events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object err, StackTrace st) {
        debugPrint('[native_player] event stream error: $err');
      },
    );
  }

  /// Severs the native channels. Safe to call multiple times.
  Future<void> detach() async {
    try {
      await _eventSub?.cancel();
    } catch (_) {}
    _eventSub = null;
    _methodChannel = null;
  }

  void _onEvent(dynamic data) {
    if (data is! Map) return;
    final name = data['event'] as String?;
    switch (name) {
      case 'playing':
        _applyPlayingEvent(data);
        break;
      case 'tracks':
        final raw = (data['variants'] as List?) ?? const [];
        runInAction(() {
          variants
            ..clear()
            ..addAll(raw.whereType<Map>().map(NativeVariant.fromMap));
        });
        break;
      case 'videoSize':
        runInAction(() {
          videoWidth = (data['width'] as num?)?.toInt() ?? 0;
          videoHeight = (data['height'] as num?)?.toInt() ?? 0;
        });
        break;
      case 'error':
        runInAction(() {
          lastError = (data['message'] as String?) ?? (data['code'] as String?);
          isPlaying = false;
          state = NativePlayerState.idle;
        });
        break;
      case 'audioSession':
        // no-op on Dart side for now.
        break;
      case 'ad':
        runInAction(() {
          adActive = (data['active'] as bool?) ?? false;
        });
        break;
    }
  }

  Future<void> setHideAds(bool enabled) async {
    await _methodChannel?.invokeMethod<void>('setHideAds', {'enabled': enabled});
  }

  @action
  void _applyPlayingEvent(Map<dynamic, dynamic> data) {
    isPlaying = (data['isPlaying'] as bool?) ?? false;
    playWhenReady = (data['playWhenReady'] as bool?) ?? false;
    final s = data['playbackState'] as String?;
    state = switch (s) {
      'idle' => NativePlayerState.idle,
      'buffering' => NativePlayerState.buffering,
      'ready' => NativePlayerState.ready,
      'ended' => NativePlayerState.ended,
      _ => NativePlayerState.unknown,
    };
  }

  // region commands

  Future<void> setDataSource(
    String url, {
    String? userAgent,
    Map<String, String>? headers,
    String? proxyBase,
  }) async {
    lastError = null;
    // Kotlin clears any previous TrackSelectionOverride on every
    // setDataSource; mirror that on the Dart side so the quality chooser
    // reflects "Auto" until the user (or VideoStore) picks something on the
    // freshly loaded master playlist.
    selectedQuality = 'auto';
    await _methodChannel?.invokeMethod<void>('setDataSource', {
      'url': url,
      if (userAgent != null) 'userAgent': userAgent,
      if (headers != null) 'headers': headers,
      if (proxyBase != null && proxyBase.isNotEmpty) 'proxyBase': proxyBase,
    });
  }

  Future<void> play() async {
    await _methodChannel?.invokeMethod<void>('play');
  }

  Future<void> pause() async {
    await _methodChannel?.invokeMethod<void>('pause');
  }

  Future<void> setVolume(double v) async {
    await _methodChannel?.invokeMethod<void>('setVolume', {'volume': v});
  }

  Future<void> seekToLive() async {
    await _methodChannel?.invokeMethod<void>('seekToLive');
  }

  /// Applies a quality constraint using ExoPlayer's TrackSelectionParameters.
  ///
  /// If [variant] is null (or `'auto'` is selected), all constraints are
  /// cleared. Otherwise we cap max video width/height to the variant's
  /// resolution and bitrate to its bandwidth, which for Twitch effectively
  /// pins ExoPlayer to that variant (their rungs are well separated).
  @action
  Future<void> applyQuality(TwitchHlsVariant? variant) async {
    if (variant == null) {
      selectedQuality = 'auto';
      await _methodChannel?.invokeMethod<void>('setMaxVideoSize', {
        'width': null,
        'height': null,
        'bitrate': null,
      });
      return;
    }
    if (variant.audioOnly) {
      selectedQuality = 'audio_only';
      await _methodChannel?.invokeMethod<void>('setMaxVideoSize', {
        'width': 1,
        'height': 1,
        'bitrate': 1000,
      });
      return;
    }
    selectedQuality = variant.groupId;
    await _methodChannel?.invokeMethod<void>('setMaxVideoSize', {
      'width': variant.width,
      'height': variant.height,
      if (variant.bandwidth != null) 'bitrate': variant.bandwidth,
    });
  }

  Future<void> setMirror(bool enabled) async {
    await _methodChannel?.invokeMethod<void>('setMirror', {'enabled': enabled});
  }

  Future<void> setDynamicsProcessing(bool enabled) async {
    await _methodChannel?.invokeMethod<void>('setDynamicsProcessing', {'enabled': enabled});
  }

  /// Asks the native side to recompute latency from the current HLS media
  /// playlist and stores it in [latencyMs]. Call this on a timer.
  Future<void> refreshLatency() async {
    final v = await _methodChannel?.invokeMethod<dynamic>('getLatencyMs');
    runInAction(() {
      if (v is int) {
        latencyMs = v;
      } else if (v is num) {
        latencyMs = v.toInt();
      } else {
        latencyMs = null;
      }
    });
  }

  // endregion
}

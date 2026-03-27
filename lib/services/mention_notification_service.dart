import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android: no audio focus request so stream WebView audio keeps playing.
/// iOS: [mixWithOthers] so mention ping does not take over [AVAudioSession] and pause WKWebView.
final AudioContext _mentionAudioContext = AudioContext(
  android: const AudioContextAndroid(
    audioFocus: AndroidAudioFocus.none,
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.notification,
  ),
  iOS: AudioContextIOS(
    options: {AVAudioSessionOptions.mixWithOthers},
  ),
);

/// Service for handling mention notifications (vibration and sound).
class MentionNotificationService {
  static final MentionNotificationService _instance =
      MentionNotificationService._internal();

  factory MentionNotificationService() => _instance;

  MentionNotificationService._internal();

  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;

  /// Initialize the audio player for notification sounds.
  Future<void> init() async {
    if (_isInitialized) return;
    _audioPlayer = AudioPlayer();
    _audioPlayer?.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer?.setAudioContext(_mentionAudioContext);

    await rootBundle.load('assets/sounds/mention.ogg');

    _isInitialized = true;
  }

  /// Trigger vibration feedback for mention notification.
  Future<void> vibrate() async {
    // Use multiple haptic impacts for a more noticeable vibration
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Play notification sound for mention with specified volume (0.0 to 1.0).
  Future<void> playSound({double volume = 0.5}) async {
    if (!_isInitialized) await init();
    try {
      await _audioPlayer?.setVolume(volume);
      await _audioPlayer?.play(AssetSource('sounds/mention.ogg'));
    } catch (e) {
      debugPrint('Failed to play mention sound: $e');
    }
  }

  /// Trigger mention notification based on settings.
  Future<void> notify({
    required bool vibrationEnabled,
    required bool soundEnabled,
    double soundVolume = 0.5,
  }) async {
    if (vibrationEnabled) {
      vibrate();
    }
    if (soundEnabled) {
      playSound(volume: soundVolume);
    }
  }

  /// Dispose of the audio player resources.
  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _isInitialized = false;
  }
}

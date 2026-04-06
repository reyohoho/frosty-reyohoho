import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/widgets/settings_list_switch.dart';
import 'package:frosty/utils.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:frosty/widgets/settings_page_layout.dart';

class VideoSettings extends StatefulWidget {
  final SettingsStore settingsStore;

  const VideoSettings({super.key, required this.settingsStore});

  @override
  State<VideoSettings> createState() => _VideoSettingsState();
}

class _VideoSettingsState extends State<VideoSettings> {
  void _handleProxyToggle(bool newValue) {
    widget.settingsStore.usePlaylistProxy = newValue;
  }

  Future<void> _handleBackgroundAudioToggle(bool newValue) async {
    if (newValue && Platform.isAndroid) {
      // Request notification permission on Android 13+
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }
    widget.settingsStore.backgroundAudioEnabled = newValue;
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => SettingsPageLayout(
        children: [
          const SectionHeader('Player', isFirst: true),
          SettingsListSwitch(
            title: 'Enable video',
            value: widget.settingsStore.showVideo,
            onChanged: (newValue) => widget.settingsStore.showVideo = newValue,
          ),
          if (!Platform.isIOS || isIPad())
            SettingsListSwitch(
              title: 'Default to highest quality',
              value: widget.settingsStore.defaultToHighestQuality,
              onChanged: (newValue) =>
                  widget.settingsStore.defaultToHighestQuality = newValue,
            ),
          if (Platform.isAndroid)
            SettingsListSwitch(
              title: 'Use fast video rendering',
              subtitle: const Text(
                'Uses a faster WebView rendering method. Disable if you experience crashes while watching streams.',
              ),
              value: widget.settingsStore.useTextureRendering,
              onChanged: (newValue) =>
                  widget.settingsStore.useTextureRendering = newValue,
            ),
          SettingsListSwitch(
            title: 'Use playlist proxy',
            subtitle: Text(
              widget.settingsStore.usePlaylistProxy &&
                      widget.settingsStore.selectedProxyUrl.isNotEmpty
                  ? 'Active: ${Uri.parse(widget.settingsStore.selectedProxyUrl).host}'
                  : 'Routes stream playlist requests through a proxy server.',
            ),
            value: widget.settingsStore.usePlaylistProxy,
            onChanged: _handleProxyToggle,
          ),
          const SectionHeader('Overlay'),
          SettingsListSwitch(
            title: 'Use custom video overlay',
            subtitle: const Text(
              'Replaces Twitch\'s default web overlay with a mobile-friendly version.',
            ),
            value: widget.settingsStore.showOverlay,
            onChanged: (newValue) =>
                widget.settingsStore.showOverlay = newValue,
          ),
          SettingsListSwitch(
            title: 'Long-press player to toggle overlay',
            subtitle: const Text(
              'Allows switching between Twitch\'s overlay and the custom overlay.',
            ),
            value: widget.settingsStore.toggleableOverlay,
            onChanged: (newValue) =>
                widget.settingsStore.toggleableOverlay = newValue,
          ),
          SettingsListSwitch(
            title: 'Show latency',
            subtitle: const Text(
              'Displays the stream latency in the video overlay.',
            ),
            value: widget.settingsStore.showLatency,
            onChanged: (newValue) =>
                widget.settingsStore.showLatency = newValue,
          ),
          const SectionHeader('Audio'),
          SettingsListSwitch(
            title: 'Background audio playback',
            subtitle: const Text(
              'Continue playing audio when the screen is off or app is in background. Requires stream restart to take effect.',
            ),
            value: widget.settingsStore.backgroundAudioEnabled,
            onChanged: _handleBackgroundAudioToggle,
          ),
        ],
      ),
    );
  }
}

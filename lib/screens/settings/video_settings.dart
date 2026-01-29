import 'dart:io';

import 'package:dio/dio.dart';
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
  static const List<String> _proxyServers = [
    'https://proxy4.rte.net.ru',
    'https://proxy5.rte.net.ru',
    'https://proxy6.rte.net.ru',
    'https://proxy7.rte.net.ru',
  ];

  final Map<String, ProxyStatus> _proxyStatuses = {};
  bool _isTesting = false;
  final _dio = Dio();

  @override
  void initState() {
    super.initState();
    // Initialize statuses
    for (final proxy in _proxyServers) {
      _proxyStatuses[proxy] = ProxyStatus.unknown;
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  Future<void> _testProxiesAndSelectFastest() async {
    setState(() {
      _isTesting = true;
      for (final proxy in _proxyServers) {
        _proxyStatuses[proxy] = ProxyStatus.testing;
      }
    });

    String? fastestProxy;
    int fastestTime = 999999;

    final futures = <Future<void>>[];

    for (final proxy in _proxyServers) {
      futures.add(_testProxy(proxy).then((responseTime) {
        setState(() {
          if (responseTime != null) {
            _proxyStatuses[proxy] = ProxyStatus.available;
            if (responseTime < fastestTime) {
              fastestTime = responseTime;
              fastestProxy = proxy;
            }
          } else {
            _proxyStatuses[proxy] = ProxyStatus.unavailable;
          }
        });
      }));
    }

    await Future.wait(futures);

    setState(() {
      _isTesting = false;
    });

    if (fastestProxy != null) {
      widget.settingsStore.selectedProxyUrl = fastestProxy!;
      widget.settingsStore.usePlaylistProxy = true;
    } else {
      widget.settingsStore.usePlaylistProxy = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No proxy servers available'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<int?> _testProxy(String proxyBase) async {
    try {
      final stopwatch = Stopwatch()..start();
      await _dio.head(
        '$proxyBase/https://www.google.com',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return null;
    }
  }

  void _handleProxyToggle(bool newValue) {
    if (newValue) {
      _testProxiesAndSelectFastest();
    } else {
      widget.settingsStore.usePlaylistProxy = false;
      widget.settingsStore.selectedProxyUrl = '';
    }
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
            onChanged: _isTesting ? null : _handleProxyToggle,
          ),
          if (widget.settingsStore.usePlaylistProxy || _isTesting)
            _buildProxyList(),
          const SectionHeader('Overlay'),
          SettingsListSwitch(
            title: 'Use custom video overlay',
            subtitle: const Text(
              'Replaces Twitch\'s default web overlay with a mobile-friendly version.',
            ),
            value: widget.settingsStore.showOverlay,
            onChanged: (newValue) => widget.settingsStore.showOverlay = newValue,
          ),
          SettingsListSwitch(
            title: 'Long-press player to toggle overlay',
            subtitle: const Text(
              'Allows switching between Twitch\'s overlay and the custom overlay.',
            ),
            value: widget.settingsStore.toggleableOverlay,
            onChanged: (newValue) => widget.settingsStore.toggleableOverlay = newValue,
          ),
          SettingsListSwitch(
            title: 'Show latency',
            subtitle: const Text(
              'Displays the stream latency in the video overlay.',
            ),
            value: widget.settingsStore.showLatency,
            onChanged: (newValue) => widget.settingsStore.showLatency = newValue,
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
          if (Platform.isAndroid)
            const SectionHeader('Picture-in-Picture'),
          if (Platform.isAndroid)
            SettingsListSwitch(
              title: 'Stop video when PIP is dismissed',
              subtitle: const Text(
                'Automatically pause video when the picture-in-picture window is closed.',
              ),
              value: widget.settingsStore.stopVideoOnPipDismiss,
              onChanged: (newValue) =>
                  widget.settingsStore.stopVideoOnPipDismiss = newValue,
            ),
        ],
      ),
    );
  }

  Widget _buildProxyList() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Proxy Servers',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (_isTesting) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ...(_proxyServers.map((proxy) => _buildProxyItem(proxy))),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyItem(String proxy) {
    final status = _proxyStatuses[proxy] ?? ProxyStatus.unknown;
    final isSelected = widget.settingsStore.selectedProxyUrl == proxy;
    final host = Uri.parse(proxy).host;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildStatusIcon(status, isSelected),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              host,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
          if (isSelected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Active',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ProxyStatus status, bool isSelected) {
    switch (status) {
      case ProxyStatus.testing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ProxyStatus.available:
        return Icon(
          Icons.check_circle,
          size: 16,
          color: isSelected ? Colors.green : Colors.green.withValues(alpha: 0.6),
        );
      case ProxyStatus.unavailable:
        return Icon(
          Icons.cancel,
          size: 16,
          color: Colors.red.withValues(alpha: 0.6),
        );
      case ProxyStatus.unknown:
        return Icon(
          Icons.circle_outlined,
          size: 16,
          color: Colors.grey.withValues(alpha: 0.6),
        );
    }
  }
}

enum ProxyStatus {
  unknown,
  testing,
  available,
  unavailable,
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/widgets/settings_list_select.dart';
import 'package:frosty/screens/settings/widgets/settings_list_slider.dart';
import 'package:frosty/screens/settings/widgets/settings_list_switch.dart';
import 'package:frosty/screens/settings/widgets/settings_muted_words.dart';
import 'package:frosty/utils/context_extensions.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:frosty/widgets/settings_page_layout.dart';
import 'package:url_launcher/url_launcher.dart';

enum EmoteProxyStatus {
  unknown,
  testing,
  available,
  unavailable,
}

class ChatSettings extends StatefulWidget {
  final SettingsStore settingsStore;

  const ChatSettings({super.key, required this.settingsStore});

  @override
  State<ChatSettings> createState() => _ChatSettingsState();
}

class _ChatSettingsState extends State<ChatSettings> {
  var showPreview = false;

  static const List<String> _emoteProxyServers = [
    'https://starege.rte.net.ru',
    'https://starege3.rte.net.ru',
    'https://starege4.rte.net.ru',
    'https://starege5.rte.net.ru',
  ];

  final Map<String, EmoteProxyStatus> _emoteProxyStatuses = {};
  bool _isTestingEmoteProxies = false;
  final _dio = Dio();

  @override
  void initState() {
    super.initState();
    for (final proxy in _emoteProxyServers) {
      _emoteProxyStatuses[proxy] = EmoteProxyStatus.unknown;
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  Future<void> _testEmoteProxiesAndSelectFastest() async {
    setState(() {
      _isTestingEmoteProxies = true;
      for (final proxy in _emoteProxyServers) {
        _emoteProxyStatuses[proxy] = EmoteProxyStatus.testing;
      }
    });

    String? fastestProxy;
    int fastestTime = 999999;

    final futures = <Future<void>>[];

    for (final proxy in _emoteProxyServers) {
      futures.add(_testEmoteProxy(proxy).then((responseTime) {
        setState(() {
          if (responseTime != null) {
            _emoteProxyStatuses[proxy] = EmoteProxyStatus.available;
            if (responseTime < fastestTime) {
              fastestTime = responseTime;
              fastestProxy = proxy;
            }
          } else {
            _emoteProxyStatuses[proxy] = EmoteProxyStatus.unavailable;
          }
        });
      }));
    }

    await Future.wait(futures);

    setState(() {
      _isTestingEmoteProxies = false;
    });

    if (fastestProxy != null) {
      widget.settingsStore.selectedEmoteProxyUrl = fastestProxy!;
      widget.settingsStore.useEmoteProxy = true;
    } else {
      widget.settingsStore.useEmoteProxy = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No emote proxy servers available'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<int?> _testEmoteProxy(String proxyBase) async {
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

  void _handleEmoteProxyToggle(bool newValue) {
    if (newValue) {
      _testEmoteProxiesAndSelectFastest();
    } else {
      widget.settingsStore.useEmoteProxy = false;
      widget.settingsStore.selectedEmoteProxyUrl = '';
    }
  }

  Widget _buildEmoteProxyList() {
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
                  'Emote Proxy Servers',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (_isTestingEmoteProxies) ...[
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
            ...(_emoteProxyServers.map((proxy) => _buildEmoteProxyItem(proxy))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmoteProxyItem(String proxy) {
    final status = _emoteProxyStatuses[proxy] ?? EmoteProxyStatus.unknown;
    final isSelected = widget.settingsStore.selectedEmoteProxyUrl == proxy;
    final host = Uri.parse(proxy).host;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildEmoteProxyStatusIcon(status, isSelected),
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

  Widget _buildEmoteProxyStatusIcon(EmoteProxyStatus status, bool isSelected) {
    switch (status) {
      case EmoteProxyStatus.testing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case EmoteProxyStatus.available:
        return Icon(
          Icons.check_circle,
          size: 16,
          color: isSelected ? Colors.green : Colors.green.withValues(alpha: 0.6),
        );
      case EmoteProxyStatus.unavailable:
        return Icon(
          Icons.cancel,
          size: 16,
          color: Colors.red.withValues(alpha: 0.6),
        );
      case EmoteProxyStatus.unknown:
        return Icon(
          Icons.circle_outlined,
          size: 16,
          color: Colors.grey.withValues(alpha: 0.6),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsStore = widget.settingsStore;

    return Observer(
      builder: (context) => SettingsPageLayout(
        children: [
          const SectionHeader('Message sizing', isFirst: true),
          ExpansionTile(
            title: const Text('Preview'),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: DefaultTextStyle(
                  style: DefaultTextStyle.of(
                    context,
                  ).style.copyWith(fontSize: settingsStore.fontSize),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: FrostyCachedNetworkImage(
                                imageUrl:
                                    'https://static-cdn.jtvnw.net/badges/v1/bbbe0db0-a598-423e-86d0-f9fb98ca1933/3',
                                height:
                                    defaultBadgeSize * settingsStore.badgeScale,
                                width:
                                    defaultBadgeSize * settingsStore.badgeScale,
                              ),
                            ),
                            const TextSpan(text: ' Badge and emote preview. '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: FrostyCachedNetworkImage(
                                imageUrl:
                                    'https://static-cdn.jtvnw.net/emoticons/v2/425618/default/dark/3.0',
                                height:
                                    defaultEmoteSize * settingsStore.emoteScale,
                                width:
                                    defaultEmoteSize * settingsStore.emoteScale,
                              ),
                            ),
                          ],
                        ),
                        textScaler: settingsStore.messageScale.textScaler,
                      ),
                      SizedBox(height: settingsStore.messageSpacing),
                      Text(
                        'Hello! Here\'s a text preview.',
                        textScaler: settingsStore.messageScale.textScaler,
                      ),
                      SizedBox(height: settingsStore.messageSpacing),
                      Text(
                        'And another for spacing without an emote!',
                        textScaler: settingsStore.messageScale.textScaler,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SettingsListSlider(
            title: 'Badge scale',
            trailing: '${settingsStore.badgeScale.toStringAsFixed(2)}x',
            value: settingsStore.badgeScale,
            min: 0.25,
            max: 3.0,
            divisions: 11,
            onChanged: (newValue) => settingsStore.badgeScale = newValue,
          ),
          SettingsListSlider(
            title: 'Emote scale',
            trailing: '${settingsStore.emoteScale.toStringAsFixed(2)}x',
            value: settingsStore.emoteScale,
            min: 0.25,
            max: 3.0,
            divisions: 11,
            onChanged: (newValue) => settingsStore.emoteScale = newValue,
          ),
          SettingsListSlider(
            title: 'Message scale',
            trailing: '${settingsStore.messageScale.toStringAsFixed(2)}x',
            value: settingsStore.messageScale,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            onChanged: (newValue) => settingsStore.messageScale = newValue,
          ),
          SettingsListSlider(
            title: 'Message spacing',
            trailing: '${settingsStore.messageSpacing.toStringAsFixed(0)}px',
            value: settingsStore.messageSpacing,
            max: 30.0,
            divisions: 15,
            onChanged: (newValue) => settingsStore.messageSpacing = newValue,
          ),
          SettingsListSlider(
            title: 'Font size',
            trailing: settingsStore.fontSize.toInt().toString(),
            value: settingsStore.fontSize,
            min: 5,
            max: 20,
            divisions: 15,
            onChanged: (newValue) => settingsStore.fontSize = newValue,
          ),
          const SectionHeader('Message appearance'),
          SettingsListSwitch(
            title: 'Show deleted messages',
            subtitle: const Text(
              'Restores the original message of deleted messages.',
            ),
            value: settingsStore.showDeletedMessages,
            onChanged: (newValue) =>
                settingsStore.showDeletedMessages = newValue,
          ),
          SettingsListSwitch(
            title: 'Show message dividers',
            value: settingsStore.showChatMessageDividers,
            onChanged: (newValue) =>
                settingsStore.showChatMessageDividers = newValue,
          ),
          SettingsListSelect(
            title: 'Message timestamps',
            selectedOption: timestampNames[settingsStore.timestampType.index],
            options: timestampNames,
            onChanged: (newValue) => settingsStore.timestampType =
                TimestampType.values[timestampNames.indexOf(newValue)],
          ),
          const SectionHeader('Delay and latency'),
          SettingsListSwitch(
            title: 'Sync message delay and stream latency',
            value: settingsStore.autoSyncChatDelay,
            onChanged: (newValue) => settingsStore.autoSyncChatDelay = newValue,
          ),
          if (!settingsStore.autoSyncChatDelay)
            SettingsListSlider(
              title: 'Message delay',
              trailing: '${settingsStore.chatDelay.toInt()} seconds',
              subtitle:
                  'Adds a delay before each message is rendered in chat. ${Platform.isIOS ? '15 seconds is recommended for iOS.' : ''}',
              value: settingsStore.chatDelay,
              max: 30.0,
              divisions: 30,
              onChanged: (newValue) => settingsStore.chatDelay = newValue,
            ),
          const SectionHeader('Alerts'),
          SettingsListSwitch(
            title: 'Highlight first time chatters',
            value: settingsStore.highlightFirstTimeChatter,
            onChanged: (newValue) =>
                settingsStore.highlightFirstTimeChatter = newValue,
          ),
          SettingsListSwitch(
            title: 'Show notices',
            subtitle: const Text(
              'Shows notices such as subs and re-subs, announcements, and raids.',
            ),
            value: settingsStore.showUserNotices,
            onChanged: (newValue) => settingsStore.showUserNotices = newValue,
          ),
          const SectionHeader('Layout'),
          SettingsListSwitch(
            title: 'Move emote menu button left',
            subtitle: const Text(
              'Places the emote menu button on the left side to avoid accidental presses.',
            ),
            value: settingsStore.emoteMenuButtonOnLeft,
            onChanged: (newValue) =>
                settingsStore.emoteMenuButtonOnLeft = newValue,
          ),
          SettingsListSwitch(
            title: 'Persist chat tabs',
            subtitle: const Text(
              'Secondary chat tabs are remembered when switching channels.',
            ),
            value: settingsStore.persistChatTabs,
            onChanged: (newValue) {
              settingsStore.persistChatTabs = newValue;
              if (!newValue) {
                settingsStore.secondaryTabs = [];
              }
            },
          ),
          const SectionHeader('Landscape mode'),
          SettingsListSwitch(
            title: 'Move chat left',
            value: settingsStore.landscapeChatLeftSide,
            onChanged: (newValue) =>
                settingsStore.landscapeChatLeftSide = newValue,
          ),
          SettingsListSwitch(
            title: 'Force vertical chat',
            subtitle: const Text(
              'Intended for tablets and other larger displays.',
            ),
            value: settingsStore.landscapeForceVerticalChat,
            onChanged: (newValue) =>
                settingsStore.landscapeForceVerticalChat = newValue,
          ),
          SettingsListSelect(
            title: 'Fill notch side',
            subtitle:
                'Overrides and fills the available space in devices with a display notch.',
            selectedOption:
                landscapeCutoutNames[settingsStore.landscapeCutout.index],
            options: landscapeCutoutNames,
            onChanged: (newValue) => settingsStore.landscapeCutout =
                LandscapeCutoutType.values[landscapeCutoutNames.indexOf(
                  newValue,
                )],
          ),
          SettingsListSlider(
            title: 'Chat overlay opacity',
            trailing:
                '${(settingsStore.fullScreenChatOverlayOpacity * 100).toStringAsFixed(0)}%',
            subtitle:
                'Sets the opacity (transparency) of the overlay chat in fullscreen mode.',
            value: settingsStore.fullScreenChatOverlayOpacity,
            divisions: 10,
            onChanged: (newValue) =>
                settingsStore.fullScreenChatOverlayOpacity = newValue,
          ),
          const SectionHeader('Muted keywords'),
          SettingsMutedWords(settingsStore: settingsStore),
          SettingsListSwitch(
            title: 'Match whole words',
            subtitle: const Text(
              'Only matches whole words instead of partial matches.',
            ),
            value: settingsStore.matchWholeWord,
            onChanged: (newValue) => settingsStore.matchWholeWord = newValue,
          ),
          const SectionHeader('Autocomplete'),
          SettingsListSwitch(
            title: 'Show autocomplete bar',
            subtitle: const Text(
              'Shows a bar containing matching emotes and mentions while typing.',
            ),
            value: settingsStore.autocomplete,
            onChanged: (newValue) => settingsStore.autocomplete = newValue,
          ),
          const SectionHeader('Emotes and badges'),
          SettingsListSwitch(
            title: 'Show Twitch emotes',
            value: settingsStore.showTwitchEmotes,
            onChanged: (newValue) => settingsStore.showTwitchEmotes = newValue,
          ),
          SettingsListSwitch(
            title: 'Show Twitch badges',
            value: settingsStore.showTwitchBadges,
            onChanged: (newValue) => settingsStore.showTwitchBadges = newValue,
          ),
          SettingsListSwitch(
            title: 'Show 7TV emotes',
            value: settingsStore.show7TVEmotes,
            onChanged: (newValue) => settingsStore.show7TVEmotes = newValue,
          ),
          SettingsListSwitch(
            title: 'Show BTTV emotes',
            value: settingsStore.showBTTVEmotes,
            onChanged: (newValue) => settingsStore.showBTTVEmotes = newValue,
          ),
          SettingsListSwitch(
            title: 'Show BTTV badges',
            value: settingsStore.showBTTVBadges,
            onChanged: (newValue) => settingsStore.showBTTVBadges = newValue,
          ),
          SettingsListSwitch(
            title: 'Show FFZ emotes',
            value: settingsStore.showFFZEmotes,
            onChanged: (newValue) => settingsStore.showFFZEmotes = newValue,
          ),
          SettingsListSwitch(
            title: 'Show FFZ badges',
            value: settingsStore.showFFZBadges,
            onChanged: (newValue) => settingsStore.showFFZBadges = newValue,
          ),
          SettingsListSwitch(
            title: 'Show ReYohoho badges',
            value: settingsStore.showReyohohoBadges,
            onChanged: (newValue) =>
                settingsStore.showReyohohoBadges = newValue,
          ),
          SettingsListSwitch(
            title: 'Show colored nicknames (paints)',
            subtitle: const Text(
              'Displays custom nickname gradients from 7TV and ReYohoho.',
            ),
            value: settingsStore.showPaints,
            onChanged: (newValue) => settingsStore.showPaints = newValue,
          ),
          SettingsListSwitch(
            title: 'Use emote proxy',
            subtitle: Text(
              settingsStore.useEmoteProxy &&
                      settingsStore.selectedEmoteProxyUrl.isNotEmpty
                  ? 'Active: ${Uri.parse(settingsStore.selectedEmoteProxyUrl).host}'
                  : 'Routes emote requests through a proxy server for regions with blocked access.',
            ),
            value: settingsStore.useEmoteProxy,
            onChanged: _isTestingEmoteProxies ? null : _handleEmoteProxyToggle,
          ),
          if (settingsStore.useEmoteProxy || _isTestingEmoteProxies)
            _buildEmoteProxyList(),
          const SectionHeader('Recent messages'),
          SettingsListSwitch(
            title: 'Show historical recent messages',
            subtitle: Text.rich(
              TextSpan(
                text:
                    'Loads historical recent messages in chat through a third-party API service at ',
                children: [
                  TextSpan(
                    text: 'https://recent-messages.robotty.de/',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.blue,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => launchUrl(
                        Uri.parse('https://recent-messages.robotty.de/'),
                        mode: settingsStore.launchUrlExternal
                            ? LaunchMode.externalApplication
                            : LaunchMode.inAppBrowserView,
                      ),
                  ),
                ],
              ),
            ),
            value: settingsStore.showRecentMessages,
            onChanged: (newValue) =>
                settingsStore.showRecentMessages = newValue,
          ),
          const SectionHeader('Link previews'),
          SettingsListSwitch(
            title: 'Show link previews',
            subtitle: const Text(
              'Displays inline previews for images and supported links (Imgur, 7TV, Kappa.lol).',
            ),
            value: settingsStore.showLinkPreviews,
            onChanged: (newValue) => settingsStore.showLinkPreviews = newValue,
          ),
          if (settingsStore.showLinkPreviews) ...[
            SettingsListSwitch(
              title: 'Hide link text',
              subtitle: const Text(
                'Hides the link text when showing a preview.',
              ),
              value: settingsStore.hideLinkPreviewLinks,
              onChanged: (newValue) =>
                  settingsStore.hideLinkPreviewLinks = newValue,
            ),
            SettingsListSlider(
              title: 'Max preview width',
              trailing: '${settingsStore.linkPreviewMaxWidth.toInt()}px',
              value: settingsStore.linkPreviewMaxWidth,
              min: 100,
              max: 500,
              divisions: 8,
              onChanged: (newValue) =>
                  settingsStore.linkPreviewMaxWidth = newValue,
            ),
            SettingsListSlider(
              title: 'Max preview height',
              trailing: '${settingsStore.linkPreviewMaxHeight.toInt()}px',
              value: settingsStore.linkPreviewMaxHeight,
              min: 100,
              max: 400,
              divisions: 6,
              onChanged: (newValue) =>
                  settingsStore.linkPreviewMaxHeight = newValue,
            ),
          ],
        ],
      ),
    );
  }
}

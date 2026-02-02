import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:frosty/apis/bttv_api.dart';
import 'package:frosty/apis/ffz_api.dart';
import 'package:frosty/apis/reyohoho_api.dart';
import 'package:frosty/apis/seventv_api.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/badges.dart';
import 'package:frosty/models/emotes.dart';
import 'package:frosty/models/vod_comment.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/stores/global_assets_store.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:frosty/widgets/link_preview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget displaying synced VOD chat replay
class VodChat extends StatefulWidget {
  final TwitchApi twitchApi;
  final String videoId;
  final String channelId;

  /// Current playback position in seconds - should be updated externally
  final ValueNotifier<double> currentTimeNotifier;

  /// Whether the video is paused
  final ValueNotifier<bool> pausedNotifier;

  const VodChat({
    super.key,
    required this.twitchApi,
    required this.videoId,
    required this.channelId,
    required this.currentTimeNotifier,
    required this.pausedNotifier,
  });

  @override
  State<VodChat> createState() => _VodChatState();
}

class _VodChatState extends State<VodChat> {
  final List<VodComment> _comments = [];
  final ScrollController _scrollController = ScrollController();

  Timer? _fetchTimer;
  int _lastFetchedOffset = -1;
  bool _isLoading = false;
  bool _autoScroll = true;
  bool _showDelayControls = false;

  late final SettingsStore _settingsStore;
  late final GlobalAssetsStore _globalAssetsStore;
  late final ReyohohoApi _reyohohoApi;

  /// Combined emotes map (name -> Emote) for third-party emotes
  Map<String, Emote> _channelEmotes = {};

  /// Store build context for link launching
  BuildContext? _context;

  /// On-demand cache for Reyohoho badges (userId -> ChatBadge).
  final _reyohohoBadgeCache = <String, ChatBadge?>{};

  /// Set of pending Reyohoho badge requests to prevent duplicate requests.
  final _pendingReyohohoBadgeRequests = <String>{};

  @override
  void initState() {
    super.initState();
    _settingsStore = context.read<SettingsStore>();
    _globalAssetsStore = context.read<GlobalAssetsStore>();
    _reyohohoApi = context.read<ReyohohoApi>();
    widget.currentTimeNotifier.addListener(_onTimeChanged);
    widget.pausedNotifier.addListener(_onPausedChanged);
    _scrollController.addListener(_onScroll);

    // Initial fetch
    _fetchComments(widget.currentTimeNotifier.value.toInt());

    // Start periodic fetch timer
    _startFetchTimer();

    // Load channel emotes for third-party emote support
    _loadChannelEmotes();
  }

  Future<void> _loadChannelEmotes() async {
    try {
      final bttvApi = context.read<BTTVApi>();
      final ffzApi = context.read<FFZApi>();
      final sevenTVApi = context.read<SevenTVApi>();

      final emotes = <String, Emote>{};

      // Add global emotes from store
      emotes.addAll(_globalAssetsStore.globalEmoteMap);

      // Load channel-specific emotes in parallel
      final futures = await Future.wait([
        // BTTV returns List<Emote> directly
        bttvApi
            .getEmotesChannel(id: widget.channelId)
            .then<List<Emote>>((list) => list)
            .catchError((_) => <Emote>[]),
        // FFZ returns (RoomFFZ, List<Emote>) tuple
        ffzApi
            .getRoomInfo(id: widget.channelId)
            .then<List<Emote>>((result) => result.$2)
            .catchError((_) => <Emote>[]),
        // 7TV returns (String, List<Emote>) tuple
        sevenTVApi
            .getEmotesChannel(id: widget.channelId)
            .then<List<Emote>>((result) => result.$2)
            .catchError((_) => <Emote>[]),
      ]);

      for (final emoteList in futures) {
        for (final emote in emoteList) {
          emotes[emote.name] = emote;
        }
      }

      if (mounted) {
        setState(() {
          _channelEmotes = emotes;
        });
      }
    } catch (e) {
      debugPrint('Error loading channel emotes: $e');
    }
  }

  void _startFetchTimer() {
    _fetchTimer?.cancel();
    _fetchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.pausedNotifier.value) {
        _fetchComments(widget.currentTimeNotifier.value.toInt());
      }
    });
  }

  void _onTimeChanged() {
    final currentOffset = widget.currentTimeNotifier.value.toInt();

    // If user seeked to a different position (more than 30 seconds difference)
    if ((_lastFetchedOffset - currentOffset).abs() > 30) {
      _comments.clear();
      _lastFetchedOffset = -1;
      _fetchComments(currentOffset);
    }

    // Trigger rebuild to show newly visible comments and auto-scroll
    if (mounted) {
      setState(() {});
    }
  }

  void _onPausedChanged() {
    if (widget.pausedNotifier.value) {
      _fetchTimer?.cancel();
    } else {
      _startFetchTimer();
    }
  }

  void _onScroll() {
    // With reverse: true, position.pixels == 0 means at the bottom (latest messages)
    // position.pixels > 0 means user scrolled up to see older messages
    if (_scrollController.hasClients) {
      if (_scrollController.position.pixels <= 0) {
        _autoScroll = true;
      } else if (_scrollController.position.pixels > 0) {
        _autoScroll = false;
      }
    }
  }

  /// Re-enables auto-scroll (called when user taps "scroll to bottom" button)
  void _enableAutoScroll() {
    _autoScroll = true;
    if (_scrollController.hasClients) {
      // With reverse: true, position 0 is at the bottom (latest messages)
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _fetchComments(int offsetSeconds) async {
    if (_isLoading) return;

    // Don't refetch if we're close to the last fetched offset (5 sec window for high-activity VODs)
    if ((_lastFetchedOffset - offsetSeconds).abs() < 5 &&
        _lastFetchedOffset != -1) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final allComments = <VodComment>[];
      VodCommentsResponse? response = await widget.twitchApi.getVodComments(
        videoId: widget.videoId,
        contentOffsetSeconds: offsetSeconds,
      );

      const maxPages = 50; // Safety limit for very high-activity VODs
      var pageCount = 0;

      while (response != null && pageCount < maxPages) {
        allComments.addAll(response.comments);
        if (!response.hasNextPage ||
            response.cursor == null ||
            response.cursor!.isEmpty) {
          break;
        }
        response = await widget.twitchApi.getVodComments(
          videoId: widget.videoId,
          cursor: response.cursor,
        );
        pageCount++;
      }

      if (mounted) {
        setState(() {
          // Filter out duplicates and add new comments
          for (final comment in allComments) {
            if (!_comments.any((c) => c.id == comment.id)) {
              _comments.add(comment);
            }
          }

          // Sort by offset
          _comments.sort(
            (a, b) => a.contentOffsetSeconds.compareTo(b.contentOffsetSeconds),
          );

          // Keep only comments within reasonable range (last 5 minutes)
          final minOffset = offsetSeconds - 300;
          _comments.removeWhere((c) => c.contentOffsetSeconds < minOffset);

          _lastFetchedOffset = offsetSeconds;
          _isLoading = false;
        });
        // With reverse: true, new messages appear at the bottom automatically
        // when autoScroll is enabled (position stays at 0)
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatOffset(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _adjustDelay(double delta) {
    setState(() {
      _settingsStore.vodChatDelay =
          (_settingsStore.vodChatDelay + delta).clamp(-300.0, 300.0);
    });
  }

  /// Renders message fragments with support for third-party emotes and link previews
  /// Returns a tuple of (spans, linkPreviews)
  (List<InlineSpan>, List<LinkPreviewInfo>) _renderMessageFragments(
    VodCommentMessage message,
  ) {
    final spans = <InlineSpan>[];
    final linkPreviews = <LinkPreviewInfo>[];
    final emoteScale = _settingsStore.emoteScale;
    final emoteHeight = 22.0 * emoteScale;
    final showLinkPreviews = _settingsStore.showLinkPreviews;

    for (final fragment in message.fragments) {
      if (fragment.emote != null) {
        // Twitch native emote
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FrostyCachedNetworkImage(
              imageUrl: fragment.emote!.url3x,
              height: emoteHeight,
              useFade: false,
              placeholder: (_, _) => SizedBox(
                width: emoteHeight,
                height: emoteHeight,
              ),
            ),
          ),
        );
      } else {
        // Check for third-party emotes and links in text
        final words = fragment.text.split(' ');
        for (var i = 0; i < words.length; i++) {
          final word = words[i];
          final emote = _channelEmotes[word];

          if (emote != null) {
            // Found a third-party emote
            // Calculate dimensions - use emote's own size if available
            final height = emote.height != null
                ? emote.height! * emoteScale
                : emoteHeight;
            final width = emote.width != null ? emote.width! * emoteScale : null;

            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: FrostyCachedNetworkImage(
                  imageUrl: emote.url,
                  height: height,
                  width: width,
                  useFade: false,
                  placeholder: (_, _) => SizedBox(
                    width: width ?? emoteHeight,
                    height: height,
                  ),
                ),
              ),
            );
          } else if (word.startsWith('http://') || word.startsWith('https://')) {
            // URL - check for link preview
            if (showLinkPreviews) {
              final preview = detectLinkPreview(word);
              if (preview != null) {
                linkPreviews.add(preview);
              }
            }

            // Add tappable link
            spans.add(
              TextSpan(
                text: _settingsStore.hideLinkPreviewLinks &&
                        showLinkPreviews &&
                        detectLinkPreview(word) != null
                    ? '[link]'
                    : word,
                style: TextStyle(
                  color: Theme.of(_context!).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(
                        Uri.parse(word),
                        mode: _settingsStore.launchUrlExternal
                            ? LaunchMode.externalApplication
                            : LaunchMode.inAppBrowserView,
                      ),
              ),
            );
          } else {
            // Regular text
            spans.add(TextSpan(text: word));
          }

          // Add space between words (except for last word)
          if (i < words.length - 1) {
            spans.add(const TextSpan(text: ' '));
          }
        }
      }
    }

    return (spans, linkPreviews);
  }

  /// Gets a Reyohoho badge for a user, loading on-demand if needed.
  /// Returns null if user has no badge or badge hasn't loaded yet.
  ChatBadge? _getReyohohoBadge(String userId) {
    // Return cached badge if available
    if (_reyohohoBadgeCache.containsKey(userId)) {
      return _reyohohoBadgeCache[userId];
    }

    // Avoid duplicate requests
    if (_pendingReyohohoBadgeRequests.contains(userId)) {
      return null;
    }

    // Trigger async fetch
    _fetchReyohohoBadge(userId);
    return null;
  }

  /// Fetches Reyohoho badge for a user asynchronously.
  Future<void> _fetchReyohohoBadge(String userId) async {
    if (_pendingReyohohoBadgeRequests.contains(userId)) return;

    _pendingReyohohoBadgeRequests.add(userId);

    try {
      final badge = await _reyohohoApi.getUserBadge(userId);
      _reyohohoBadgeCache[userId] = badge;
      // Trigger rebuild to show the badge
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Failed to fetch Reyohoho badge for $userId: $e');
      _reyohohoBadgeCache[userId] = null;
    } finally {
      _pendingReyohohoBadgeRequests.remove(userId);
    }
  }

  /// Renders custom badges (FFZ, BTTV, Reyohoho) for a user
  List<Widget> _renderCustomBadges(String? commenterUserId) {
    if (commenterUserId == null) return [];

    final badges = <Widget>[];
    final badgeSize = 16.0 * _settingsStore.badgeScale;

    // FFZ badges
    final ffzBadges = _globalAssetsStore.ffzBadges[commenterUserId];
    if (ffzBadges != null) {
      for (final badge in ffzBadges) {
        final bgColor = badge.color != null
            ? Color(int.parse(badge.color!.replaceFirst('#', '0xFF')))
            : null;

        badges.add(
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: bgColor != null
                ? ColoredBox(
                    color: bgColor,
                    child: FrostyCachedNetworkImage(
                      imageUrl: badge.url,
                      width: badgeSize,
                      height: badgeSize,
                      useFade: false,
                    ),
                  )
                : FrostyCachedNetworkImage(
                    imageUrl: badge.url,
                    width: badgeSize,
                    height: badgeSize,
                    useFade: false,
                  ),
          ),
        );
      }
    }

    // BTTV badge
    final bttvBadge = _globalAssetsStore.bttvBadges[commenterUserId];
    if (bttvBadge != null) {
      badges.add(
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: FrostyCachedNetworkImage(
            imageUrl: bttvBadge.url,
            width: badgeSize,
            height: badgeSize,
            useFade: false,
          ),
        ),
      );
    }

    // Reyohoho badge (on-demand loading)
    if (_settingsStore.showReyohohoBadges) {
      final reyohohoBadge = _getReyohohoBadge(commenterUserId);
      if (reyohohoBadge != null) {
        badges.add(
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: FrostyCachedNetworkImage(
              imageUrl: reyohohoBadge.url,
              width: badgeSize,
              height: badgeSize,
              useFade: false,
            ),
          ),
        );
      }
    }

    return badges;
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) {
      return Colors.grey;
    }
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    _context = context; // Store context for link launching
    final theme = Theme.of(context);
    final currentTime = widget.currentTimeNotifier.value.toInt();
    final chatDelay = _settingsStore.vodChatDelay;

    // Filter comments to show only those before or at current time
    // Positive delay = chat is behind video, so we subtract delay from video time
    // Negative delay = chat is ahead of video, so we add to video time (subtracting negative)
    final adjustedTime = currentTime - chatDelay.toInt();
    final visibleComments = _comments
        .where((c) => c.contentOffsetSeconds <= adjustedTime + 2)
        .toList();

    // With reverse: true, new messages automatically appear at the bottom
    // when autoScroll is enabled (scroll position stays at 0)

    if (visibleComments.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'No chat messages',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.chat,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chat Replay',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (chatDelay != 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${chatDelay > 0 ? '+' : ''}${chatDelay.toStringAsFixed(0)}s',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Delay settings button
                  IconButton(
                    icon: Icon(
                      _showDelayControls
                          ? Icons.timer_off_outlined
                          : Icons.timer_outlined,
                      size: 18,
                    ),
                    tooltip: 'Chat sync delay',
                    onPressed: () {
                      setState(() => _showDelayControls = !_showDelayControls);
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  if (!_autoScroll)
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      tooltip: 'Scroll to bottom',
                      onPressed: _enableAutoScroll,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              // Delay controls
              if (_showDelayControls)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text(
                        'Delay:',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // -10s button
                      _DelayButton(
                        label: '-10',
                        onPressed: () => _adjustDelay(-10),
                      ),
                      const SizedBox(width: 4),
                      // -1s button
                      _DelayButton(
                        label: '-1',
                        onPressed: () => _adjustDelay(-1),
                      ),
                      const SizedBox(width: 8),
                      // Current delay display
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${chatDelay >= 0 ? '+' : ''}${chatDelay.toStringAsFixed(0)}s',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // +1s button
                      _DelayButton(
                        label: '+1',
                        onPressed: () => _adjustDelay(1),
                      ),
                      const SizedBox(width: 4),
                      // +10s button
                      _DelayButton(
                        label: '+10',
                        onPressed: () => _adjustDelay(10),
                      ),
                      const SizedBox(width: 8),
                      // Reset button
                      if (chatDelay != 0)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 16),
                          tooltip: 'Reset delay',
                          onPressed: () {
                            setState(() {
                              _settingsStore.vodChatDelay = 0;
                            });
                          },
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Chat messages
        Expanded(
          child: ListView.builder(
            reverse: true,
            controller: _scrollController,
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 4,
              // Add bottom padding for system navigation bar
              // Use viewPadding to get actual insets regardless of SafeArea
              bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
            ),
            itemCount: visibleComments.length,
            itemBuilder: (context, index) {
              // With reverse: true, we need to reverse the index to show oldest at top
              final comment =
                  visibleComments[visibleComments.length - 1 - index];
              final userColor = _parseColor(comment.message.userColor);
              final badgeScale = _settingsStore.badgeScale;
              final badgeSize = 16.0 * badgeScale;

              // Render message and collect link previews
              final (messageSpans, linkPreviews) =
                  _renderMessageFragments(comment.message);

              // Build badges list
              final badgeSpans = <InlineSpan>[];

              // Twitch badges
              for (final badge in comment.message.userBadges) {
                final badgeKey = '${badge.setID}/${badge.version}';
                final chatBadge =
                    _globalAssetsStore.twitchGlobalBadges[badgeKey];

                if (chatBadge != null) {
                  badgeSpans.add(
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: FrostyCachedNetworkImage(
                          imageUrl: chatBadge.url,
                          width: badgeSize,
                          height: badgeSize,
                          fit: BoxFit.contain,
                          useFade: false,
                        ),
                      ),
                    ),
                  );
                }
              }

              // Custom badges (FFZ, BTTV)
              final customBadges = _renderCustomBadges(comment.commenter.id);

              // Build the message widget
              Widget messageWidget = RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13 * _settingsStore.messageScale,
                    color: theme.colorScheme.onSurface,
                  ),
                  children: [
                    // Twitch badges
                    ...badgeSpans,
                    // Custom badges as WidgetSpans
                    ...customBadges.map(
                      (badge) => WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: badge,
                      ),
                    ),
                    // Username
                    TextSpan(
                      text: comment.commenter.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: userColor,
                      ),
                    ),
                    const TextSpan(text: ': '),
                    // Message fragments (with third-party emote and link support)
                    ...messageSpans,
                  ],
                ),
              );

              // Add link previews if any
              if (linkPreviews.isNotEmpty) {
                messageWidget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    messageWidget,
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: linkPreviews
                          .map(
                            (preview) => LinkPreviewWidget(
                              previewInfo: preview,
                              maxWidth: _settingsStore.linkPreviewMaxWidth,
                              maxHeight: _settingsStore.linkPreviewMaxHeight,
                              launchExternal: _settingsStore.launchUrlExternal,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timestamp
                    if (_settingsStore.timestampType != TimestampType.disabled)
                      SizedBox(
                        width: 48,
                        child: Text(
                          _formatOffset(comment.contentOffsetSeconds),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.outline,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    // Message content
                    Expanded(child: messageWidget),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    widget.currentTimeNotifier.removeListener(_onTimeChanged);
    widget.pausedNotifier.removeListener(_onPausedChanged);
    _scrollController.dispose();
    super.dispose();
  }
}

/// Small button for adjusting chat delay
class _DelayButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _DelayButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}



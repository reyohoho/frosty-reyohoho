import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/screens/channel/chat/stores/chat_store.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:intl/intl.dart';

class PinnedMessageBanner extends StatelessWidget {
  final ChatStore chatStore;

  const PinnedMessageBanner({super.key, required this.chatStore});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final msg = chatStore.pinnedMessage;
        if (msg == null || chatStore.pinnedMessageHidden || msg.hasExpired) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isCollapsed = chatStore.pinnedMessageCollapsed;

        return Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          child: InkWell(
            onTap: chatStore.togglePinnedCollapsed,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: isCollapsed
                      ? _CollapsedContent(msg: msg, chatStore: chatStore)
                      : _ExpandedContent(msg: msg, chatStore: chatStore),
                ),
                Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CollapsedContent extends StatelessWidget {
  final PinnedChatMessage msg;
  final ChatStore chatStore;

  const _CollapsedContent({required this.msg, required this.chatStore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat.Hm().format(msg.sentAt.toLocal());

    return Row(
      children: [
        Icon(Icons.push_pin_rounded, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${msg.sender.displayName}  ·  $timeStr',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _ActionButtons(
          chatStore: chatStore,
          expandIcon: Icons.keyboard_arrow_down_rounded,
        ),
      ],
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  final PinnedChatMessage msg;
  final ChatStore chatStore;

  const _ExpandedContent({required this.msg, required this.chatStore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.push_pin_rounded, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pinned by ${msg.pinnedByDisplayName}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (msg.endsAt != null) _ExpiryLabel(endsAt: msg.endsAt!),
            _ActionButtons(
              chatStore: chatStore,
              expandIcon: Icons.keyboard_arrow_up_rounded,
            ),
          ],
        ),
        const SizedBox(height: 4),
        _SenderRow(msg: msg, chatStore: chatStore),
        const SizedBox(height: 2),
        _MessageBody(msg: msg, chatStore: chatStore),
      ],
    );
  }
}

class _SenderRow extends StatelessWidget {
  final PinnedChatMessage msg;
  final ChatStore chatStore;

  const _SenderRow({required this.msg, required this.chatStore});

  @override
  Widget build(BuildContext context) {
    final badgesMap = chatStore.assetsStore.twitchBadgesToObject;
    final senderColor = _parseChatColor(msg.sender.chatColor, context);

    return Row(
      children: [
        for (final badge in msg.sender.badges) ...[
          Builder(
            builder: (context) {
              final key = '${badge.setId}/${badge.version}';
              final chatBadge = badgesMap[key];
              if (chatBadge == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 3),
                child: FrostyCachedNetworkImage(
                  imageUrl: chatBadge.url,
                  height: defaultBadgeSize,
                  width: defaultBadgeSize,
                  useFade: false,
                  placeholder: (context, url) => const SizedBox(),
                ),
              );
            },
          ),
        ],
        Text(
          msg.sender.displayName,
          style: TextStyle(
            color: senderColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _MessageBody extends StatelessWidget {
  final PinnedChatMessage msg;
  final ChatStore chatStore;

  const _MessageBody({required this.msg, required this.chatStore});

  @override
  Widget build(BuildContext context) {
    final emoteMap = chatStore.assetsStore.emoteToObject;
    final spans = <InlineSpan>[];

    for (final fragment in msg.fragments) {
      if (fragment.emoteId != null) {
        final url = 'https://static-cdn.jtvnw.net/emoticons/v2/${fragment.emoteId}/default/dark/3.0';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FrostyCachedNetworkImage(
              imageUrl: url,
              height: defaultEmoteSize,
              useFade: false,
              placeholder: (context, url) => const SizedBox(),
            ),
          ),
        );
      } else {
        final words = fragment.text.split(' ');
        for (var i = 0; i < words.length; i++) {
          final word = words[i];
          if (word.isEmpty) {
            if (i < words.length - 1) spans.add(const TextSpan(text: ' '));
            continue;
          }
          final emote = emoteMap[word];
          if (emote != null) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: FrostyCachedNetworkImage(
                  imageUrl: emote.url,
                  height: emote.height?.toDouble() ?? defaultEmoteSize,
                  width: emote.width?.toDouble(),
                  useFade: false,
                  placeholder: (context, url) => const SizedBox(),
                ),
              ),
            );
          } else {
            spans.add(TextSpan(text: word));
          }
          if (i < words.length - 1) spans.add(const TextSpan(text: ' '));
        }
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      style: DefaultTextStyle.of(context).style,
    );
  }
}

class _ExpiryLabel extends StatelessWidget {
  final DateTime endsAt;

  const _ExpiryLabel({required this.endsAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat.Hm().format(endsAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        'until $timeStr',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ChatStore chatStore;
  final IconData expandIcon;

  const _ActionButtons({
    required this.chatStore,
    required this.expandIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            onPressed: chatStore.togglePinnedCollapsed,
            icon: Icon(expandIcon, size: 18),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            onPressed: chatStore.hidePinnedMessage,
            icon: const Icon(Icons.close_rounded, size: 16),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

Color _parseChatColor(String? hex, BuildContext context) {
  if (hex == null || hex.isEmpty) {
    return Theme.of(context).colorScheme.primary;
  }
  try {
    final colorValue = int.parse(hex.replaceFirst('#', ''), radix: 16);
    return Color(0xFF000000 | colorValue);
  } catch (_) {
    return Theme.of(context).colorScheme.primary;
  }
}

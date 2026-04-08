import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/reyohoho_friend.dart';
import 'package:frosty/screens/channel/channel.dart';
import 'package:frosty/screens/home/friends/stores/friends_store.dart';
import 'package:frosty/utils.dart';
import 'package:frosty/widgets/alert_message.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:frosty/widgets/frosty_scrollbar.dart';
import 'package:frosty/widgets/live_indicator.dart';
import 'package:frosty/widgets/skeleton_loader.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';
import 'package:provider/provider.dart';

final _friendTimeFormat = DateFormat.yMMMd().add_Hm();

/// Friends from the RTE extension: who is online and which streams they watch.
class Friends extends StatefulWidget {
  final ScrollController scrollController;

  const Friends({super.key, required this.scrollController});

  @override
  State<Friends> createState() => _FriendsState();
}

class _FriendsState extends State<Friends> with AutomaticKeepAliveClientMixin {
  late final FriendsStore _friendsStore = FriendsStore(
    authStore: context.read(),
    reyohohoApi: context.read(),
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_friendsStore.fetch());
    });
  }

  Future<void> _openWatchedChannel(String channelLogin) async {
    final context = this.context;
    final twitchApi = context.read<TwitchApi>();

    try {
      final user = await twitchApi.getUser(userLogin: channelLogin);
      final channel = await twitchApi.getChannel(userId: user.id);
      if (!context.mounted) {
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => VideoChat(
            userId: channel.broadcasterId,
            userName: channel.broadcasterName,
            userLogin: channel.broadcasterLogin,
          ),
        ),
      );
    } on ApiException catch (e) {
      debugPrint('Friends open channel ApiException: $e');
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AlertMessage(message: e.message, centered: false)),
      );
    } catch (e) {
      debugPrint('Friends open channel error: $e');
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AlertMessage(message: 'Unable to open channel', centered: false),
        ),
      );
    }
  }

  double _topInset(BuildContext context) {
    return MediaQuery.of(context).padding.top + kToolbarHeight;
  }

  double _bottomInset(BuildContext context) {
    final m = MediaQuery.of(context);
    final navH = NavigationBarTheme.of(context).height ?? 80;
    return m.padding.bottom + navH;
  }

  List<_FriendFlatRow> _flattenFriends(List<ReyohohoFriend> friends) {
    final out = <_FriendFlatRow>[];
    for (final f in friends) {
      out.add(_FriendFlatRow.header(f));
      for (final c in f.channels) {
        out.add(_FriendFlatRow.channel(f, c));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topInset = _topInset(context);
    final bottomInset = _bottomInset(context);

    return Observer(
      builder: (context) {
        final future = _friendsStore.friendsFuture;

        if (future == null) {
          return Center(
            child: Padding(
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: const CircularProgressIndicator(),
            ),
          );
        }

        switch (future.status) {
          case FutureStatus.pending:
            return FrostyScrollbar(
              controller: widget.scrollController,
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: CustomScrollView(
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, topInset, 16, bottomInset),
                    sliver: SliverList.builder(
                      itemCount: 8,
                      itemBuilder: (context, index) => const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: SkeletonLoader(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          height: 72,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          case FutureStatus.rejected:
            final err = future.error;
            final message = err is ApiException
                ? err.message
                : (err?.toString() ?? 'Unable to load friends');
            return Center(
              child: Padding(
                padding: EdgeInsets.only(
                  top: topInset,
                  left: 24,
                  right: 24,
                  bottom: bottomInset,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AlertMessage(
                      message: message,
                      vertical: true,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        unawaited(_friendsStore.fetch());
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          case FutureStatus.fulfilled:
            final friends = _friendsStore.sortedFriends;
            if (friends.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                  child: const AlertMessage(message: 'No friends', vertical: true),
                ),
              );
            }

            final rows = _flattenFriends(friends);

            return FrostyScrollbar(
              controller: widget.scrollController,
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: RefreshIndicator.adaptive(
                edgeOffset: topInset,
                onRefresh: _friendsStore.fetch,
                child: CustomScrollView(
                  controller: widget.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, topInset, 16, bottomInset + 8),
                      sliver: SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final showDivider =
                              index > 0 && row is _FriendHeaderFlatRow;

                          return RepaintBoundary(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDivider) ...[
                                  Divider(
                                    height: 24,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ],
                                switch (row) {
                                  _FriendHeaderFlatRow(:final friend) =>
                                    _FriendHeaderTile(friend: friend),
                                  _FriendChannelFlatRow(:final channel) =>
                                    _FriendChannelTile(
                                      channel: channel,
                                      onOpen: () =>
                                          _openWatchedChannel(channel.channelLogin),
                                    ),
                                },
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}

sealed class _FriendFlatRow {
  const _FriendFlatRow();

  factory _FriendFlatRow.header(ReyohohoFriend friend) = _FriendHeaderFlatRow;

  factory _FriendFlatRow.channel(
    ReyohohoFriend friend,
    ReyohohoFriendChannel channel,
  ) = _FriendChannelFlatRow;
}

final class _FriendHeaderFlatRow extends _FriendFlatRow {
  const _FriendHeaderFlatRow(this.friend);

  final ReyohohoFriend friend;
}

final class _FriendChannelFlatRow extends _FriendFlatRow {
  const _FriendChannelFlatRow(this.friend, this.channel);

  final ReyohohoFriend friend;
  final ReyohohoFriendChannel channel;
}

class _FriendHeaderTile extends StatelessWidget {
  final ReyohohoFriend friend;

  const _FriendHeaderTile({required this.friend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = getReadableName(friend.displayName, friend.login);
    final radius = 22.0;
    final size = radius * 2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: friend.profileImageUrl.isNotEmpty
                ? FrostyCachedNetworkImage(
                    imageUrl: friend.profileImageUrl,
                    width: size,
                    height: size,
                    placeholder: (context, url) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: SizedBox(width: size, height: size),
                    ),
                  )
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: SizedBox(width: size, height: size),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (friend.isOnline)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        LiveIndicator(),
                        SizedBox(width: 6),
                        Text('Online', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Offline',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (friend.channels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Watching',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendChannelTile extends StatelessWidget {
  final ReyohohoFriendChannel channel;
  final VoidCallback onOpen;

  const _FriendChannelTile({
    required this.channel,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = StringBuffer(channel.streamCategory);
    if (channel.lastActiveAt != null) {
      subtitle.write(' · ');
      subtitle.write(
        _friendTimeFormat.format(channel.lastActiveAt!.toLocal()),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        getReadableName(
                          channel.channelDisplayName,
                          channel.channelLogin,
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      Text(
                        subtitle.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

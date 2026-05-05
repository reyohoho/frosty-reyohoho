import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/app_navigator_key.dart';
import 'package:frosty/screens/channel/channel.dart';
import 'package:frosty/screens/channel/chat/stores/chat_store.dart';
import 'package:frosty/screens/channel/video/video.dart';
import 'package:frosty/screens/channel/video/video_overlay.dart';
import 'package:frosty/screens/channel/video/video_store.dart';
import 'package:frosty/screens/channel/vods/vod_list_screen.dart';
import 'package:frosty/stores/mini_player_store.dart';
import 'package:frosty/utils/context_extensions.dart';
import 'package:provider/provider.dart';

/// Floating, draggable mini player rendered inside the root [Navigator]'s
/// [Overlay], above all routes. Owns the single mounted `Video` widget for
/// the active session: while [VideoChat] is on top of the navigator the
/// player is positioned to fill the slot it reports via [MiniPlayerStore.slotRect];
/// once the user pops, it shrinks into a bottom-corner thumb that stays
/// alive across other routes.
///
/// The same `Video` widget is kept mounted across both states (only its
/// `Positioned` rect changes) so the underlying PlatformView / WebView keeps
/// rendering frames continuously instead of being torn down and recreated.
///
/// Both the player chrome ([VideoOverlay] in full mode and the mini controls
/// in mini mode) live in this overlay layer too — otherwise the mini-player
/// `Video` would draw on top of any controls rendered inside [VideoChat].
class MiniPlayerOverlay extends StatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  bool _autoExpandScheduled = false;

  @override
  Widget build(BuildContext context) {
    final store = context.read<MiniPlayerStore>();

    return Observer(
      builder: (_) {
        if (store.presentation == MiniPlayerPresentation.hidden) {
          return const SizedBox.shrink();
        }
        final videoStore = store.videoStore;
        if (videoStore == null) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (ctx, constraints) {
            final mq = MediaQuery.of(ctx);
            final isLandscape = mq.orientation == Orientation.landscape;

            // Mini mode is portrait-only. If the device rotated to
            // landscape while we were minimized, push VideoChat back so the
            // player goes full-screen — much better UX than a tiny thumb on
            // a wide screen.
            if (store.presentation == MiniPlayerPresentation.mini &&
                isLandscape) {
              _maybeScheduleAutoExpand(store);
              return const SizedBox.shrink();
            }
            _autoExpandScheduled = false;

            final fullRect = store.slotRect ?? store.lastFullRect;
            final isFull = store.presentation == MiniPlayerPresentation.full;

            if (isFull && fullRect == null) {
              // VideoChat hasn't reported its slot yet (first frame).
              return const SizedBox.shrink();
            }

            final Rect targetRect;
            final bool inMini;
            if (isFull) {
              targetRect = fullRect!;
              inMini = false;
            } else {
              targetRect = _miniRect(mq, store);
              inMini = true;
            }

            return _OverlayContent(
              store: store,
              videoStore: videoStore,
              targetRect: targetRect,
              inMini: inMini,
            );
          },
        );
      },
    );
  }

  void _maybeScheduleAutoExpand(MiniPlayerStore store) {
    if (_autoExpandScheduled) return;
    _autoExpandScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = store.activeUserId;
      final login = store.activeUserLogin;
      final name = store.activeUserName;
      if (id == null || login == null || name == null) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => VideoChat(
            userId: id,
            userName: name,
            userLogin: login,
          ),
        ),
      );
    });
  }
}

/// Computes the mini-player rect for the given media query + drag state.
Rect _miniRect(MediaQueryData mq, MiniPlayerStore store) {
  const margin = 12.0;
  // Reserve some space for the typical bottom-nav bar so the thumb hovers
  // nicely above the Home tab bar. On routes without a bottom nav the thumb
  // just sits a bit higher, which is fine.
  const extraBottom = 80.0;

  final size = mq.size;
  final width = math.max(160.0, math.min(size.width * 0.42, 280.0));
  final height = width * 9 / 16;

  final dragLeft = store.draggingLeftPx;
  final left = dragLeft != null
      ? dragLeft.clamp(margin, size.width - width - margin)
      : (store.dockedSide == MiniPlayerDockSide.right
            ? size.width - width - margin
            : margin);

  final top =
      size.height - height - margin - mq.viewPadding.bottom - extraBottom;
  return Rect.fromLTWH(left, top, width, height);
}

/// Animated stack that positions the Video and its chrome (controls).
class _OverlayContent extends StatelessWidget {
  const _OverlayContent({
    required this.store,
    required this.videoStore,
    required this.targetRect,
    required this.inMini,
  });

  final MiniPlayerStore store;
  final VideoStore videoStore;
  final Rect targetRect;
  final bool inMini;

  @override
  Widget build(BuildContext context) {
    final duration = store.isDraggingMini
        ? Duration.zero
        : const Duration(milliseconds: 250);
    const curve = Curves.easeOutCubic;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. The actual Video. Same widget instance across full↔mini, just
        // re-positioned, so the PlatformView surface stays alive.
        AnimatedPositioned(
          left: targetRect.left,
          top: targetRect.top,
          width: targetRect.width,
          height: targetRect.height,
          duration: duration,
          curve: curve,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(inMini ? 10 : 0),
            child: KeyedSubtree(
              // Bumps when [openChannel] replaces the session, forcing a
              // fresh PlatformView for the new channel.
              key: ValueKey<int>(store.sessionEpoch),
              child: Video(videoStore: videoStore),
            ),
          ),
        ),
        // 2. Player chrome (controls). Either the full VideoOverlay (gestures
        //    + buttons) or the compact mini chrome.
        AnimatedPositioned(
          left: targetRect.left,
          top: targetRect.top,
          width: targetRect.width,
          height: targetRect.height,
          duration: duration,
          curve: curve,
          child: inMini
              ? _MiniChrome(store: store, videoStore: videoStore)
              : _FullChrome(store: store, videoStore: videoStore),
        ),
      ],
    );
  }
}

/// Full-size player chrome: the existing [VideoOverlay] wrapped in the same
/// gesture handlers that used to live in `channel.dart`.
class _FullChrome extends StatelessWidget {
  const _FullChrome({required this.store, required this.videoStore});

  final MiniPlayerStore store;
  final VideoStore videoStore;

  @override
  Widget build(BuildContext context) {
    final settingsStore = videoStore.settingsStore;
    final tabsStore = store.chatTabsStore;
    if (tabsStore == null) {
      // Session torn down between frames — nothing to render.
      return const SizedBox.shrink();
    }
    return Observer(
      builder: (_) {
        if (!settingsStore.showOverlay) {
          // Same behaviour as the old `Stack(children: [player, overlay])`
          // when overlay is disabled — render nothing on top of the video.
          return const SizedBox.shrink();
        }
        final chatStore = tabsStore.activeChatStore;
        return GestureDetector(
          onLongPress: videoStore.handleToggleOverlay,
          onDoubleTap: context.isLandscape
              ? () => settingsStore.fullScreen = !settingsStore.fullScreen
              : null,
          onTap: () => _onTap(chatStore),
          behavior: HitTestBehavior.translucent,
          child: Observer(
            builder: (_) {
              final videoOverlay = VideoOverlay(
                videoStore: videoStore,
                chatStore: chatStore,
                settingsStore: settingsStore,
                onOpenVodList: () => _openVodList(store),
              );

              if (videoStore.paused || videoStore.streamInfo == null) {
                return videoOverlay;
              }

              return AnimatedOpacity(
                opacity: videoStore.overlayVisible ? 1.0 : 0.0,
                curve: Curves.ease,
                duration: const Duration(milliseconds: 200),
                child: ColoredBox(
                  color: Colors.transparent,
                  child: IgnorePointer(
                    ignoring: !videoStore.overlayVisible,
                    child: videoOverlay,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _onTap(ChatStore chatStore) {
    if (chatStore.assetsStore.showEmoteMenu) {
      chatStore.assetsStore.showEmoteMenu = false;
      return;
    }
    if (chatStore.textFieldFocusNode.hasFocus) {
      chatStore.unfocusInput();
      return;
    }
    videoStore.handleVideoTap();
  }
}

/// Replacement for `_VideoChatState._openVodsReplacingChannel`. The user's
/// choice is "pushReplacement to VOD list closes the player" (no mini), so
/// we tear down the session before navigating.
void _openVodList(MiniPlayerStore store) {
  final id = store.activeUserId;
  final login = store.activeUserLogin;
  final name = store.activeUserName;
  if (id == null || login == null || name == null) return;
  store.closeSession(reason: 'open-vod');
  navigatorKey.currentState?.pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => VodListScreen(
        userId: id,
        userLogin: login,
        displayName: name,
        restoreChannelBuilder: () => VideoChat(
          userId: id,
          userName: name,
          userLogin: login,
        ),
      ),
    ),
  );
}

/// Compact chrome for the mini thumb: tap → expand, X → close, play/pause
/// in the centre, horizontal drag to move (with snap), strong horizontal
/// flick to dismiss.
class _MiniChrome extends StatefulWidget {
  const _MiniChrome({required this.store, required this.videoStore});

  final MiniPlayerStore store;
  final VideoStore videoStore;

  @override
  State<_MiniChrome> createState() => _MiniChromeState();
}

class _MiniChromeState extends State<_MiniChrome> {
  double? _dragStartLeft;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _expand,
      onHorizontalDragStart: (details) {
        final rect = _miniRect(mq, widget.store);
        _dragStartLeft = rect.left;
        widget.store.beginDrag();
        widget.store.updateDrag(rect.left);
      },
      onHorizontalDragUpdate: (details) {
        final start = _dragStartLeft;
        if (start == null) return;
        final next =
            (widget.store.draggingLeftPx ?? start) + details.delta.dx;
        widget.store.updateDrag(next);
      },
      onHorizontalDragEnd: (details) {
        final size = mq.size;
        final velocity = details.velocity.pixelsPerSecond.dx;
        final rect = _miniRect(mq, widget.store);
        final centerX = rect.center.dx;
        if (velocity.abs() > 1200) {
          HapticFeedback.mediumImpact();
          widget.store.closeSession(reason: 'swipe-dismiss');
          return;
        }
        final settledSide = centerX < size.width / 2
            ? MiniPlayerDockSide.left
            : MiniPlayerDockSide.right;
        widget.store.endDrag(settledSide);
      },
      onHorizontalDragCancel: () {
        widget.store.endDrag(widget.store.dockedSide);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle gradient so the controls stay readable over bright
          // streams. Pointer events fall through to the gesture detector.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                  ],
                  stops: const [0, 0.4, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: _CircleIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close mini player',
              onPressed: () =>
                  widget.store.closeSession(reason: 'mini-x-button'),
            ),
          ),
          Center(
            child: Observer(
              builder: (_) {
                final paused = widget.videoStore.paused;
                return _CircleIconButton(
                  icon: paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  tooltip: paused ? 'Resume' : 'Pause',
                  onPressed: widget.videoStore.handlePausePlay,
                  size: 40,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _expand() {
    final id = widget.store.activeUserId;
    final login = widget.store.activeUserLogin;
    final name = widget.store.activeUserName;
    if (id == null || login == null || name == null) return;
    if (Platform.isAndroid) HapticFeedback.lightImpact();
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => VideoChat(
          userId: id,
          userName: name,
          userLogin: login,
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 28,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.65,
          ),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Transparent placeholder that [VideoChat] renders in the place where the
/// player would have been. On every layout it reports its rect (in global
/// coordinates) to [MiniPlayerStore] so the overlay can position the real
/// `Video` widget on top of it.
class PlayerSlotReporter extends StatefulWidget {
  const PlayerSlotReporter({
    super.key,
    required this.store,
    this.aspectRatio,
    this.child,
  });

  final MiniPlayerStore store;

  /// If supplied, the placeholder is wrapped in an [AspectRatio] so the slot
  /// has a known intrinsic size in unconstrained contexts (e.g. portrait
  /// `Column`).
  final double? aspectRatio;

  /// Optional child rendered inside the slot. Used by [VideoChat] for the
  /// PiP-swipe gesture wrapper.
  final Widget? child;

  @override
  State<PlayerSlotReporter> createState() => _PlayerSlotReporterState();
}

class _PlayerSlotReporterState extends State<PlayerSlotReporter> {
  final GlobalKey _key = GlobalKey();
  Rect? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_postFrame);
  }

  @override
  void didUpdateWidget(covariant PlayerSlotReporter old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback(_postFrame);
  }

  void _postFrame(Duration _) {
    if (!mounted) return;
    final ctx = _key.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
    if (_last != rect) {
      _last = rect;
      widget.store.reportSlotRect(rect);
    }
    // Keep polling on every frame while we're mounted — handles cases like
    // landscape rotation, fullScreen toggle, divider drag, where the slot
    // moves without our build being rebuilt.
    if (mounted) WidgetsBinding.instance.addPostFrameCallback(_postFrame);
  }

  @override
  void dispose() {
    // Don't call store.reportSlotRect(null) from dispose — by the time
    // VideoChat is being torn down, the [MiniPlayerStore] state machine
    // (driven by the route observer) has already taken over and may have
    // moved us into mini mode. Nullifying the slot here would race with
    // that and briefly hide the overlay.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox.expand(
      key: _key,
      child: widget.child ?? const ColoredBox(color: Colors.black),
    );
    if (widget.aspectRatio != null) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio!,
        child: placeholder,
      );
    }
    return placeholder;
  }
}

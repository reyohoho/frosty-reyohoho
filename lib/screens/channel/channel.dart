import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/channel/chat/stores/chat_store.dart';
import 'package:frosty/screens/channel/chat/stores/chat_tabs_store.dart';
import 'package:frosty/screens/channel/chat/widgets/chat_tabs.dart';
import 'package:frosty/screens/channel/video/stream_info_bar.dart';
import 'package:frosty/screens/channel/video/video_store.dart';
import 'package:frosty/screens/channel/vods/vod_list_screen.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/stores/mini_player_store.dart';
import 'package:frosty/theme.dart';
import 'package:frosty/utils/context_extensions.dart';
import 'package:frosty/widgets/blurred_container.dart';
import 'package:frosty/widgets/draggable_divider.dart';
import 'package:frosty/widgets/frosty_notification.dart';
import 'package:frosty/widgets/loading_indicator.dart';
import 'package:frosty/widgets/mini_player/mini_player_overlay.dart';
import 'package:frosty/widgets/mini_player/mini_player_route_observer.dart';
import 'package:provider/provider.dart';
import 'package:simple_pip_mode/actions/pip_actions_layout.dart';
import 'package:simple_pip_mode/pip_widget.dart';

/// Creates a widget that shows the video stream (if live) and chat of the given user.
///
/// The actual `Video` widget and its overlay live in the global
/// [MiniPlayerOverlay], not inside this screen — VideoChat only renders a
/// transparent placeholder ([PlayerSlotReporter]) at the spot where the
/// player should appear, then reports that rect to [MiniPlayerStore]. This
/// lets the player survive being popped: the slot disappears, the overlay
/// notices and animates the same Video widget into a floating mini thumb.
class VideoChat extends StatefulWidget {
  final String userId;
  final String userName;
  final String userLogin;

  const VideoChat({
    super.key,
    required this.userId,
    required this.userName,
    required this.userLogin,
  });

  @override
  State<VideoChat> createState() => _VideoChatState();
}

class _VideoChatState extends State<VideoChat>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  final _chatKey = GlobalKey();

  // PiP drag state - essential only.
  // The "PiP" naming is now a misnomer: this swipe-down gesture used to
  // request system Picture-in-Picture, but the user-selected behaviour is
  // now to collapse into the in-app mini player instead.
  double _pipDragDistance = 0;
  bool _isPipDragging = false;
  bool _isInPipTriggerZone = false;

  // Divider drag state for synchronizing animation
  bool _isDividerDragging = false;

  // Essential constants for good UX balance
  static const double _pipTriggerDistance = 80;
  static const double _pipMaxDragDistance = 150;

  // Animation controller for smooth spring-back
  late AnimationController _animationController;
  late Animation<double> _springBackAnimation;

  bool _channelStoresReady = false;
  late MiniPlayerStore _miniPlayerStore;

  ChatTabsStore get _chatTabsStore => _miniPlayerStore.chatTabsStore!;
  VideoStore get _videoStore => _miniPlayerStore.videoStore!;
  ChatStore get _chatStore => _chatTabsStore.activeChatStore;

  Future<void> _initChannelStores() async {
    final isReusing = _miniPlayerStore.isSessionFor(widget.userId);
    if (!isReusing) {
      await _miniPlayerStore.openChannel(
        userId: widget.userId,
        userLogin: widget.userLogin,
        userName: widget.userName,
      );
    }
    if (!mounted) return;
    // The session may have been replaced by a parallel `openChannel` while
    // we were awaiting (user opened a second channel). Bail out — our route
    // will be auto-popped via the didPopNext check.
    if (!_miniPlayerStore.isSessionFor(widget.userId)) return;
    setState(() => _channelStoresReady = true);
    _miniPlayerStore.enterFull();
  }

  @override
  void initState() {
    super.initState();
    _miniPlayerStore = context.read<MiniPlayerStore>();

    unawaited(_initChannelStores());

    // Initialize animation controller for smooth drag interactions
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    // Spring-back animation with smooth easing
    _springBackAnimation =
        Tween<double>(begin: 0, end: 0).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        )..addListener(() {
          setState(() {
            _pipDragDistance = _springBackAnimation.value;
          });
        });

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) {
      miniPlayerRouteObserver.subscribe(this, route);
    }
  }

  // RouteAware overrides — drive the mini-player presentation as the user
  // navigates around. Only `didPop` and `didPushNext` collapse into mini;
  // `didPush` and `didPopNext` restore full mode. Replacements (e.g. the
  // VOD list) are handled by the explicit `closeSession` in `_openVodList`.

  @override
  void didPush() {
    if (_channelStoresReady) _miniPlayerStore.enterFull();
  }

  @override
  void didPopNext() {
    if (!_channelStoresReady) return;
    // If a sibling VideoChat replaced our session in the meantime (user
    // opened a different channel from the stream list while we were sitting
    // in the navigator stack), don't rebuild ourselves with someone else's
    // chat/video — auto-pop instead.
    if (!_miniPlayerStore.isSessionFor(widget.userId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
      return;
    }
    _miniPlayerStore.enterFull();
  }

  @override
  void didPushNext() {
    if (_channelStoresReady) _miniPlayerStore.minimizeAfterPop();
  }

  @override
  void didPop() {
    if (_channelStoresReady) _miniPlayerStore.minimizeAfterPop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && _channelStoresReady) {
      _videoStore.handleAppResume();
    }
  }

  void _handlePipDragStart(DragStartDetails details) {
    // Disable swipe-down gesture when video is paused.
    if (!_channelStoresReady || _videoStore.paused) return;

    _animationController.stop();
    setState(() {
      _isPipDragging = true;
      _pipDragDistance = 0;
      _isInPipTriggerZone = false;
    });
  }

  void _handlePipDragUpdate(DragUpdateDetails details) {
    if (!_isPipDragging || !_channelStoresReady || _videoStore.paused) {
      return;
    }

    setState(() {
      _pipDragDistance += details.delta.dy;
      _pipDragDistance = _pipDragDistance.clamp(0, _pipMaxDragDistance);

      final wasInTriggerZone = _isInPipTriggerZone;
      _isInPipTriggerZone = _pipDragDistance >= _pipTriggerDistance;

      if (!wasInTriggerZone && _isInPipTriggerZone) {
        HapticFeedback.mediumImpact();
      } else if (wasInTriggerZone && !_isInPipTriggerZone) {
        HapticFeedback.lightImpact();
      }
    });
  }

  void _handlePipDragEnd(DragEndDetails details) {
    if (!_isPipDragging || !_channelStoresReady || _videoStore.paused) {
      return;
    }

    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldMinimize =
        _pipDragDistance >= _pipTriggerDistance || velocity > 600;

    if (shouldMinimize) {
      HapticFeedback.mediumImpact();
      // Pop the channel route — the RouteAware didPop handler then drives
      // [MiniPlayerStore] into mini mode.
      _resetDragState();
      Navigator.of(context).maybePop();
    } else {
      _animateSpringBack();
    }
  }

  void _handlePipDragCancel() {
    if (!_isPipDragging) return;
    _animateSpringBack();
  }

  void _resetDragState() {
    setState(() {
      _isPipDragging = false;
      _pipDragDistance = 0;
      _isInPipTriggerZone = false;
    });
  }

  void _animateSpringBack() {
    _springBackAnimation = Tween<double>(begin: _pipDragDistance, end: 0)
        .animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _animationController.reset();
    _animationController.forward().then((_) {
      _resetDragState();
    });
  }

  /// Wraps a video slot widget with the in-app mini-player swipe-down gesture.
  ///
  /// Provides visual feedback (translate + scale), haptic feedback, and an
  /// instructional overlay during the drag gesture.
  Widget _buildPipGestureWrapper({required Widget child, double? aspectRatio}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_animationController, _springBackAnimation]),
      builder: (context, _) {
        final currentDragDistance = _isPipDragging
            ? _pipDragDistance
            : _springBackAnimation.value;

        final scaleFactor =
            1.0 - (currentDragDistance / _pipMaxDragDistance * 0.1);

        Widget content = child;
        if (aspectRatio != null) {
          content = AspectRatio(aspectRatio: aspectRatio, child: child);
        }

        return Transform.translate(
          offset: Offset(0, currentDragDistance),
          child: Transform.scale(
            scale: scaleFactor.clamp(0.9, 1.0),
            child: Stack(
              children: [
                GestureDetector(
                  onPanStart: _handlePipDragStart,
                  onPanUpdate: _handlePipDragUpdate,
                  onPanEnd: _handlePipDragEnd,
                  onPanCancel: _handlePipDragCancel,
                  child: content,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !(_isPipDragging && _pipDragDistance > 0),
                    child: AnimatedOpacity(
                      opacity: (_isPipDragging && _pipDragDistance > 0)
                          ? 1.0
                          : 0.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.4),
                        child: const Center(
                          child: Text(
                            'Swipe down for mini player',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds a transparent placeholder that occupies the same space the player
  /// used to occupy. The real `Video` widget lives in [MiniPlayerOverlay] and
  /// reads its target rect from this slot.
  Widget _buildSlot({double? aspectRatio}) {
    return PlayerSlotReporter(
      store: _miniPlayerStore,
      aspectRatio: aspectRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    // If the session was torn down (e.g. user popped + closeSession from
    // mini chrome happened in the same frame), avoid building UI that
    // dereferences null stores. The route will be popped by the auto-pop
    // logic in didPopNext or by the navigator transition.
    if (!_channelStoresReady ||
        _miniPlayerStore.videoStore == null ||
        _miniPlayerStore.chatTabsStore == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    final settingsStore = _chatTabsStore.settingsStore;

    final chat = Observer(
      builder: (context) {
        final bool chatOnly = !settingsStore.showVideo;

        return Stack(
          children: [
            ChatTabs(
              key: _chatKey,
              chatTabsStore: _chatTabsStore,
              listPadding: chatOnly
                  ? EdgeInsets.only(top: context.safePaddingTop)
                  : null,
            ),
            Observer(
              builder: (_) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _chatStore.notification != null
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: chatOnly ? context.safePaddingTop : 0,
                          ),
                          child: FrostyNotification(
                            message: _chatStore.notification!,
                            onDismissed: _chatStore.clearNotification,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        );
      },
    );

    final videoChat = Observer(
      builder: (context) {
        // Build a blurred AppBar when in chat-only mode (no video)
        PreferredSizeWidget? chatOnlyBlurredAppBar;
        if (!settingsStore.showVideo) {
          final streamInfo = _videoStore.streamInfo;

          chatOnlyBlurredAppBar = AppBar(
            centerTitle: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  context.theme.brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            title: StreamInfoBar(
              streamInfo: streamInfo,
              offlineChannelInfo: _videoStore.offlineChannelInfo,
              displayName: _chatStore.displayName,
              isCompact: true,
              isOffline: streamInfo == null,
              isInSharedChatMode: _chatStore.isInSharedChatMode,
              showTextShadows: false,
              onAvatarTap: _openVodsReplacingChannel,
            ),
            flexibleSpace: BlurredContainer(
              gradientDirection: GradientDirection.up,
              child: const SizedBox.expand(),
            ),
          );
        }

        return Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: chatOnlyBlurredAppBar,
          body: Observer(
            builder: (context) {
              if (context.isLandscape &&
                  !settingsStore.landscapeForceVerticalChat) {
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky,
                );

                final landscapeChat = AnimatedContainer(
                  curve: Curves.ease,
                  duration: _isDividerDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  width: _chatStore.expandChat
                      ? context.screenWidth / 2
                      : context.screenWidth * settingsStore.chatWidth,
                  color: settingsStore.fullScreen
                      ? Colors.black.withValues(
                          alpha: settingsStore.fullScreenChatOverlayOpacity,
                        )
                      : context.scaffoldColor,
                  child: chat,
                );

                final overlayChat = Visibility(
                  visible: settingsStore.fullScreenChatOverlay,
                  maintainState: true,
                  child: Theme(
                    data: FrostyThemes(
                      colorSchemeSeed: Color(settingsStore.accentColor),
                    ).dark,
                    child: DefaultTextStyle(
                      style: context.defaultTextStyle.copyWith(
                        color: context
                            .watch<FrostyThemes>()
                            .dark
                            .colorScheme
                            .onSurface,
                      ),
                      child: landscapeChat,
                    ),
                  ),
                );

                return ColoredBox(
                  color: settingsStore.showVideo
                      ? Colors.black
                      : context.scaffoldColor,
                  child: settingsStore.showVideo
                      ? settingsStore.fullScreen
                            ? Stack(
                                children: [
                                  _buildPipGestureWrapper(child: _buildSlot()),
                                  if (settingsStore.showOverlay)
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final totalWidth = constraints.maxWidth;
                                        final chatWidth = _chatStore.expandChat
                                            ? 0.5
                                            : settingsStore.chatWidth;

                                        final draggableDivider = Observer(
                                          builder: (_) => DraggableDivider(
                                            currentWidth: chatWidth,
                                            maxWidth: 0.6,
                                            isResizableOnLeft: settingsStore
                                                .landscapeChatLeftSide,
                                            showHandle:
                                                _videoStore.overlayVisible &&
                                                settingsStore
                                                    .fullScreenChatOverlay,
                                            onDragStart: () {
                                              setState(() {
                                                _isDividerDragging = true;
                                              });
                                            },
                                            onDrag: (newWidth) {
                                              if (!_chatStore.expandChat) {
                                                settingsStore.chatWidth =
                                                    newWidth;
                                              }
                                            },
                                            onDragEnd: () {
                                              setState(() {
                                                _isDividerDragging = false;
                                              });
                                            },
                                          ),
                                        );

                                        return Stack(
                                          children: [
                                            Row(
                                              children:
                                                  settingsStore
                                                      .landscapeChatLeftSide
                                                  ? [
                                                      overlayChat,
                                                      const Expanded(
                                                        child: SizedBox(),
                                                      ),
                                                    ]
                                                  : [
                                                      const Expanded(
                                                        child: SizedBox(),
                                                      ),
                                                      overlayChat,
                                                    ],
                                            ),
                                            if (settingsStore
                                                .fullScreenChatOverlay)
                                              Positioned(
                                                top: 0,
                                                bottom: 0,
                                                left:
                                                    settingsStore
                                                        .landscapeChatLeftSide
                                                    ? (totalWidth * chatWidth) -
                                                          12
                                                    : null,
                                                right:
                                                    !settingsStore
                                                        .landscapeChatLeftSide
                                                    ? (totalWidth * chatWidth) -
                                                          12
                                                    : null,
                                                child: draggableDivider,
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              )
                            : SafeArea(
                                bottom: false,
                                left:
                                    !settingsStore
                                        .landscapeDisplayUnderCutout &&
                                    settingsStore.landscapeCutout !=
                                        LandscapeCutoutType.left &&
                                    settingsStore.landscapeCutout !=
                                        LandscapeCutoutType.both,
                                right:
                                    !settingsStore
                                        .landscapeDisplayUnderCutout &&
                                    settingsStore.landscapeCutout !=
                                        LandscapeCutoutType.right &&
                                    settingsStore.landscapeCutout !=
                                        LandscapeCutoutType.both,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final availableWidth = constraints.maxWidth;
                                    final chatWidth = _chatStore.expandChat
                                        ? 0.5
                                        : settingsStore.chatWidth;

                                    final chatContainer = AnimatedContainer(
                                      curve: Curves.ease,
                                      duration: _isDividerDragging
                                          ? Duration.zero
                                          : const Duration(milliseconds: 200),
                                      width: availableWidth * chatWidth,
                                      color: settingsStore.fullScreen
                                          ? Colors.black.withValues(
                                              alpha: settingsStore
                                                  .fullScreenChatOverlayOpacity,
                                            )
                                          : context.scaffoldColor,
                                      child: chat,
                                    );

                                    final draggableDivider = Observer(
                                      builder: (_) => DraggableDivider(
                                        currentWidth: chatWidth,
                                        minWidth: 0.1,
                                        maxWidth: 0.6,
                                        isResizableOnLeft:
                                            settingsStore.landscapeChatLeftSide,
                                        showHandle: _videoStore.overlayVisible,
                                        onDragStart: () {
                                          setState(() {
                                            _isDividerDragging = true;
                                          });
                                        },
                                        onDrag: (newWidth) {
                                          if (!_chatStore.expandChat) {
                                            settingsStore.chatWidth = newWidth;
                                          }
                                        },
                                        onDragEnd: () {
                                          setState(() {
                                            _isDividerDragging = false;
                                          });
                                        },
                                      ),
                                    );

                                    return Stack(
                                      children: [
                                        Row(
                                          children:
                                              settingsStore
                                                  .landscapeChatLeftSide
                                              ? [
                                                  chatContainer,
                                                  Expanded(
                                                    child:
                                                        _buildPipGestureWrapper(
                                                          child: _buildSlot(),
                                                        ),
                                                  ),
                                                ]
                                              : [
                                                  Expanded(
                                                    child:
                                                        _buildPipGestureWrapper(
                                                          child: _buildSlot(),
                                                        ),
                                                  ),
                                                  chatContainer,
                                                ],
                                        ),
                                        Positioned(
                                          top: 0,
                                          bottom: 0,
                                          left:
                                              settingsStore
                                                  .landscapeChatLeftSide
                                              ? (availableWidth * chatWidth) -
                                                    12
                                              : null,
                                          right:
                                              !settingsStore
                                                  .landscapeChatLeftSide
                                              ? (availableWidth * chatWidth) -
                                                    12
                                              : null,
                                          child: draggableDivider,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              )
                      : SafeArea(child: chat),
                );
              }

              SystemChrome.setEnabledSystemUIMode(
                SystemUiMode.manual,
                overlays: SystemUiOverlay.values,
              );
              return SafeArea(
                top: settingsStore.showVideo,
                bottom: false,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        if (settingsStore.showVideo) ...[
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(),
                          ),
                        ],
                        Expanded(child: chat),
                      ],
                    ),
                    if (settingsStore.showVideo)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildPipGestureWrapper(
                          child: _buildSlot(aspectRatio: 16 / 9),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    // System Picture-in-Picture (out-of-app overlay) is still used when the
    // user backgrounds the whole app — it's wired up in [VideoStore]'s
    // `didChangeAppLifecycleState`. The PipWidget below provides the special
    // shrunk-down render path for that case (it draws just the player,
    // which we wrap as the `pipChild`).
    if (Platform.isAndroid) {
      return PipWidget(
        pipLayout: PipActionsLayout.mediaOnlyPause,
        onPipAction: (_) {
          debugPrint(
            '[PIP] Channel: PipWidget onPipAction (play/pause tapped in PIP)',
          );
          _videoStore.handlePausePlay();
        },
        // In system PiP mode the global mini-player overlay isn't visible
        // (the OS shows our process at thumbnail size). We draw a fresh
        // slot here so the same `Video` widget can be re-targeted to it
        // briefly. When the user collapses out of system PiP the regular
        // overlay logic takes over again.
        pipChild: PlayerSlotReporter(store: _miniPlayerStore),
        child: videoChat,
      );
    }

    return videoChat;
  }

  void _openVodsReplacingChannel() {
    final navigator = Navigator.of(context);
    // The user opted "pushReplacement (VOD list) closes the player" — same
    // behaviour as before this refactor. Tear down the session before
    // navigating so the mini-player overlay doesn't try to keep showing
    // the disposed Video.
    _miniPlayerStore.closeSession(reason: 'open-vod');
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VodListScreen(
          userId: widget.userId,
          userLogin: widget.userLogin,
          displayName: widget.userName,
          restoreChannelBuilder: () => VideoChat(
            userId: widget.userId,
            userName: widget.userName,
            userLogin: widget.userLogin,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    miniPlayerRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();

    // Don't dispose the channel stores here — they belong to
    // [MiniPlayerStore] now and live on across the route's pop so the mini
    // player can keep playing.

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    SystemChrome.setPreferredOrientations([]);

    super.dispose();
  }
}

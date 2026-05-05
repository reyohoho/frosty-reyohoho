import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frosty/apis/bttv_api.dart';
import 'package:frosty/apis/ffz_api.dart';
import 'package:frosty/apis/reyohoho_api.dart';
import 'package:frosty/apis/seventv_api.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/cache_manager.dart';
import 'package:frosty/screens/channel/chat/stores/chat_tabs_store.dart';
import 'package:frosty/screens/channel/video/video_store.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/stores/global_assets_store.dart';
import 'package:mobx/mobx.dart';

part 'mini_player_store.g.dart';

/// Where the global player is currently rendered.
///
/// * `hidden` — no active session, or the channel is in chat-only mode and
///   so there is no video to show anywhere.
/// * `full` — the channel screen ([VideoChat]) is on top of the navigator and
///   the player is rendered into its slot at full size. The mini overlay is
///   not visible to the user but the same `Video` widget is kept mounted in
///   the global overlay layer.
/// * `mini` — the channel screen is no longer the top route; the player has
///   collapsed into a floating thumb at the bottom of the screen, on top of
///   whatever route is currently visible.
enum MiniPlayerPresentation { hidden, full, mini }

/// Which edge the mini player snaps to. Vertical position is fixed (bottom
/// of the screen above the system insets / nav bar).
enum MiniPlayerDockSide { left, right }

/// Owns the lifetime of [VideoStore] + [ChatTabsStore] across navigator
/// transitions and exposes the geometry needed by the global mini-player
/// overlay to position the single mounted `Video` widget.
///
/// Lives as a Provider singleton in `main.dart`, just like [SettingsStore].
class MiniPlayerStore = MiniPlayerStoreBase with _$MiniPlayerStore;

abstract class MiniPlayerStoreBase with Store {
  MiniPlayerStoreBase({
    required this.twitchApi,
    required this.bttvApi,
    required this.ffzApi,
    required this.sevenTVApi,
    required this.reyohohoApi,
    required this.authStore,
    required this.settingsStore,
    required this.globalAssetsStore,
  }) {
    // Auto-close mini when the stream goes offline. We don't fire while the
    // channel screen is on top — there the regular offline UI handles it; we
    // only want to dismiss the floating thumb when it's the only thing left.
    _autoCloseDisposer = reaction<bool>(
      (_) =>
          presentation == MiniPlayerPresentation.mini &&
          videoStore != null &&
          videoStore!.streamInfo == null &&
          videoStore!.offlineChannelInfo != null,
      (offline) {
        if (offline) closeSession(reason: 'offline');
      },
    );
  }

  final TwitchApi twitchApi;
  final BTTVApi bttvApi;
  final FFZApi ffzApi;
  final SevenTVApi sevenTVApi;
  final ReyohohoApi reyohohoApi;
  final AuthStore authStore;
  final SettingsStore settingsStore;
  final GlobalAssetsStore globalAssetsStore;

  // region session state

  /// `null` when no session is active.
  @observable
  VideoStore? videoStore;

  @observable
  ChatTabsStore? chatTabsStore;

  /// Identity of the currently active channel session. `null` when no session.
  @observable
  String? activeUserId;

  @observable
  String? activeUserLogin;

  @observable
  String? activeUserName;

  /// Bumped every time we (re)create the underlying stores. Used as a key on
  /// the global `Video` widget so it gets a fresh PlatformView when the
  /// channel changes, but is preserved while just toggling full↔mini.
  @observable
  int sessionEpoch = 0;

  /// Guards against re-entrant `openChannel` while the previous future is
  /// still in flight (e.g. user taps two channel cards in quick succession).
  Future<void>? _openInFlight;

  // endregion

  // region presentation state

  @observable
  MiniPlayerPresentation presentation = MiniPlayerPresentation.hidden;

  /// Geometry of the player slot inside the active [VideoChat] route, in
  /// **global** coordinates (i.e. relative to the root overlay). Updated on
  /// every layout pass while [VideoChat] is on top.
  ///
  /// `null` while no [VideoChat] is mounted, or while it is mounted but in
  /// chat-only mode (no video slot to attach to).
  @observable
  Rect? slotRect;

  /// Last known full-size slot rect. Used as the starting point for the
  /// full→mini animation when the slot disappears (e.g. on `pop`).
  Rect? _lastFullRect;
  Rect? get lastFullRect => _lastFullRect;

  @observable
  MiniPlayerDockSide dockedSide = MiniPlayerDockSide.right;

  /// True while the user is dragging the mini thumb. Disables the implicit
  /// AnimatedPositioned animation in the overlay so the player tracks the
  /// finger 1:1.
  @observable
  bool isDraggingMini = false;

  /// While the user drags horizontally, this overrides the docked-side
  /// position. `null` when no drag is in progress.
  @observable
  double? draggingLeftPx;

  // endregion

  late final ReactionDisposer _autoCloseDisposer;

  @computed
  bool get hasSession => videoStore != null;

  /// Whether the given channel is the one currently owned by this store.
  bool isSessionFor(String userId) =>
      activeUserId != null && activeUserId == userId;

  // region session lifecycle

  /// Opens (or re-opens) a session for the given channel.
  ///
  /// * Same `userId` as the active session → no-op (caller should just push
  ///   [VideoChat], which will call [enterFull]).
  /// * Different `userId` → existing session is torn down and a fresh one
  ///   starts.
  ///
  /// Mirrors the bootstrap that used to live in `_VideoChatState._initChannelStores`.
  Future<void> openChannel({
    required String userId,
    required String userLogin,
    required String userName,
  }) async {
    if (isSessionFor(userId)) return;

    // Serialize concurrent calls so two near-simultaneous `push VideoChat`
    // events don't both run the heavy bootstrap.
    final pending = _openInFlight;
    if (pending != null) {
      await pending;
      if (isSessionFor(userId)) return;
    }

    final completer = Completer<void>();
    _openInFlight = completer.future;
    try {
      await _replaceSession(
        userId: userId,
        userLogin: userLogin,
        userName: userName,
      );
    } finally {
      completer.complete();
      _openInFlight = null;
    }
  }

  Future<void> _replaceSession({
    required String userId,
    required String userLogin,
    required String userName,
  }) async {
    // Tear down the previous session before we overwrite the fields.
    _disposeStores();

    // Always verify a working starege domain on channel open. This is what
    // used to live in `_initChannelStores` and is required for emote proxy +
    // image widgets to work.
    final domain = await reyohohoApi.initializeDomain(force: true);
    if (settingsStore.useEmoteProxy && domain != null) {
      bttvApi.proxyUrlPrefix = domain;
      ffzApi.proxyUrlPrefix = domain;
      sevenTVApi.proxyUrlPrefix = domain;
    }

    if (CustomCacheManager.needsCacheFlush) {
      CustomCacheManager.needsCacheFlush = false;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await CustomCacheManager.instance.emptyCache();
    }

    final qualityProxy = settingsStore.usePlaylistProxy
        ? (await reyohohoApi.findQualityDomain()) ?? ''
        : '';

    final newChatTabs = ChatTabsStore(
      twitchApi: twitchApi,
      bttvApi: bttvApi,
      ffzApi: ffzApi,
      sevenTVApi: sevenTVApi,
      reyohohoApi: reyohohoApi,
      authStore: authStore,
      settingsStore: settingsStore,
      globalAssetsStore: globalAssetsStore,
      primaryChannelId: userId,
      primaryChannelLogin: userLogin,
      primaryDisplayName: userName,
    );

    final newVideo = VideoStore(
      userLogin: userLogin,
      userId: userId,
      twitchApi: twitchApi,
      reyohohoApi: reyohohoApi,
      authStore: authStore,
      settingsStore: settingsStore,
      usherProxyBaseUrl: qualityProxy,
    );

    runInAction(() {
      activeUserId = userId;
      activeUserLogin = userLogin;
      activeUserName = userName;
      videoStore = newVideo;
      chatTabsStore = newChatTabs;
      sessionEpoch++;
      slotRect = null;
      _lastFullRect = null;
      // Don't touch presentation here — caller (typically [VideoChat] in
      // its initState, or the in-app router that pushed it) decides via
      // [enterFull]. If we set it to `hidden` here we would override the
      // `full` state that was already requested by the route's didPush
      // observer.
    });
  }

  /// Tears down the current session and clears all state. Safe to call when
  /// no session is active.
  @action
  void closeSession({String reason = 'manual'}) {
    debugPrint('[mini_player] closeSession reason=$reason');
    _disposeStores();
    activeUserId = null;
    activeUserLogin = null;
    activeUserName = null;
    slotRect = null;
    _lastFullRect = null;
    isDraggingMini = false;
    draggingLeftPx = null;
    presentation = MiniPlayerPresentation.hidden;
  }

  void _disposeStores() {
    final v = videoStore;
    final c = chatTabsStore;
    videoStore = null;
    chatTabsStore = null;
    try {
      c?.dispose();
    } catch (e) {
      debugPrint('[mini_player] chatTabsStore dispose failed: $e');
    }
    try {
      v?.dispose();
    } catch (e) {
      debugPrint('[mini_player] videoStore dispose failed: $e');
    }
  }

  // endregion

  // region presentation transitions

  /// Reports the current slot rect from the active [VideoChat]. Pass `null`
  /// to clear (chat-only mode, or VideoChat about to unmount).
  @action
  void reportSlotRect(Rect? rect) {
    slotRect = rect;
    if (rect != null) _lastFullRect = rect;
  }

  /// Called when [VideoChat] mounts (or re-mounts after expansion). Flips
  /// the overlay to `full` if there is a session.
  @action
  void enterFull() {
    if (!hasSession) return;
    presentation = MiniPlayerPresentation.full;
  }

  /// Called when [VideoChat] is popped from the navigator. The session
  /// stays alive and the overlay collapses into the mini thumb.
  @action
  void minimizeAfterPop() {
    if (!hasSession) return;
    // chat-only mode never had a slot to collapse from — just drop the
    // session entirely, mini wouldn't be useful (no video).
    if (!settingsStore.showVideo) {
      closeSession(reason: 'chat-only-pop');
      return;
    }
    slotRect = null;
    presentation = MiniPlayerPresentation.mini;
  }

  /// Called when the user taps the mini thumb to expand back to the channel.
  /// Caller is responsible for actually pushing [VideoChat] on the navigator;
  /// the route's `didPush` listener in the global RouteObserver will then
  /// call [enterFull].
  @action
  void requestExpand() {
    if (!hasSession) return;
    presentation = MiniPlayerPresentation.full;
  }

  @action
  void setDockedSide(MiniPlayerDockSide side) {
    dockedSide = side;
  }

  @action
  void beginDrag() {
    isDraggingMini = true;
  }

  @action
  void updateDrag(double leftPx) {
    draggingLeftPx = leftPx;
  }

  @action
  void endDrag(MiniPlayerDockSide settledSide) {
    isDraggingMini = false;
    draggingLeftPx = null;
    dockedSide = settledSide;
  }

  // endregion

  void dispose() {
    _autoCloseDisposer();
    _disposeStores();
  }
}

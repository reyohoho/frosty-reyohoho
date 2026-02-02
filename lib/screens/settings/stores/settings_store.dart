import 'package:frosty/screens/channel/chat/stores/chat_tabs_store.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mobx/mobx.dart';

part 'settings_store.g.dart';

@JsonSerializable()
class SettingsStore extends _SettingsStoreBase with _$SettingsStore {
  SettingsStore();

  factory SettingsStore.fromJson(Map<String, dynamic> json) =>
      _$SettingsStoreFromJson(json);
  Map<String, dynamic> toJson() => _$SettingsStoreToJson(this);
}

abstract class _SettingsStoreBase with Store {
  // * General Settings
  // Theme defaults
  static const defaultThemeType = ThemeType.system;
  static const defaultAccentColor = 0xff9146ff;

  // Stream card defaults
  static const defaultShowThumbnails = true;
  static const defaultLargeStreamCard = false;

  // Links defaults
  static const defaultLaunchUrlExternal = false;

  // Theme options
  @JsonKey(defaultValue: defaultThemeType, unknownEnumValue: ThemeType.system)
  @observable
  var themeType = defaultThemeType;

  @JsonKey(defaultValue: defaultAccentColor)
  @observable
  var accentColor = defaultAccentColor;

  // Stream card options
  @JsonKey(defaultValue: defaultShowThumbnails)
  @observable
  var showThumbnails = defaultShowThumbnails;

  @JsonKey(defaultValue: defaultLargeStreamCard)
  @observable
  var largeStreamCard = defaultLargeStreamCard;

  // Links options
  @JsonKey(defaultValue: defaultLaunchUrlExternal)
  @observable
  var launchUrlExternal = defaultLaunchUrlExternal;

  @action
  void resetGeneralSettings() {
    themeType = defaultThemeType;
    accentColor = defaultAccentColor;

    largeStreamCard = defaultLargeStreamCard;
    showThumbnails = defaultShowThumbnails;

    launchUrlExternal = defaultLaunchUrlExternal;
    landscapeDisplayUnderCutout = defaultLandscapeDisplayUnderCutout;
  }

  // * Video Settings
  // Player defaults
  static const defaultShowVideo = true;
  static const defaultDefaultToHighestQuality = false;
  static const defaultUseTextureRendering = true;
  static const defaultUsePlaylistProxy = false;
  static const defaultSelectedProxyUrl = '';

  // Overlay defaults
  static const defaultShowOverlay = true;
  static const defaultToggleableOverlay = false;
  static const defaultShowLatency = false;

  // Audio compressor defaults
  static const defaultAudioCompressorEnabled = false;

  // Background audio defaults
  static const defaultBackgroundAudioEnabled = false;

  // VOD chat defaults
  static const defaultVodChatDelay = 0.0;

  // Player options
  @JsonKey(defaultValue: defaultShowVideo)
  @observable
  var showVideo = defaultShowVideo;

  @JsonKey(defaultValue: defaultDefaultToHighestQuality)
  @observable
  var defaultToHighestQuality = defaultDefaultToHighestQuality;

  @JsonKey(defaultValue: defaultUseTextureRendering)
  @observable
  var useTextureRendering = defaultUseTextureRendering;

  @JsonKey(defaultValue: defaultUsePlaylistProxy)
  @observable
  var usePlaylistProxy = defaultUsePlaylistProxy;

  @JsonKey(defaultValue: defaultSelectedProxyUrl)
  @observable
  var selectedProxyUrl = defaultSelectedProxyUrl;

  // Overlay options
  @JsonKey(defaultValue: defaultShowOverlay)
  @observable
  var showOverlay = defaultShowOverlay;

  @JsonKey(defaultValue: defaultToggleableOverlay)
  @observable
  var toggleableOverlay = defaultToggleableOverlay;

  @JsonKey(defaultValue: defaultShowLatency)
  @observable
  var showLatency = defaultShowLatency;

  // Audio compressor options
  @JsonKey(defaultValue: defaultAudioCompressorEnabled)
  @observable
  var audioCompressorEnabled = defaultAudioCompressorEnabled;

  // Background audio options
  @JsonKey(defaultValue: defaultBackgroundAudioEnabled)
  @observable
  var backgroundAudioEnabled = defaultBackgroundAudioEnabled;

  /// VOD chat delay in seconds. Positive values delay the chat,
  /// negative values make the chat appear earlier relative to the video.
  @JsonKey(defaultValue: defaultVodChatDelay)
  @observable
  var vodChatDelay = defaultVodChatDelay;

  @action
  void resetVideoSettings() {
    showVideo = defaultShowVideo;
    defaultToHighestQuality = defaultDefaultToHighestQuality;
    useTextureRendering = defaultUseTextureRendering;
    usePlaylistProxy = defaultUsePlaylistProxy;
    selectedProxyUrl = defaultSelectedProxyUrl;

    showOverlay = defaultShowOverlay;
    toggleableOverlay = defaultToggleableOverlay;
    showLatency = defaultShowLatency;
    audioCompressorEnabled = defaultAudioCompressorEnabled;
    backgroundAudioEnabled = defaultBackgroundAudioEnabled;
    vodChatDelay = defaultVodChatDelay;
  }

  // * Chat Settings
  // Message sizing defaults
  static const defaultBadgeScale = 1.0;
  static const defaultEmoteScale = 1.0;
  static const defaultMessageScale = 1.0;
  static const defaultMessageSpacing = 8.0;
  static const defaultFontSize = 12.0;

  // Message appearance defaults
  static const defaultShowDeletedMessages = false;
  static const defaultShowChatMessageDividers = false;
  static const defaultTimestampType = TimestampType.disabled;

  // Delay defaults
  static const defaultAutoSyncChatDelay = false;
  static const defaultChatDelay = 0.0;

  // Alert defaults
  static const defaultHighlightFirstTimeChatter = true;
  static const defaultShowUserNotices = true;

  // Layout defaults
  static const defaultEmoteMenuButtonOnLeft = false;

  // Landscape mode defaults
  static const defaultLandscapeChatLeftSide = false;
  static const defaultLandscapeForceVerticalChat = false;
  static const defaultLandscapeCutout = LandscapeCutoutType.none;
  static const defaultLandscapeDisplayUnderCutout = false;
  static const defaultChatWidth = 0.2;
  static const defaultFullScreenChatOverlayOpacity = 0.5;

  // mute words defaults
  static const defaultMutedWords = <String>[];
  static const defaultMatchWholeWord = true;

  // Autocomplete defaults
  static const defaultAutocomplete = true;

  // Emotes and badges defaults
  static const defaultShowTwitchEmotes = true;
  static const defaultShowTwitchBadges = true;
  static const defaultShow7TVEmotes = true;
  static const defaultShowBTTVEmotes = true;
  static const defaultShowBTTVBadges = true;
  static const defaultShowFFZEmotes = true;
  static const defaultShowFFZBadges = true;
  static const defaultShowReyohohoBadges = true;
  static const defaultShowPaints = true;

  // Emote proxy defaults
  static const defaultUseEmoteProxy = false;
  static const defaultSelectedEmoteProxyUrl = '';
  static const emoteCdnProxyUrl = 'https://cdn.rte.net.ru';

  /// Cache buster timestamp for emote proxy requests.
  /// Updated when user refreshes emotes to bypass proxy cache.
  /// Not persisted - each app session starts with a fresh timestamp.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @observable
  int emoteProxyCacheBuster = DateTime.now().millisecondsSinceEpoch;

  /// Updates the cache buster to force reload of proxied emotes.
  @action
  void refreshEmoteProxyCacheBuster() {
    emoteProxyCacheBuster = DateTime.now().millisecondsSinceEpoch;
  }

  // Recent messages defaults
  static const defaultShowRecentMessages = false;

  // Link preview defaults
  static const defaultShowLinkPreviews = true;
  static const defaultHideLinkPreviewLinks = false;
  static const defaultLinkPreviewMaxHeight = 200.0;
  static const defaultLinkPreviewMaxWidth = 300.0;

  // Chat tabs defaults
  static const defaultPersistChatTabs = true;
  static const defaultSecondaryTabs = <PersistedChatTab>[];

  // Message sizing options
  @JsonKey(defaultValue: defaultBadgeScale)
  @observable
  var badgeScale = defaultBadgeScale;

  @JsonKey(defaultValue: defaultEmoteScale)
  @observable
  var emoteScale = defaultEmoteScale;

  @JsonKey(defaultValue: defaultMessageScale)
  @observable
  var messageScale = defaultMessageScale;

  @JsonKey(defaultValue: defaultMessageSpacing)
  @observable
  var messageSpacing = defaultMessageSpacing;

  @JsonKey(defaultValue: defaultFontSize)
  @observable
  var fontSize = defaultFontSize;

  // Message appearance options
  @JsonKey(defaultValue: defaultShowDeletedMessages)
  @observable
  var showDeletedMessages = defaultShowDeletedMessages;

  @JsonKey(defaultValue: defaultShowChatMessageDividers)
  @observable
  var showChatMessageDividers = defaultShowChatMessageDividers;

  @JsonKey(
    defaultValue: defaultTimestampType,
    unknownEnumValue: TimestampType.disabled,
  )
  @observable
  var timestampType = defaultTimestampType;

  // Delay options
  @JsonKey(defaultValue: defaultAutoSyncChatDelay)
  @observable
  var autoSyncChatDelay = defaultAutoSyncChatDelay;

  @JsonKey(defaultValue: defaultChatDelay)
  @observable
  var chatDelay = defaultChatDelay;

  // Alert options
  @JsonKey(defaultValue: defaultHighlightFirstTimeChatter)
  @observable
  var highlightFirstTimeChatter = defaultHighlightFirstTimeChatter;

  @JsonKey(defaultValue: defaultShowUserNotices)
  @observable
  var showUserNotices = defaultShowUserNotices;

  // Layout options
  @JsonKey(defaultValue: defaultEmoteMenuButtonOnLeft)
  @observable
  var emoteMenuButtonOnLeft = defaultEmoteMenuButtonOnLeft;

  // Landscape mode options
  @JsonKey(defaultValue: defaultLandscapeChatLeftSide)
  @observable
  var landscapeChatLeftSide = defaultLandscapeChatLeftSide;

  @JsonKey(defaultValue: defaultLandscapeForceVerticalChat)
  @observable
  var landscapeForceVerticalChat = defaultLandscapeForceVerticalChat;

  @JsonKey(defaultValue: defaultLandscapeCutout)
  @observable
  var landscapeCutout = defaultLandscapeCutout;

  /// When true, in landscape the app draws under the display cutout (notch).
  @JsonKey(defaultValue: defaultLandscapeDisplayUnderCutout)
  @observable
  var landscapeDisplayUnderCutout = defaultLandscapeDisplayUnderCutout;

  @JsonKey(defaultValue: defaultChatWidth)
  @observable
  var chatWidth = defaultChatWidth;

  @JsonKey(defaultValue: defaultFullScreenChatOverlayOpacity)
  @observable
  var fullScreenChatOverlayOpacity = defaultFullScreenChatOverlayOpacity;

  // Autocomplete options
  @JsonKey(defaultValue: defaultAutocomplete)
  @observable
  var autocomplete = defaultAutocomplete;

  // Emotes and badges
  @JsonKey(defaultValue: defaultShowTwitchEmotes)
  @observable
  var showTwitchEmotes = defaultShowTwitchEmotes;

  @JsonKey(defaultValue: defaultShowTwitchBadges)
  @observable
  var showTwitchBadges = defaultShowTwitchBadges;

  @JsonKey(defaultValue: defaultShow7TVEmotes)
  @observable
  var show7TVEmotes = defaultShow7TVEmotes;

  @JsonKey(defaultValue: defaultShowBTTVEmotes)
  @observable
  var showBTTVEmotes = defaultShowBTTVEmotes;

  @JsonKey(defaultValue: defaultShowBTTVBadges)
  @observable
  var showBTTVBadges = defaultShowBTTVBadges;

  @JsonKey(defaultValue: defaultShowFFZEmotes)
  @observable
  var showFFZEmotes = defaultShowFFZEmotes;

  @JsonKey(defaultValue: defaultShowFFZBadges)
  @observable
  var showFFZBadges = defaultShowFFZBadges;

  @JsonKey(defaultValue: defaultShowReyohohoBadges)
  @observable
  var showReyohohoBadges = defaultShowReyohohoBadges;

  @JsonKey(defaultValue: defaultShowPaints)
  @observable
  var showPaints = defaultShowPaints;

  // Emote proxy
  @JsonKey(defaultValue: defaultUseEmoteProxy)
  @observable
  var useEmoteProxy = defaultUseEmoteProxy;

  @JsonKey(defaultValue: defaultSelectedEmoteProxyUrl)
  @observable
  var selectedEmoteProxyUrl = defaultSelectedEmoteProxyUrl;

  /// Returns the proxied emote URL if proxy is enabled, otherwise the original URL.
  /// Adds a cache buster timestamp to bypass proxy cache.
  String getProxiedEmoteUrl(String originalUrl) {
    if (!useEmoteProxy || originalUrl.isEmpty) return originalUrl;
    return '$emoteCdnProxyUrl/$originalUrl?t=$emoteProxyCacheBuster';
  }

  // Recent messages
  @JsonKey(defaultValue: defaultShowRecentMessages)
  @observable
  var showRecentMessages = defaultShowRecentMessages;

  // Link previews
  @JsonKey(defaultValue: defaultShowLinkPreviews)
  @observable
  var showLinkPreviews = defaultShowLinkPreviews;

  @JsonKey(defaultValue: defaultHideLinkPreviewLinks)
  @observable
  var hideLinkPreviewLinks = defaultHideLinkPreviewLinks;

  @JsonKey(defaultValue: defaultLinkPreviewMaxHeight)
  @observable
  var linkPreviewMaxHeight = defaultLinkPreviewMaxHeight;

  @JsonKey(defaultValue: defaultLinkPreviewMaxWidth)
  @observable
  var linkPreviewMaxWidth = defaultLinkPreviewMaxWidth;

  // Chat tabs
  @JsonKey(defaultValue: defaultPersistChatTabs)
  @observable
  var persistChatTabs = defaultPersistChatTabs;

  @JsonKey(defaultValue: defaultSecondaryTabs)
  @observable
  var secondaryTabs = defaultSecondaryTabs;

  @JsonKey(defaultValue: defaultMutedWords)
  @observable
  List<String> mutedWords = defaultMutedWords;

  @JsonKey(defaultValue: defaultMatchWholeWord)
  @observable
  bool matchWholeWord = defaultMatchWholeWord;

  @action
  void resetChatSettings() {
    badgeScale = defaultBadgeScale;
    emoteScale = defaultEmoteScale;
    messageScale = defaultMessageScale;
    messageSpacing = defaultMessageSpacing;
    fontSize = defaultFontSize;

    showDeletedMessages = defaultShowDeletedMessages;
    showChatMessageDividers = defaultShowChatMessageDividers;
    timestampType = defaultTimestampType;

    autoSyncChatDelay = defaultAutoSyncChatDelay;
    chatDelay = defaultChatDelay;

    highlightFirstTimeChatter = defaultHighlightFirstTimeChatter;
    showUserNotices = defaultShowUserNotices;

    emoteMenuButtonOnLeft = defaultEmoteMenuButtonOnLeft;

    landscapeChatLeftSide = defaultLandscapeChatLeftSide;
    landscapeForceVerticalChat = defaultLandscapeForceVerticalChat;
    landscapeCutout = defaultLandscapeCutout;
    chatWidth = defaultChatWidth;
    fullScreenChatOverlayOpacity = defaultFullScreenChatOverlayOpacity;

    mutedWords = defaultMutedWords;
    matchWholeWord = defaultMatchWholeWord;

    autocomplete = defaultAutocomplete;

    showTwitchEmotes = defaultShowTwitchEmotes;
    showTwitchBadges = defaultShowTwitchBadges;
    show7TVEmotes = defaultShow7TVEmotes;
    showBTTVEmotes = defaultShowBTTVEmotes;
    showBTTVBadges = defaultShowBTTVBadges;
    showFFZEmotes = defaultShowFFZEmotes;
    showFFZBadges = defaultShowFFZBadges;
    showReyohohoBadges = defaultShowReyohohoBadges;
    showPaints = defaultShowPaints;

    useEmoteProxy = defaultUseEmoteProxy;
    selectedEmoteProxyUrl = defaultSelectedEmoteProxyUrl;

    showRecentMessages = defaultShowRecentMessages;

    showLinkPreviews = defaultShowLinkPreviews;
    hideLinkPreviewLinks = defaultHideLinkPreviewLinks;
    linkPreviewMaxHeight = defaultLinkPreviewMaxHeight;
    linkPreviewMaxWidth = defaultLinkPreviewMaxWidth;

    persistChatTabs = defaultPersistChatTabs;
    secondaryTabs = defaultSecondaryTabs;
  }

  // * Other settings
  static const defaultShareCrashLogsAndAnalytics = true;

  @JsonKey(defaultValue: defaultShareCrashLogsAndAnalytics)
  @observable
  var shareCrashLogsAndAnalytics = defaultShareCrashLogsAndAnalytics;

  @action
  void resetOtherSettings() {
    shareCrashLogsAndAnalytics = defaultShareCrashLogsAndAnalytics;
  }

  // * Global configs
  static const defaultFullScreen = false;
  static const defaultFullScreenChatOverlay = false;
  static const defaultPinnedChannelIds = <String>[];

  @JsonKey(defaultValue: defaultFullScreen)
  @observable
  var fullScreen = defaultFullScreen;

  @JsonKey(defaultValue: defaultFullScreenChatOverlay)
  @observable
  var fullScreenChatOverlay = defaultFullScreenChatOverlay;

  @JsonKey(defaultValue: defaultPinnedChannelIds)
  @observable
  var pinnedChannelIds = defaultPinnedChannelIds;

  @action
  void resetGlobalConfigs() {
    fullScreen = defaultFullScreen;
    fullScreenChatOverlay = defaultFullScreenChatOverlay;
    pinnedChannelIds = defaultPinnedChannelIds;
  }

  @action
  void resetAllSettings() {
    resetGeneralSettings();
    resetVideoSettings();
    resetChatSettings();
    resetOtherSettings();
    resetGlobalConfigs();
  }
}

const themeNames = ['System', 'Light', 'Dark'];

enum ThemeType { system, light, dark }

const timestampNames = ['Disabled', '12-hour', '24-hour'];

enum TimestampType { disabled, twelve, twentyFour }

const landscapeCutoutNames = ['None', 'Left', 'Right', 'Both'];

enum LandscapeCutoutType { none, left, right, both }


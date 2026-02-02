import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/badges.dart';
import 'package:frosty/models/category.dart';
import 'package:frosty/models/channel.dart';
import 'package:frosty/models/emotes.dart';
import 'package:frosty/models/followed_channel.dart';
import 'package:frosty/models/shared_chat_session.dart';
import 'package:frosty/models/stream.dart';
import 'package:frosty/models/user.dart';
import 'package:frosty/models/vod.dart';
import 'package:frosty/models/vod_comment.dart';

/// Starege proxy domains for recent messages API.
const _recentMessagesProxyDomains = [
  'https://starege.rte.net.ru',
  'https://starege3.rte.net.ru',
  'https://starege5.rte.net.ru',
  'https://starege4.rte.net.ru',
];

/// The Twitch service for making API calls.
class TwitchApi extends BaseApiClient {
  static const String _helixBaseUrl = 'https://api.twitch.tv/helix';
  static const String _oauthBaseUrl = 'https://id.twitch.tv/oauth2';
  static const String _recentMessagesUrl =
      'https://recent-messages.robotty.de/api/v2';

  /// Cached working proxy domain for recent messages.
  String? _workingProxyDomain;
  Future<String?>? _proxyInitFuture;
  bool _proxyInitialized = false;

  TwitchApi(Dio dio) : super(dio, _helixBaseUrl);

  /// Finds a working proxy domain for recent messages.
  Future<String?> _initializeProxyDomain() async {
    if (_proxyInitialized && _workingProxyDomain != null) {
      return _workingProxyDomain;
    }

    if (_proxyInitFuture != null) {
      return _proxyInitFuture;
    }

    _proxyInitFuture = _findWorkingProxyDomain();
    _workingProxyDomain = await _proxyInitFuture;
    _proxyInitialized = true;
    _proxyInitFuture = null;

    return _workingProxyDomain;
  }

  Future<String?> _findWorkingProxyDomain() async {
    for (final domain in _recentMessagesProxyDomains) {
      try {
        final testUrl = '$domain/https://google.com';
        final response = await Dio().head(
          testUrl,
          options: Options(
            receiveTimeout: const Duration(seconds: 3),
            sendTimeout: const Duration(seconds: 3),
          ),
        );

        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 400) {
          debugPrint('TwitchApi: Using proxy domain for recent messages: $domain');
          return domain;
        }
      } catch (e) {
        // Try next domain
      }
    }

    debugPrint('TwitchApi: All proxy domains unavailable, using direct connection');
    return null;
  }

  /// Returns a list of all Twitch global emotes.
  Future<List<Emote>> getEmotesGlobal() async {
    final data = await get<JsonMap>('/chat/emotes/global');

    final decoded = data['data'] as JsonList;
    final emotes = decoded.map((emote) => EmoteTwitch.fromJson(emote)).toList();

    return emotes
        .map((emote) => Emote.fromTwitch(emote, EmoteType.twitchGlobal))
        .toList();
  }

  /// Returns a list of a channel's Twitch emotes given their [id].
  Future<List<Emote>> getEmotesChannel({required String id}) async {
    final data = await get<JsonMap>(
      '/chat/emotes',
      queryParameters: {'broadcaster_id': id},
    );

    final decoded = data['data'] as JsonList;
    final emotes = decoded.map((emote) => EmoteTwitch.fromJson(emote)).toList();

    return emotes.map((emote) {
      switch (emote.emoteType) {
        case 'bitstier':
          return Emote.fromTwitch(emote, EmoteType.twitchBits);
        case 'follower':
          return Emote.fromTwitch(emote, EmoteType.twitchFollower);
        case 'subscriptions':
          return Emote.fromTwitch(emote, EmoteType.twitchChannel);
        default:
          return Emote.fromTwitch(emote, EmoteType.twitchChannel);
      }
    }).toList();
  }

  /// Returns a list of Twitch emotes under the provided [setId].
  Future<List<Emote>> getEmotesSets({required String setId}) async {
    final data = await get<JsonMap>(
      '/chat/emotes/set',
      queryParameters: {'emote_set_id': setId},
    );

    final decoded = data['data'] as JsonList;
    final emotes = decoded.map((emote) => EmoteTwitch.fromJson(emote)).toList();

    return emotes.map((emote) {
      switch (emote.emoteType) {
        case 'globals':
        case 'smilies':
          return Emote.fromTwitch(emote, EmoteType.twitchGlobal);
        case 'subscriptions':
          return Emote.fromTwitch(emote, EmoteType.twitchSub);
        default:
          return Emote.fromTwitch(emote, EmoteType.twitchUnlocked);
      }
    }).toList();
  }

  /// Returns a map of global Twitch badges to their [Emote] object.
  Future<Map<String, ChatBadge>> getBadgesGlobal() async {
    final data = await get<JsonMap>('/chat/badges/global');

    final result = <String, ChatBadge>{};
    final decoded = data['data'] as JsonList;

    for (final badge in decoded) {
      final id = badge['set_id'] as String;
      final versions = badge['versions'] as JsonList;

      for (final version in versions) {
        final badgeInfo = BadgeInfoTwitch.fromJson(version);
        result['$id/${badgeInfo.id}'] = ChatBadge.fromTwitch(badgeInfo);
      }
    }

    return result;
  }

  /// Returns a map of a channel's Twitch badges to their [Emote] object.
  Future<Map<String, ChatBadge>> getBadgesChannel({required String id}) async {
    final data = await get<JsonMap>(
      '/chat/badges',
      queryParameters: {'broadcaster_id': id},
    );

    final result = <String, ChatBadge>{};
    final decoded = data['data'] as JsonList;

    for (final badge in decoded) {
      final id = badge['set_id'] as String;
      final versions = badge['versions'] as JsonList;

      for (final version in versions) {
        final badgeInfo = BadgeInfoTwitch.fromJson(version);
        result['$id/${badgeInfo.id}'] = ChatBadge.fromTwitch(badgeInfo);
      }
    }

    return result;
  }

  /// Returns the user's info given their token.
  Future<UserTwitch> getUserInfo() async {
    final data = await get<JsonMap>('/users');

    final userData = data['data'] as JsonList;
    return UserTwitch.fromJson(userData.first);
  }

  /// Returns a token for an anonymous user.
  Future<String> getDefaultToken() async {
    // Use custom base URL for OAuth
    final data = await post<JsonMap>(
      '$_oauthBaseUrl/token',
      queryParameters: {
        'client_id': clientId,
        'client_secret': secret,
        'grant_type': 'client_credentials',
      },
    );

    return data['access_token'] as String;
  }

  /// Returns a bool indicating the validity of the given token.
  Future<bool> validateToken({required String token}) async {
    try {
      await get<JsonMap>(
        '$_oauthBaseUrl/validate',
        headers: {'Authorization': 'Bearer $token'},
      );
      return true;
    } on UnauthorizedException {
      // 401 -> token is invalid/expired (propagated from interceptor for validate requests)
      return false;
    } on ApiException catch (e) {
      // Network/timeout/server errors -> treat as indeterminate, not invalid
      debugPrint('Token validation indeterminate: $e');
      rethrow;
    }
  }

  /// Returns a [StreamsTwitch] object that contains the top 20 streams and a cursor for further requests.
  Future<StreamsTwitch> getTopStreams({String? cursor}) async {
    final data = await get<JsonMap>(
      '/streams',
      queryParameters: cursor != null ? {'after': cursor} : null,
    );

    return StreamsTwitch.fromJson(data);
  }

  /// Returns a [StreamsTwitch] object that contains the given user ID's top 20 followed streams and a cursor for further requests.
  Future<StreamsTwitch> getFollowedStreams({
    required String id,
    String? cursor,
  }) async {
    final queryParams = {'user_id': id};
    if (cursor != null) queryParams['after'] = cursor;

    final data = await get<JsonMap>(
      '/streams/followed',
      queryParameters: queryParams,
    );

    return StreamsTwitch.fromJson(data);
  }

  /// Returns a [FollowedChannels] object containing all followed channels (including offline ones) for the given user ID.
  Future<FollowedChannels> getFollowedChannels({
    required String userId,
    String? cursor,
  }) async {
    final queryParams = {'user_id': userId, 'first': '20'};
    if (cursor != null) queryParams['after'] = cursor;

    final data = await get<JsonMap>(
      '/channels/followed',
      queryParameters: queryParams,
    );

    return FollowedChannels.fromJson(data);
  }

  /// Returns a [StreamsTwitch] object that contains the list of streams under the given game/category ID.
  Future<StreamsTwitch> getStreamsUnderCategory({
    required String gameId,
    String? cursor,
  }) async {
    final queryParams = {'game_id': gameId};
    if (cursor != null) queryParams['after'] = cursor;

    final data = await get<JsonMap>('/streams', queryParameters: queryParams);

    return StreamsTwitch.fromJson(data);
  }

  /// Returns a [StreamTwitch] object containing the stream info associated with the given [userLogin].
  Future<StreamTwitch> getStream({required String userLogin}) async {
    final data = await get<JsonMap>(
      '/streams',
      queryParameters: {'user_login': userLogin},
    );

    final streamData = data['data'] as JsonList;
    if (streamData.isNotEmpty) {
      return StreamTwitch.fromJson(streamData.first);
    } else {
      throw ApiException('$userLogin is offline', 404);
    }
  }

  Future<StreamsTwitch> getStreamsByIds({required List<String> userIds}) async {
    // Create query string manually for multiple user_id parameters
    final userIdParams = userIds.map((id) => 'user_id=$id').join('&');
    final url = '/streams?$userIdParams&first=100';

    final data = await get<JsonMap>(url);

    return StreamsTwitch.fromJson(data);
  }

  /// Returns a [UserTwitch] object containing the user info associated with the given [userLogin].
  Future<UserTwitch> getUser({String? userLogin, String? id}) async {
    final queryParams = <String, String>{};
    if (id != null) {
      queryParams['id'] = id;
    } else if (userLogin != null) {
      queryParams['login'] = userLogin;
    }

    final data = await get<JsonMap>('/users', queryParameters: queryParams);

    final userData = data['data'] as JsonList;
    if (userData.isNotEmpty) {
      return UserTwitch.fromJson(userData.first);
    } else {
      throw NotFoundException('User does not exist');
    }
  }

  /// Returns a [Channel] object containing a channels's info associated with the given [userId].
  Future<Channel> getChannel({required String userId}) async {
    final data = await get<JsonMap>(
      '/channels',
      queryParameters: {'broadcaster_id': userId},
    );

    final channelData = data['data'] as JsonList;
    if (channelData.isNotEmpty) {
      return Channel.fromJson(channelData.first);
    } else {
      throw ApiException('Channel does not exist', 404);
    }
  }

  /// Returns a list of [ChannelQuery] objects closest matching the given [query].
  Future<List<ChannelQuery>> searchChannels({required String query}) async {
    final data = await get<JsonMap>(
      '/search/channels',
      queryParameters: {'first': '8', 'query': query},
    );

    final channelData = data['data'] as JsonList;
    return channelData.map((e) => ChannelQuery.fromJson(e)).toList();
  }

  /// Returns a [CategoriesTwitch] object containing the next top 20 categories/games and a cursor for further requests.
  Future<CategoriesTwitch> getTopCategories({String? cursor}) async {
    final data = await get<JsonMap>(
      '/games/top',
      queryParameters: cursor != null ? {'after': cursor} : null,
    );

    return CategoriesTwitch.fromJson(data);
  }

  /// Returns a [CategoriesTwitch] object containing the category info corresponding to the provided [gameId].
  Future<CategoriesTwitch> getCategory({required String gameId}) async {
    final data = await get<JsonMap>('/games', queryParameters: {'id': gameId});

    return CategoriesTwitch.fromJson(data);
  }

  /// Returns a [CategoriesTwitch] containing up to 20 categories/games closest matching the [query] and a cursor for further requests.
  Future<CategoriesTwitch> searchCategories({
    required String query,
    String? cursor,
  }) async {
    final queryParams = {'first': '8', 'query': query};
    if (cursor != null) queryParams['after'] = cursor;

    final data = await get<JsonMap>(
      '/search/categories',
      queryParameters: queryParams,
    );

    return CategoriesTwitch.fromJson(data);
  }

  /// Returns the sub count associated with the given [userId].
  Future<int> getSubscriberCount({required String userId}) async {
    final data = await get<JsonMap>(
      '/subscriptions',
      queryParameters: {'broadcaster_id': userId},
    );

    return data['total'] as int;
  }

  /// Returns a user's list of blocked users given their id.
  Future<List<UserBlockedTwitch>> getUserBlockedList({
    required String id,
    String? cursor,
  }) async {
    final queryParams = {'first': '100', 'broadcaster_id': id};
    if (cursor != null) queryParams['after'] = cursor;

    final data = await get<JsonMap>(
      '/users/blocks',
      queryParameters: queryParams,
    );

    final paginationCursor = data['pagination']['cursor'];
    final blockedList = data['data'] as JsonList;

    if (blockedList.isNotEmpty) {
      final result = blockedList
          .map((e) => UserBlockedTwitch.fromJson(e))
          .toList();

      if (paginationCursor != null) {
        // Wait a bit (150 milliseconds) before recursively calling.
        // This will prevent going over the rate limit to due a massive blocked users list.
        //
        // With the Twitch API, we can make up to 800 requests per minute.
        // Waiting 150 milliseconds between requests will cap the rate here at 400 requests per minute.
        await Future.delayed(const Duration(milliseconds: 150));
        result.addAll(
          await getUserBlockedList(id: id, cursor: paginationCursor),
        );
      }

      return result;
    } else {
      debugPrint('User does not have anyone blocked');
      return [];
    }
  }

  // Blocks the user with the given ID and returns true on success or false on failure.
  Future<bool> blockUser({required String userId}) async {
    try {
      await put<dynamic>(
        '/users/blocks',
        queryParameters: {'target_user_id': userId},
      );
      return true; // If no exception, operation succeeded
    } on ApiException {
      return false;
    }
  }

  // Unblocks the user with the given ID and returns true on success or false on failure.
  Future<bool> unblockUser({required String userId}) async {
    try {
      await delete<dynamic>(
        '/users/blocks',
        queryParameters: {'target_user_id': userId},
      );
      return true; // If no exception, operation succeeded
    } on ApiException {
      return false;
    }
  }

  /// Bans a user from the specified channel.
  /// [broadcasterId] - The ID of the channel to ban the user from
  /// [moderatorId] - The ID of the moderator performing the action
  /// [userId] - The ID of the user to ban
  /// [reason] - Optional reason for the ban
  /// Returns true on success or false on failure.
  Future<bool> banUser({
    required String broadcasterId,
    required String moderatorId,
    required String userId,
    String? reason,
  }) async {
    try {
      await post<dynamic>(
        '/moderation/bans',
        queryParameters: {
          'broadcaster_id': broadcasterId,
          'moderator_id': moderatorId,
        },
        data: {
          'data': {
            'user_id': userId,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          },
        },
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Times out a user in the specified channel.
  /// [broadcasterId] - The ID of the channel to timeout the user in
  /// [moderatorId] - The ID of the moderator performing the action
  /// [userId] - The ID of the user to timeout
  /// [duration] - The duration of the timeout in seconds (max 1209600 = 2 weeks)
  /// [reason] - Optional reason for the timeout
  /// Returns true on success or false on failure.
  Future<bool> timeoutUser({
    required String broadcasterId,
    required String moderatorId,
    required String userId,
    required int duration,
    String? reason,
  }) async {
    try {
      await post<dynamic>(
        '/moderation/bans',
        queryParameters: {
          'broadcaster_id': broadcasterId,
          'moderator_id': moderatorId,
        },
        data: {
          'data': {
            'user_id': userId,
            'duration': duration,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          },
        },
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Removes a ban or timeout from a user in the specified channel.
  /// [broadcasterId] - The ID of the channel to unban the user from
  /// [moderatorId] - The ID of the moderator performing the action
  /// [userId] - The ID of the user to unban
  /// Returns true on success or false on failure.
  Future<bool> unbanUser({
    required String broadcasterId,
    required String moderatorId,
    required String userId,
  }) async {
    try {
      await delete<dynamic>(
        '/moderation/bans',
        queryParameters: {
          'broadcaster_id': broadcasterId,
          'moderator_id': moderatorId,
          'user_id': userId,
        },
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Deletes a specific chat message.
  /// [broadcasterId] - The ID of the channel the message was sent in
  /// [moderatorId] - The ID of the moderator performing the action
  /// [messageId] - The ID of the message to delete
  /// Returns true on success or false on failure.
  Future<bool> deleteMessage({
    required String broadcasterId,
    required String moderatorId,
    required String messageId,
  }) async {
    try {
      await delete<dynamic>(
        '/moderation/chat',
        queryParameters: {
          'broadcaster_id': broadcasterId,
          'moderator_id': moderatorId,
          'message_id': messageId,
        },
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<SharedChatSession?> getSharedChatSession({
    required String broadcasterId,
  }) async {
    final data = await get<JsonMap>(
      '/shared_chat/session',
      queryParameters: {'broadcaster_id': broadcasterId},
    );

    final sessionData = data['data'] as JsonList;
    if (sessionData.isEmpty) {
      return null;
    }

    return SharedChatSession.fromJson(sessionData.first);
  }

  /// Gets the color used for the user's name in chat.
  /// [userId] - The ID of the user whose chat color to get
  /// Returns the color as a hex string or empty string if no color is set.
  Future<String> getUserChatColor({required String userId}) async {
    try {
      final data = await get<JsonMap>(
        '/chat/color',
        queryParameters: {'user_id': userId},
      );

      final users = data['data'] as JsonList;
      if (users.isNotEmpty) {
        final user = users.first as JsonMap;
        return user['color'] as String? ?? '';
      }

      return '';
    } on ApiException {
      return '';
    }
  }

  /// Updates the color used for the user's name in chat.
  /// [userId] - The ID of the user whose chat color to update
  /// [color] - The color to use. Can be a named color (blue, blue_violet, etc.) or hex code for Turbo/Prime users
  /// Returns true on success or false on failure.
  Future<bool> updateUserChatColor({
    required String userId,
    required String color,
  }) async {
    try {
      await put<dynamic>(
        '/chat/color',
        queryParameters: {'user_id': userId, 'color': color},
      );
      return true; // If no exception, operation succeeded
    } on ApiException catch (e) {
      // Log the specific error for debugging
      debugPrint('Failed to update chat color: $e');
      return false;
    }
  }

  static const String _gqlBaseUrl = 'https://gql.twitch.tv/gql';

  /// Fetches VOD comments for a specific video at a given offset or cursor.
  ///
  /// Uses Twitch GQL API to get chat replay comments.
  /// [videoId] - The ID of the VOD
  /// [contentOffsetSeconds] - The offset in seconds from video start (used when [cursor] is null)
  /// [cursor] - Pagination cursor from previous response (fetches next page when provided)
  Future<VodCommentsResponse> getVodComments({
    required String videoId,
    int? contentOffsetSeconds,
    String? cursor,
  }) async {
    const persistedQueryHash =
        'b70a3591ff0f4e0313d126c6a1502d79a1c02baebb288227c582044aa76adf6a';

    final variables = <String, dynamic>{
      'videoID': videoId,
    };
    if (cursor != null) {
      variables['cursor'] = cursor;
    } else if (contentOffsetSeconds != null) {
      variables['contentOffsetSeconds'] = contentOffsetSeconds;
    }

    final body = [
      {
        'operationName': 'VideoCommentsByOffsetOrCursor',
        'variables': variables,
        'extensions': {
          'persistedQuery': {
            'version': 1,
            'sha256Hash': persistedQueryHash,
          },
        },
      },
    ];

    try {
      final response = await dio.post<List<dynamic>>(
        _gqlBaseUrl,
        data: body,
        options: Options(
          headers: {
            'Client-ID': 'kimne78kx3ncx6brgo4mv6wki5h1ko',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.data != null && response.data!.isNotEmpty) {
        return VodCommentsResponse.fromJson(
          response.data!.first as Map<String, dynamic>,
        );
      }

      return const VodCommentsResponse(
        comments: [],
        hasNextPage: false,
        hasPreviousPage: false,
      );
    } catch (e) {
      debugPrint('Error fetching VOD comments: $e');
      return const VodCommentsResponse(
        comments: [],
        hasNextPage: false,
        hasPreviousPage: false,
      );
    }
  }

  /// Returns a [VideosTwitch] object containing videos for the given user ID.
  ///
  /// [userId] - The ID of the user whose videos to get.
  /// [type] - Filter by video type: 'all', 'archive', 'highlight', 'upload'. Defaults to 'all'.
  /// [sort] - Sort order: 'time' (newest first), 'trending', 'views'. Defaults to 'time'.
  /// [cursor] - Pagination cursor for fetching more results.
  /// [first] - Number of videos to fetch (1-100). Defaults to 20.
  Future<VideosTwitch> getVideos({
    required String userId,
    String type = 'all',
    String sort = 'time',
    String? cursor,
    int first = 20,
  }) async {
    final queryParams = <String, String>{
      'user_id': userId,
      'type': type,
      'sort': sort,
      'first': first.toString(),
    };
    if (cursor != null) queryParams['after'] = cursor;

    final data = await get<JsonMap>('/videos', queryParameters: queryParams);

    return VideosTwitch.fromJson(data);
  }

  /// Returns a single video by its ID.
  Future<VideoTwitch> getVideo({required String videoId}) async {
    final data = await get<JsonMap>(
      '/videos',
      queryParameters: {'id': videoId},
    );

    final videoData = data['data'] as JsonList;
    if (videoData.isNotEmpty) {
      return VideoTwitch.fromJson(videoData.first);
    } else {
      throw NotFoundException('Video not found');
    }
  }

  // Gets recent messages from a third-party service via proxy.
  Future<JsonList> getRecentMessages({required String userLogin}) async {
    final proxyDomain = await _initializeProxyDomain();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final targetUrl = '$_recentMessagesUrl/recent-messages/$userLogin?t=$timestamp';

    // Use proxy if available, otherwise fall back to direct connection
    final url = proxyDomain != null ? '$proxyDomain/$targetUrl' : targetUrl;

    final data = await get<JsonMap>(url);

    return data['messages'] as JsonList;
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reyohoho_friend.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReyohohoFriendChannel _$ReyohohoFriendChannelFromJson(
  Map<String, dynamic> json,
) => ReyohohoFriendChannel(
  channelLogin: json['channel_login'] as String,
  channelDisplayName: json['channel_display_name'] as String,
  streamCategory: json['stream_category'] as String,
  lastActiveAt: _dateTimeFromJson(json['last_active_at']),
);

ReyohohoFriend _$ReyohohoFriendFromJson(Map<String, dynamic> json) =>
    ReyohohoFriend(
      twitchId: _stringId(json['twitch_id']),
      login: json['login'] as String,
      displayName: json['display_name'] as String,
      profileImageUrl: json['profile_image_url'] as String,
      channels: (json['channels'] as List<dynamic>)
          .map((e) => ReyohohoFriendChannel.fromJson(e as Map<String, dynamic>))
          .toList(),
      isOnline: json['is_online'] as bool,
    );

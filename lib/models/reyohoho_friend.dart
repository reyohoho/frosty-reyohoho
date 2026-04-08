import 'package:json_annotation/json_annotation.dart';

part 'reyohoho_friend.g.dart';

String _stringId(Object? value) => value?.toString() ?? '';

DateTime? _dateTimeFromJson(Object? value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// A channel a friend is currently watching (RTE extension API).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ReyohohoFriendChannel {
  final String channelLogin;
  final String channelDisplayName;
  final String streamCategory;

  @JsonKey(fromJson: _dateTimeFromJson)
  final DateTime? lastActiveAt;

  const ReyohohoFriendChannel({
    required this.channelLogin,
    required this.channelDisplayName,
    required this.streamCategory,
    this.lastActiveAt,
  });

  factory ReyohohoFriendChannel.fromJson(Map<String, dynamic> json) =>
      _$ReyohohoFriendChannelFromJson(json);
}

/// Friend entry from `/api/ext/friends/{twitchUserId}`.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ReyohohoFriend {
  @JsonKey(fromJson: _stringId)
  final String twitchId;
  final String login;
  final String displayName;
  final String profileImageUrl;
  final List<ReyohohoFriendChannel> channels;
  final bool isOnline;

  const ReyohohoFriend({
    required this.twitchId,
    required this.login,
    required this.displayName,
    required this.profileImageUrl,
    required this.channels,
    required this.isOnline,
  });

  factory ReyohohoFriend.fromJson(Map<String, dynamic> json) => _$ReyohohoFriendFromJson(json);
}

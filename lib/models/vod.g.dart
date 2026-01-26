// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vod.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VideoTwitch _$VideoTwitchFromJson(Map<String, dynamic> json) => VideoTwitch(
  id: json['id'] as String,
  streamId: json['stream_id'] as String?,
  userId: json['user_id'] as String,
  userLogin: json['user_login'] as String,
  userName: json['user_name'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  createdAt: json['created_at'] as String,
  publishedAt: json['published_at'] as String,
  url: json['url'] as String,
  thumbnailUrl: json['thumbnail_url'] as String,
  viewable: json['viewable'] as String,
  viewCount: (json['view_count'] as num).toInt(),
  language: json['language'] as String,
  type: json['type'] as String,
  duration: json['duration'] as String,
  mutedSegments: (json['muted_segments'] as List<dynamic>?)
      ?.map((e) => MutedSegment.fromJson(e as Map<String, dynamic>))
      .toList(),
);

MutedSegment _$MutedSegmentFromJson(Map<String, dynamic> json) => MutedSegment(
  offset: (json['offset'] as num).toInt(),
  duration: (json['duration'] as num).toInt(),
);

VideosTwitch _$VideosTwitchFromJson(Map<String, dynamic> json) => VideosTwitch(
  (json['data'] as List<dynamic>)
      .map((e) => VideoTwitch.fromJson(e as Map<String, dynamic>))
      .toList(),
  (json['pagination'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
);

import 'package:json_annotation/json_annotation.dart';

part 'vod.g.dart';

/// Video types from Twitch API
enum VideoType {
  archive,
  highlight,
  upload,
}

/// Represents a Twitch VOD (Video on Demand)
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class VideoTwitch {
  final String id;
  final String? streamId;
  final String userId;
  final String userLogin;
  final String userName;
  final String title;
  final String? description;
  final String createdAt;
  final String publishedAt;
  final String url;
  final String thumbnailUrl;
  final String viewable;
  final int viewCount;
  final String language;
  final String type;
  final String duration;
  final List<MutedSegment>? mutedSegments;

  const VideoTwitch({
    required this.id,
    this.streamId,
    required this.userId,
    required this.userLogin,
    required this.userName,
    required this.title,
    this.description,
    required this.createdAt,
    required this.publishedAt,
    required this.url,
    required this.thumbnailUrl,
    required this.viewable,
    required this.viewCount,
    required this.language,
    required this.type,
    required this.duration,
    this.mutedSegments,
  });

  factory VideoTwitch.fromJson(Map<String, dynamic> json) =>
      _$VideoTwitchFromJson(json);

  /// Returns the video type as enum
  VideoType get videoType {
    switch (type) {
      case 'highlight':
        return VideoType.highlight;
      case 'upload':
        return VideoType.upload;
      case 'archive':
      default:
        return VideoType.archive;
    }
  }

  /// Returns duration in seconds parsed from format like "3h2m1s"
  int get durationInSeconds {
    final regex = RegExp(r'(\d+)h|(\d+)m|(\d+)s');
    final matches = regex.allMatches(duration);

    int totalSeconds = 0;
    for (final match in matches) {
      if (match.group(1) != null) {
        totalSeconds += int.parse(match.group(1)!) * 3600;
      } else if (match.group(2) != null) {
        totalSeconds += int.parse(match.group(2)!) * 60;
      } else if (match.group(3) != null) {
        totalSeconds += int.parse(match.group(3)!);
      }
    }
    return totalSeconds;
  }

  /// Returns formatted duration like "3:02:01" or "2:01"
  String get formattedDuration {
    final seconds = durationInSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  /// Returns the thumbnail URL with specified dimensions
  String getThumbnailUrl({int width = 320, int height = 180}) {
    return thumbnailUrl
        .replaceFirst('%{width}', width.toString())
        .replaceFirst('%{height}', height.toString());
  }
}

/// Represents a muted segment in a VOD
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class MutedSegment {
  final int offset;
  final int duration;

  const MutedSegment({
    required this.offset,
    required this.duration,
  });

  factory MutedSegment.fromJson(Map<String, dynamic> json) =>
      _$MutedSegmentFromJson(json);
}

/// Response wrapper for videos list with pagination
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class VideosTwitch {
  final List<VideoTwitch> data;
  final Map<String, String>? pagination;

  const VideosTwitch(this.data, this.pagination);

  factory VideosTwitch.fromJson(Map<String, dynamic> json) =>
      _$VideosTwitchFromJson(json);
}


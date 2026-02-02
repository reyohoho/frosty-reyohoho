/// Represents a VOD chat comment from Twitch GQL API
class VodComment {
  final String id;
  final VodCommenter commenter;
  final int contentOffsetSeconds;
  final String createdAt;
  final VodCommentMessage message;

  const VodComment({
    required this.id,
    required this.commenter,
    required this.contentOffsetSeconds,
    required this.createdAt,
    required this.message,
  });

  factory VodComment.fromJson(Map<String, dynamic> json) {
    return VodComment(
      id: json['id'] as String,
      commenter: VodCommenter.fromJson(json['commenter'] as Map<String, dynamic>),
      contentOffsetSeconds: json['contentOffsetSeconds'] as int,
      createdAt: json['createdAt'] as String,
      message: VodCommentMessage.fromJson(json['message'] as Map<String, dynamic>),
    );
  }
}

/// Commenter info for VOD comment
class VodCommenter {
  final String id;
  final String login;
  final String displayName;

  const VodCommenter({
    required this.id,
    required this.login,
    required this.displayName,
  });

  factory VodCommenter.fromJson(Map<String, dynamic> json) {
    return VodCommenter(
      id: json['id'] as String,
      login: json['login'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

/// Message content for VOD comment
class VodCommentMessage {
  final List<VodMessageFragment> fragments;
  final List<VodUserBadge> userBadges;
  final String? userColor;

  const VodCommentMessage({
    required this.fragments,
    required this.userBadges,
    this.userColor,
  });

  factory VodCommentMessage.fromJson(Map<String, dynamic> json) {
    final fragmentsList = json['fragments'] as List<dynamic>;
    final badgesList = json['userBadges'] as List<dynamic>;

    return VodCommentMessage(
      fragments: fragmentsList
          .map((f) => VodMessageFragment.fromJson(f as Map<String, dynamic>))
          .toList(),
      userBadges: badgesList
          .map((b) => VodUserBadge.fromJson(b as Map<String, dynamic>))
          .toList(),
      userColor: json['userColor'] as String?,
    );
  }

  /// Returns the full text of the message
  String get text => fragments.map((f) => f.text).join();
}

/// Message fragment (text or emote)
class VodMessageFragment {
  final String text;
  final VodEmote? emote;

  const VodMessageFragment({
    required this.text,
    this.emote,
  });

  factory VodMessageFragment.fromJson(Map<String, dynamic> json) {
    final emoteData = json['emote'];
    return VodMessageFragment(
      text: json['text'] as String,
      emote: emoteData != null
          ? VodEmote.fromJson(emoteData as Map<String, dynamic>)
          : null,
    );
  }
}

/// Emote in a message fragment
class VodEmote {
  final String id;
  final String emoteID;

  const VodEmote({
    required this.id,
    required this.emoteID,
  });

  factory VodEmote.fromJson(Map<String, dynamic> json) {
    return VodEmote(
      id: json['id'] as String,
      emoteID: json['emoteID'] as String,
    );
  }

  /// Returns URL for the emote image
  String get url => 'https://static-cdn.jtvnw.net/emoticons/v2/$emoteID/default/dark/1.0';
  String get url2x => 'https://static-cdn.jtvnw.net/emoticons/v2/$emoteID/default/dark/2.0';
  String get url3x => 'https://static-cdn.jtvnw.net/emoticons/v2/$emoteID/default/dark/3.0';
}

/// User badge in VOD comment
class VodUserBadge {
  final String id;
  final String setID;
  final String version;

  const VodUserBadge({
    required this.id,
    required this.setID,
    required this.version,
  });

  factory VodUserBadge.fromJson(Map<String, dynamic> json) {
    return VodUserBadge(
      id: json['id'] as String,
      setID: json['setID'] as String,
      version: json['version'] as String,
    );
  }
}

/// Response wrapper for VOD comments
class VodCommentsResponse {
  final List<VodComment> comments;
  final bool hasNextPage;
  final bool hasPreviousPage;

  /// Cursor for fetching the next page (when [hasNextPage] is true).
  final String? cursor;

  const VodCommentsResponse({
    required this.comments,
    required this.hasNextPage,
    required this.hasPreviousPage,
    this.cursor,
  });

  factory VodCommentsResponse.fromJson(Map<String, dynamic> json) {
    final video = json['data']?['video'];
    if (video == null) {
      return const VodCommentsResponse(
        comments: [],
        hasNextPage: false,
        hasPreviousPage: false,
      );
    }

    final commentsData = video['comments'];
    if (commentsData == null) {
      return const VodCommentsResponse(
        comments: [],
        hasNextPage: false,
        hasPreviousPage: false,
      );
    }

    final edges = commentsData['edges'] as List<dynamic>;
    final pageInfo = commentsData['pageInfo'] as Map<String, dynamic>;

    return VodCommentsResponse(
      comments: edges
          .map((e) => VodComment.fromJson(e['node'] as Map<String, dynamic>))
          .toList(),
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
      hasPreviousPage: pageInfo['hasPreviousPage'] as bool? ?? false,
      cursor: pageInfo['endCursor'] as String?,
    );
  }
}


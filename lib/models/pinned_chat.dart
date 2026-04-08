/// Fragment of a pinned message (text or Twitch emote).
class PinnedMessageFragment {
  final String text;
  final String? emoteId;

  const PinnedMessageFragment({required this.text, this.emoteId});

  factory PinnedMessageFragment.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>?;
    return PinnedMessageFragment(
      text: json['text'] as String,
      emoteId: content?['emoteID'] as String?,
    );
  }
}

/// Badge attached to the pinned message sender.
class PinnedMessageBadge {
  final String setId;
  final String version;

  const PinnedMessageBadge({required this.setId, required this.version});

  factory PinnedMessageBadge.fromJson(Map<String, dynamic> json) {
    return PinnedMessageBadge(
      setId: json['setID'] as String,
      version: json['version'] as String,
    );
  }
}

/// Sender of the pinned message.
class PinnedMessageSender {
  final String id;
  final String displayName;
  final String? chatColor;
  final List<PinnedMessageBadge> badges;

  const PinnedMessageSender({
    required this.id,
    required this.displayName,
    this.chatColor,
    required this.badges,
  });

  factory PinnedMessageSender.fromJson(Map<String, dynamic> json) {
    final badgesList = json['displayBadges'] as List<dynamic>? ?? [];
    return PinnedMessageSender(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      chatColor: json['chatColor'] as String?,
      badges: badgesList.map((b) => PinnedMessageBadge.fromJson(b as Map<String, dynamic>)).toList(),
    );
  }
}

/// Pinned chat message from Twitch GQL API.
class PinnedChatMessage {
  final String id;
  final String fullText;
  final List<PinnedMessageFragment> fragments;
  final DateTime sentAt;
  final PinnedMessageSender sender;
  final DateTime startsAt;
  final DateTime updatedAt;
  final DateTime? endsAt;
  final String pinnedByDisplayName;

  const PinnedChatMessage({
    required this.id,
    required this.fullText,
    required this.fragments,
    required this.sentAt,
    required this.sender,
    required this.startsAt,
    required this.updatedAt,
    this.endsAt,
    required this.pinnedByDisplayName,
  });

  bool get hasExpired => endsAt != null && DateTime.now().isAfter(endsAt!);

  /// Parses the first GetPinnedChat response from the GQL batch.
  /// Returns null when no pinned message exists.
  static PinnedChatMessage? fromGqlResponse(List<dynamic> response) {
    if (response.isEmpty) return null;

    final data = response[0] as Map<String, dynamic>;
    final channel = data['data']?['channel'] as Map<String, dynamic>?;
    if (channel == null) return null;

    final connection = channel['pinnedChatMessages'] as Map<String, dynamic>?;
    if (connection == null) return null;

    final edges = connection['edges'] as List<dynamic>?;
    if (edges == null || edges.isEmpty) return null;

    final node = (edges[0] as Map<String, dynamic>)['node'] as Map<String, dynamic>;
    final pinnedMessage = node['pinnedMessage'] as Map<String, dynamic>;
    final content = pinnedMessage['content'] as Map<String, dynamic>;
    final fragmentsList = content['fragments'] as List<dynamic>;
    final senderJson = pinnedMessage['sender'] as Map<String, dynamic>;
    final pinnedBy = node['pinnedBy'] as Map<String, dynamic>;

    return PinnedChatMessage(
      id: node['id'] as String,
      fullText: content['text'] as String,
      fragments: fragmentsList.map((f) => PinnedMessageFragment.fromJson(f as Map<String, dynamic>)).toList(),
      sentAt: DateTime.parse(pinnedMessage['sentAt'] as String),
      sender: PinnedMessageSender.fromJson(senderJson),
      startsAt: DateTime.parse(node['startsAt'] as String),
      updatedAt: DateTime.parse(node['updatedAt'] as String),
      endsAt: node['endsAt'] != null ? DateTime.parse(node['endsAt'] as String) : null,
      pinnedByDisplayName: pinnedBy['displayName'] as String,
    );
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/models/badges.dart';

/// Starege API domains in priority order.
const _staregeDomains = [
  'https://starege.rte.net.ru',
  'https://starege3.rte.net.ru',
  'https://starege5.rte.net.ru',
  'https://starege4.rte.net.ru',
];

/// The Reyohoho service for making API calls (badges and paints).
class ReyohohoApi extends BaseApiClient {
  String? _workingDomain;
  Future<String?>? _initFuture;
  bool _isInitialized = false;

  ReyohohoApi(Dio dio) : super(dio, '');

  /// Initializes and finds a working starege domain.
  Future<String?> _initializeDomain({bool force = false}) async {
    if (_isInitialized && !force && _workingDomain != null) {
      return _workingDomain;
    }

    if (_initFuture != null && !force) {
      return _initFuture;
    }

    if (force) {
      _isInitialized = false;
      _workingDomain = null;
    }

    _initFuture = _findWorkingDomain();
    _workingDomain = await _initFuture;
    _isInitialized = true;
    _initFuture = null;

    return _workingDomain;
  }

  Future<String?> _findWorkingDomain() async {
    for (final domain in _staregeDomains) {
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
          debugPrint('ReyohohoApi: Using Starege domain: $domain');
          return domain;
        }
      } catch (e) {
        // Try next domain
      }
    }

    debugPrint('ReyohohoApi: All Starege domains are unavailable');
    return null;
  }

  /// Gets the API URL for a given path.
  Future<String?> _getApiUrl(String path) async {
    final domain = await _initializeDomain();
    if (domain == null) return null;

    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$domain$cleanPath';
  }

  /// Returns a map of user IDs to their Reyohoho badges.
  /// Uses on-demand loading per user.
  Future<ChatBadge?> getUserBadge(String userId) async {
    final apiUrl = await _getApiUrl('/api/badge-users/$userId');
    if (apiUrl == null) return null;

    try {
      final response = await get<JsonMap?>(apiUrl);
      if (response == null) return null;

      final badgeUrl = response['badgeUrl'] as String?;
      if (badgeUrl == null) return null;

      return ChatBadge(
        name: 'ReYohoho Badge',
        url: badgeUrl,
        type: BadgeType.reyohoho,
      );
    } on NotFoundException {
      // User has no badge
      return null;
    } catch (e) {
      debugPrint('ReyohohoApi: Failed to fetch badge for user $userId: $e');
      return null;
    }
  }

  /// Gets a user's paint data.
  /// Returns paint info if user has a custom paint, null otherwise.
  Future<UserPaint?> getUserPaint(String userId) async {
    // First check if user has a custom paint in our backend
    final paintApiUrl = await _getApiUrl('/api/paint/$userId');
    if (paintApiUrl == null) return null;

    try {
      final response = await get<JsonMap>(paintApiUrl);
      final hasPaint = response['has_paint'] as bool? ?? false;

      if (hasPaint) {
        final paintId = response['paint_id'] as String?;
        if (paintId != null) {
          // Fetch the paint details
          final paintData = await _fetchPaintById(paintId);
          if (paintData != null) {
            return UserPaint(
              paintId: paintId,
              paint: paintData,
              source: PaintSource.reyohoho,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('ReyohohoApi: Error getting user paint: $e');
    }

    // Fall back to 7TV API
    return _fetch7TVUserPaint(userId);
  }

  /// Fetches paint by ID from our backend cache.
  Future<PaintData?> _fetchPaintById(String paintId) async {
    final apiUrl = await _getApiUrl('/api/paints/$paintId');
    if (apiUrl == null) return null;

    try {
      final response = await get<JsonMap>(apiUrl);
      return PaintData.fromJson(response);
    } catch (e) {
      debugPrint('ReyohohoApi: Failed to fetch paint $paintId: $e');
      return null;
    }
  }

  /// Fetches paint from 7TV API for a user.
  Future<UserPaint?> _fetch7TVUserPaint(String userId) async {
    const seventvGqlEndpoint = 'https://7tv.io/v3/gql';

    const query = '''
      query GetUserPaint(\$id: String!) {
        userByConnection(id: \$id, platform: TWITCH) {
          style {
            paint {
              id
              name
              color
              function
              angle
              shape
              image_url
              repeat
              stops {
                at
                color
              }
              shadows {
                x_offset
                y_offset
                radius
                color
              }
            }
          }
        }
      }
    ''';

    try {
      // Use the working domain as proxy
      final domain = await _initializeDomain();
      final proxyUrl = domain != null ? '$domain/' : '';

      final response = await post<JsonMap>(
        '$proxyUrl$seventvGqlEndpoint',
        data: {
          'operationName': 'GetUserPaint',
          'variables': {'id': userId},
          'query': query,
        },
      );

      final paintJson =
          response['data']?['userByConnection']?['style']?['paint'] as JsonMap?;
      if (paintJson == null) return null;

      return UserPaint(
        paintId: paintJson['id'] as String,
        paint: PaintData.fromJson(paintJson),
        source: PaintSource.sevenTV,
      );
    } catch (e) {
      debugPrint('ReyohohoApi: Failed to fetch 7TV paint for user $userId: $e');
      return null;
    }
  }
}

/// Source of the paint (7TV or Reyohoho).
enum PaintSource {
  sevenTV,
  reyohoho,
}

/// User paint assignment data.
class UserPaint {
  final String paintId;
  final PaintData paint;
  final PaintSource source;

  const UserPaint({
    required this.paintId,
    required this.paint,
    required this.source,
  });

  String get sourceName =>
      source == PaintSource.reyohoho ? 'RTE Custom Paint' : '7TV Paint';
}

/// Paint data with gradient/styling information.
class PaintData {
  final String id;
  final String name;
  final int? color;
  final String? function; // LINEAR_GRADIENT, RADIAL_GRADIENT, URL
  final int? angle;
  final String? shape;
  final String? imageUrl;
  final bool repeat;
  final List<PaintStop> stops;
  final List<PaintShadow> shadows;

  const PaintData({
    required this.id,
    required this.name,
    this.color,
    this.function,
    this.angle,
    this.shape,
    this.imageUrl,
    this.repeat = false,
    this.stops = const [],
    this.shadows = const [],
  });

  factory PaintData.fromJson(JsonMap json) {
    return PaintData(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as int?,
      function: json['function'] as String?,
      angle: json['angle'] as int?,
      shape: json['shape'] as String?,
      imageUrl: json['image_url'] as String?,
      repeat: json['repeat'] as bool? ?? false,
      stops:
          (json['stops'] as List<dynamic>?)
              ?.map((s) => PaintStop.fromJson(s as JsonMap))
              .toList() ??
          [],
      shadows:
          (json['shadows'] as List<dynamic>?)
              ?.map((s) => PaintShadow.fromJson(s as JsonMap))
              .toList() ??
          [],
    );
  }
}

/// Gradient stop.
class PaintStop {
  final double at;
  final int color;

  const PaintStop({required this.at, required this.color});

  factory PaintStop.fromJson(JsonMap json) {
    return PaintStop(
      at: (json['at'] as num).toDouble(),
      color: json['color'] as int,
    );
  }
}

/// Paint shadow.
class PaintShadow {
  final double xOffset;
  final double yOffset;
  final double radius;
  final int color;

  const PaintShadow({
    required this.xOffset,
    required this.yOffset,
    required this.radius,
    required this.color,
  });

  factory PaintShadow.fromJson(JsonMap json) {
    return PaintShadow(
      xOffset: (json['x_offset'] as num).toDouble(),
      yOffset: (json['y_offset'] as num).toDouble(),
      radius: (json['radius'] as num).toDouble(),
      color: json['color'] as int,
    );
  }
}



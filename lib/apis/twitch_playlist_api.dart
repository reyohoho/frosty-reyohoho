import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frosty/constants.dart' as frosty_const;

/// A single HLS variant parsed from a Twitch Usher master playlist.
@immutable
class TwitchHlsVariant {
  /// Human readable name taken from `#EXT-X-MEDIA:NAME`, e.g. `720p60` or `Source`.
  final String name;

  /// Programmatic group id, e.g. `chunked`, `720p60`, `audio_only`.
  final String groupId;

  /// Resolution if advertised. Audio-only variants have null dimensions.
  final int? width;
  final int? height;

  /// Peak bandwidth from `#EXT-X-STREAM-INF:BANDWIDTH=...`.
  final int? bandwidth;

  /// Frame rate if advertised.
  final double? frameRate;

  /// Codecs declared on the stream-inf tag.
  final String? codecs;

  /// Absolute media-playlist URI for this variant.
  final String uri;

  /// `true` if this is the `audio_only` track.
  final bool audioOnly;

  const TwitchHlsVariant({
    required this.name,
    required this.groupId,
    required this.uri,
    required this.audioOnly,
    this.width,
    this.height,
    this.bandwidth,
    this.frameRate,
    this.codecs,
  });

  /// Display label matching Twitch's own UI: `1080p60`, `720p`, `Audio Only`.
  String get displayLabel {
    if (audioOnly) return 'Audio Only';
    if (name.isNotEmpty && name.toLowerCase() != 'source') return name;
    if (height != null) {
      final fps = (frameRate != null && frameRate! >= 50) ? '60' : '';
      return '${height}p$fps${name.toLowerCase() == 'source' ? ' (Source)' : ''}';
    }
    return name.isEmpty ? groupId : name;
  }

  @override
  String toString() => 'TwitchHlsVariant($displayLabel, ${width}x$height, $bandwidth)';
}

/// Thin client that produces the Usher `m3u8` URL for a Twitch live stream
/// and parses the master playlist into a list of selectable HLS variants.
///
/// This is the minimal server-side component needed to play Twitch live
/// streams natively without embedding the Twitch web player. It mirrors the
/// approach used by Xtra / Streamlink / twitch-cli.
class TwitchPlaylistApi {
  TwitchPlaylistApi({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Public Twitch web Client-ID baked into twitch.tv. This is the same value
  /// used by the official website and is required for the anonymous GQL
  /// PlaybackAccessToken query to succeed.
  static const String _webClientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

  /// Persisted query hash for `PlaybackAccessToken`. Stable for years; if
  /// Twitch ever rotates it, update this constant.
  static const String _playbackAccessTokenHash =
      'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9';

  static const String _gqlUrl = 'https://gql.twitch.tv/gql';
  static const String _usherChannelBase = 'https://usher.ttvnw.net/api/v2/channel/hls';

  /// Default codec preference list sent to Usher. Matches what the web player
  /// sends and keeps AV1/HEVC available if the device supports them.
  static const String defaultSupportedCodecs = 'av1,h265,h264';

  /// Fetches the playback access token/signature pair required by Usher.
  ///
  /// When [userAuthToken] is provided, we make an authenticated request using
  /// Frosty's own registered Client-ID (since the user token was issued for
  /// that client). If [userAuthToken] is null we fall back to an anonymous
  /// request using Twitch's public web Client-ID, which works for all public
  /// streams.
  ///
  /// On any auth-level failure (401/403) we transparently retry anonymously so
  /// that a stale / wrong-scope user token does not break playback.
  Future<({String token, String signature})> fetchStreamAccessToken({
    required String channelLogin,
    String? userAuthToken,
    String playerType = 'site',
  }) async {
    if (userAuthToken != null && userAuthToken.isNotEmpty) {
      try {
        return await _fetchAccessTokenWith(
          channelLogin: channelLogin,
          playerType: playerType,
          clientId: frosty_const.clientId,
          authorization: 'Bearer $userAuthToken',
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        // Any authentication-ish failure → retry anonymously. We also retry on
        // 400 because Twitch occasionally returns that when client-id ≠ token.
        if (status == 401 || status == 403 || status == 400) {
          debugPrint(
            '[TwitchPlaylistApi] authed PlaybackAccessToken returned $status, '
            'falling back to anonymous request',
          );
        } else {
          rethrow;
        }
      }
    }

    return _fetchAccessTokenWith(
      channelLogin: channelLogin,
      playerType: playerType,
      clientId: _webClientId,
      authorization: null,
    );
  }

  Future<({String token, String signature})> _fetchAccessTokenWith({
    required String channelLogin,
    required String playerType,
    required String clientId,
    required String? authorization,
  }) async {
    final body = {
      'operationName': 'PlaybackAccessToken',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash': _playbackAccessTokenHash,
        },
      },
      'variables': {
        'isLive': true,
        'login': channelLogin,
        'isVod': false,
        'vodID': '',
        'platform': 'web',
        'playerType': playerType,
      },
    };

    final headers = <String, String>{
      'Client-ID': clientId,
      'Content-Type': 'application/json',
    };
    if (authorization != null && authorization.isNotEmpty) {
      headers['Authorization'] = authorization;
    }

    final response = await _dio.post<dynamic>(
      _gqlUrl,
      data: body,
      options: Options(headers: headers, responseType: ResponseType.json),
    );

    final raw = response.data;
    final Map<String, dynamic> payload;
    if (raw is Map<String, dynamic>) {
      payload = raw;
    } else if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
      payload = raw.first as Map<String, dynamic>;
    } else if (raw is String) {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } else {
      throw Exception('Unexpected PlaybackAccessToken response: $raw');
    }

    final access = (payload['data'] as Map<String, dynamic>?)?['streamPlaybackAccessToken']
        as Map<String, dynamic>?;
    if (access == null) {
      throw Exception('PlaybackAccessToken missing: $payload');
    }
    final token = access['value'];
    final signature = access['signature'];
    if (token is! String || signature is! String || token.isEmpty || signature.isEmpty) {
      throw Exception('PlaybackAccessToken malformed: $access');
    }
    return (token: token, signature: signature);
  }

  /// Builds the full Usher HLS URL for a live channel using a previously
  /// fetched [token] / [signature] pair.
  ///
  /// [proxyBaseUrl] optionally proxies the final Usher request by prepending
  /// the user-provided proxy (e.g. `https://proxy1.rte.net.ru`). The convention
  /// used by the existing Reyohoho proxy is `{proxy}/{full_usher_url}`.
  String buildStreamUsherUrl({
    required String channelLogin,
    required String token,
    required String signature,
    String supportedCodecs = defaultSupportedCodecs,
    String? proxyBaseUrl,
  }) {
    final p = math.Random().nextInt(9999999);
    final uri = Uri.parse('$_usherChannelBase/${Uri.encodeComponent(channelLogin)}.m3u8').replace(
      queryParameters: {
        'allow_source': 'true',
        'allow_audio_only': 'true',
        'fast_bread': 'true', // low latency HLS
        'p': '$p',
        'platform': 'web',
        'player_backend': 'mediaplayer',
        'playlist_include_framerate': 'true',
        'reassignments_supported': 'true',
        'sig': signature,
        'supported_codecs': supportedCodecs,
        'token': token,
        'cdm': 'wv',
        'player_version': '1.29.0',
      },
    );
    final full = uri.toString();
    if (proxyBaseUrl == null || proxyBaseUrl.isEmpty) return full;
    final trimmed = proxyBaseUrl.endsWith('/')
        ? proxyBaseUrl.substring(0, proxyBaseUrl.length - 1)
        : proxyBaseUrl;
    return '$trimmed/$full';
  }

  /// Convenience wrapper: fetches the access token, then returns the full
  /// Usher URL ready to be passed to the native ExoPlayer.
  Future<String> resolveStreamPlaylistUrl({
    required String channelLogin,
    String? userAuthToken,
    String playerType = 'site',
    String supportedCodecs = defaultSupportedCodecs,
    String? proxyBaseUrl,
  }) async {
    final access = await fetchStreamAccessToken(
      channelLogin: channelLogin,
      userAuthToken: userAuthToken,
      playerType: playerType,
    );
    return buildStreamUsherUrl(
      channelLogin: channelLogin,
      token: access.token,
      signature: access.signature,
      supportedCodecs: supportedCodecs,
      proxyBaseUrl: proxyBaseUrl,
    );
  }

  /// Downloads the Usher master playlist and parses its `#EXT-X-MEDIA` /
  /// `#EXT-X-STREAM-INF` pairs into a user-facing list of variants.
  ///
  /// The variants are ordered source/best first, then descending by height,
  /// with the optional `audio_only` track last.
  Future<List<TwitchHlsVariant>> fetchVariants({
    required String masterPlaylistUrl,
    String? proxyBaseUrl,
  }) async {
    final trimmedProxy = proxyBaseUrl != null && proxyBaseUrl.isNotEmpty
        ? (proxyBaseUrl.endsWith('/')
              ? proxyBaseUrl.substring(0, proxyBaseUrl.length - 1)
              : proxyBaseUrl)
        : null;
    // If the caller passed a raw usher URL plus a proxy, combine them the same
    // way buildStreamUsherUrl does.
    final effectiveUrl = () {
      if (trimmedProxy == null) return masterPlaylistUrl;
      if (masterPlaylistUrl.startsWith(trimmedProxy)) return masterPlaylistUrl;
      return '$trimmedProxy/$masterPlaylistUrl';
    }();

    final resp = await _dio.get<String>(
      effectiveUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Origin': 'https://player.twitch.tv',
          'Referer': 'https://player.twitch.tv/',
          'Accept': 'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
        },
      ),
    );
    final body = resp.data ?? '';
    return parseMasterPlaylist(body);
  }

  /// Parses a Twitch Usher master `m3u8` body into a list of [TwitchHlsVariant].
  @visibleForTesting
  static List<TwitchHlsVariant> parseMasterPlaylist(String body) {
    final lines = const LineSplitter().convert(body);
    final mediaByGroup = <String, _MediaRecord>{};
    final variants = <TwitchHlsVariant>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final attrs = _parseAttrs(line.substring('#EXT-X-MEDIA:'.length));
        final type = attrs['TYPE'] ?? '';
        if (type != 'VIDEO' && type != 'AUDIO') continue;
        final groupId = attrs['GROUP-ID'] ?? '';
        if (groupId.isEmpty) continue;
        mediaByGroup[groupId] = _MediaRecord(
          type: type,
          name: attrs['NAME'] ?? groupId,
        );
      } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final attrs = _parseAttrs(line.substring('#EXT-X-STREAM-INF:'.length));
        // The next non-comment line is the URI for this variant.
        String? uri;
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty || next.startsWith('#')) continue;
          uri = next;
          break;
        }
        if (uri == null) continue;

        final videoGroup = attrs['VIDEO'] ?? '';
        final audioGroup = attrs['AUDIO'] ?? '';
        final media = mediaByGroup[videoGroup] ?? mediaByGroup[audioGroup];
        final groupId = videoGroup.isNotEmpty ? videoGroup : audioGroup;
        final name = media?.name ?? groupId;
        final resolution = attrs['RESOLUTION'];
        int? w;
        int? h;
        if (resolution != null) {
          final parts = resolution.split('x');
          if (parts.length == 2) {
            w = int.tryParse(parts[0]);
            h = int.tryParse(parts[1]);
          }
        }
        variants.add(
          TwitchHlsVariant(
            name: name,
            groupId: groupId,
            uri: uri,
            audioOnly: groupId == 'audio_only' || (w == null && h == null),
            width: w,
            height: h,
            bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? ''),
            frameRate: double.tryParse(attrs['FRAME-RATE'] ?? ''),
            codecs: attrs['CODECS'],
          ),
        );
      }
    }

    variants.sort((a, b) {
      if (a.audioOnly != b.audioOnly) return a.audioOnly ? 1 : -1;
      final ha = a.height ?? 0;
      final hb = b.height ?? 0;
      if (ha != hb) return hb.compareTo(ha);
      final ba = a.bandwidth ?? 0;
      final bb = b.bandwidth ?? 0;
      return bb.compareTo(ba);
    });
    return variants;
  }

  /// Parses the attribute list of an `#EXT-X-*` tag into a map.
  static Map<String, String> _parseAttrs(String src) {
    final result = <String, String>{};
    final re = RegExp(r'([A-Z0-9\-]+)=("([^"]*)"|([^,]*))');
    for (final m in re.allMatches(src)) {
      final key = m.group(1)!;
      final value = m.group(3) ?? m.group(4) ?? '';
      result[key] = value;
    }
    return result;
  }
}

class _MediaRecord {
  final String type;
  final String name;
  const _MediaRecord({required this.type, required this.name});
}

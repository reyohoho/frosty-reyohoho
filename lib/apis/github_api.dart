import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frosty/apis/base_api_client.dart';

class GitHubRelease {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool prerelease;
  final bool draft;
  final String? apkDownloadUrl;
  final DateTime? publishedAt;

  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.draft,
    this.publishedAt,
    this.apkDownloadUrl,
  });

  factory GitHubRelease.fromJson(JsonMap json) {
    String? apkUrl;
    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    final publishedAtStr = json['published_at'] as String?;

    return GitHubRelease(
      tagName: json['tag_name'] as String,
      name: (json['name'] as String?) ?? json['tag_name'] as String,
      body: (json['body'] as String?) ?? '',
      htmlUrl: json['html_url'] as String,
      prerelease: json['prerelease'] as bool? ?? false,
      draft: json['draft'] as bool? ?? false,
      publishedAt: publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null,
      apkDownloadUrl: apkUrl,
    );
  }
}

class GitHubApi extends BaseApiClient {
  static const _repo = 'reyohoho/frosty-reyohoho';

  GitHubApi(Dio dio) : super(dio, 'https://api.github.com');

  /// Returns the latest stable release as reported by GitHub's
  /// `/releases/latest` endpoint (excludes drafts and prereleases by design).
  /// We intentionally do not fall back to the full releases list so that
  /// prereleases never trigger an update prompt.
  Future<GitHubRelease?> getLatestRelease() async {
    try {
      final data = await get<JsonMap>('/repos/$_repo/releases/latest');
      return GitHubRelease.fromJson(data);
    } catch (e) {
      debugPrint('GitHubApi: Failed to fetch latest release: $e');
      return null;
    }
  }

  Future<List<GitHubRelease>> getReleases({int perPage = 20}) async {
    try {
      final data = await get<JsonList>(
        '/repos/$_repo/releases',
        queryParameters: {'per_page': perPage},
      );
      return data
          .map((e) => GitHubRelease.fromJson(e as JsonMap))
          .toList();
    } catch (e) {
      debugPrint('GitHubApi: Failed to fetch releases: $e');
      return [];
    }
  }
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// A [FileService] implementation that uses Dio instead of the default `http`
/// package. This ensures proxy URLs with embedded `://` in the path are sent
/// without re-encoding — matching how our API requests are sent.
class DioFileService extends FileService {
  final Dio _dio;
  CancelToken _cancelToken = CancelToken();

  DioFileService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 15),
            followRedirects: true,
            maxRedirects: 5,
          ),
        );

  /// Cancels all in-flight image downloads and prepares a fresh token
  /// for subsequent requests.
  void cancelPendingRequests() {
    _cancelToken.cancel('Proxy settings changed');
    _cancelToken = CancelToken();
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: _cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );
      if (kDebugMode) {
        debugPrint(
          'DioFileService: ${response.statusCode} $url',
        );
      }
      return _DioFileServiceResponse(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DioFileService ERROR: $e for $url');
      }
      rethrow;
    }
  }
}

class _DioFileServiceResponse implements FileServiceResponse {
  final Response<ResponseBody> _response;

  _DioFileServiceResponse(this._response);

  @override
  Stream<List<int>> get content =>
      _response.data?.stream ?? const Stream.empty();

  @override
  int? get contentLength {
    final values = _response.headers[Headers.contentLengthHeader];
    final header = values != null && values.isNotEmpty ? values.first : null;
    return header != null ? int.tryParse(header) : null;
  }

  @override
  String? get eTag {
    final values = _response.headers['etag'];
    return values != null && values.isNotEmpty ? values.first : null;
  }

  @override
  String get fileExtension {
    final values = _response.headers[Headers.contentTypeHeader];
    final contentType = values != null && values.isNotEmpty
        ? values.first
        : null;
    if (contentType != null) {
      if (contentType.contains('webp')) return '.webp';
      if (contentType.contains('gif')) return '.gif';
      if (contentType.contains('png')) return '.png';
      if (contentType.contains('svg')) return '.svg';
      if (contentType.contains('jpeg') || contentType.contains('jpg')) {
        return '.jpg';
      }
    }

    final path = _response.realUri.path;
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < path.length - 1) {
      final ext = path.substring(dotIndex);
      if (ext.length <= 6) return ext;
    }
    return '';
  }

  @override
  int get statusCode => _response.statusCode ?? 500;

  @override
  DateTime get validTill {
    final ccValues = _response.headers['cache-control'];
    final cacheControl = ccValues != null && ccValues.isNotEmpty
        ? ccValues.join(', ')
        : null;
    if (cacheControl != null) {
      final maxAgeMatch = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
      if (maxAgeMatch != null) {
        final maxAge = int.tryParse(maxAgeMatch.group(1)!);
        if (maxAge != null) {
          return DateTime.now().add(Duration(seconds: maxAge));
        }
      }
    }
    return DateTime.now().add(const Duration(days: 7));
  }
}

class CustomCacheManager {
  static const key = 'libCachedImageData';
  static final _repo = CacheObjectProvider(databaseName: key);
  static final _fileService = DioFileService();
  static final instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 10000,
      repo: _repo,
      fileService: _fileService,
    ),
  );

  /// Set to true by the proxy-toggle reaction in main.dart so that the
  /// next channel open can flush stale entries. Reset to false after flush.
  static bool needsCacheFlush = false;

  /// Cancels all in-flight image downloads (e.g. when proxy settings change).
  static void cancelPendingDownloads() {
    _fileService.cancelPendingRequests();
  }

  static Future<void> removeOrphanedCacheFiles() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/$key');

    if (!await cacheDir.exists()) {
      return;
    }

    final allFiles = cacheDir.listSync(recursive: true).toList();

    await _repo.open();
    final cachedObjects = await _repo.getAllObjects();
    final dbFiles = cachedObjects.map((e) => e.relativePath).toSet();

    final orphanedFiles = allFiles.where((file) {
      final relativePath = file.path.split('$key/').last;
      return !dbFiles.contains(relativePath);
    }).toList();

    final deletions = orphanedFiles.map((file) => file.delete()).toList();

    try {
      await Future.wait(deletions);
      // ignore: empty_catches
    } catch (e) {}
  }
}

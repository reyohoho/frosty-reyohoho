import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Common type aliases to reduce repetition
typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<dynamic>;
typedef QueryParams = Map<String, dynamic>;
typedef ApiHeaders = Map<String, String>;

/// Custom API exceptions for better error handling
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final DioExceptionType? type;

  const ApiException(this.message, [this.statusCode, this.type]);

  @override
  String toString() => 'ApiException: $message';
}

class NetworkException extends ApiException {
  const NetworkException(String message)
    : super(message, null, DioExceptionType.connectionError);
}

class TimeoutException extends ApiException {
  const TimeoutException(String message)
    : super(message, null, DioExceptionType.connectionTimeout);
}

class ServerException extends ApiException {
  const ServerException(String message, int statusCode)
    : super(message, statusCode, DioExceptionType.badResponse);
}

class NotFoundException extends ApiException {
  const NotFoundException(String message)
    : super(message, 404, DioExceptionType.badResponse);
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException(String message)
    : super(message, 401, DioExceptionType.badResponse);
}

/// Base API client to eliminate code duplication across API services
abstract class BaseApiClient {
  final Dio _dio;
  final String baseUrl;

  /// Optional proxy URL prefix for routing requests through a proxy server.
  /// When set, all requests will be prefixed with this URL.
  String? proxyUrlPrefix;

  BaseApiClient(this._dio, this.baseUrl);

  /// Protected accessor for Dio instance for subclasses that need direct access
  @protected
  Dio get dio => _dio;

  /// Builds the full URL, handling both relative endpoints and full URLs.
  /// Applies proxy prefix if set and adds cache-busting timestamp when proxied.
  String _buildUrl(String endpoint) {
    String url;
    // If endpoint is already a full URL (starts with http:// or https://), use it as-is
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      url = endpoint;
    } else {
      // Otherwise, concatenate with base URL
      url = '$baseUrl$endpoint';
    }

    // Apply proxy prefix if set
    if (proxyUrlPrefix != null && proxyUrlPrefix!.isNotEmpty) {
      // Add cache-busting timestamp to bypass proxy cache
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final separator = url.contains('?') ? '&' : '?';
      final urlWithTimestamp = '$url${separator}_t=$timestamp';
      return '$proxyUrlPrefix/$urlWithTimestamp';
    }

    return url;
  }

  /// Generic GET request with common error handling
  Future<T> get<T>(
    String endpoint, {
    QueryParams? queryParameters,
    ApiHeaders? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final url = _buildUrl(endpoint);
      final response = await _dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Generic POST request with common error handling
  Future<T> post<T>(
    String endpoint, {
    dynamic data,
    QueryParams? queryParameters,
    ApiHeaders? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final url = _buildUrl(endpoint);
      final response = await _dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Generic PUT request with common error handling
  Future<T> put<T>(
    String endpoint, {
    dynamic data,
    QueryParams? queryParameters,
    ApiHeaders? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final url = _buildUrl(endpoint);
      final response = await _dio.put(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Generic DELETE request with common error handling
  Future<T> delete<T>(
    String endpoint, {
    QueryParams? queryParameters,
    ApiHeaders? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final url = _buildUrl(endpoint);
      final response = await _dio.delete(
        url,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Check if response indicates success (useful for status-only operations)
  bool isSuccessResponse(Response response) {
    return response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300;
  }

  /// Converts DioException to appropriate ApiException subtype
  ApiException _handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException(_getTimeoutMessage(error.type));

      case DioExceptionType.connectionError:
        return NetworkException(
          'No internet connection. Please check your network.',
        );

      case DioExceptionType.badResponse:
        return _handleHttpError(error);

      case DioExceptionType.cancel:
        return ApiException('Request was cancelled');

      case DioExceptionType.badCertificate:
        return ApiException('Security certificate error');

      case DioExceptionType.unknown:
        return ApiException(error.message ?? 'An unexpected error occurred');
    }
  }

  /// Gets specific timeout message based on timeout type
  String _getTimeoutMessage(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Please try again.';
      case DioExceptionType.sendTimeout:
        return 'Upload timeout. Please try again.';
      case DioExceptionType.receiveTimeout:
        return 'Server response timeout. Please try again.';
      default:
        return 'Request timeout. Please try again.';
    }
  }

  /// Handles HTTP status code errors with specific exception types
  ApiException _handleHttpError(DioException error) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;

    // Extract error message from server response
    String? serverMessage;
    if (responseData is JsonMap) {
      serverMessage =
          responseData['message'] as String? ??
          responseData['error'] as String? ??
          responseData['error_description'] as String?;
    }

    switch (statusCode) {
      case 400:
        return ApiException(serverMessage ?? 'Invalid request data');
      case 401:
        return UnauthorizedException('Please log in to continue');
      case 403:
        return ApiException('Access denied. Insufficient permissions');
      case 404:
        return NotFoundException(serverMessage ?? 'Resource not found');
      case 409:
        return ApiException('Conflict with current state. Please refresh');
      case 422:
        return ApiException(serverMessage ?? 'Invalid data provided');
      case 429:
        return ApiException(
          'Rate limit exceeded. Please wait before trying again',
        );
      case 500:
        return ServerException('Server error. Please try again later', 500);
      case 502:
        return ServerException('Service temporarily unavailable', 502);
      case 503:
        return ServerException(
          'Service maintenance. Please try again later',
          503,
        );
      case 504:
        return ServerException('Server timeout. Please try again', 504);
      default:
        return ServerException(
          serverMessage ?? 'HTTP Error $statusCode occurred',
          statusCode ?? 500,
        );
    }
  }
}

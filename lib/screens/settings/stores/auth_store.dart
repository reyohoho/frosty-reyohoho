import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/screens/settings/stores/user_store.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:mobx/mobx.dart';
import 'package:url_launcher/url_launcher.dart';

part 'auth_store.g.dart';

class AuthStore = AuthBase with _$AuthStore;

abstract class AuthBase with Store {
  /// Secure storage to store tokens.
  static const _storage = FlutterSecureStorage();

  /// The shared_preferences key for the default token.
  static const _defaultTokenKey = 'default_token';

  /// The shared_preferences key for the user token.
  static const _userTokenKey = 'user_token';

  /// The Twitch API service for making requests.
  final TwitchApi twitchApi;

  /// Whether the token is valid or not.
  var _tokenIsValid = false;

  /// Timer used to retry authentication when offline or on transient failures.
  Timer? _reconnectTimer;

  /// Retry count for reconnection attempts.
  var _reconnectAttempts = 0;

  /// Maximum number of reconnection attempts before giving up.
  static const _maxReconnectAttempts = 5;

  /// The MobX store containing information relevant to the current user.
  final UserStore user;

  /// The user token used to authenticate with the Twitch API.
  @readonly
  String? _token;

  /// Whether the user is logged in or not.
  @readonly
  var _isLoggedIn = false;

  /// Authentication headers for Twitch API requests.
  @computed
  Map<String, String> get headersTwitch => {'Authorization': 'Bearer $_token', 'Client-Id': clientId};

  /// Error flag that will be non-null and contain an error message if login failed.
  @readonly
  String? _error;

  /// OAuth scopes requested during Twitch authorization.
  static const _oauthScopes =
      'chat:read chat:edit user:read:follows user:read:blocked_users user:manage:blocked_users user:manage:chat_color moderator:manage:banned_users moderator:manage:chat_messages';

  /// Builds the Twitch OAuth authorization URI for the implicit grant flow.
  Uri get oauthUri => Uri(
        scheme: 'https',
        host: 'id.twitch.tv',
        path: '/oauth2/authorize',
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': oauthRedirectUri,
          'response_type': 'token',
          'scope': _oauthScopes,
          'force_verify': 'true',
        },
      );

  /// Launches the Twitch OAuth page in an external browser.
  Future<void> launchLogin() async {
    await launchUrl(oauthUri, mode: LaunchMode.externalApplication);
  }

  /// Handles an OAuth redirect URI, extracting and storing the access token.
  /// Returns true if a valid token was found and login succeeded.
  Future<bool> handleOAuthRedirect(Uri uri) async {
    if (uri.host != Uri.parse(oauthRedirectUri).host) return false;

    final fragment = uri.fragment;
    if (fragment.isEmpty) return false;

    final params = Uri.splitQueryString(fragment);
    final token = params['access_token'];
    if (token == null) return false;

    await login(token: token);
    return true;
  }

  /// Shows a dialog verifying that the user is sure they want to block/unblock the target user.
  Future<void> showBlockDialog(BuildContext context, {required String targetUser, required String targetUserId}) {
    final isBlocked = user.blockedUsers.where((blockedUser) => blockedUser.userId == targetUserId).isNotEmpty;

    final title = isBlocked ? 'Unblock' : 'Block';

    final message =
        'Are you sure you want to ${isBlocked ? 'unblock "$targetUser"?' : 'block "$targetUser"? This will remove them from channel lists, search results, and chat messages.'}';

    void onPressed() {
      if (isBlocked) {
        user.unblock(targetId: targetUserId);
      } else {
        user.block(targetId: targetUserId, displayName: targetUser);
      }
      Navigator.pop(context);
    }

    return showDialog(
      context: context,
      builder: (context) => FrostyDialog(
        title: title,
        message: message,
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('Cancel')),
          FilledButton(onPressed: onPressed, child: const Text('Yes')),
        ],
      ),
    );
  }

  AuthBase({required this.twitchApi}) : user = UserStore(twitchApi: twitchApi);

  /// Initialize by retrieving a token if it does not already exist.
  @action
  Future<void> init() async {
    try {
      // Read and set the currently stored user token, if any.
      _token = await _storage.read(key: _userTokenKey);

      // If the token does not exist, get the default token.
      // Otherwise, log in.
      if (_token == null) {
        // Retrieve the currently stored default token if it exists.
        _token = await _storage.read(key: _defaultTokenKey);
        // If the token does not exist or is invalid, get a new token and store it.
        if (_token == null || !await twitchApi.validateToken(token: _token!)) {
          _token = await twitchApi.getDefaultToken();
          await _storage.write(key: _defaultTokenKey, value: _token);
        }
      } else {
        // Validate the existing token. If it fails, start reconnect loop.
        try {
          _tokenIsValid = await twitchApi.validateToken(token: _token!);
        } on ApiException catch (e) {
          debugPrint('Token validation failed: $e');
          _isLoggedIn = false;
          _startReconnectLoop();
          return;
        }

        // If the token is invalid, logout.
        if (!_tokenIsValid) return await logout();

        // Initialize the user store.
        await user.init();

        if (user.details != null) {
          _isLoggedIn = true;
          _stopReconnectLoop();
        }
      }

      _error = null;
    } catch (e) {
      debugPrint(e.toString());
      _error = e.toString();
    }
  }

  /// Logs in the user with the provided [token] and updates fields accordingly upon successful login.
  @action
  Future<void> login({required String token}) async {
    try {
      // Validate the custom token.
      _tokenIsValid = await twitchApi.validateToken(token: token);
      if (!_tokenIsValid) return;

      // Replace the current default token with the new custom token.
      _token = token;

      // Store the user token.
      await _storage.write(key: _userTokenKey, value: token);

      // Initialize the user with the new token.
      await user.init();

      // Set the login status to logged in.
      if (user.details != null) {
        _isLoggedIn = true;
        _stopReconnectLoop();
      }
    } catch (e) {
      debugPrint('Login failed due to $e');
    }
  }

  /// Logs out the current user and updates fields accordingly.
  @action
  Future<void> logout() async {
    try {
      _stopReconnectLoop();
      // Delete the existing user token.
      await _storage.delete(key: _userTokenKey);
      _token = null;

      // Clear the user info.
      user.dispose();

      // If the default token already exists, set it.
      _token = await _storage.read(key: _defaultTokenKey);

      // If the default token does not already exist or it's invalid, get the new default token and store it.
      if (_token == null || !await twitchApi.validateToken(token: _token!)) {
        _token = await twitchApi.getDefaultToken();
        await _storage.write(key: _defaultTokenKey, value: _token);
      }

      // Set the login status to logged out.
      _isLoggedIn = false;

      debugPrint('Successfully logged out');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _startReconnectLoop() {
    if (_reconnectTimer != null) return;
    _reconnectAttempts = 0;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        _reconnectAttempts++;
        if (_reconnectAttempts > _maxReconnectAttempts) {
          await logout();
          return;
        }

        final stored = await _storage.read(key: _userTokenKey);
        if (stored == null) {
          _stopReconnectLoop();
          return;
        }

        final isValid = await twitchApi.validateToken(token: stored);
        if (!isValid) {
          await logout();
          return;
        }

        // Token valid again — restore session.
        _token = stored;
        await user.init();
        if (user.details != null) {
          _isLoggedIn = true;
          _error = null;
          _stopReconnectLoop();
        }
      } on ApiException catch (_) {
        // Continue trying
      } catch (e) {
        debugPrint('Reconnect loop error: $e');
      }
    });
  }

  void _stopReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }
}

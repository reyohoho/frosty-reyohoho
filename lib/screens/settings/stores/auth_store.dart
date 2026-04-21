import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/app_navigator_key.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/screens/onboarding/login_webview.dart';
import 'package:frosty/screens/settings/stores/user_store.dart';
import 'package:frosty/utils/chromium_login_support.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:mobx/mobx.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'auth_store.g.dart';

class AuthStore = AuthBase with _$AuthStore;

abstract class AuthBase with Store {
  /// Secure storage to store tokens.
  static const _storage = FlutterSecureStorage();

  /// The shared_preferences key for the default token.
  static const _defaultTokenKey = 'default_token_new';

  /// The shared_preferences key for the user token.
  static const _userTokenKey = 'user_token_new';

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

  /// User-Agent for the auth WebView (works around Google OAuth WebView blocking).
  static String get webViewUserAgent => Platform.isIOS
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'
      : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36';

  /// Whether the incoming URL matches our configured OAuth redirect URI
  /// (scheme + host). Path/fragment may vary.
  static bool _isOAuthRedirectUrl(String url) {
    final incoming = Uri.tryParse(url);
    if (incoming == null) return false;
    final redirect = Uri.parse(oauthRedirectUri);
    return incoming.scheme == redirect.scheme && incoming.host == redirect.host;
  }

  /// Extracts `access_token` from an OAuth redirect URL. Twitch's implicit
  /// grant puts it in the URI fragment, but we also accept query parameters in
  /// case something in the stack converts `#` → `?`.
  static String? _extractAccessToken(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.fragment.isNotEmpty) {
      final params = Uri.splitQueryString(uri.fragment);
      final token = params['access_token'];
      if (token != null) return token;
    }
    return uri.queryParameters['access_token'];
  }

  /// WebView-based OAuth flow used by [LoginWebView] when the user picks the
  /// in-app browser option. Uses [oauthRedirectUri] and detects the token via
  /// three independent paths to survive Android WebView quirks where the URI
  /// fragment is sometimes stripped from navigation events:
  ///   1. `onNavigationRequest` — fastest, usually has the fragment
  ///   2. `onUrlChange`         — fires on every URL update (fragment-safe)
  ///   3. `onPageFinished` + JS — reads `window.location.hash` from the page
  ///
  /// Once the token is recovered we only call [login]; closing the WebView is
  /// the caller's responsibility (e.g. [LoginWebView] watches `isLoggedIn` and
  /// pops itself). Keeping navigation out of the store avoids races with MobX
  /// reactions that also listen to `isLoggedIn`.
  WebViewController createAuthWebViewController({VoidCallback? onRedirectWithoutToken}) {
    var loginHandled = false;

    void finishLogin(String token) {
      if (loginHandled) return;
      loginHandled = true;
      debugPrint('Auth WebView: token captured, calling login()');
      unawaited(login(token: token));
    }

    final webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(webViewUserAgent);

    return webViewController
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isOAuthRedirectUrl(request.url)) {
              debugPrint('Auth WebView: onNavigationRequest redirect url = ${request.url}');
              final token = _extractAccessToken(request.url);
              if (token != null) {
                finishLogin(token);
                // Block loading the external redirect stub inside the WebView.
                return NavigationDecision.prevent;
              }
              // Fragment may have been stripped on this platform — let the
              // page load so `onUrlChange` / JS fallback can recover it.
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            if (_isOAuthRedirectUrl(url)) {
              debugPrint('Auth WebView: onUrlChange redirect url = $url');
              final token = _extractAccessToken(url);
              if (token != null) finishLogin(token);
            }
          },
          onWebResourceError: (error) {
            debugPrint('Auth WebView error: ${error.description}');
          },
          onPageFinished: (url) async {
            try {
              if (_isOAuthRedirectUrl(url) && !loginHandled) {
                debugPrint('Auth WebView: onPageFinished on redirect, reading hash via JS');
                final result = await webViewController.runJavaScriptReturningResult(
                  'window.location.hash',
                );
                final raw = result is String ? result : result.toString();
                final hash = raw.replaceAll('"', '');
                if (hash.isNotEmpty) {
                  final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
                  final params = Uri.splitQueryString(fragment);
                  final token = params['access_token'];
                  if (token != null) {
                    finishLogin(token);
                    return;
                  }
                }
                if (!loginHandled) {
                  debugPrint('Auth WebView: redirect reached without token');
                  onRedirectWithoutToken?.call();
                }
                return;
              }

              await webViewController.runJavaScript('''
                {
                  function modifyElement(element) {
                    element.style.maxHeight = '20vh';
                    element.style.overflow = 'auto';
                  }

                  const observer = new MutationObserver((mutations) => {
                    for (let mutation of mutations) {
                      if (mutation.type === 'childList') {
                        const element = document.querySelector('.fAVISI');
                        if (element) {
                          modifyElement(element);
                          observer.disconnect();
                          break;
                        }
                      }
                    }
                  });

                  observer.observe(document.body, {
                    childList: true,
                    subtree: true
                  });
                }
                ''');
            } catch (e) {
              debugPrint('Auth WebView JavaScript error: $e');
            }
          },
        ),
      )
      ..loadRequest(oauthUri);
  }

  /// Builds the Twitch OAuth authorization URI for the implicit grant flow.
  /// Used for both the external browser flow and the in-app [LoginWebView];
  /// only [oauthRedirectUri] needs to be registered in the Twitch developer
  /// console.
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

  /// Shows a chooser dialog letting the user pick how to sign in (in-app WebView,
  /// external browser with Chrome preference, or copy the auth URL).
  ///
  /// Post-login navigation (e.g. onboarding → setup) is expected to be driven
  /// by the caller's own MobX reaction on [isLoggedIn]; this method only opens
  /// the picked auth flow.
  Future<void> launchLogin(BuildContext? context) async {
    debugPrint('launchLogin: called (context mounted=${context?.mounted})');
    // Prefer the global navigator context — it stays valid across MobX
    // rebuilds that may invalidate a passed-in Observer builder context.
    final ctx = navigatorKey.currentContext ?? context;
    if (ctx == null || !ctx.mounted) {
      debugPrint('launchLogin: no usable context, falling back to external browser');
      await launchUrlInChromeOrChooser(oauthUri);
      return;
    }

    final choice = await showLoginMethodChooser(ctx, authUrl: oauthUri);
    debugPrint('launchLogin: user chose $choice');
    switch (choice) {
      case LoginMethodChoice.internal:
        navigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => const LoginWebView(),
          ),
        );
        return;
      case LoginMethodChoice.external:
        final confirmCtx = navigatorKey.currentContext ?? ctx;
        if (!confirmCtx.mounted) return;
        final confirmed = await showExternalBrowserWarningDialog(confirmCtx);
        if (!confirmed) return;
        await launchUrlInChromeOrChooser(oauthUri);
        return;
      case LoginMethodChoice.cancelled:
        return;
    }
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

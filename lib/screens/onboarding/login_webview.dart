import 'package:flutter/material.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/widgets/frosty_app_bar.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:mobx/mobx.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app WebView for Twitch OAuth when the user opts for the internal browser.
///
/// Owns its lifecycle: once [AuthStore.isLoggedIn] flips to `true` (or the
/// WebView reaches the OAuth redirect without a usable token), the screen
/// removes itself from the navigator stack. Any post-login navigation
/// (e.g. onboarding → setup) is handled by the caller's own MobX reaction on
/// `isLoggedIn`, so we don't race with it here.
class LoginWebView extends StatefulWidget {
  const LoginWebView({super.key});

  @override
  State<LoginWebView> createState() => _LoginWebViewState();
}

class _LoginWebViewState extends State<LoginWebView> {
  ReactionDisposer? _loginReactionDisposer;
  late final WebViewController _controller;

  void _removeSelf() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    // `removeRoute` dismisses this specific route regardless of whether it is
    // currently on top of the stack, which protects us from other reactions
    // pushing routes on top before our reaction fires.
    Navigator.of(context).removeRoute(route);
  }

  @override
  void initState() {
    super.initState();

    final authStore = context.read<AuthStore>();

    _controller = authStore.createAuthWebViewController(
      onRedirectWithoutToken: _removeSelf,
    );

    _loginReactionDisposer = reaction<bool>(
      (_) => authStore.isLoggedIn,
      (isLoggedIn) {
        if (isLoggedIn) _removeSelf();
      },
    );
  }

  @override
  void dispose() {
    _loginReactionDisposer?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FrostyAppBar(
        title: const Text('Connect with Twitch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_rounded),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) {
                return FrostyDialog(
                  title: 'Workaround for the Twitch cookie banner',
                  message:
                      'If the Twitch cookie banner is still blocking the login, try clicking one of the links in the cookie policy description and navigating until you reach the Twitch home page. From there, you can try logging in on the top right profile icon. Once logged in, go back to the first step of the onboarding and then try again.',
                  actions: [TextButton(onPressed: Navigator.of(context).pop, child: const Text('Close'))],
                );
              },
            ),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

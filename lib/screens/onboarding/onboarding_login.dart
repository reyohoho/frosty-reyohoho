import 'package:flutter/material.dart';
import 'package:frosty/screens/onboarding/onboarding_scaffold.dart';
import 'package:frosty/screens/onboarding/onboarding_setup.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:mobx/mobx.dart';
import 'package:provider/provider.dart';
import 'package:simple_icons/simple_icons.dart';

class OnboardingLogin extends StatefulWidget {
  const OnboardingLogin({super.key});

  @override
  State<OnboardingLogin> createState() => _OnboardingLoginState();
}

class _OnboardingLoginState extends State<OnboardingLogin> {
  ReactionDisposer? _loginReaction;

  @override
  void initState() {
    super.initState();
    final authStore = context.read<AuthStore>();
    _loginReaction = reaction(
      (_) => authStore.isLoggedIn,
      (bool isLoggedIn) {
        if (isLoggedIn && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OnboardingSetup()),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _loginReaction?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authStore = context.read<AuthStore>();
    return OnboardingScaffold(
      header: 'Log in',
      subtitle:
          'Frosty needs your permission in order to enable the ability to chat, view followed streams, and more.',
      disclaimer:
          'Frosty only asks for the necessary permissions through the official Twitch API. You\'ll be able to review them before authorizing.',
      buttonText: 'Connect with Twitch',
      buttonIcon: const Icon(SimpleIcons.twitch),
      skipRoute: const OnboardingSetup(),
      onButtonPressed: authStore.launchLogin,
    );
  }
}

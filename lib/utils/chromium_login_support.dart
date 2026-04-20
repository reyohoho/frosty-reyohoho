import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

const _browserChannel = MethodChannel('ru.refrosty/browser');

/// Result of [showLoginMethodChooser].
enum LoginMethodChoice {
  internal,
  external,
  cancelled,
}

/// Whether a Chrome/Chromium-family browser is installed (Android only).
/// Non-Android platforms return `true`.
Future<bool> hasChromiumBrowserForLogin() async {
  if (!Platform.isAndroid) return true;
  try {
    final result = await _browserChannel.invokeMethod<bool>('hasChromiumBrowser');
    return result ?? false;
  } catch (e, st) {
    debugPrint('hasChromiumBrowserForLogin: $e\n$st');
    return true;
  }
}

/// Opens [url] in Chrome if installed, otherwise shows a system chooser among
/// installed browsers. Android only; other platforms fall back to
/// [launchUrl] with [LaunchMode.externalApplication].
Future<bool> launchUrlInChromeOrChooser(Uri url) async {
  if (!Platform.isAndroid) {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
  try {
    final launched = await _browserChannel.invokeMethod<bool>(
      'launchUrlInChromeOrChooser',
      {'url': url.toString()},
    );
    if (launched ?? false) return true;
  } catch (e, st) {
    debugPrint('launchUrlInChromeOrChooser: $e\n$st');
  }
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Shows a chooser dialog letting the user pick how to sign in:
/// in-app WebView, external browser (Chrome-preferred), or copy the auth link.
Future<LoginMethodChoice> showLoginMethodChooser(
  BuildContext context, {
  required Uri authUrl,
}) async {
  debugPrint('showLoginMethodChooser: probing chromium availability');
  final hasChromium = await hasChromiumBrowserForLogin();
  debugPrint('showLoginMethodChooser: hasChromium=$hasChromium, context.mounted=${context.mounted}');
  if (!context.mounted) return LoginMethodChoice.cancelled;

  final choice = await showDialog<LoginMethodChoice>(
    context: context,
    builder: (dialogContext) => _LoginMethodChooserDialog(
      authUrl: authUrl,
      hasChromium: hasChromium,
    ),
  );
  debugPrint('showLoginMethodChooser: dialog returned $choice');
  return choice ?? LoginMethodChoice.cancelled;
}

/// Confirmation dialog shown before launching the external browser.
/// Returns `true` if the user chose to continue.
Future<bool> showExternalBrowserWarningDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => FrostyDialog(
      title: 'Внешний браузер',
      message:
          'Поддерживаются только последние версии Google Chrome или Firefox. '
          'В других браузерах авторизация Twitch может не работать (например, блокируется Google OAuth).\n\n'
          'Если Chrome установлен, он будет использован автоматически. Иначе появится выбор браузера.',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Продолжить'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _LoginMethodChooserDialog extends StatelessWidget {
  final Uri authUrl;
  final bool hasChromium;

  const _LoginMethodChooserDialog({
    required this.authUrl,
    required this.hasChromium,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Вход через Twitch'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Выберите, как открыть страницу авторизации Twitch.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            _LoginMethodTile(
              icon: Icons.phone_android_rounded,
              title: 'Внутренний браузер',
              subtitle:
                  'Открывается внутри приложения. Рекомендуется, если внешний браузер не работает.',
              onTap: () => Navigator.of(context).pop(LoginMethodChoice.internal),
            ),
            _LoginMethodTile(
              icon: Icons.open_in_browser_rounded,
              title: 'Внешний браузер',
              subtitle: hasChromium
                  ? 'Будет использован Google Chrome. Поддерживаются только последние версии Chrome или Firefox.'
                  : 'Chrome не найден — будет показан выбор из установленных браузеров. Поддерживаются только последние версии Chrome или Firefox.',
              onTap: () => Navigator.of(context).pop(LoginMethodChoice.external),
            ),
            _LoginMethodTile(
              icon: Icons.content_copy_rounded,
              title: 'Скопировать ссылку',
              subtitle:
                  'Скопировать URL авторизации, чтобы открыть его вручную в любом браузере.',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: authUrl.toString()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(LoginMethodChoice.cancelled),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}

class _LoginMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LoginMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}

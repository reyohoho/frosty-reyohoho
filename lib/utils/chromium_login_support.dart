import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

const _browserChannel = MethodChannel('ru.refrosty/browser');

/// Whether a Chrome/Chromium-family browser is installed (Android only).
/// On other platforms always returns true.
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

/// Opens the best available store listing or search page for installing Chrome.
/// Result of [showChromiumRequiredDialog].
enum ChromiumLoginChoice {
  dismissed,
  openStore,
  inAppWebView,
}

Future<void> openChromeInstallInDeviceStore() async {
  if (!Platform.isAndroid) {
    final web = Uri.parse('https://www.google.com/chrome/');
    if (await canLaunchUrl(web)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
    return;
  }

  final android = await DeviceInfoPlugin().androidInfo;
  final manufacturer = android.manufacturer.toLowerCase();

  final playMarket = Uri.parse('market://details?id=com.android.chrome');
  final playHttps = Uri.parse('https://play.google.com/store/apps/details?id=com.android.chrome');

  if (manufacturer.contains('huawei') || manufacturer.contains('honor')) {
    final appGallerySearch = Uri.parse('https://appgallery.huawei.com/search/chrome');
    if (await canLaunchUrl(appGallerySearch)) {
      await launchUrl(appGallerySearch, mode: LaunchMode.externalApplication);
      return;
    }
  }

  if (await canLaunchUrl(playMarket)) {
    await launchUrl(playMarket, mode: LaunchMode.externalApplication);
    return;
  }

  if (await canLaunchUrl(playHttps)) {
    await launchUrl(playHttps, mode: LaunchMode.externalApplication);
  }
}

Future<ChromiumLoginChoice?> showChromiumRequiredDialog(BuildContext context) {
  return showDialog<ChromiumLoginChoice>(
    context: context,
    builder: (dialogContext) => FrostyDialog(
      title: 'Browser required',
      message:
          'Signing in with Twitch works best with Google Chrome or Chromium. '
          'Install Chrome from your app store (Google Play, AppGallery, etc.), then try again. '
          'If you cannot install Chrome, you can sign in inside the app instead (may be less reliable).',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(ChromiumLoginChoice.dismissed),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(ChromiumLoginChoice.inAppWebView),
          child: const Text('Can\'t install'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(ChromiumLoginChoice.openStore),
          child: const Text('Open store'),
        ),
      ],
    ),
  );
}

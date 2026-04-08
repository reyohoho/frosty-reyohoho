import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:frosty/apis/reyohoho_api.dart';
import 'package:frosty/cache_manager.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:provider/provider.dart';

/// CDN domains that should be proxied when emote proxy is enabled.
/// Includes emotes and badges from BTTV, FFZ, and 7TV.
const emoteProxyCdnDomains = [
  'cdn.betterttv.net',
  'cdn.frankerfacez.com',
  'cdn.7tv.app',
];

/// Checks if the URL belongs to a third-party emote/badge CDN.
bool isEmoteCdnUrl(String url) {
  for (final domain in emoteProxyCdnDomains) {
    if (url.contains(domain)) return true;
  }
  return false;
}

/// Returns the proxied URL for emotes/badges if proxy is enabled and URL matches CDN.
/// Uses the dynamically verified starege domain from [ReyohohoApi.workingDomain].
/// Returns the original URL if proxy is disabled or no working domain is available.
String getProxiedEmoteUrl(BuildContext context, String url) {
  if (url.isEmpty || !isEmoteCdnUrl(url)) return url;

  try {
    final settingsStore = context.read<SettingsStore>();
    if (settingsStore.useEmoteProxy) {
      final reyohohoApi = context.read<ReyohohoApi>();
      final proxyBase = reyohohoApi.workingDomain;
      if (proxyBase != null) {
        return '$proxyBase/$url';
      }
    }
  } catch (e) {
    // Provider not available in context
  }
  return url;
}

/// A wrapper around [CachedNetworkImage] that adds custom defaults for Frosty.
///
/// For emote CDN URLs, wraps in an [Observer] so the widget automatically
/// rebuilds when [SettingsStore.useEmoteProxy] is toggled.
class FrostyCachedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String? cacheKey;
  final double? width;
  final double? height;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Widget Function(BuildContext, String)? placeholder;
  final bool useOldImageOnUrlChange;
  final bool useFade;
  final BoxFit? fit;

  const FrostyCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.cacheKey,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.placeholder,
    this.useFade = true,
    this.useOldImageOnUrlChange = false,
    this.fit,
  });

  @override
  Widget build(BuildContext context) => _buildImage(context);

  Widget _buildImage(BuildContext context) {
    final effectiveUrl = getProxiedEmoteUrl(context, imageUrl);

    return CachedNetworkImage(
      imageUrl: effectiveUrl,
      cacheKey: cacheKey ?? imageUrl,
      width: width,
      height: height,
      color: color,
      colorBlendMode: colorBlendMode,
      placeholder: placeholder,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      fadeOutDuration: useFade
          ? const Duration(milliseconds: 500)
          : Duration.zero,
      fadeInDuration: useFade
          ? const Duration(milliseconds: 500)
          : Duration.zero,
      fadeInCurve: Curves.easeOut,
      fadeOutCurve: Curves.easeIn,
      fit: fit,
      cacheManager: CustomCacheManager.instance,
    );
  }
}

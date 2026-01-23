import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:frosty/cache_manager.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/widgets/frosty_photo_view_dialog.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Determines the type of link preview to display.
enum LinkPreviewType {
  image,
  video,
  sevenTVEmote,
  imgur,
  kappaLol,
}

/// Information about a link that can be previewed.
class LinkPreviewInfo {
  final LinkPreviewType type;
  final String originalUrl;
  final String displayUrl;
  final String? id;

  const LinkPreviewInfo({
    required this.type,
    required this.originalUrl,
    required this.displayUrl,
    this.id,
  });
}

/// Checks if a URL should be proxied for link previews.
bool shouldProxyLinkPreview(String url) {
  // Don't proxy our own proxy servers
  for (final domain in linkPreviewNoProxyDomains) {
    if (url.contains(domain)) return false;
  }
  // Proxy specific CDN domains
  for (final domain in linkPreviewProxyDomains) {
    if (url.contains(domain)) return true;
  }
  // Also proxy kappa.lol
  if (url.contains('kappa.lol')) return true;
  return false;
}

/// Detects if a text contains a previewable link and returns info about it.
LinkPreviewInfo? detectLinkPreview(String text) {
  // Check 7TV emote links
  final sevenTVMatch = regex7TVEmote.firstMatch(text);
  if (sevenTVMatch != null) {
    return LinkPreviewInfo(
      type: LinkPreviewType.sevenTVEmote,
      originalUrl: text,
      displayUrl: 'https://cdn.7tv.app/emote/${sevenTVMatch.group(1)}/2x.webp',
      id: sevenTVMatch.group(1),
    );
  }

  // Check Imgur links
  final imgurMatch = regexImgur.firstMatch(text);
  if (imgurMatch != null) {
    return LinkPreviewInfo(
      type: LinkPreviewType.imgur,
      originalUrl: text,
      displayUrl: 'https://i.imgur.com/${imgurMatch.group(1)}.jpg',
      id: imgurMatch.group(1),
    );
  }

  // Check Kappa.lol links
  final kappaLolMatch = regexKappaLol.firstMatch(text);
  if (kappaLolMatch != null) {
    return LinkPreviewInfo(
      type: LinkPreviewType.kappaLol,
      originalUrl: text,
      displayUrl: text,
      id: kappaLolMatch.group(1),
    );
  }

  // Check direct image URLs
  if (regexImageUrl.hasMatch(text)) {
    return LinkPreviewInfo(
      type: LinkPreviewType.image,
      originalUrl: text,
      displayUrl: text,
    );
  }

  // Check direct video URLs
  if (regexVideoUrl.hasMatch(text)) {
    return LinkPreviewInfo(
      type: LinkPreviewType.video,
      originalUrl: text,
      displayUrl: text,
    );
  }

  return null;
}

/// A widget that displays a preview for images in chat.
class LinkPreviewWidget extends StatelessWidget {
  final LinkPreviewInfo previewInfo;
  final double maxWidth;
  final double maxHeight;
  final bool launchExternal;

  const LinkPreviewWidget({
    super.key,
    required this.previewInfo,
    required this.maxWidth,
    required this.maxHeight,
    required this.launchExternal,
  });

  String _getProxiedUrl(BuildContext context) {
    final settingsStore = context.read<SettingsStore>();
    final url = previewInfo.displayUrl;

    if (!settingsStore.useEmoteProxy) return url;
    if (!shouldProxyLinkPreview(url)) return url;

    return settingsStore.getProxiedEmoteUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    // For videos, show a thumbnail-like preview with play icon
    if (previewInfo.type == LinkPreviewType.video) {
      return _VideoPreviewPlaceholder(
        videoUrl: previewInfo.originalUrl,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        launchExternal: launchExternal,
      );
    }

    return _ImagePreview(
      previewInfo: previewInfo,
      imageUrl: _getProxiedUrl(context),
      originalUrl: previewInfo.originalUrl,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      launchExternal: launchExternal,
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final LinkPreviewInfo previewInfo;
  final String imageUrl;
  final String originalUrl;
  final double maxWidth;
  final double maxHeight;
  final bool launchExternal;

  const _ImagePreview({
    required this.previewInfo,
    required this.imageUrl,
    required this.originalUrl,
    required this.maxWidth,
    required this.maxHeight,
    required this.launchExternal,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (context) => FrostyPhotoViewDialog(imageUrl: imageUrl),
      ),
      onLongPress: () => launchUrl(
        Uri.parse(originalUrl),
        mode: launchExternal
            ? LaunchMode.externalApplication
            : LaunchMode.inAppBrowserView,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheKey: previewInfo.displayUrl,
            cacheManager: CustomCacheManager.instance,
            fit: BoxFit.contain,
            placeholder: (context, url) => Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// A placeholder widget for video previews that opens the video in browser on tap.
class _VideoPreviewPlaceholder extends StatelessWidget {
  final String videoUrl;
  final double maxWidth;
  final double maxHeight;
  final bool launchExternal;

  const _VideoPreviewPlaceholder({
    required this.videoUrl,
    required this.maxWidth,
    required this.maxHeight,
    required this.launchExternal,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(videoUrl),
        mode: launchExternal
            ? LaunchMode.externalApplication
            : LaunchMode.inAppBrowserView,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Video',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Tap to open',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

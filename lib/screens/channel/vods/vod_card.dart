import 'dart:math';

import 'package:flutter/material.dart';
import 'package:frosty/models/vod.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:frosty/widgets/skeleton_loader.dart';
import 'package:intl/intl.dart';

/// A card widget displaying VOD information
class VodCard extends StatelessWidget {
  final VideoTwitch video;
  final VoidCallback onTap;

  const VodCard({
    super.key,
    required this.video,
    required this.onTap,
  });

  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  String _formatRelativeDate(String dateString) {
    final date = DateTime.parse(dateString);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      return DateFormat.yMMMd().format(date);
    }
  }

  String _getTypeLabel() {
    switch (video.videoType) {
      case VideoType.highlight:
        return 'Highlight';
      case VideoType.upload:
        return 'Upload';
      case VideoType.archive:
        return 'Past Broadcast';
    }
  }

  Color _getTypeColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (video.videoType) {
      case VideoType.highlight:
        return colorScheme.tertiary;
      case VideoType.upload:
        return colorScheme.secondary;
      case VideoType.archive:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontColor = theme.textTheme.bodyMedium?.color;

    // Calculate thumbnail dimensions
    final size = MediaQuery.of(context).size;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final thumbnailWidth = min((size.width * pixelRatio) ~/ 2, 640);
    final thumbnailHeight = (thumbnailWidth * (9 / 16)).toInt();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            SizedBox(
              width: 160,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: FrostyCachedNetworkImage(
                        imageUrl: video.getThumbnailUrl(
                          width: thumbnailWidth,
                          height: thumbnailHeight,
                        ),
                        placeholder: (context, url) => const SkeletonLoader(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Duration badge
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.formattedDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  // Video type badge
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(context).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getTypeLabel(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Video info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    video.title.isNotEmpty ? video.title : 'Untitled Broadcast',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fontColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Date and time
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: fontColor?.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(video.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: fontColor?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Relative date
                  Text(
                    _formatRelativeDate(video.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: fontColor?.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // View count
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 14,
                        color: fontColor?.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${NumberFormat.compact().format(video.viewCount)} views',
                        style: TextStyle(
                          fontSize: 12,
                          color: fontColor?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

/// Skeleton loader for VOD card
class VodCardSkeleton extends StatelessWidget {
  const VodCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail skeleton
          const SizedBox(
            width: 160,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: SkeletonLoader(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info skeleton
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  height: 16,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                SkeletonLoader(
                  height: 14,
                  width: 100,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                SkeletonLoader(
                  height: 14,
                  width: 80,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


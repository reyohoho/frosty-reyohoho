import 'package:flutter/material.dart';
import 'package:frosty/utils/context_extensions.dart';
import 'package:frosty/widgets/animated_scroll_border.dart';
import 'package:frosty/widgets/frosty_scrollbar.dart';

/// A reusable layout for settings pages that handles common functionality:
/// - Orientation detection
/// - Responsive padding calculations
/// - AnimatedScrollBorder positioning
/// - ScrollController management
class SettingsPageLayout extends StatefulWidget {
  final List<Widget> children;
  final bool hasBottomPadding;
  final EdgeInsetsGeometry? additionalPadding;
  final RefreshCallback? onRefresh;

  const SettingsPageLayout({
    super.key,
    required this.children,
    this.hasBottomPadding = true,
    this.additionalPadding,
    this.onRefresh,
  });

  @override
  State<SettingsPageLayout> createState() => _SettingsPageLayoutState();
}

class _SettingsPageLayoutState extends State<SettingsPageLayout> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get the original view padding (unaffected by MediaQuery.removePadding)
    final view = View.of(context);
    final topPadding = view.padding.top / view.devicePixelRatio;
    
    // Calculate header height dynamically: status bar + toolbar
    final headerHeight = topPadding + kToolbarHeight;

    final listPadding = EdgeInsets.only(
      top: headerHeight + 8,
      bottom: widget.hasBottomPadding ? context.safePaddingBottom + 8 : 0,
    );
    
    final borderTop = headerHeight;

    final content = Stack(
      children: [
        FrostyScrollbar(
          controller: _scrollController,
          padding: EdgeInsets.only(top: borderTop.toDouble()),
          child: ListView(
            controller: _scrollController,
            padding: widget.additionalPadding != null
                ? widget.additionalPadding!.add(listPadding)
                : listPadding,
            children: widget.children,
          ),
        ),
        Positioned(
          top: borderTop.toDouble(),
          left: 0,
          right: 0,
          child: AnimatedScrollBorder(scrollController: _scrollController),
        ),
      ],
    );

    // Conditionally wrap with RefreshIndicator if onRefresh is provided
    if (widget.onRefresh != null) {
      return RefreshIndicator.adaptive(
        onRefresh: widget.onRefresh!,
        child: content,
      );
    }

    return content;
  }
}

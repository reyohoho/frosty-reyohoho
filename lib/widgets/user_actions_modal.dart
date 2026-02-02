import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/widgets/blurred_container.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Timeout duration presets with their labels and durations in seconds.
const _timeoutPresets = [
  (label: '1 minute', duration: 60),
  (label: '10 minutes', duration: 600),
  (label: '1 hour', duration: 3600),
  (label: '1 day', duration: 86400),
  (label: '1 week', duration: 604800),
];

class UserActionsModal extends StatelessWidget {
  final AuthStore authStore;
  final String name;
  final String userLogin;
  final String userId;
  final bool showPinOption;
  final bool? isPinned;

  /// Whether the current user can moderate (is mod or channel owner).
  final bool canModerate;

  /// Callback when user should be timed out. Receives duration in seconds.
  final Future<bool> Function(int duration)? onTimeout;

  /// Callback when user should be banned.
  final Future<bool> Function()? onBan;

  /// Callback when user should be unbanned.
  final Future<bool> Function()? onUnban;

  /// Callback to show moderation notice in chat.
  final void Function(String message)? onModerationNotice;

  /// Callback to show error notification.
  final void Function(String message)? onError;

  const UserActionsModal({
    super.key,
    required this.authStore,
    required this.name,
    required this.userLogin,
    required this.userId,
    this.showPinOption = false,
    this.isPinned,
    this.canModerate = false,
    this.onTimeout,
    this.onBan,
    this.onUnban,
    this.onModerationNotice,
    this.onError,
  });

  void _showTimeoutOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        primary: false,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Timeout $name',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(indent: 12, endIndent: 12),
          for (final preset in _timeoutPresets)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(preset.label),
              onTap: () async {
                Navigator.pop(context); // Close timeout options
                if (onTimeout != null) {
                  final success = await onTimeout!(preset.duration);
                  if (context.mounted) {
                    Navigator.pop(context); // Close main modal
                    if (success) {
                      onModerationNotice?.call(
                        '$name has been timed out for ${preset.label}',
                      );
                    } else {
                      onError?.call('Failed to timeout $name');
                    }
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  void _showBanConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FrostyDialog(
        title: 'Ban $name',
        message: 'Are you sure you want to permanently ban $name from the channel?',
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              if (onBan != null) {
                final success = await onBan!();
                if (context.mounted) {
                  Navigator.pop(context); // Close main modal
                  if (success) {
                    onModerationNotice?.call('$name has been permanently banned');
                  } else {
                    onError?.call('Failed to ban $name');
                  }
                }
              }
            },
            child: const Text('Ban'),
          ),
        ],
      ),
    );
  }

  void _showUnbanConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FrostyDialog(
        title: 'Unban $name',
        message: 'Are you sure you want to unban $name?',
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              if (onUnban != null) {
                final success = await onUnban!();
                if (context.mounted) {
                  Navigator.pop(context); // Close main modal
                  if (success) {
                    onModerationNotice?.call('$name has been unbanned');
                  } else {
                    onError?.call('Failed to unban $name');
                  }
                }
              }
            },
            child: const Text('Unban'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      primary: false,
      shrinkWrap: true,
      children: [
        if (showPinOption)
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: Text('${isPinned == true ? 'Unpin' : 'Pin'} $name'),
            onTap: () {
              if (isPinned == true) {
                context.read<SettingsStore>().pinnedChannelIds = [
                  ...context.read<SettingsStore>().pinnedChannelIds
                    ..remove(userId),
                ];
              } else {
                context.read<SettingsStore>().pinnedChannelIds = [
                  ...context.read<SettingsStore>().pinnedChannelIds,
                  userId,
                ];
              }

              Navigator.pop(context);
            },
          ),
        if (canModerate && onTimeout != null)
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text('Timeout $name'),
            onTap: () => _showTimeoutOptions(context),
          ),
        if (canModerate && onBan != null)
          ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: Text('Ban $name'),
            onTap: () => _showBanConfirmation(context),
          ),
        if (canModerate && onUnban != null)
          ListTile(
            leading: const Icon(Icons.lock_open_rounded),
            title: Text('Unban $name'),
            onTap: () => _showUnbanConfirmation(context),
          ),
        if (authStore.isLoggedIn)
          ListTile(
            leading: const Icon(Icons.block_rounded),
            onTap: () => authStore
                .showBlockDialog(
                  context,
                  targetUser: name,
                  targetUserId: userId,
                )
                .then((_) {
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }),
            title: Text('Block $name'),
          ),
        ListTile(
          leading: const Icon(Icons.outlined_flag_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                final theme = Theme.of(context);

                return Scaffold(
                  backgroundColor: theme.scaffoldBackgroundColor,
                  extendBody: true,
                  extendBodyBehindAppBar: true,
                  appBar: AppBar(
                    centerTitle: false,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness:
                          theme.brightness == Brightness.dark
                          ? Brightness.light
                          : Brightness.dark,
                    ),
                    leading: IconButton(
                      tooltip: 'Back',
                      icon: Icon(Icons.adaptive.arrow_back_rounded),
                      onPressed: Navigator.of(context).pop,
                    ),
                    title: Text('Report $name'),
                  ),
                  body: Stack(
                    children: [
                      // WebView content
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top:
                                MediaQuery.of(context).padding.top +
                                kToolbarHeight,
                          ),
                          child: WebViewWidget(
                            controller: WebViewController()
                              ..setJavaScriptMode(JavaScriptMode.unrestricted)
                              ..loadRequest(
                                Uri.parse(
                                  'https://www.twitch.tv/$userLogin/report',
                                ),
                              )
                              ..setNavigationDelegate(
                                NavigationDelegate(
                                  onWebResourceError: (error) {
                                    debugPrint(
                                      'WebView error: ${error.description}',
                                    );
                                  },
                                ),
                              ),
                          ),
                        ),
                      ),
                      // Blurred app bar overlay
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: BlurredContainer(
                          gradientDirection: GradientDirection.up,
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top,
                            left: MediaQuery.of(context).padding.left,
                            right: MediaQuery.of(context).padding.right,
                          ),
                          child: const SizedBox(height: kToolbarHeight),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          title: Text('Report $name'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:frosty/apis/github_api.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatefulWidget {
  final GitHubRelease release;
  final String currentVersion;

  const UpdateDialog({super.key, required this.release, required this.currentVersion});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _tapped = false;

  @override
  Widget build(BuildContext context) {
    return FrostyDialog(
      title: 'Update available',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${widget.currentVersion} \u2192 ${widget.release.tagName}'),
          if (widget.release.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Text(
                  widget.release.body,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _tapped
              ? null
              : () async {
                  setState(() => _tapped = true);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('skipped_release_tag', widget.release.tagName);
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _tapped
              ? null
              : () {
                  setState(() => _tapped = true);
                  Navigator.of(context).pop();
                  final url = widget.release.apkDownloadUrl ?? widget.release.htmlUrl;
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
          child: Text(widget.release.apkDownloadUrl != null ? 'Download' : 'Open'),
        ),
      ],
    );
  }
}

bool isNewerVersion(String remote, String current) {
  final remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  final maxLen = remoteParts.length > currentParts.length ? remoteParts.length : currentParts.length;
  for (var i = 0; i < maxLen; i++) {
    final r = i < remoteParts.length ? remoteParts[i] : 0;
    final c = i < currentParts.length ? currentParts[i] : 0;
    if (r > c) return true;
    if (r < c) return false;
  }
  return false;
}

/// Shows the update dialog if a newer release is available.
/// When [ignoreSkipped] is true, shows even if the user previously skipped this version.
Future<void> checkForUpdate(BuildContext context, {bool ignoreSkipped = false}) async {
  try {
    final githubApi = context.read<GitHubApi>();
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    if (!ignoreSkipped) {
      final prefs = await SharedPreferences.getInstance();
      final skippedTag = prefs.getString('skipped_release_tag');
      final release = await githubApi.getLatestRelease();
      if (release == null || !context.mounted) return;
      if (release.tagName == skippedTag) return;

      final remoteVersion = release.tagName.replaceFirst(RegExp('^v'), '');
      if (isNewerVersion(remoteVersion, currentVersion)) {
        _showDialog(context, release, currentVersion);
      }
    } else {
      final release = await githubApi.getLatestRelease();
      if (release == null || !context.mounted) return;

      final remoteVersion = release.tagName.replaceFirst(RegExp('^v'), '');
      if (isNewerVersion(remoteVersion, currentVersion)) {
        _showDialog(context, release, currentVersion);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version')),
        );
      }
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check for updates')),
      );
    }
  }
}

void _showDialog(BuildContext context, GitHubRelease release, String currentVersion) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(release: release, currentVersion: currentVersion),
  );
}

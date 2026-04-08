import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:frosty/apis/github_api.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/widgets/blurred_container.dart';
import 'package:frosty/widgets/frosty_scrollbar.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ReleaseNotes extends StatefulWidget {
  const ReleaseNotes({super.key});

  @override
  State<ReleaseNotes> createState() => _ReleaseNotesState();
}

class _ReleaseNotesState extends State<ReleaseNotes> {
  final _scrollController = ScrollController();
  String _markdownContent = '';
  bool _isLoading = true;
  String? _error;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchReleases();
  }

  Future<void> _fetchReleases() async {
    try {
      final githubApi = context.read<GitHubApi>();
      final releases = await githubApi.getReleases();

      if (!mounted) return;

      if (releases.isEmpty) {
        setState(() {
          _markdownContent = 'No releases found.';
          _isLoading = false;
        });
        return;
      }

      final buffer = StringBuffer();
      for (final release in releases) {
        buffer.writeln('## ${release.name}');
        buffer.writeln();
        if (release.body.isNotEmpty) {
          buffer.writeln(release.body);
          buffer.writeln();
        }
        buffer.writeln('---');
        buffer.writeln();
      }

      setState(() {
        _markdownContent = buffer.toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load releases';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          statusBarIconBrightness: theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.adaptive.arrow_back_rounded),
          onPressed: Navigator.of(context).pop,
        ),
        title: const Text('Release notes'),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _fetchReleases();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: FrostyScrollbar(
            controller: _scrollController,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight),
            child: Markdown(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight, 16, 16),
              controller: _scrollController,
              data: _markdownContent,
              styleSheet: MarkdownStyleSheet(
                h2: const TextStyle(fontSize: 20),
                h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                h3Padding: const EdgeInsets.only(top: 16),
                h4: const TextStyle(fontSize: 14),
                h4Padding: const EdgeInsets.only(top: 16),
                p: const TextStyle(fontSize: 14),
                horizontalRuleDecoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.transparent, width: 32)),
                ),
              ),
              onTapLink: (text, href, title) {
                if (href != null) {
                  launchUrlString(
                    href,
                    mode: context.read<SettingsStore>().launchUrlExternal
                        ? LaunchMode.externalApplication
                        : LaunchMode.inAppBrowserView,
                  );
                }
              },
            ),
          ),
        ),
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
    );
  }
}

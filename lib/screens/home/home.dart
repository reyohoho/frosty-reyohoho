import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/home/friends/friends.dart';
import 'package:frosty/screens/home/home_store.dart';
import 'package:frosty/screens/home/search/search.dart';
import 'package:frosty/screens/home/stream_list/stream_list_store.dart';
import 'package:frosty/screens/home/stream_list/streams_list.dart';
import 'package:frosty/screens/home/top/top.dart';
import 'package:frosty/screens/settings/settings.dart';
import 'package:frosty/apis/github_api.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/utils/display_cutout.dart';
import 'package:frosty/widgets/blurred_container.dart';
import 'package:frosty/widgets/frosty_dialog.dart';
import 'package:frosty/widgets/profile_picture.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final _authStore = context.read<AuthStore>();

  late final _homeStore = HomeStore(authStore: _authStore);

  Future<void> _checkForUpdate() async {
    try {
      final githubApi = context.read<GitHubApi>();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final release = await githubApi.getLatestRelease();
      if (release == null || !mounted) return;

      final remoteVersion = release.tagName.replaceFirst(RegExp('^v'), '');
      if (_isNewerVersion(remoteVersion, currentVersion)) {
        _showUpdateDialog(release, currentVersion);
      }
    } catch (_) {}
  }

  bool _isNewerVersion(String remote, String current) {
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

  void _showUpdateDialog(GitHubRelease release, String currentVersion) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => FrostyDialog(
        title: 'Update available',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$currentVersion \u2192 ${release.tagName}'),
            if (release.body.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Text(
                    release.body,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Later'),
          ),
          if (release.apkDownloadUrl != null)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse(release.apkDownloadUrl!),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('Download'),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse(release.htmlUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('Open'),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsStore = context.read<SettingsStore>();
      applyDisplayUnderCutout(settingsStore.landscapeDisplayUnderCutout);
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([]);

    final theme = Theme.of(context);

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          ),
          flexibleSpace: Observer(
            builder: (_) {
              // Blur under transparent app bar on Following and Friends (content scrolls behind it).
              final idx = _homeStore.selectedIndex;
              final useBlur = _authStore.isLoggedIn && (idx == 0 || idx == 2);

              if (!useBlur) return const SizedBox.shrink();

              return BlurredContainer(gradientDirection: GradientDirection.up, child: const SizedBox.expand());
            },
          ),
          title: Observer(
            builder: (_) {
              final titles = [
                if (_authStore.isLoggedIn) 'Following',
                'Top',
                if (_authStore.isLoggedIn) 'Friends',
                'Search',
              ];

              return Text(titles[_homeStore.selectedIndex]);
            },
          ),
          actions: [
            Observer(
              builder: (_) {
                final isLoggedIn = _authStore.isLoggedIn && _authStore.user.details != null;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: 'Settings',
                    icon: isLoggedIn
                        ? ProfilePicture(userLogin: _authStore.user.details!.login, radius: 16)
                        : const Icon(Icons.settings_rounded),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Settings(settingsStore: context.read<SettingsStore>())),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Observer(
          builder: (_) => IndexedStack(
            index: _homeStore.selectedIndex,
            children: [
              if (_authStore.isLoggedIn)
                StreamsList(listType: ListType.followed, scrollController: _homeStore.followedScrollController),
              TopSection(homeStore: _homeStore),
              if (_authStore.isLoggedIn)
                Friends(scrollController: _homeStore.friendsScrollController),
              Search(scrollController: _homeStore.searchScrollController),
            ],
          ),
        ),
        bottomNavigationBar: BlurredContainer(
          gradientDirection: GradientDirection.down,
          child: Observer(
            builder: (_) => Theme(
              data: Theme.of(context).copyWith(splashFactory: NoSplash.splashFactory),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                destinations: [
                  if (_authStore.isLoggedIn)
                    NavigationDestination(
                      icon: Icon(
                        Icons.favorite_border_rounded,
                        color: _homeStore.selectedIndex == 0
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      selectedIcon: Icon(Icons.favorite_rounded, color: theme.colorScheme.onSurface),
                      label: 'Following',
                      tooltip: 'Following',
                    ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: _homeStore.selectedIndex == (_authStore.isLoggedIn ? 1 : 0)
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    selectedIcon: Icon(Icons.arrow_upward_rounded, color: theme.colorScheme.onSurface),
                    label: 'Top',
                    tooltip: 'Top',
                  ),
                  if (_authStore.isLoggedIn)
                    NavigationDestination(
                      icon: Icon(
                        Icons.people_outline_rounded,
                        color: _homeStore.selectedIndex == 2
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      selectedIcon: Icon(Icons.people_rounded, color: theme.colorScheme.onSurface),
                      label: 'Friends',
                      tooltip: 'Friends',
                    ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.search_rounded,
                      color: _homeStore.selectedIndex == (_authStore.isLoggedIn ? 3 : 1)
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    selectedIcon: Icon(Icons.search_rounded, color: theme.colorScheme.onSurface),
                    label: 'Search',
                    tooltip: 'Search',
                  ),
                ],
                selectedIndex: _homeStore.selectedIndex,
                onDestinationSelected: _homeStore.handleTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _homeStore.dispose();
    super.dispose();
  }
}

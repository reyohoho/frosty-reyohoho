import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/screens/channel/vods/vod_card.dart';
import 'package:frosty/screens/channel/vods/vod_list_store.dart';
import 'package:frosty/screens/channel/vods/vod_player_screen.dart';
import 'package:frosty/widgets/alert_message.dart';
import 'package:frosty/widgets/blurred_container.dart';
import 'package:frosty/widgets/profile_picture.dart';
import 'package:provider/provider.dart';

/// Screen displaying a list of VODs for a specific user
class VodListScreen extends StatefulWidget {
  final String userId;
  final String userLogin;
  final String displayName;

  const VodListScreen({
    super.key,
    required this.userId,
    required this.userLogin,
    required this.displayName,
  });

  @override
  State<VodListScreen> createState() => _VodListScreenState();
}

class _VodListScreenState extends State<VodListScreen> {
  late final VodListStore _store;
  late final ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _store = VodListStore(
      twitchApi: context.read<TwitchApi>(),
      userId: widget.userId,
      userLogin: widget.userLogin,
      displayName: widget.displayName,
    );
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _store.loadMore();
    }
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _store.clearSearch();
      }
    });
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Sort by',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...VodSortType.values.map(
            (sortType) => Observer(
              builder: (_) => RadioListTile<VodSortType>(
                title: Text(sortType.displayName),
                value: sortType,
                groupValue: _store.sortType,
                onChanged: (value) {
                  if (value != null) {
                    _store.setSortType(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Filter by type',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...VodFilterType.values.map(
            (filterType) => Observer(
              builder: (_) => RadioListTile<VodFilterType>(
                title: Text(filterType.displayName),
                value: filterType,
                groupValue: _store.filterType,
                onChanged: (value) {
                  if (value != null) {
                    _store.setFilterType(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // VOD list content
          Observer(
            builder: (_) {
              if (_store.error != null && _store.videos.isEmpty) {
                return Center(
                  child: AlertMessage(
                    message: 'Failed to load videos',
                    vertical: true,
                  ),
                );
              }

              final videos = _store.filteredVideos;

              if (!_store.isLoading && videos.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.video_library_outlined,
                        size: 64,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _store.searchQuery.isNotEmpty
                            ? 'No videos matching "${_store.searchQuery}"'
                            : 'No videos available',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Header height calculation:
              // - kToolbarHeight (56) for app bar
              // - 48 for filter chips row
              // - 56 for search bar when visible
              // - 8 padding
              final headerHeight = kToolbarHeight + 48 + (_showSearch ? 56 : 0) + 8;

              return RefreshIndicator(
                onRefresh: _store.refresh,
                edgeOffset: MediaQuery.of(context).padding.top + headerHeight,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + headerHeight,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  itemCount: videos.length + (_store.isLoading ? 3 : 0),
                  itemBuilder: (context, index) {
                    if (index >= videos.length) {
                      return const VodCardSkeleton();
                    }

                    final video = videos[index];
                    return VodCard(
                      video: video,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VodPlayerScreen(
                              video: video,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
          // Blurred header with app bar and filter chips
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
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App bar section
                    SizedBox(
                      height: kToolbarHeight,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            icon: Icon(Icons.adaptive.arrow_back_rounded),
                            onPressed: Navigator.of(context).pop,
                          ),
                          ProfilePicture(
                            userLogin: widget.userLogin,
                            radius: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.displayName}\'s Videos',
                              style: theme.textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Search',
                            icon: Icon(
                              _showSearch
                                  ? Icons.search_off_rounded
                                  : Icons.search_rounded,
                            ),
                            onPressed: _toggleSearch,
                          ),
                          IconButton(
                            tooltip: 'Sort',
                            icon: const Icon(Icons.sort_rounded),
                            onPressed: _showSortOptions,
                          ),
                          IconButton(
                            tooltip: 'Filter',
                            icon: const Icon(Icons.filter_list_rounded),
                            onPressed: _showFilterOptions,
                          ),
                        ],
                      ),
                    ),
                    // Search bar (when visible)
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _showSearch
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _store.setSearchQuery,
                          decoration: InputDecoration(
                            hintText: 'Search videos...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      _store.clearSearch();
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      secondChild: const SizedBox.shrink(),
                    ),
                    // Filter chips
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Observer(
                        builder: (_) => Row(
                          children: [
                            FilterChip(
                              label: Text(_store.sortType.displayName),
                              avatar: const Icon(Icons.sort, size: 16),
                              onSelected: (_) => _showSortOptions(),
                              selected: false,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: Text(_store.filterType.displayName),
                              avatar: const Icon(Icons.filter_alt, size: 16),
                              onSelected: (_) => _showFilterOptions(),
                              selected: _store.filterType != VodFilterType.all,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}


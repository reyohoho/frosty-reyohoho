import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/vod.dart';
import 'package:mobx/mobx.dart';

part 'vod_list_store.g.dart';

/// Sort options for VOD list
enum VodSortType {
  time('Newest', 'time'),
  views('Most Viewed', 'views'),
  trending('Trending', 'trending');

  final String displayName;
  final String apiValue;
  const VodSortType(this.displayName, this.apiValue);
}

/// Filter options for VOD type
enum VodFilterType {
  all('All', 'all'),
  archive('Past Broadcasts', 'archive'),
  highlight('Highlights', 'highlight'),
  upload('Uploads', 'upload');

  final String displayName;
  final String apiValue;
  const VodFilterType(this.displayName, this.apiValue);
}

class VodListStore = VodListStoreBase with _$VodListStore;

abstract class VodListStoreBase with Store {
  final TwitchApi twitchApi;
  final String userId;
  final String userLogin;
  final String displayName;

  VodListStoreBase({
    required this.twitchApi,
    required this.userId,
    required this.userLogin,
    required this.displayName,
  }) {
    fetchVideos();
  }

  /// List of fetched videos
  @readonly
  ObservableList<VideoTwitch> _videos = ObservableList<VideoTwitch>();

  /// Current loading state
  @readonly
  var _isLoading = false;

  /// Error message if fetch failed
  @readonly
  String? _error;

  /// Whether there are more videos to load
  @readonly
  var _hasMore = true;

  /// Pagination cursor
  @readonly
  String? _cursor;

  /// Current sort type
  @observable
  VodSortType sortType = VodSortType.time;

  /// Current filter type
  @observable
  VodFilterType filterType = VodFilterType.all;

  /// Search query for filtering videos by title
  @observable
  String searchQuery = '';

  /// Filtered videos based on search query
  @computed
  List<VideoTwitch> get filteredVideos {
    if (searchQuery.isEmpty) {
      return _videos.toList();
    }
    final query = searchQuery.toLowerCase();
    return _videos
        .where((video) => video.title.toLowerCase().contains(query))
        .toList();
  }

  /// Fetches videos from the API
  @action
  Future<void> fetchVideos({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _videos.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    }

    if (!_hasMore && !refresh) return;

    _isLoading = true;
    _error = null;

    try {
      final result = await twitchApi.getVideos(
        userId: userId,
        type: filterType.apiValue,
        sort: sortType.apiValue,
        cursor: _cursor,
        first: 20,
      );

      _videos.addAll(result.data);
      _cursor = result.pagination?['cursor'];
      _hasMore = result.pagination?['cursor'] != null && result.data.isNotEmpty;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
    }
  }

  /// Loads more videos (pagination)
  @action
  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await fetchVideos();
  }

  /// Changes sort type and refreshes
  @action
  Future<void> setSortType(VodSortType newSortType) async {
    if (sortType == newSortType) return;
    sortType = newSortType;
    await fetchVideos(refresh: true);
  }

  /// Changes filter type and refreshes
  @action
  Future<void> setFilterType(VodFilterType newFilterType) async {
    if (filterType == newFilterType) return;
    filterType = newFilterType;
    await fetchVideos(refresh: true);
  }

  /// Updates search query
  @action
  void setSearchQuery(String query) {
    searchQuery = query;
  }

  /// Clears search query
  @action
  void clearSearch() {
    searchQuery = '';
  }

  /// Refreshes the video list
  @action
  Future<void> refresh() async {
    await fetchVideos(refresh: true);
  }
}


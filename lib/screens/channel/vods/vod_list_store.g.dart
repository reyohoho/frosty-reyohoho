// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vod_list_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$VodListStore on VodListStoreBase, Store {
  Computed<List<VideoTwitch>>? _$filteredVideosComputed;

  @override
  List<VideoTwitch> get filteredVideos =>
      (_$filteredVideosComputed ??= Computed<List<VideoTwitch>>(
        () => super.filteredVideos,
        name: 'VodListStoreBase.filteredVideos',
      )).value;

  late final _$_videosAtom = Atom(
    name: 'VodListStoreBase._videos',
    context: context,
  );

  ObservableList<VideoTwitch> get videos {
    _$_videosAtom.reportRead();
    return super._videos;
  }

  @override
  ObservableList<VideoTwitch> get _videos => videos;

  @override
  set _videos(ObservableList<VideoTwitch> value) {
    _$_videosAtom.reportWrite(value, super._videos, () {
      super._videos = value;
    });
  }

  late final _$_isLoadingAtom = Atom(
    name: 'VodListStoreBase._isLoading',
    context: context,
  );

  bool get isLoading {
    _$_isLoadingAtom.reportRead();
    return super._isLoading;
  }

  @override
  bool get _isLoading => isLoading;

  @override
  set _isLoading(bool value) {
    _$_isLoadingAtom.reportWrite(value, super._isLoading, () {
      super._isLoading = value;
    });
  }

  late final _$_errorAtom = Atom(
    name: 'VodListStoreBase._error',
    context: context,
  );

  String? get error {
    _$_errorAtom.reportRead();
    return super._error;
  }

  @override
  String? get _error => error;

  @override
  set _error(String? value) {
    _$_errorAtom.reportWrite(value, super._error, () {
      super._error = value;
    });
  }

  late final _$_hasMoreAtom = Atom(
    name: 'VodListStoreBase._hasMore',
    context: context,
  );

  bool get hasMore {
    _$_hasMoreAtom.reportRead();
    return super._hasMore;
  }

  @override
  bool get _hasMore => hasMore;

  @override
  set _hasMore(bool value) {
    _$_hasMoreAtom.reportWrite(value, super._hasMore, () {
      super._hasMore = value;
    });
  }

  late final _$_cursorAtom = Atom(
    name: 'VodListStoreBase._cursor',
    context: context,
  );

  String? get cursor {
    _$_cursorAtom.reportRead();
    return super._cursor;
  }

  @override
  String? get _cursor => cursor;

  @override
  set _cursor(String? value) {
    _$_cursorAtom.reportWrite(value, super._cursor, () {
      super._cursor = value;
    });
  }

  late final _$sortTypeAtom = Atom(
    name: 'VodListStoreBase.sortType',
    context: context,
  );

  @override
  VodSortType get sortType {
    _$sortTypeAtom.reportRead();
    return super.sortType;
  }

  @override
  set sortType(VodSortType value) {
    _$sortTypeAtom.reportWrite(value, super.sortType, () {
      super.sortType = value;
    });
  }

  late final _$filterTypeAtom = Atom(
    name: 'VodListStoreBase.filterType',
    context: context,
  );

  @override
  VodFilterType get filterType {
    _$filterTypeAtom.reportRead();
    return super.filterType;
  }

  @override
  set filterType(VodFilterType value) {
    _$filterTypeAtom.reportWrite(value, super.filterType, () {
      super.filterType = value;
    });
  }

  late final _$searchQueryAtom = Atom(
    name: 'VodListStoreBase.searchQuery',
    context: context,
  );

  @override
  String get searchQuery {
    _$searchQueryAtom.reportRead();
    return super.searchQuery;
  }

  @override
  set searchQuery(String value) {
    _$searchQueryAtom.reportWrite(value, super.searchQuery, () {
      super.searchQuery = value;
    });
  }

  late final _$fetchVideosAsyncAction = AsyncAction(
    'VodListStoreBase.fetchVideos',
    context: context,
  );

  @override
  Future<void> fetchVideos({bool refresh = false}) {
    return _$fetchVideosAsyncAction.run(
      () => super.fetchVideos(refresh: refresh),
    );
  }

  late final _$loadMoreAsyncAction = AsyncAction(
    'VodListStoreBase.loadMore',
    context: context,
  );

  @override
  Future<void> loadMore() {
    return _$loadMoreAsyncAction.run(() => super.loadMore());
  }

  late final _$setSortTypeAsyncAction = AsyncAction(
    'VodListStoreBase.setSortType',
    context: context,
  );

  @override
  Future<void> setSortType(VodSortType newSortType) {
    return _$setSortTypeAsyncAction.run(() => super.setSortType(newSortType));
  }

  late final _$setFilterTypeAsyncAction = AsyncAction(
    'VodListStoreBase.setFilterType',
    context: context,
  );

  @override
  Future<void> setFilterType(VodFilterType newFilterType) {
    return _$setFilterTypeAsyncAction.run(
      () => super.setFilterType(newFilterType),
    );
  }

  late final _$refreshAsyncAction = AsyncAction(
    'VodListStoreBase.refresh',
    context: context,
  );

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$VodListStoreBaseActionController = ActionController(
    name: 'VodListStoreBase',
    context: context,
  );

  @override
  void setSearchQuery(String query) {
    final _$actionInfo = _$VodListStoreBaseActionController.startAction(
      name: 'VodListStoreBase.setSearchQuery',
    );
    try {
      return super.setSearchQuery(query);
    } finally {
      _$VodListStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void clearSearch() {
    final _$actionInfo = _$VodListStoreBaseActionController.startAction(
      name: 'VodListStoreBase.clearSearch',
    );
    try {
      return super.clearSearch();
    } finally {
      _$VodListStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
sortType: ${sortType},
filterType: ${filterType},
searchQuery: ${searchQuery},
filteredVideos: ${filteredVideos}
    ''';
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friends_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$FriendsStore on FriendsStoreBase, Store {
  Computed<List<ReyohohoFriend>>? _$sortedFriendsComputed;

  @override
  List<ReyohohoFriend> get sortedFriends =>
      (_$sortedFriendsComputed ??= Computed<List<ReyohohoFriend>>(
        () => super.sortedFriends,
        name: 'FriendsStoreBase.sortedFriends',
      )).value;

  late final _$_friendsFutureAtom = Atom(
    name: 'FriendsStoreBase._friendsFuture',
    context: context,
  );

  ObservableFuture<List<ReyohohoFriend>>? get friendsFuture {
    _$_friendsFutureAtom.reportRead();
    return super._friendsFuture;
  }

  @override
  ObservableFuture<List<ReyohohoFriend>>? get _friendsFuture => friendsFuture;

  @override
  set _friendsFuture(ObservableFuture<List<ReyohohoFriend>>? value) {
    _$_friendsFutureAtom.reportWrite(value, super._friendsFuture, () {
      super._friendsFuture = value;
    });
  }

  late final _$fetchAsyncAction = AsyncAction(
    'FriendsStoreBase.fetch',
    context: context,
  );

  @override
  Future<void> fetch() {
    return _$fetchAsyncAction.run(() => super.fetch());
  }

  @override
  String toString() {
    return '''
sortedFriends: ${sortedFriends}
    ''';
  }
}

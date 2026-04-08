import 'package:frosty/apis/reyohoho_api.dart';
import 'package:frosty/models/reyohoho_friend.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:mobx/mobx.dart';

part 'friends_store.g.dart';

class FriendsStore = FriendsStoreBase with _$FriendsStore;

abstract class FriendsStoreBase with Store {
  final AuthStore authStore;
  final ReyohohoApi reyohohoApi;

  FriendsStoreBase({required this.authStore, required this.reyohohoApi});

  @readonly
  ObservableFuture<List<ReyohohoFriend>>? _friendsFuture;

  @computed
  List<ReyohohoFriend> get sortedFriends {
    if (_friendsFuture?.status != FutureStatus.fulfilled) {
      return const [];
    }
    final blocked = authStore.user.blockedUsers.map((u) => u.userId).toSet();
    final list = (_friendsFuture!.result as List<ReyohohoFriend>)
        .where((f) => !blocked.contains(f.twitchId))
        .toList();
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) {
        return a.isOnline ? -1 : 1;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  @action
  Future<void> fetch() async {
    final id = authStore.user.details?.id;
    if (id == null) {
      _friendsFuture = ObservableFuture(Future.value(const <ReyohohoFriend>[]));
      return;
    }
    final future = reyohohoApi.getExtFriends(id);
    _friendsFuture = ObservableFuture(future);
    await future;
  }
}

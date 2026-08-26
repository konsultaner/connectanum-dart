import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';

class ProfileService {
  const ProfileService({required this.store});

  final AccountStore store;

  Future<AccountProfile> get(String username) => store.getProfile(username);

  Future<AccountProfile> update(String username, AccountProfileUpdate update) =>
      store.updateProfile(username, update);
}

import 'package:connectanum_router/auth.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';

class AccountCredentialProvider extends AuthCredentialProvider {
  const AccountCredentialProvider({
    required this.store,
    required this.serviceTicket,
  });

  final AccountStore store;
  final String serviceTicket;

  @override
  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async {
    if (authId != WampAppProtocol.serviceAuthId ||
        (realmUri != WampAppProtocol.registrationRealm &&
            realmUri != WampAppProtocol.appRealm)) {
      return null;
    }
    return TicketCredential(
      ticket: serviceTicket,
      role: WampAppProtocol.serviceRole,
      provider: 'wamp-app-bootstrap',
    );
  }

  @override
  Future<ScramCredential?> loadScram({
    required String realmUri,
    required String authId,
  }) async {
    if (realmUri != WampAppProtocol.appRealm) return null;
    final account = await store.find(authId);
    if (account == null) return null;
    return ScramCredential(
      storedKey: account.storedKey,
      serverKey: account.serverKey,
      salt: account.salt,
      iterations: account.iterations,
      memory: account.memoryKiB,
      kdf: account.kdf,
      role: WampAppProtocol.memberRole,
      provider: 'wamp-app-account-store',
      authExtra: {
        'display_name': account.displayName,
        'created_at': account.createdAt.toIso8601String(),
      },
    );
  }

  @override
  Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async => null;

  @override
  Future<CryptosignCredential?> loadCryptosign({
    required String realmUri,
    required String authId,
  }) async => null;
}

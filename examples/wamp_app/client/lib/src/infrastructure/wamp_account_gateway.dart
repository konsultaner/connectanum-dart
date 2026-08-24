import 'package:connectanum_client/connectanum.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

abstract interface class AccountGateway {
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  });

  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  });
}

class AccountConnection {
  AccountConnection({
    required this.endpoint,
    required this.username,
    required this.displayName,
    required this.closeTransport,
  });

  final ServerEndpoint endpoint;
  final String username;
  final String displayName;
  final Future<void> Function() closeTransport;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await closeTransport();
  }
}

class WampAccountGateway implements AccountGateway {
  const WampAccountGateway({
    this.connectionTimeout = const Duration(seconds: 15),
    this.derivationTimeout = const Duration(seconds: 75),
  });

  final Duration connectionTimeout;
  final Duration derivationTimeout;

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) async {
    endpoint.requireSecureRegistration();
    registration.validate();
    final client = Client(
      transport: WebSocketTransport.withCborSerializer(
        endpoint.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    Session? session;
    try {
      session = await _connect(client);
      final result = await session
          .callSingle(
            WampAppProtocol.accountRegister,
            argumentsKeywords: registration.toWampKeywords(),
          )
          .timeout(connectionTimeout);
      return RegistrationReceipt.fromWampKeywords(result.argumentsKeywords);
    } finally {
      await _close(client, session);
    }
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    endpoint.requireSecureRegistration();
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    final authentication = ScramAuthentication(
      password,
      derivationTimeout: derivationTimeout,
      challengeTimeout: connectionTimeout + derivationTimeout,
    );
    final client = Client(
      transport: WebSocketTransport.withCborSerializer(
        endpoint.websocketUri.toString(),
      ),
      realm: WampAppProtocol.appRealm,
      authId: normalizedUsername,
      authenticationMethods: [authentication],
    );
    try {
      final session = await _connect(client);
      final displayName = session.authExtra?['display_name'];
      return AccountConnection(
        endpoint: endpoint,
        username: session.authId ?? normalizedUsername,
        displayName: displayName is String ? displayName : normalizedUsername,
        closeTransport: () async {
          try {
            await _close(client, session);
          } finally {
            await authentication.dispose();
          }
        },
      );
    } catch (_) {
      try {
        await client.disconnect();
      } finally {
        await authentication.dispose();
      }
      rethrow;
    }
  }

  Future<Session> _connect(Client client) {
    return client
        .connect(
          options: ClientConnectOptions(
            reconnectCount: 0,
            reconnectTime: const Duration(milliseconds: 100),
          ),
        )
        .first
        .timeout(connectionTimeout + derivationTimeout);
  }

  Future<void> _close(Client client, Session? session) async {
    if (session != null && session.isConnected()) {
      await session.close(timeout: Duration.zero);
    }
    await client.disconnect();
  }
}

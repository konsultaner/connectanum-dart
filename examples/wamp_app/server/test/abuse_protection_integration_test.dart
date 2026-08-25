import 'dart:io';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test('real router enforces registration and per-account budgets', () async {
    final directory = await Directory.systemTemp.createTemp('wamp-app-abuse-');
    addTearDown(() => directory.delete(recursive: true));
    final server = await WampAppServer.start(
      WampAppServerConfig(
        host: '127.0.0.1',
        port: 0,
        websocketPath: '/ws',
        accountStorePath: '${directory.path}/accounts.json',
        messageStorePath: '${directory.path}/messages.json',
        backupStorePath: '${directory.path}/backups',
        abuseProtection: const WampAppAbuseProtectionConfig(
          registration: WampAppRateLimitPolicy(
            maxRequests: 2,
            window: Duration(minutes: 1),
            maxConcurrent: 2,
          ),
          controlGlobal: WampAppRateLimitPolicy(
            maxRequests: 100,
            window: Duration(minutes: 1),
            maxConcurrent: 10,
          ),
          controlPerAccount: WampAppRateLimitPolicy(
            maxRequests: 1,
            window: Duration(minutes: 1),
            maxConcurrent: 2,
          ),
          transferGlobal: WampAppRateLimitPolicy(
            maxRequests: 100,
            window: Duration(minutes: 1),
            maxConcurrent: 10,
          ),
          transferPerAccount: WampAppRateLimitPolicy(
            maxRequests: 1,
            window: Duration(minutes: 1),
            maxConcurrent: 2,
          ),
        ),
        argonIterations: 2,
        argonMemoryKiB: 8192,
      ),
    );
    addTearDown(server.close);

    final registrationClient = Client(
      transport: WebSocketTransport.withCborSerializer(
        server.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    addTearDown(registrationClient.disconnect);
    final registrationSession = await registrationClient
        .connect(options: _singleAttempt)
        .first
        .timeout(const Duration(seconds: 15));
    addTearDown(() => registrationSession.close(timeout: Duration.zero));

    await _register(registrationSession, 'alice', 'correct horse battery');
    await _register(registrationSession, 'bob', 'another correct horse');
    await _expectRateLimited(
      registrationSession.callSingle(
        WampAppProtocol.accountRegister,
        argumentsKeywords: AccountRegistration(
          username: 'charlie',
          displayName: 'Charlie Example',
          password: 'a third correct horse',
        ).toWampKeywords(),
      ),
    );

    final alice = await _connectMember(
      server.websocketUri,
      'alice',
      'correct horse battery',
    );
    addTearDown(alice.close);
    final bob = await _connectMember(
      server.websocketUri,
      'bob',
      'another correct horse',
    );
    addTearDown(bob.close);

    await alice.session.callSingle(WampAppProtocol.deviceList);
    await _expectRateLimited(
      alice.session.callSingle(WampAppProtocol.deviceList),
    );
    await bob.session.callSingle(WampAppProtocol.deviceList);

    await expectLater(
      alice.session.callSingle(WampAppProtocol.backupMetadataGet),
      throwsA(
        isA<Error>().having(
          (error) => error.error,
          'error URI',
          WampAppProtocol.errorBackupNotFound,
        ),
      ),
    );
    await _expectRateLimited(
      alice.session.callSingle(WampAppProtocol.backupMetadataGet),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _register(
  Session session,
  String username,
  String password,
) async {
  await session.callSingle(
    WampAppProtocol.accountRegister,
    argumentsKeywords: AccountRegistration(
      username: username,
      displayName: '$username Example',
      password: password,
    ).toWampKeywords(),
  );
}

Future<void> _expectRateLimited(Future<Result> call) async {
  try {
    await call;
    fail('Expected the WAMP call to be rate limited.');
  } on Error catch (error) {
    expect(error.error, WampAppProtocol.errorRateLimited);
    expect(error.arguments, ['Too many requests. Retry later.']);
    expect(error.argumentsKeywords?['retry_after_ms'], isA<int>());
    expect(error.argumentsKeywords?['retry_after_ms'], greaterThan(0));
  }
}

Future<_MemberConnection> _connectMember(
  Uri websocketUri,
  String username,
  String password,
) async {
  final authentication = ScramAuthentication(
    password,
    derivationTimeout: const Duration(seconds: 30),
  );
  final client = Client(
    transport: WebSocketTransport.withCborSerializer(websocketUri.toString()),
    realm: WampAppProtocol.appRealm,
    authId: username,
    authenticationMethods: [authentication],
  );
  try {
    final session = await client
        .connect(options: _singleAttempt)
        .first
        .timeout(const Duration(seconds: 45));
    return _MemberConnection(client, session, authentication);
  } catch (_) {
    await client.disconnect();
    await authentication.dispose();
    rethrow;
  }
}

final class _MemberConnection {
  _MemberConnection(this.client, this.session, this.authentication);

  final Client client;
  final Session session;
  final ScramAuthentication authentication;

  Future<void> close() async {
    await session.close(timeout: Duration.zero);
    await client.disconnect();
    await authentication.dispose();
  }
}

final _singleAttempt = ClientConnectOptions(
  reconnectCount: 0,
  reconnectTime: const Duration(milliseconds: 100),
);

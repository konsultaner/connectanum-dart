import 'dart:io';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test('anonymous registration provisions a verifiable SCRAM account', () async {
    final directory = await Directory.systemTemp.createTemp('wamp-app-smoke-');
    addTearDown(() => directory.delete(recursive: true));
    final accountFile = File('${directory.path}/accounts.json');
    late final WampAppServer server;
    try {
      server = await WampAppServer.start(
        WampAppServerConfig(
          host: '127.0.0.1',
          port: 0,
          websocketPath: '/ws',
          accountStorePath: accountFile.path,
          argonIterations: 2,
          argonMemoryKiB: 8192,
        ),
      );
    } on Abort catch (abort) {
      fail(
        'Server bootstrap aborted: ${abort.reason} '
        '${abort.message?.message ?? abort.arguments ?? abort.argumentsKeywords ?? ''}',
      );
    }
    addTearDown(server.close);

    final registrationClient = Client(
      transport: WebSocketTransport.withCborSerializer(
        server.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    late final Session registrationSession;
    try {
      registrationSession = await registrationClient
          .connect(options: _singleAttempt)
          .first
          .timeout(const Duration(seconds: 15));
    } on Abort catch (abort) {
      fail(
        'Registration connection aborted: ${abort.reason} '
        '${abort.message?.message ?? abort.arguments ?? abort.argumentsKeywords ?? ''}',
      );
    }
    final result = await registrationSession.callSingle(
      WampAppProtocol.accountRegister,
      argumentsKeywords: AccountRegistration(
        username: 'alice',
        displayName: 'Alice Example',
        password: 'correct horse battery',
      ).toWampKeywords(),
    );
    final receipt = RegistrationReceipt.fromWampKeywords(
      result.argumentsKeywords,
    );
    expect(receipt.username, 'alice');
    await expectLater(
      registrationSession.callSingle(
        WampAppProtocol.accountRegister,
        argumentsKeywords: AccountRegistration(
          username: 'alice',
          displayName: 'Alice Duplicate',
          password: 'another correct horse',
        ).toWampKeywords(),
      ),
      throwsA(
        isA<Error>().having(
          (error) => error.error,
          'error URI',
          WampAppProtocol.errorUsernameTaken,
        ),
      ),
    );
    await registrationSession.close(timeout: Duration.zero);
    await registrationClient.disconnect();

    final authentication = ScramAuthentication(
      'correct horse battery',
      derivationTimeout: const Duration(seconds: 30),
    );
    addTearDown(authentication.dispose);
    final appClient = Client(
      transport: WebSocketTransport.withCborSerializer(
        server.websocketUri.toString(),
      ),
      realm: WampAppProtocol.appRealm,
      authId: 'alice',
      authenticationMethods: [authentication],
    );
    late final Session appSession;
    try {
      appSession = await appClient
          .connect(options: _singleAttempt)
          .first
          .timeout(const Duration(seconds: 45));
    } on Abort catch (abort) {
      fail(
        'SCRAM connection aborted: ${abort.reason} '
        '${abort.message?.message ?? abort.arguments ?? abort.argumentsKeywords ?? ''}',
      );
    }
    expect(appSession.authId, 'alice');
    expect(appSession.authRole, WampAppProtocol.memberRole);
    expect(appSession.authExtra?['display_name'], 'Alice Example');
    await appSession.close(timeout: Duration.zero);
    await appClient.disconnect();

    final storedDocument = await accountFile.readAsString();
    expect(storedDocument, isNot(contains('correct horse battery')));
    expect(storedDocument, contains('stored_key'));
    expect(storedDocument, contains('server_key'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

final _singleAttempt = ClientConnectOptions(
  reconnectCount: 0,
  reconnectTime: Duration(milliseconds: 100),
);

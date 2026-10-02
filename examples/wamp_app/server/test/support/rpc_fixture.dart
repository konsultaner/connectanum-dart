import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

final class RpcFixture {
  RpcFixture._(this.directory, this.server);

  final Directory directory;
  final WampAppServer server;

  static Future<RpcFixture> start() async {
    final directory = await Directory.systemTemp.createTemp('wamp-rpc-');
    addTearDown(() => directory.delete(recursive: true));
    final server = await WampAppServer.start(
      WampAppServerConfig(
        host: '127.0.0.1',
        port: 0,
        websocketPath: '/ws',
        accountStorePath: '${directory.path}/accounts.json',
        messageStorePath: '${directory.path}/messages.json',
        backupStorePath: '${directory.path}/backups',
        attachmentStorePath: '${directory.path}/attachments',
        argonIterations: 2,
        argonMemoryKiB: 8192,
      ),
    );
    addTearDown(server.close);
    final client = wamp.Client(
      transport: wamp.WebSocketTransport.withCborSerializer(
        server.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    addTearDown(client.disconnect);
    final session = await client
        .connect(options: _singleAttempt)
        .first
        .timeout(const Duration(seconds: 15));
    addTearDown(() => session.close(timeout: Duration.zero));
    for (final username in ['alice', 'bob', 'charlie']) {
      await session.callSingle(
        WampAppProtocol.accountRegister,
        argumentsKeywords: AccountRegistration(
          username: username,
          displayName: username,
          password: _password,
        ).toWampKeywords(),
      );
    }
    await session.close(timeout: Duration.zero);
    await client.disconnect();
    return RpcFixture._(directory, server);
  }

  Future<RpcPeer> connect(String username, int seed) async {
    final authentication = wamp.ScramAuthentication(_password);
    addTearDown(authentication.dispose);
    final client = wamp.Client(
      transport: wamp.WebSocketTransport.withCborSerializer(
        server.websocketUri.toString(),
      ),
      realm: WampAppProtocol.appRealm,
      authId: username,
      authenticationMethods: [authentication],
    );
    addTearDown(client.disconnect);
    final session = await client
        .connect(options: _singleAttempt)
        .first
        .timeout(const Duration(seconds: 45));
    addTearDown(() => session.close(timeout: Duration.zero));
    final key = SigningKey.fromSeed(
      Uint8List.fromList(List<int>.filled(32, seed)),
    );
    final signing = key.verifyKey.asTypedList;
    final exchange = List<int>.filled(32, seed + 10);
    final deviceId = encodeToken(
      sha256.convert([...signing, ...exchange]).bytes,
    );
    final createdAt = DateTime.now().toUtc();
    final payload = DeviceEnrollment.attestationPayloadFor(
      username: username,
      deviceId: deviceId,
      deviceName: '$username test device',
      signingPublicKey: encodeToken(signing),
      exchangePublicKey: encodeToken(exchange),
      createdAt: createdAt,
    );
    final peer = RpcPeer(username, session, key, deviceId);
    final enrolled = DeviceRecord.fromWampKeywords(
      await peer.call(
        WampAppProtocol.deviceEnroll,
        DeviceEnrollment(
          deviceId: deviceId,
          deviceName: '$username test device',
          signingPublicKey: encodeToken(signing),
          exchangePublicKey: encodeToken(exchange),
          attestation: peer.sign(payload),
          createdAt: createdAt,
        ).toWampKeywords(),
      ),
    );
    expect(enrolled.username, username);
    expect(enrolled.deviceId, deviceId);
    return peer;
  }
}

final class RpcPeer {
  RpcPeer(this.username, this.session, this.key, this.deviceId);

  final String username;
  final wamp.Session session;
  final SigningKey key;
  final String deviceId;

  Future<Map<String, dynamic>> call(
    String procedure, [
    Map<String, dynamic>? keywords,
  ]) async =>
      (await session
              .callSingle(procedure, argumentsKeywords: keywords)
              .timeout(const Duration(seconds: 10)))
          .argumentsKeywords!;

  String sign(List<int> bytes) =>
      encodeToken(key.sign(Uint8List.fromList(bytes)).signature.asTypedList);
}

Future<void> expectRpcError(Future<Object?> call, String uri) => expectLater(
  call,
  throwsA(
    isA<wamp.Error>()
        .having((error) => error.error, 'WAMP error URI', uri)
        .having((error) => error.arguments, 'bounded public message', [
          isA<String>().having(
            (message) => message.length,
            'length',
            inInclusiveRange(1, 200),
          ),
        ]),
  ),
);

String encodeToken(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
String token(int count, int seed) => encodeToken(List<int>.filled(count, seed));

const _password = 'test-only correct horse battery';
final _singleAttempt = wamp.ClientConnectOptions(
  reconnectCount: 0,
  reconnectTime: Duration.zero,
);

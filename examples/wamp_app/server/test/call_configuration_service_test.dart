import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test('issues account-bound expiring coturn REST credentials', () {
    final now = DateTime.utc(2026, 8, 25, 10);
    final service = CallConfigurationService(
      stunUrls: const ['stun:stun.example.net:3478'],
      turnRest: TurnRestConfig(
        urls: const ['turns:turn.example.net:5349?transport=tcp'],
        sharedSecret: 'test-secret',
        credentialTtl: const Duration(minutes: 15),
      ),
    );

    final configuration = service.forAccount('Alice', now: now);
    final turn = configuration.iceServers.last;
    final expectedUsername =
        '${now.add(const Duration(minutes: 15)).millisecondsSinceEpoch ~/ 1000}:'
        'alice';
    final expectedCredential = base64.encode(
      Hmac(
        sha1,
        utf8.encode('test-secret'),
      ).convert(utf8.encode(expectedUsername)).bytes,
    );

    expect(configuration.iceServers, hasLength(2));
    expect(turn.username, expectedUsername);
    expect(turn.credential, expectedCredential);
    expect(configuration.expiresAt, now.add(const Duration(minutes: 15)));
  });

  test('static or host-only ICE configuration remains valid', () {
    final now = DateTime.utc(2026, 8, 25, 10);
    final staticOnly = CallConfigurationService(
      stunUrls: const ['stun:stun.example.net:3478'],
    ).forAccount('alice', now: now);
    final hostOnly = CallConfigurationService().forAccount('alice', now: now);

    expect(staticOnly.iceServers.single.username, isNull);
    expect(hostOnly.iceServers, isEmpty);
    expect(hostOnly.expiresAt, now.add(const Duration(hours: 1)));
  });
}

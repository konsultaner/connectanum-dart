import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('defaults host-only addresses to secure websocket /ws', () {
    final endpoint = ServerEndpoint.parse('chat.example.com');

    expect(endpoint.websocketUri, Uri.parse('wss://chat.example.com/ws'));
    endpoint.requireSecureRegistration();
  });

  test('maps HTTPS paths to WSS', () {
    final endpoint = ServerEndpoint.parse('https://chat.example.com/wamp');

    expect(endpoint.websocketUri, Uri.parse('wss://chat.example.com/wamp'));
  });

  test('permits cleartext registration only on loopback', () {
    ServerEndpoint.parse('ws://127.0.0.1:8080/ws').requireSecureRegistration();
    expect(
      () => ServerEndpoint.parse(
        'ws://chat.example.com/ws',
      ).requireSecureRegistration(),
      throwsFormatException,
    );
  });
}

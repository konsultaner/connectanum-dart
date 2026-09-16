import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test(
    'rejects empty, malformed, credentialed and non-WebSocket endpoints',
    () {
      for (final input in [
        '',
        '   ',
        'https://',
        'wss://[',
        'wss://user@example.com/ws',
        'ftp://example.com/ws',
        'wss://example.com/ws?token=not-accepted',
        'wss://example.com/ws#fragment',
      ]) {
        expect(
          () => ServerEndpoint.parse(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );

  test('normalizes each supported scheme and all loopback host forms', () {
    for (final scheme in ['ws', 'wss', 'http', 'https']) {
      for (final host in ['localhost', '127.0.0.1', '[::1]']) {
        final endpoint = ServerEndpoint.parse(' $scheme://$host/ ');
        expect(endpoint.websocketUri.path, '/ws');
        expect(endpoint.isLoopback, isTrue);
        expect(endpoint.isSecure, scheme == 'wss' || scheme == 'https');
        endpoint.requireSecureRegistration();
      }
    }
  });

  test('defaults host-only addresses to secure websocket /ws', () {
    final endpoint = ServerEndpoint.parse('chat.example.com');

    expect(endpoint.websocketUri, Uri.parse('wss://chat.example.com/ws'));
    endpoint.requireSecureRegistration();
  });

  test('maps HTTPS paths to WSS', () {
    final endpoint = ServerEndpoint.parse('https://chat.example.com/wamp');

    expect(endpoint.websocketUri, Uri.parse('wss://chat.example.com/wamp'));
    expect(endpoint.toString(), 'wss://chat.example.com/wamp');
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

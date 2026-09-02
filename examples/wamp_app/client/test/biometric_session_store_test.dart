import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/biometric_session_store_contract.dart';

void main() {
  test('remembered login round-trips and can be cleared from memory', () {
    final login = RememberedLogin(
      serverAddress: 'wss://chat.example/ws',
      username: 'alice',
      password: 'correct horse battery staple',
    );

    final decoded = RememberedLogin.decode(login.encode());

    expect(decoded.serverAddress, 'wss://chat.example/ws');
    expect(decoded.username, 'alice');
    expect(decoded.password, 'correct horse battery staple');
    decoded.dispose();
    expect(decoded.password, isEmpty);
    login.dispose();
    expect(login.password, isEmpty);
  });

  test('remembered login rejects malformed and unbounded secrets', () {
    expect(
      () => RememberedLogin.decode('{"username":"alice"}'),
      throwsFormatException,
    );
    expect(
      () => RememberedLogin(
        serverAddress: 'wss://chat.example/ws',
        username: 'alice',
        password: '',
      ),
      throwsFormatException,
    );
    expect(
      () => RememberedLogin(
        serverAddress: 'wss://chat.example/ws',
        username: 'alice',
        password: List.filled(
          RememberedLogin.maxPasswordLength + 1,
          'x',
        ).join(),
      ),
      throwsFormatException,
    );
  });
}

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('normalizes and round-trips account registration', () {
    final registration = AccountRegistration(
      username: ' Alice.Example ',
      password: 'a sufficiently long password',
      displayName: ' Alice ',
    );

    final decoded = AccountRegistration.fromWampKeywords(
      registration.toWampKeywords(),
    );

    expect(decoded.username, 'alice.example');
    expect(decoded.displayName, 'Alice');
    expect(decoded.password, 'a sufficiently long password');
  });

  test('rejects weak passwords and malformed usernames', () {
    expect(
      () => AccountRegistration(
        username: 'No Spaces',
        password: 'short',
        displayName: 'No Spaces',
      ).validate(),
      throwsFormatException,
    );
  });
}

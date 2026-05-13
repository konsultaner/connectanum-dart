import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

import '../../fixtures/cryptosign_keys.dart';

void main() {
  group('Local transport authentication test', () {
    test('success', () async {
      var authentication = CryptosignAuthentication.fromPuttyPrivateKey(
        MockCryptosignKey.ed25519Ppk.value,
      );
      var client = Client(
        realm: "com.connectanum",
        authenticationMethods: [authentication],
        authId: "Burkhardt",
        transport: LocalTransport(authenticationKey: authentication.privateKey),
      );
      var session = await client.connect().first;
      expect(session, isNotNull);
    });
    test('fail', () async {
      var client = Client(
        realm: "com.connectanum",
        authenticationMethods: [
          CryptosignAuthentication.fromPuttyPrivateKey(
            MockCryptosignKey.ed25519Ppk.value,
          ),
        ],
        authId: "Burkhardt",
        transport: LocalTransport(),
      );
      AbstractMessage? errorMessage;
      Session? session;
      try {
        session = await client.connect().first;
      } catch (error) {
        errorMessage = error as AbstractMessage;
      }
      expect(session, isNull);
      expect(errorMessage, isNotNull);
    });
  });
}

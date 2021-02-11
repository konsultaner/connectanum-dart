
import 'package:connectanum/src/authentication/cryptosign_authentication.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:test/test.dart';

void main() {
  group('CRYPTOSIGN', () {
    var publicKey = 'AAAAII1JdneHIXoCtfASzKujUSGgiquwMklqA8sO25cKIzzU';
    var challenge = '???';
    var signature = '???';

    test('message handling', () async {
      final authMethod = CryptosignAuthentication.fromRawBase64(publicKey);
      expect(authMethod.getName(), equals('cryptosign'));
      var extra = Extra(challenge: challenge, channel_binding: 'null');
      final authenticate = await authMethod.challenge(extra);
      expect(authenticate.signature, equals(signature));
    });
  });
}

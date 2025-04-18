import 'package:connectanum/connectanum.dart';
import 'package:test/test.dart';

void main() {
  group('Local transport authentication test', () {
    test('success', () async {
      var client = Client(
          realm: "com.connectanum",
          authId: "Burkhardt",
          transport: LocalTransport()
      );
      var session = await client
          .connect()
          .first;
      expect(session, isNotNull);
    });
  });
}
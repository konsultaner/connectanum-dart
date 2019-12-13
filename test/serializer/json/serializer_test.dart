import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/details.dart';
import 'package:connectanum_dart/src/message/hello.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/serializer/json/serializer.dart';
import 'package:test/test.dart';

void main() {
  Serializer serializer = new Serializer();
  group('serialize', () {
    test('Hello', () => {
      expect(serializer.serialize(new Hello("my.realm", Details.forHello())), startsWith('[1,"my.realm",'))
      // TODO test details
    });
    test('Authenticate', () => {
      expect(serializer.serialize(new Authenticate()), equals('[${MessageTypes.CODE_AUTHENTICATE},"",{}]'))
    });
  });
  group('unserialize', () {

  });
}
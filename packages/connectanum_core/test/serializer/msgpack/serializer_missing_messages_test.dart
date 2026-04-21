import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
import 'package:test/test.dart';

void main() {
  final serializer = Serializer();

  group('msgpack serializer router message coverage', () {
    test('serializes result payloads for RPC replies', () {
      final encoded = serializer.serialize(
        Result(
          9001,
          ResultDetails(progress: false, custom: {'path': 'bench.rpc.echo'}),
          arguments: const ['payload'],
          argumentsKeywords: const {'ok': true},
        ),
      );

      expect(
        msgpack_dart.deserialize(encoded),
        equals([
          MessageTypes.codeResult,
          9001,
          {'progress': false, 'path': 'bench.rpc.echo'},
          ['payload'],
          {'ok': true},
        ]),
      );
    });

    test('serializes interrupt frames for cancellation forwarding', () {
      final encoded = serializer.serialize(
        Interrupt(
          77,
          options: InterruptOptions()..mode = CancelOptions.modeKillNoWait,
        ),
      );

      expect(
        msgpack_dart.deserialize(encoded),
        equals([
          MessageTypes.codeInterrupt,
          77,
          {'mode': CancelOptions.modeKillNoWait},
        ]),
      );
    });

    test('serializes welcome details with realm and auth metadata', () {
      final encoded = serializer.serialize(
        Welcome(
          4242,
          Details.forWelcome(
            realm: 'test.realm',
            authId: 'native-user',
            authMethod: 'ticket',
            authProvider: 'native-router',
            authRole: 'client',
          ),
        ),
      );

      expect(msgpack_dart.deserialize(encoded), isA<List<dynamic>>());
      final frame = msgpack_dart.deserialize(encoded) as List<dynamic>;
      expect(frame[0], MessageTypes.codeWelcome);
      expect(frame[1], 4242);
      final details = frame[2] as Map<dynamic, dynamic>;
      expect(details['realm'], 'test.realm');
      expect(details['authid'], 'native-user');
      expect(details['authmethod'], 'ticket');
      expect(details['authprovider'], 'native-router');
      expect(details['authrole'], 'client');
      expect(details['roles'], isA<Map<dynamic, dynamic>>());
      final roles = details['roles'] as Map<dynamic, dynamic>;
      expect(roles.keys, containsAll(['broker', 'dealer']));
    });
  });
}

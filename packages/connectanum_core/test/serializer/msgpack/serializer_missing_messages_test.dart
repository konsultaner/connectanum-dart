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
  });
}

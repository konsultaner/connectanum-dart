import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:test/test.dart';

void main() {
  final codec = flat.Serializer();
  const feature = '_connectanum_flatbuffers_metadata_v1';

  test('metadata access preserves unknown role features and current edits', () {
    final hello = core.Hello('realm', core.Details.forHello());
    codec.retainMetadataValues(hello, {
      'agent': 'original',
      'roles': {
        'caller': {
          'features': {feature: true, 'call_timeout': true},
        },
      },
      'x_vendor': {
        'bytes': Uint8List.fromList([7, 8]),
      },
    });
    hello.details.agent = 'updated';
    final decoded = codec.deserialize(codec.serialize(hello))!;
    final dictionary = codec.metadataFor(decoded);
    expect(dictionary['agent'], 'updated');
    expect(dictionary['roles']['caller']['features'][feature], isTrue);

    dictionary['roles']['caller']['features'][feature] = false;
    (dictionary['x_vendor']['bytes'] as Uint8List)[0] = 99;
    final fresh = codec.metadataFor(decoded);
    expect(fresh['roles']['caller']['features'][feature], isTrue);
    expect(fresh['x_vendor']['bytes'], [7, 8]);
  });

  test('metadata access and updates never read application vectors', () {
    final call = core.Call(1, 'com.proc');
    final encoded = Uint8List.fromList([0x81, 1]);
    var reads = 0;
    call.setLazyPayload(
      argumentsBytes: encoded,
      argumentsDecoder: (_) {
        reads++;
        throw StateError('Application payload was decoded');
      },
      encoding: core.LazyPayloadEncoding.cbor,
    );
    final metadata = codec.metadataFor(call)..['x_vendor'] = true;
    codec.retainMetadataValues(call, metadata);
    expect(codec.metadataFor(call)['x_vendor'], isTrue);
    expect(identical(call.debugEncodedArgumentsBytes, encoded), isTrue);
    expect(reads, 0);
  });

  test('metadata updates reject over-budget and cyclic input', () {
    final hello = core.Hello('realm', core.Details.forHello());
    expect(
      () => codec.retainMetadataValues(hello, {'x': Uint8List(1048577)}),
      throwsArgumentError,
    );
    final cyclic = <String, dynamic>{};
    cyclic['x'] = cyclic;
    expect(
      () => codec.retainMetadataValues(hello, cyclic),
      throwsArgumentError,
    );
    expect(codec.metadataFor(hello).containsKey('x'), isFalse);
  });
}

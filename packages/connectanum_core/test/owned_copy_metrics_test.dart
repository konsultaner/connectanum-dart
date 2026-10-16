import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/src/message/ppt_copy_metrics.dart';
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';

class _UnreadableBytes extends ListBase<int> {
  @override
  int get length => 3;
  @override
  set length(int _) => throw UnsupportedError('fixed');
  @override
  int operator [](int _) => throw StateError('unreadable');
  @override
  void operator []=(int _, int value) => throw UnsupportedError('fixed');
}

class _DelegatingAllocator extends fb.Allocator {
  final _delegate = const fb.DefaultAllocator();
  @override
  ByteData allocate(int size) => _delegate.allocate(size);
  @override
  void deallocate(ByteData data) => _delegate.deallocate(data);
  @override
  ByteData resize(ByteData data, int size, int back, int front) =>
      _delegate.resize(data, size, back, front);
}

void main() {
  Map<String, int> delta(void Function() operation) {
    final before = OwnedCopyMetrics.snapshot()!;
    operation();
    final after = OwnedCopyMetrics.snapshot()!;
    return {for (final key in before.keys) key: after[key]! - before[key]!};
  }

  setUpAll(() {
    expect(OwnedCopyMetrics.snapshot(), isNull);
    expect(OwnedCopyMetrics.copyBytes([1, 2]), [1, 2]);
    expect(OwnedCopyMetrics.snapshot(), isNull);
    OwnedCopyMetrics.enable();
  });

  test('clone records exact logical bytes and keeps independent storage', () {
    final input = Uint8List.fromList([1, 2, 3]);
    final observed = delta(() {
      final copy = OwnedCopyMetrics.copyBytes(input);
      copy[0] = 9;
      expect(input[0], 1);
    });
    expect(observed['clone_copy_bytes'], 3);
    expect(observed.values.reduce((a, b) => a + b), 3);
  });

  test('failed clones do not invent a completed copy', () {
    final before = OwnedCopyMetrics.snapshot();
    expect(
      () => OwnedCopyMetrics.copyBytes(_UnreadableBytes()),
      throwsStateError,
    );
    final after = OwnedCopyMetrics.snapshot()!;
    expect(after['clone_copy_bytes'], before!['clone_copy_bytes']);
    expect(
      after['failed_copy_operations'],
      before['failed_copy_operations']! + 1,
    );
  });

  test('a failed cast clone reports an unmeasured prefix instead of zero', () {
    final malformed = <dynamic>[1, 2, 'invalid'].cast<int>();
    final observed = delta(() {
      expect(
        () => OwnedCopyMetrics.copyBytes(malformed),
        throwsA(isA<TypeError>()),
      );
    });
    expect(observed['clone_copy_bytes'], 0);
    expect(observed['failed_copy_operations'], 1);
  });

  test('nested exclusion restores recording after exceptions', () {
    final observed = delta(() {
      expect(
        () => OwnedCopyMetrics.withoutRecording(() {
          OwnedCopyMetrics.copyBytes([1, 2]);
          OwnedCopyMetrics.withoutRecording(
            () => OwnedCopyMetrics.copyBytes([3]),
          );
          throw StateError('PPT failure');
        }),
        throwsStateError,
      );
      OwnedCopyMetrics.copyBytes([4]);
    });
    expect(observed['clone_copy_bytes'], 1);
  });

  test('snapshots cannot mutate counters and enable does not reset them', () {
    OwnedCopyMetrics.record(OwnedCopyKind.framing, 4);
    final before = OwnedCopyMetrics.snapshot()!;
    final modified = OwnedCopyMetrics.snapshot()!;
    modified['framing_copy_bytes'] = -100;
    OwnedCopyMetrics.enable();
    expect(OwnedCopyMetrics.snapshot(), before);
    expect(
      () => OwnedCopyMetrics.record(OwnedCopyKind.clone, -1),
      throwsArgumentError,
    );
  });

  test('one typed chunk retains its exact bounded span without a copy', () {
    final input = Uint8List.sublistView(Uint8List.fromList([8, 1, 2, 9]), 1, 3);
    final builder = CopyAwareBytesBuilder();
    final observed = delta(() {
      builder.add(input);
      expect(builder.length, 2);
      expect(identical(builder.takeBytes(), input), isTrue);
      expect(builder.isEmpty, isTrue);
    });
    expect(observed.values.every((value) => value == 0), isTrue);
  });

  test('two chunks copy once each and take clears the builder', () {
    final builder = CopyAwareBytesBuilder();
    final observed = delta(() {
      builder
        ..add(Uint8List.fromList([1, 2]))
        ..add(Uint8List.fromList([3]));
      expect(builder.takeBytes(), [1, 2, 3]);
      expect(builder.length, 0);
      expect(builder.takeBytes(), isEmpty);
    });
    expect(observed['coalescing_copy_bytes'], 3);
    expect(observed['clone_copy_bytes'], 0);
  });

  test('untyped add clones before coalescing and truncates byte values', () {
    final builder = CopyAwareBytesBuilder();
    final observed = delta(() {
      builder
        ..add([256, -1])
        ..addByte(258);
      expect(builder.takeBytes(), [0, 255, 2]);
    });
    expect(observed['clone_copy_bytes'], 2);
    expect(observed['coalescing_copy_bytes'], 3);
  });

  test('toBytes copies a single span on each call without consuming it', () {
    final input = Uint8List.fromList([1, 2]);
    final builder = CopyAwareBytesBuilder()..add(input);
    final observed = delta(() {
      final first = builder.toBytes();
      first[0] = 9;
      expect(builder.toBytes(), [1, 2]);
      expect(builder.isNotEmpty, isTrue);
      expect(identical(builder.takeBytes(), input), isTrue);
    });
    expect(observed['coalescing_copy_bytes'], 4);
  });

  test('empty chunks do not force a typed span to copy', () {
    final span = Uint8List.fromList([7]);
    final builder = CopyAwareBytesBuilder();
    final observed = delta(() {
      builder
        ..add([])
        ..add(Uint8List(0))
        ..add(span)
        ..add([]);
      expect(identical(builder.takeBytes(), span), isTrue);
      expect(builder.takeBytes(), isEmpty);
      builder
        ..addByte(4)
        ..clear();
      expect(builder.toBytes(), isEmpty);
    });
    expect(observed.values.every((value) => value == 0), isTrue);
  });

  for (final entry in <String, AbstractSerializer>{
    'cbor': cbor.Serializer(),
    'msgpack': msgpack.Serializer(),
    'json': json.Serializer(),
    'flatbuffers': flatbuffers.Serializer(),
  }.entries) {
    test(
      '${entry.key} observes actual byte buffers without changing the message',
      () {
        final body = Uint8List.fromList([1, 2, 3, 4, 5]);
        final message = Call(41, 'com.copy.echo', arguments: [body]);
        final observed = delta(() {
          final fragments = entry.value.serializeFragments(message);
          final encoded = fragments == null
              ? entry.value.serialize(message)
              : Uint8List.fromList([for (final part in fragments) ...part]);
          final decoded =
              entry.value.deserialize(
                    encoded is String ? utf8.encode(encoded) : encoded,
                  )
                  as Call;
          expect(decoded.requestId, 41);
          expect(decoded.procedure, 'com.copy.echo');
          expect(decoded.arguments, [body]);
        });
        expect(observed['failed_copy_operations'], 0);
        expect(
          OwnedCopyMetrics.fields
              .map((key) => observed[key]!)
              .reduce((a, b) => a + b),
          greaterThan(0),
        );
      },
    );
  }

  test('unknown allocator growth cannot certify an assumed byte count', () {
    final observed = delta(() {
      final builder = flatbuffers.WampFlatBufferBuilder(
        initialSize: 8,
        allocator: _DelegatingAllocator(),
      );
      builder.writeListUint8([1, 2, 3]);
      final root = builder.writeListUint8(List<int>.filled(128, 4));
      builder.finish(root);
      expect(builder.buffer.length, greaterThan(128));
    });
    expect(observed['flatbuffer_growth_copy_bytes'], 0);
    expect(observed['unmeasured_copy_operations'], greaterThan(0));
  });

  test('legacy PPT coercion observes the copied prefix before rejection', () {
    final observed = delta(() {
      expect(
        () => unwrapLazyPayloadView(
          LazyMessagePayload.encoded(
            arguments: [
              <dynamic>[7, 8, 300],
            ],
          ),
          pptScheme: 'x_custom_typed',
          pptSerializer: 'flatbuffers',
        ),
        throwsFormatException,
      );
    });
    expect(observed['clone_copy_bytes'], 2);
    expect(observed['failed_copy_operations'], 0);
  });

  test('typed FlatBuffers PPT keeps its buffer and records zero copying', () {
    final body = Uint8List.fromList([1, 2, 3]);
    final observed = delta(() {
      final result = flatbuffers.Serializer().serializePPT(
        PPTPayload(arguments: [body]),
      );
      expect(identical(result, body), isTrue);
    });
    expect(observed.values.every((value) => value == 0), isTrue);
  });

  test('PPT observations survive outside a dedicated benchmark window', () {
    final observed = delta(() {
      PptCopyMetrics.measure(
        () => cbor.Serializer().serializePPT(
          PPTPayload(
            arguments: [
              Uint8List.fromList([7, 8, 9]),
            ],
          ),
        ),
      );
    });
    expect(
      OwnedCopyMetrics.fields.fold<int>(
        0,
        (sum, field) => sum + observed[field]!,
      ),
      greaterThan(0),
    );
    expect(observed['clone_copy_bytes'], 0);
    expect(observed['coalescing_copy_bytes'], 0);
  });

  test(
    'dedicated PPT counters report once in cumulative totals',
    () {
      PptCopyMetrics.beginWindow();
      late PptCopyMetricsSnapshot dedicated;
      final observed = delta(() {
        try {
          PptCopyMetrics.measure(
            () => cbor.Serializer().serializePPT(
              PPTPayload(
                arguments: [
                  Uint8List.fromList([7, 8, 9]),
                ],
              ),
            ),
          );
        } finally {
          dedicated = PptCopyMetrics.endWindow();
        }
      });
      expect(dedicated.knownOwnCopyBytes, greaterThan(0));
      expect(
        observed['ppt_serializer_copy_bytes'],
        dedicated.knownOwnCopyBytes,
      );
      expect(observed['clone_copy_bytes'], 0);
      expect(observed['coalescing_copy_bytes'], 0);
    },
  );

  test('failed dedicated PPT work prevents complete observations', () {
    final observed = delta(() {
      expect(
        () => PptCopyMetrics.measure(
          () => OwnedCopyMetrics.copyBytes(_UnreadableBytes()),
        ),
        throwsStateError,
      );
    });
    expect(observed['failed_copy_operations'], 1);
  });

  test('model vector writes are observed without an envelope writer', () {
    final observed = delta(() {
      final builder = flatbuffers.WampFlatBufferBuilder(initialSize: 256);
      builder.writeListInt8([-1, 2]);
      final root = builder.writeListUint8([3, 4, 5]);
      builder.finish(root);
    });
    expect(observed['flatbuffer_vector_copy_bytes'], 5);
    expect(observed['flatbuffer_growth_copy_bytes'], 0);
  });

  test(
    'portable key normalization counts actual copied bytes and rejected prefixes',
    () {
      final valid = delta(() {
        WampCborAes256GcmProvider(keys: {'key': List<int>.filled(32, 7)});
      });
      expect(valid['key_material_copy_bytes'], 32);
      final invalid = List<int>.filled(32, 7)..[2] = 300;
      final rejected = delta(() {
        expect(
          () => WampCborAes256GcmProvider(keys: {'key': invalid}),
          throwsArgumentError,
        );
      });
      expect(rejected['key_material_copy_bytes'], 2);
    },
  );

  test('copyByteValues counts conversion without exposing the source', () {
    final input = Uint8List.fromList([5, 6]);
    final observed = delta(() {
      final copy = OwnedCopyMetrics.copyByteValues(input)..[0] = 7;
      expect(copy, [7, 6]);
      expect(input, [5, 6]);
    });
    expect(observed['clone_copy_bytes'], 2);
  });
}

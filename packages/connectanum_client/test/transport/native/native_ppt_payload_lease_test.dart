@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:test/test.dart';

final class _ForwardingSource implements PackedPayloadSource {
  _ForwardingSource(this.source);
  final PackedPayloadSource source;
  @override
  Uint8List get bytes => source.bytes;
}

void main() {
  late NativeBufferAllocator allocator;
  setUpAll(() => allocator = NativeBufferAllocator.instance());

  NativeOwnedBuffer native([List<int> values = const [1, 2, 3, 4]]) {
    final builder = allocator.allocate(values.length);
    try {
      builder.writeBytes(0, values);
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  test('lease owns an independent reference without exporting a Dart view', () {
    final producer = native();
    final lease = producer.leaseFlatBuffersPptPayload();
    addTearDown(lease.dispose);
    expect(lease.isDisposed, isFalse);
    expect(lease.hasExportedByteView, isFalse);
    expect(lease.payload.packedPayloadSource, same(lease));
    final clone = lease.payload.withAnchor(Object());
    expect(lease.nativeOwnerFor(clone), isNotNull);
    producer.dispose();
    allocator.validateFrozenBuffer(lease.nativeOwnerFor(clone)!);
    expect(lease.hasExportedByteView, isFalse);
    lease.dispose();
    expect(lease.nativeOwnerFor(clone), isNull);
    expect(lease.isDisposed, isTrue);
    expect(() => clone.packedPayloadBytes, throwsStateError);
    expect(() => lease.bytes, throwsStateError);
    expect(() => producer.leaseFlatBuffersPptPayload(), throwsStateError);
    lease.dispose();
  });

  test(
    'lease disposal preserves the producer and prior exported derived views',
    () {
      final producer = native();
      addTearDown(producer.dispose);
      final lease = producer.leaseFlatBuffersPptPayload();
      addTearDown(lease.dispose);
      final bytes = lease.payload.packedPayloadBytes!;
      final derived = Uint8List.sublistView(bytes, 1, 3);
      final bufferView = bytes.buffer.asUint8List();
      expect(lease.bytes, same(bytes));
      expect(lease.hasExportedByteView, isTrue);
      expect(() => bytes[0] = 9, throwsUnsupportedError);
      expect(() => derived[0] = 9, throwsUnsupportedError);
      expect(() => bufferView[0] = 9, throwsUnsupportedError);
      lease.dispose();
      expect(producer.isDisposed, isFalse);
      expect(producer.bytes, [1, 2, 3, 4]);
      producer.dispose();
      expect(bytes, [1, 2, 3, 4]);
      expect(derived, [2, 3]);
      expect(bufferView, [1, 2, 3, 4]);
      expect(lease.payload.packedPayloadBytes, same(bytes));
      expect(lease.nativeOwnerFor(lease.payload), isNull);
    },
  );

  test(
    'native identity cannot be borrowed by an anchor, forwarding source or encoding',
    () {
      final producer = native();
      addTearDown(producer.dispose);
      final lease = producer.leaseFlatBuffersPptPayload();
      addTearDown(lease.dispose);
      MaterializedPayloadView decode(Uint8List bytes) =>
          (arguments: <dynamic>[bytes], argumentsKeywords: null);
      final fakeAnchor = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.flatbuffers,
        packedPayloadBytes: Uint8List.fromList([9]),
        packedPayloadDecoder: decode,
        anchor: lease,
        storageOwner: lease,
      );
      final fakeSource = LazyMessagePayload.packedSource(
        encoding: LazyPayloadEncoding.flatbuffers,
        source: _ForwardingSource(lease),
        packedPayloadDecoder: decode,
      );
      final otherEncoding = LazyMessagePayload.packedSource(
        encoding: LazyPayloadEncoding.cbor,
        source: lease,
        packedPayloadDecoder: decode,
      );
      for (final payload in [fakeAnchor, fakeSource, otherEncoding]) {
        expect(lease.nativeOwnerFor(payload), isNull);
      }
      expect(lease.hasExportedByteView, isFalse);
      expect(
        lease.nativeOwnerFor(lease.payload.withAnchor(fakeAnchor)),
        isNotNull,
      );
    },
  );

  for (final decodeFirst in [false, true]) {
    test(
      'owned copy drops native authority and survives disposal decode=$decodeFirst',
      () {
        final producer = native();
        addTearDown(producer.dispose);
        final lease = producer.leaseFlatBuffersPptPayload();
        addTearDown(lease.dispose);
        if (decodeFirst) {
          expect(lease.payload.arguments, [
            [1, 2, 3, 4],
          ]);
        }
        final owned = lease.payload.toOwned();
        expect(lease.hasExportedByteView, isTrue);
        expect(owned.packedPayloadSource, isNull);
        expect(owned.storageOwner, isNull);
        expect(lease.nativeOwnerFor(owned), isNull);
        lease.dispose();
        producer.dispose();
        expect(owned.arguments, [
          [1, 2, 3, 4],
        ]);
        expect(owned.packedPayloadBytes, [1, 2, 3, 4]);
        owned.packedPayloadBytes![0] = 99;
        expect(lease.bytes, [1, 2, 3, 4]);
      },
    );
  }

  test(
    'mutable message access ends native source eligibility before in-place edits',
    () {
      final producer = native();
      addTearDown(producer.dispose);
      final lease = producer.leaseFlatBuffersPptPayload();
      addTearDown(lease.dispose);
      final message = Call(1, 'app.entity')..restoreLazyPayload(lease.payload);
      expect(lease.nativeOwnerFor(message.toLazyPayload()), isNotNull);
      message.arguments![0] = Uint8List.fromList([9]);
      expect(lease.nativeOwnerFor(message.toLazyPayload()), isNull);
      expect(message.wireArguments, [
        [9],
      ]);
    },
  );

  for (final encoding in [
    LazyPayloadEncoding.cbor,
    LazyPayloadEncoding.messagePack,
  ]) {
    test(
      'generic $encoding lease is lazy and application decode runs once',
      () {
        final producer = native();
        addTearDown(producer.dispose);
        var decoded = 0;
        final lease = producer.leasePptPayload(
          encoding: encoding,
          packedPayloadDecoder: (bytes) {
            decoded++;
            return (arguments: <dynamic>[bytes], argumentsKeywords: null);
          },
        );
        addTearDown(lease.dispose);
        expect(lease.encoding, encoding);
        expect(lease.hasExportedByteView, isFalse);
        expect(decoded, 0);
        producer.dispose();
        expect(lease.payload.arguments, [
          [1, 2, 3, 4],
        ]);
        expect(lease.payload.argumentsKeywords, isNull);
        expect(decoded, 1);
        expect(lease.hasExportedByteView, isTrue);
      },
    );
  }
}

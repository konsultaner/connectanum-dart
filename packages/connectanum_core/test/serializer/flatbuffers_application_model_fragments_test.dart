import 'dart:typed_data';

import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:test/test.dart';

int _root(flat.WampFlatBufferBuilder builder, int vector, int identity) {
  builder.startTable(3);
  builder.addUint32(0, identity);
  builder.addUint32(1, identity);
  builder.addOffset(2, vector);
  return builder.endTable();
}

Uint8List _ordinary(Uint8List body, int identity, String? identifier) {
  final builder = flat.WampFlatBufferBuilder(
    initialSize: body.length + 128,
    deduplicateTables: false,
  );
  final vector = builder.writeListUint8(body);
  builder.finish(_root(builder, vector, identity), identifier);
  return builder.buffer;
}

Uint8List _join(Iterable<Uint8List> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.takeBytes();
}

void main() {
  setUpAll(OwnedCopyMetrics.enable);

  test('invalid identifiers fail before application construction', () {
    for (final identifier in ['', 'x', 'abcde', 'A☃CD', '😀ab']) {
      var called = false;
      expect(
        () => flat.buildFlatBufferPayloadParts(
          bytes: Uint8List(0),
          fileIdentifier: identifier,
          buildRoot: (builder, vector) {
            called = true;
            return _root(builder, vector.offset, 7);
          },
        ),
        throwsArgumentError,
      );
      expect(called, isFalse);
    }
  });

  test(
    'borrowed tail preserves nested strings and eight-byte scalar alignment',
    () {
      int build(flat.WampFlatBufferBuilder builder, int vector) {
        final text = builder.writeString('nested application metadata');
        builder.startTable(2);
        builder.addOffset(0, text);
        builder.addFloat64(1, 1.25);
        final nested = builder.endTable();
        builder.startTable(3);
        builder.addOffset(0, nested);
        builder.addFloat64(1, 2.5);
        builder.addOffset(2, vector);
        return builder.endTable();
      }

      for (var length = 0; length < 32; length++) {
        final body = Uint8List(length);
        final ordinary = flat.WampFlatBufferBuilder(
          initialSize: 1024,
          deduplicateTables: false,
        );
        ordinary.finish(build(ordinary, ordinary.writeListUint8(body)), 'NEST');
        final parts = flat.buildFlatBufferPayloadParts(
          bytes: body,
          fileIdentifier: 'NEST',
          buildRoot: (builder, vector) => build(builder, vector.offset),
        );
        expect(
          _join(parts.fragments),
          ordinary.buffer,
          reason: 'length=$length',
        );
      }
    },
  );

  for (final identifier in <String?>[null, 'PART']) {
    for (final length in [
      0,
      1,
      2,
      3,
      4,
      7,
      8,
      15,
      16,
      31,
      256,
      65535,
      65536,
      65537,
    ]) {
      test(
        'application bytes stay identical size=$length identifier=$identifier',
        () {
          for (final identity in [0, 1, 2147483647, 4294967295]) {
            final storage = Uint8List(length + 7);
            for (var i = 0; i < length; i++) {
              storage[i + 3] = (i * 31 + identity) & 255;
            }
            final body = Uint8List.sublistView(
              storage,
              3,
              3 + length,
            ).asUnmodifiableView();
            final expected = _ordinary(body, identity, identifier);
            final source = flat.buildFlatBufferPayloadParts(
              bytes: body,
              fileIdentifier: identifier,
              buildRoot: (builder, vector) {
                expect(identical(vector.builder, builder), isTrue);
                return _root(builder, vector.offset, identity);
              },
            );
            expect(
              source.fragments.any((part) => identical(part, body)),
              isTrue,
            );
            final actual = _join(source.fragments);
            expect(actual, expected);
            final data = ByteData.sublistView(actual);
            final root = data.getUint32(0, Endian.little);
            final decoded = const flat.FlatBufferUint8ListReader()
                .vTableGetNullable(flat.flatBufferContext(actual), root, 8);
            expect(decoded, body);
          }
        },
      );
    }
  }

  test(
    'body-vector copy disappears while the owned prefix copy stays counted',
    () {
      final body = Uint8List(65536);
      final before = OwnedCopyMetrics.snapshot()!;
      _ordinary(body, 7, 'PART');
      final ordinary = OwnedCopyMetrics.snapshot()!;
      final source = flat.buildFlatBufferPayloadParts(
        bytes: body,
        fileIdentifier: 'PART',
        buildRoot: (builder, vector) => _root(builder, vector.offset, 7),
      );
      final fragmented = OwnedCopyMetrics.snapshot()!;
      expect(
        ordinary['flatbuffer_vector_copy_bytes']! -
            before['flatbuffer_vector_copy_bytes']!,
        body.length,
      );
      expect(
        fragmented['flatbuffer_vector_copy_bytes']! -
            ordinary['flatbuffer_vector_copy_bytes']!,
        0,
      );
      expect(
        fragmented['clone_copy_bytes']! - ordinary['clone_copy_bytes']!,
        source.fragments.first.length,
      );
      expect(
        fragmented['coalescing_copy_bytes'],
        ordinary['coalescing_copy_bytes'],
      );
    },
  );

  test('an escaped builder cannot mutate the owned prefix snapshot', () {
    final body = Uint8List.fromList([1, 2, 3, 4, 5]);
    late flat.WampFlatBufferBuilder escaped;
    final expected = _ordinary(body, 7, 'PART');
    final source = flat.buildFlatBufferPayloadParts(
      bytes: body,
      fileIdentifier: 'PART',
      buildRoot: (builder, vector) {
        escaped = builder;
        return _root(builder, vector.offset, 7);
      },
    );
    escaped.buffer.fillRange(0, escaped.buffer.length, 0);
    expect(_join(source.fragments), expected);
    expect(() => source.fragments.first[0] = 3, throwsUnsupportedError);
  });

  test(
    'caller failures, invalid roots and invalid identifiers fail explicitly',
    () {
      final error = StateError('application encoder failed');
      expect(
        () => flat.buildFlatBufferPayloadParts(
          bytes: Uint8List(1),
          buildRoot: (_, _) => throw error,
        ),
        throwsA(same(error)),
      );
      for (final invalid in [-1, 0, 1, 1000000]) {
        expect(
          () => flat.buildFlatBufferPayloadParts(
            bytes: Uint8List(1),
            buildRoot: (_, _) => invalid,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => flat.buildFlatBufferPayloadParts(
          bytes: Uint8List(1),
          fileIdentifier: 'BAD',
          buildRoot: (builder, vector) => _root(builder, vector.offset, 1),
        ),
        throwsArgumentError,
      );
    },
  );

  test('resetting the builder cannot silently replace the borrowed tail', () {
    expect(
      () => flat.buildFlatBufferPayloadParts(
        bytes: Uint8List(8),
        buildRoot: (builder, vector) {
          builder.reset();
          final replacement = builder.writeListUint8([7, 8, 9]);
          return _root(builder, replacement, 1);
        },
      ),
      throwsStateError,
    );
  });

  test(
    'size limits reject the body and the complete model without copying it',
    () {
      final storage = Uint8List(64 * 1024 * 1024 + 1);
      var calls = 0;
      int encode(flat.WampFlatBufferBuilder builder, dynamic vector) {
        calls++;
        return _root(builder, vector.offset as int, 1);
      }

      expect(
        () =>
            flat.buildFlatBufferPayloadParts(bytes: storage, buildRoot: encode),
        throwsArgumentError,
      );
      expect(calls, 0);
      expect(
        () => flat.buildFlatBufferPayloadParts(
          bytes: Uint8List.sublistView(storage, 0, storage.length - 1),
          buildRoot: encode,
        ),
        throwsArgumentError,
      );
      expect(calls, 1);
    },
  );
}

import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:test/test.dart';

final class _FragmentsOnly implements FragmentedPackedPayloadSource {
  _FragmentsOnly(this.fragments);
  @override
  final List<Uint8List> fragments;
  var byteReads = 0;
  @override
  Uint8List get bytes {
    byteReads++;
    throw StateError('Unexpected contiguous access');
  }
}

MaterializedPayloadView _decode(Uint8List bytes) =>
    (arguments: <dynamic>[bytes], argumentsKeywords: null);

LazyMessagePayload _payload(PackedPayloadSource source) =>
    LazyMessagePayload.packedSource(
      encoding: LazyPayloadEncoding.flatbuffers,
      source: source,
      packedPayloadDecoder: _decode,
    );

Call _call(PackedPayloadSource source) => Call(
  123,
  'app.parts',
  options: CallOptions(pptScheme: 'x_parts', pptSerializer: 'flatbuffers'),
)..restoreLazyPayload(_payload(source));

Uint8List _join(Iterable<Uint8List> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.takeBytes();
}

int _coalescingSince(Map<String, int> before) =>
    OwnedCopyMetrics.snapshot()!['coalescing_copy_bytes']! -
    before['coalescing_copy_bytes']!;

void main() {
  setUpAll(OwnedCopyMetrics.enable);

  test('parts snapshot the caller list and borrow the exact input views', () {
    final first = Uint8List.fromList([1, 2]);
    final last = Uint8List.fromList([3, 4]);
    final input = [first, last];
    final source = PackedPayloadParts(input);
    input.clear();
    expect(source.length, 4);
    expect(source.fragments, [same(first), same(last)]);
    expect(() => source.fragments.clear(), throwsUnsupportedError);
  });

  test('contiguous access coalesces once and shares its read-only cache', () {
    final source = PackedPayloadParts([
      Uint8List.fromList([1, 2]),
      Uint8List(0),
      Uint8List.fromList([3, 4, 5]),
    ]);
    final before = OwnedCopyMetrics.snapshot()!;
    final bytes = source.bytes;
    expect(bytes, [1, 2, 3, 4, 5]);
    expect(identical(bytes, source.bytes), isTrue);
    expect(_coalescingSince(before), 5);
    expect(() => bytes[0] = 7, throwsUnsupportedError);
    final payload = _payload(source);
    expect(payload.withAnchor(Object()).packedPayloadBytes, same(bytes));
    expect(payload.packedPayloadBytes, same(bytes));
    expect(_coalescingSince(before), 5);
  });

  test('empty and one nonempty part need no coalescing copy', () {
    final input = Uint8List.fromList([4, 5, 6]);
    final before = OwnedCopyMetrics.snapshot()!;
    for (final parts in <List<Uint8List>>[
      [],
      [Uint8List(0)],
      [Uint8List(0), input, Uint8List(0)],
    ]) {
      final source = PackedPayloadParts(parts);
      expect(source.bytes, parts.contains(input) ? input : isEmpty);
      expect(identical(source.bytes, source.bytes), isTrue);
    }
    expect(_coalescingSince(before), 0);
  });

  test(
    'logical size limit is enforced without allocating the combined data',
    () {
      final chunk = Uint8List(1024 * 1024);
      expect(
        PackedPayloadParts(List.filled(64, chunk)).length,
        64 * 1024 * 1024,
      );
      expect(
        () => PackedPayloadParts(List.filled(65, chunk)),
        throwsArgumentError,
      );
    },
  );

  test('toOwned detaches every borrowed part and drops source identity', () {
    final first = Uint8List.fromList([1, 2]);
    final last = Uint8List.fromList([3, 4]);
    final source = PackedPayloadParts([first, last]);
    final payload = _payload(source);
    final owned = payload.toOwned();
    first.fillRange(0, first.length, 8);
    last.fillRange(0, last.length, 9);
    expect(packedPayloadSourceOf(owned), isNull);
    expect(owned.packedPayloadBytes, [1, 2, 3, 4]);
    expect(owned.arguments!.single, [1, 2, 3, 4]);
  });

  for (final length in [0, 1, 7, 8, 31, 256, 65536]) {
    test(
      'fragment-aware frame keeps original views and full bytes length=$length',
      () {
        final input = Uint8List(length + 5);
        for (var i = 0; i < input.length; i++) {
          input[i] = i & 255;
        }
        final first = Uint8List.sublistView(input, 1, 3).asUnmodifiableView();
        final body = Uint8List.sublistView(
          input,
          3,
          3 + length,
        ).asUnmodifiableView();
        final source = _FragmentsOnly([first, body]);
        final serializer = flat.Serializer();
        final expectedPayload = _join([first, body]);
        final ordinary = Call(
          123,
          'app.parts',
          options: CallOptions(
            pptScheme: 'x_parts',
            pptSerializer: 'flatbuffers',
          ),
          arguments: [expectedPayload],
        );
        final expected = _join(serializer.serializeFragments(ordinary)!);
        final before = OwnedCopyMetrics.snapshot()!;
        final pieces = serializer.serializeFragments(_call(source))!;
        expect(source.byteReads, 0);
        expect(pieces.any((part) => identical(part, first)), isTrue);
        expect(pieces.any((part) => identical(part, body)), isTrue);
        expect(_coalescingSince(before), 0);
        final actual = _join(pieces);
        expect(actual, expected);
        final decoded = serializer.deserialize(actual)! as Call;
        expect(decoded.options!.pptScheme, 'x_parts');
        expect(decoded.options!.pptSerializer, 'flatbuffers');
        expect(decoded.transparentBinaryPayload, expectedPayload);
      },
    );
  }

  test('ordinary serialization materializes a cached source and counts it', () {
    final source = PackedPayloadParts([
      Uint8List.fromList([1, 2]),
      Uint8List.fromList([3, 4, 5]),
    ]);
    final before = OwnedCopyMetrics.snapshot()!;
    final serializer = flat.Serializer();
    final message = _call(source);
    final first = serializer.serialize(message);
    expect((serializer.deserialize(first)! as Call).transparentBinaryPayload, [
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(_coalescingSince(before), 5);
    expect(serializer.serialize(message), first);
    expect(_coalescingSince(before), 5);
  });

  test(
    'fragment frame limit rejects oversized views before contiguous access',
    () {
      final chunk = Uint8List(1024 * 1024);
      for (final count in [64, 65]) {
        final source = _FragmentsOnly(List.filled(count, chunk));
        expect(
          () => flat.Serializer().serializeFragments(_call(source)),
          throwsArgumentError,
        );
        expect(source.byteReads, 0);
      }
    },
  );
}

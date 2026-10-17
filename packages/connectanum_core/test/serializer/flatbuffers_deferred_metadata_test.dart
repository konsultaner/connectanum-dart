import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:test/test.dart';

void main() {
  final codec = flatbuffers.Serializer();
  Uint8List encode(Object? value) => Uint8List.fromList(
    cbor.cbor.encode(cbor.CborValue(value)),
  ).asUnmodifiableView();
  Call initial() =>
      Call(17, 'com.original', options: CallOptions(timeout: 123));

  test('native retention builds the initial projection once, after edits', () {
    final message = initial();
    final bytes = encode({
      'timeout': 123,
      'x_future': {
        'values': [1, 2],
      },
    });
    var builds = 0;
    codec.retainNativeMetadata(message, bytes, () {
      builds++;
      return initial();
    });
    expect(builds, 0);
    message.options!.timeout = 456;
    final first = codec.metadataFor(message);
    expect(first, {
      'timeout': 456,
      'x_future': {
        'values': [1, 2],
      },
    });
    expect(builds, 1);
    (first['x_future'] as Map)['values'] = ['detached'];
    message.options!.timeout = 789;
    expect(codec.metadataFor(message), {
      'timeout': 789,
      'x_future': {
        'values': [1, 2],
      },
    });
    expect(builds, 1);
  });

  test(
    'root replacement before first resend does not build unused history',
    () {
      final message = initial();
      codec.retainNativeMetadata(
        message,
        encode({'timeout': 123, 'x_future': 42}),
        () => throw StateError('Unused baseline'),
      );
      message.options = CallOptions(timeout: 456);
      expect(codec.metadataFor(message), {'timeout': 456});
    },
  );

  test(
    'native retention and segmented resend never decode application vectors',
    () {
      final message = initial();
      var reads = 0;
      final args = Uint8List.fromList([0x81, 1]).asUnmodifiableView();
      final kwargs = Uint8List.fromList([
        0xa1,
        0x61,
        0x6b,
        2,
      ]).asUnmodifiableView();
      message.setLazyPayload(
        argumentsBytes: args,
        argumentsDecoder: (_) {
          reads++;
          throw StateError('application read');
        },
        argumentsKeywordsBytes: kwargs,
        argumentsKeywordsDecoder: (_) {
          reads++;
          throw StateError('application read');
        },
        encoding: LazyPayloadEncoding.cbor,
      );
      codec.retainNativeMetadata(
        message,
        encode({
          'timeout': 123,
          'x_future': Uint8List.fromList([3, 4]),
        }),
        initial,
      );
      expect(codec.metadataFor(message)['x_future'], [3, 4]);
      final fragments = codec.serializeFragments(message)!;
      expect(fragments, contains(same(args)));
      expect(fragments, contains(same(kwargs)));
      expect(reads, 0);
      final frame = BytesBuilder(copy: false)
        ..add(fragments.expand((v) => v).toList());
      final decoded = codec.deserialize(frame.takeBytes()) as Call;
      expect(decoded.arguments, [1]);
      expect(decoded.argumentsKeywords, {'k': 2});
      expect(codec.metadataFor(decoded)['x_future'], [3, 4]);
      expect(reads, 0);
    },
  );

  test('successful native retention replaces earlier retained metadata', () {
    final message = initial();
    codec.retainMetadata(message, encode({'timeout': 123, 'old': true}));
    codec.retainNativeMetadata(
      message,
      encode({'timeout': 123, 'new': true}),
      initial,
    );
    expect(codec.metadataFor(message), {'timeout': 123, 'new': true});
    codec.retainNativeMetadata(
      message,
      encode({'timeout': 123, 'latest': true}),
      initial,
    );
    expect(codec.metadataFor(message), {'timeout': 123, 'latest': true});
  });

  test(
    'valid semantic tags retain the eager path without calling a factory',
    () {
      for (final bytes in [
        [0xa1, 0x61, 0x78, 0xc0, 1],
        [0xa1, 0x61, 0x78, 0xc2, 0x41, 1],
      ]) {
        final message = initial();
        codec.retainNativeMetadata(
          message,
          Uint8List.fromList(bytes),
          () => throw StateError('tagged metadata must stay eager'),
        );
        final expected = codec.deserializeMetadata(Uint8List.fromList(bytes));
        expect(codec.metadataFor(message), expected);
      }
    },
  );

  test('tag-like binary contents remain opaque to deferred validation', () {
    final message = initial();
    var calls = 0;
    codec.retainNativeMetadata(
      message,
      encode({
        'x': Uint8List.fromList([0xc0, 0x61, 0x78]),
      }),
      () {
        calls++;
        return initial();
      },
    );
    expect(calls, 0);
    expect(codec.metadataFor(message)['x'], [0xc0, 0x61, 0x78]);
    expect(calls, 1);
  });

  test('tagged invalid date metadata is rejected at native retention', () {
    final message = initial();
    codec.retainMetadata(message, encode({'timeout': 123, 'x_future': 42}));
    for (final bytes in [
      [0xa1, 0x61, 0x78, 0xc0, 0x60],
      [0xa1, 0x61, 0x78, 0xc0, 0x61, 0x78],
      [0xa1, 0x61, 0x78, 0x81, 0xc0, 0x61, 0x78],
      [0xa1, 0x61, 0x78, 0xa1, 0x61, 0x79, 0xc0, 0x61, 0x78],
    ]) {
      expect(
        () => codec.retainNativeMetadata(
          message,
          Uint8List.fromList(bytes),
          () => throw StateError('factory must not run'),
        ),
        throwsFormatException,
      );
      expect(codec.metadataFor(message)['x_future'], 42);
    }
  });

  test('invalid deferred metadata preserves previous retained state', () {
    final message = initial();
    codec.retainMetadata(message, encode({'timeout': 123, 'x_future': 42}));
    for (final invalid in [
      [0x80],
      [0xa0, 0],
      [0xa1],
      [0xa1, 1, 0],
      [0xa2, 0x61, 0x78, 1, 0x61, 0x78, 2],
    ]) {
      expect(
        () => codec.retainNativeMetadata(
          message,
          Uint8List.fromList(invalid),
          () => throw StateError('factory must not run'),
        ),
        throwsFormatException,
      );
      expect(codec.metadataFor(message)['x_future'], 42);
    }
  });
}

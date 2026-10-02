import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart';
import 'package:test/test.dart';

const _argsKey = [0x64, 0x61, 0x72, 0x67, 0x73];
const _kwargsKey = [0x66, 0x6b, 0x77, 0x61, 0x72, 0x67, 0x73];

Uint8List _envelope(List<int> args, List<int> kwargs) => Uint8List.fromList([
  0xa2,
  ..._argsKey,
  ...args,
  ..._kwargsKey,
  ...kwargs,
]);

Uint8List _encoded(Object? value) =>
    Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value)));

void main() {
  final serializer = Serializer();

  group('CBOR PPT binary wire and borrowed views', () {
    for (final (length, header) in <(int, List<int>)>[
      (0, [0x40]),
      (1, [0x41]),
      (23, [0x57]),
      (24, [0x58, 0x18]),
      (255, [0x58, 0xff]),
      (256, [0x59, 0x01, 0x00]),
      (65535, [0x59, 0xff, 0xff]),
      (65536, [0x5a, 0, 1, 0, 0]),
    ]) {
      test('emits the exact byte-string header for $length bytes', () {
        final data = Uint8List.fromList(
          List.generate(length, (index) => (index * 7 + 129) & 255),
        );
        final expected = _envelope([0x81, ...header, ...data], [0xf6]);
        final fragments = serializer.serializePPTFragments(arguments: [data]);
        final payload = serializer.serializePPT(PPTPayload(arguments: [data]));
        expect(fragments, orderedEquals(expected));
        expect(payload, orderedEquals(expected));
        expect(cbor.cbor.decode(fragments).toObject(), {
          'args': [data],
          'kwargs': null,
        });
      });

      for (final prefix in [0, 7]) {
        test(
          'borrows $length bytes at input offset $prefix without copying',
          () {
            final data = List.generate(length, (index) => (index + 123) & 255);
            final frame = _envelope([0x81, ...header, ...data], [0xf6]);
            final storage = Uint8List.fromList([
              ...List.filled(prefix, 0xff),
              ...frame,
              0xff,
              0xff,
            ]);
            final input = Uint8List.sublistView(
              storage,
              prefix,
              prefix + frame.length,
            );
            final decoded = serializer.deserializePPT(input)!;
            expect(decoded.arguments, hasLength(1));
            expect(decoded.argumentsKeywords, isNull);
            final bytes = decoded.arguments!.single as Uint8List;
            expect(bytes, orderedEquals(data));
            final payloadOffset =
                prefix + 1 + _argsKey.length + 1 + header.length;
            expect(bytes.offsetInBytes, payloadOffset);
            expect(bytes.lengthInBytes, length);
            if (length != 0) {
              storage[payloadOffset] = 42;
              expect(bytes.first, 42, reason: 'the payload must remain a view');
              bytes[length - 1] = 99;
              expect(storage[payloadOffset + length - 1], 99);
            }
            expect(storage.last, 0xff);
            expect(storage[prefix], 0xa2);
          },
        );
      }
    }

    for (final header in <List<int>>[
      [0x58, 3],
      [0x59, 0, 3],
      [0x5a, 0, 0, 0, 3],
      [0x5b, 0, 0, 0, 0, 0, 0, 0, 3],
    ]) {
      test('accepts a valid non-minimal binary length $header as a view', () {
        final frame = _envelope([0x81, ...header, 0, 128, 255], [0xf6]);
        final decoded = serializer.deserializePPT(frame)!;
        final bytes = decoded.arguments!.single as Uint8List;
        expect(bytes, [0, 128, 255]);
        expect(bytes.offsetInBytes, 1 + _argsKey.length + 1 + header.length);
        frame[bytes.offsetInBytes] = 17;
        expect(bytes.first, 17);
        expect(decoded.argumentsKeywords, isNull);
      });
    }
  });

  group('CBOR PPT independently encoded fragment precedence', () {
    final argCases = <(String, Uint8List?, Object?)>[
      ('absent', null, [8, 'materialized']),
      ('empty', Uint8List(0), null),
      ('null', Uint8List.fromList([0xf6]), null),
      ('list', _encoded([9, 'encoded']), [9, 'encoded']),
      ('empty-list', Uint8List.fromList([0x80]), <Object?>[]),
      ('non-minimal-list', Uint8List.fromList([0x98, 0x01, 0x09]), [9]),
      (
        'binary-list',
        Uint8List.fromList([0x81, 0x43, 0, 128, 255]),
        [
          Uint8List.fromList([0, 128, 255]),
        ],
      ),
    ];
    final kwargCases = <(String, Uint8List?, Object?)>[
      ('absent', null, {'fallback': 17}),
      ('empty', Uint8List(0), null),
      ('null', Uint8List.fromList([0xf6]), null),
      ('map', _encoded({'encoded': false}), {'encoded': false}),
      ('empty-map', Uint8List.fromList([0xa0]), <String, Object?>{}),
      (
        'non-minimal-map',
        Uint8List.fromList([0xb8, 0x01, 0x61, 0x78, 0xf4]),
        {'x': false},
      ),
    ];
    for (final (argName, argBytes, expectedArgs) in argCases) {
      for (final (kwargName, kwargBytes, expectedKwargs) in kwargCases) {
        test(
          '$argName args and $kwargName kwargs override materialized values',
          () {
            final encoded = serializer.serializePPTFragments(
              argumentsBytes: argBytes,
              argumentsKeywordsBytes: kwargBytes,
              arguments: [8, 'materialized'],
              argumentsKeywords: {'fallback': 17},
            );
            expect(cbor.cbor.decode(encoded).toObject(), {
              'args': expectedArgs,
              'kwargs': expectedKwargs,
            });
            final rawArgs = argBytes ?? _encoded([8, 'materialized']);
            final rawKwargs = kwargBytes ?? _encoded({'fallback': 17});
            expect(
              encoded,
              _envelope(
                rawArgs.isEmpty ? [0xf6] : rawArgs,
                rawKwargs.isEmpty ? [0xf6] : rawKwargs,
              ),
              reason: 'supplied fragments must not be decoded and re-encoded',
            );
            final decoded = serializer.deserializePPT(encoded)!;
            expect(decoded.arguments, expectedArgs);
            expect(decoded.argumentsKeywords, expectedKwargs);
          },
        );
      }
    }

    test(
      'encoded arguments take precedence over the single-binary shortcut',
      () {
        final frame = serializer.serializePPTFragments(
          argumentsBytes: Uint8List.fromList([0x81, 0x09]),
          arguments: [
            Uint8List.fromList([1, 2, 3]),
          ],
        );
        expect(frame, _envelope([0x81, 0x09], [0xf6]));
      },
    );

    test('encoded kwargs survive alongside a materialized single binary', () {
      final frame = serializer.serializePPTFragments(
        arguments: [
          Uint8List.fromList([1, 2, 3]),
        ],
        argumentsKeywordsBytes: Uint8List.fromList([0xa1, 0x61, 0x78, 0xf5]),
      );
      expect(frame, _envelope([0x81, 0x43, 1, 2, 3], [0xa1, 0x61, 0x78, 0xf5]));
    });

    test('absent materialized fields remain explicit null fields', () {
      expect(serializer.serializePPTFragments(), _envelope([0xf6], [0xf6]));
    });

    test(
      'a materialized binary argument does not discard materialized kwargs',
      () {
        final frame = serializer.serializePPTFragments(
          arguments: [
            Uint8List.fromList([1, 2, 3]),
          ],
          argumentsKeywords: {'x': null},
        );
        expect(
          frame,
          _envelope([0x81, 0x43, 1, 2, 3], [0xa1, 0x61, 0x78, 0xf6]),
        );
      },
    );
  });

  group('CBOR PPT fast-path rejection preserves valid fallback semantics', () {
    final blob = Uint8List.fromList([0, 128, 255]);
    for (final (name, frame, args, kwargs)
        in <(String, Uint8List, Object?, Object?)>[
          ('no fields', _encoded({}), null, null),
          (
            'valid Unicode extension key',
            _encoded({
              'extension-\u{1f642}': 1,
              'args': [7],
            }),
            [7],
            null,
          ),
          (
            'non-text extension key',
            _encoded({9: true, 'kwargs': null}),
            null,
            null,
          ),
          (
            'unknown args key with a binary value',
            _encoded({
              'argt': [cbor.CborBytes(blob)],
              'kwargs': null,
            }),
            null,
            null,
          ),
          (
            'args only',
            _encoded({
              'args': [7],
            }),
            [7],
            null,
          ),
          (
            'kwargs only',
            _encoded({
              'kwargs': {'x': true},
            }),
            null,
            {'x': true},
          ),
          ('empty args', _envelope([0x80], [0xf6]), [], null),
          ('integer arg', _envelope([0x81, 0x09], [0xf6]), [9], null),
          ('text arg', _envelope([0x81, 0x61, 0x78], [0xf6]), ['x'], null),
          ('two args', _envelope([0x82, 0x09, 0xf5], [0xf6]), [9, true], null),
          ('indefinite args', _envelope([0x9f, 0x09, 0xff], [0xf6]), [9], null),
          (
            'chunked binary',
            _envelope([0x81, 0x5f, 0x42, 0, 128, 0x41, 255, 0xff], [0xf6]),
            [blob],
            null,
          ),
          (
            'empty kwargs',
            _envelope([0x81, 0x43, ...blob], [0xa0]),
            [blob],
            {},
          ),
          (
            'populated kwargs',
            _envelope([0x81, 0x43, ...blob], [0xa1, 0x61, 0x78, 0xf5]),
            [blob],
            {'x': true},
          ),
          (
            'unknown args key',
            _encoded({
              'argt': [7],
              'kwargs': {'x': true},
            }),
            null,
            {'x': true},
          ),
          (
            'short args key',
            _encoded({
              'arg': [7],
              'kwargs': null,
            }),
            null,
            null,
          ),
          (
            'unknown kwargs key',
            _encoded({
              'args': [7],
              'kwargt': 9,
            }),
            [7],
            null,
          ),
          (
            'reordered fields',
            _encoded({
              'kwargs': null,
              'args': [7],
            }),
            [7],
            null,
          ),
          (
            'extra field',
            _encoded({
              'args': [7],
              'kwargs': null,
              'extension': true,
            }),
            [7],
            null,
          ),
          (
            'indefinite map',
            Uint8List.fromList([
              0xbf,
              ..._argsKey,
              0x81,
              0x09,
              ..._kwargsKey,
              0xf6,
              0xff,
            ]),
            [9],
            null,
          ),
        ]) {
      test(name, () {
        final decoded = serializer.deserializePPT(frame)!;
        expect(decoded.arguments, args);
        expect(decoded.argumentsKeywords, kwargs);
      });
    }

    for (final value in [
      null,
      9,
      true,
      'text',
      <Object?>[],
      [1, 2],
    ]) {
      test('non-map root $value is not a PPT envelope', () {
        expect(serializer.deserializePPT(_encoded(value)), isNull);
      });
    }

    for (final value in [null, 9, false, 'text']) {
      test(
        'non-container field $value retains the existing nullable contract',
        () {
          final decoded = serializer.deserializePPT(
            _encoded({'args': value, 'kwargs': value}),
          )!;
          expect(decoded.arguments, isNull);
          expect(decoded.argumentsKeywords, isNull);
        },
      );
    }
  });

  group('CBOR PPT bounded malformed input and recovery', () {
    final valid = _envelope([0x81, 0x43, 0, 128, 255], [0xf6]);
    void expectRejected(List<int> bytes) {
      expect(
        () => serializer.deserializePPT(Uint8List.fromList(bytes)),
        throwsFormatException,
      );
      final recovered = serializer.deserializePPT(valid)!;
      expect(recovered.arguments, [
        Uint8List.fromList([0, 128, 255]),
      ]);
      expect(recovered.argumentsKeywords, isNull);
    }

    for (var length = 0; length < valid.length; length++) {
      test('rejects truncation at $length/${valid.length} bytes', () {
        expectRejected(valid.sublist(0, length));
      });
    }
    for (final trailer in [
      [0],
      [0xf6],
      [0xff],
      [0xa0],
      [0x81, 1],
    ]) {
      test('rejects a trailing CBOR value or break $trailer', () {
        expectRejected([...valid, ...trailer]);
      });
    }
    for (final header in <List<int>>[
      [0x58],
      [0x59, 0],
      [0x5a, 0, 0, 0],
      [0x5b, 0, 0, 0, 0, 0, 0, 0],
      [0x5c],
      [0x5d],
      [0x5e],
    ]) {
      test('rejects truncated or reserved binary header $header', () {
        expectRejected([0xa2, ..._argsKey, 0x81, ...header]);
      });
    }
    for (final header in <List<int>>[
      [0x58, 255],
      [0x59, 255, 255],
      [0x5a, 127, 255, 255, 255],
      [0x5b, 0, 0, 0, 0, 127, 255, 255, 255],
      [0x5b, 0, 0, 0, 0, 128, 0, 0, 0],
      [0x5b, 0, 0, 0, 1, 0, 0, 0, 1],
      [0x5b, 0x80, 0, 0, 0, 0, 0, 0, 0],
      [0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
    ]) {
      test('rejects declared length beyond the actual buffer $header', () {
        expectRejected(_envelope([0x81, ...header, 1], [0xf6]));
      });
    }
    for (final invalidKey in <List<int>>[
      [0x66, 0xff, 0x77, 0x61, 0x72, 0x67, 0x73],
      [0x66, 0x6b, 0x77, 0x61, 0x72, 0x67, 0xc2],
    ]) {
      test('binary shortcut cannot bypass invalid UTF-8 key $invalidKey', () {
        final malformed = Uint8List.fromList([
          0xa2,
          ..._argsKey,
          0x81,
          0x43,
          0,
          128,
          255,
          ...invalidKey,
          0xf6,
        ]);
        expectRejected(malformed);
        expect(
          () => serializer.deserializePPT(malformed),
          throwsA(
            isA<FormatException>()
                .having(
                  (error) => error.message,
                  'message',
                  'Invalid CBOR PPT map key',
                )
                .having((error) => error.source, 'source', isNull)
                .having((error) => error.offset, 'offset', isNull),
          ),
        );
      });
    }
    for (final invalidText in <List<int>>[
      [0x80],
      [0xc0, 0xaf],
      [0xed, 0xa0, 0x80],
      [0xf4, 0x90, 0x80, 0x80],
      [0xc2],
      [0xf8, 0x80, 0x80, 0x80, 0x80],
    ]) {
      for (final indefinite in [false, true]) {
        test(
          'rejects invalid UTF-8 extension key $invalidText indefinite=$indefinite',
          () {
            expectRejected([
              indefinite ? 0xbf : 0xa2,
              0x60 + invalidText.length,
              ...invalidText,
              1,
              ..._argsKey,
              0x81,
              7,
              if (indefinite) 0xff,
            ]);
          },
        );
      }
    }
    test(
      'bytes outside a supplied view cannot complete its truncated frame',
      () {
        final storage = Uint8List.fromList([0xff, ...valid, 0xff]);
        expect(
          () => serializer.deserializePPT(
            Uint8List.sublistView(storage, 1, valid.length),
          ),
          throwsFormatException,
        );
        expect(
          serializer
              .deserializePPT(
                Uint8List.sublistView(storage, 1, 1 + valid.length),
              )!
              .arguments,
          [
            Uint8List.fromList([0, 128, 255]),
          ],
        );
      },
    );
  });
}

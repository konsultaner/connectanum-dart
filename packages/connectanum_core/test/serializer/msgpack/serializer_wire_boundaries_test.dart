import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

// Independent format bytes, including legal wider-than-necessary encodings.
final _values = <(String, List<int>, Object?)>[
  ('nil', [0xc0], null),
  ('false', [0xc2], false),
  ('true', [0xc3], true),
  ('fixint', [0x07], 7),
  ('negative fixint', [0xff], -1),
  ('uint8', [0xcc, 7], 7),
  ('uint16', [0xcd, 0, 7], 7),
  ('uint32', [0xce, 0, 0, 0, 7], 7),
  ('uint64', [0xcf, 0, 0, 0, 0, 0, 0, 0, 7], 7),
  ('int8', [0xd0, 0xdf], -33),
  ('int16', [0xd1, 0xff, 0xdf], -33),
  ('int32', [0xd2, 0xff, 0xff, 0xff, 0xdf], -33),
  ('int64', [0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xdf], -33),
  ('float32', [0xca, 0x3f, 0xc0, 0, 0], 1.5),
  ('float64', [0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0], 1.5),
  ('fixstr', [0xa2, 0x6f, 0x6b], 'ok'),
  ('str8', [0xd9, 2, 0x6f, 0x6b], 'ok'),
  ('str16', [0xda, 0, 2, 0x6f, 0x6b], 'ok'),
  ('str32', [0xdb, 0, 0, 0, 2, 0x6f, 0x6b], 'ok'),
  ('bin8', [0xc4, 3, 0, 0x7f, 0xff], Uint8List.fromList([0, 0x7f, 0xff])),
  ('bin16', [0xc5, 0, 3, 0, 0x7f, 0xff], Uint8List.fromList([0, 0x7f, 0xff])),
  (
    'bin32',
    [0xc6, 0, 0, 0, 3, 0, 0x7f, 0xff],
    Uint8List.fromList([0, 0x7f, 0xff]),
  ),
  ('fixarray', [0x91, 7], [7]),
  ('array16', [0xdc, 0, 1, 7], [7]),
  ('array32', [0xdd, 0, 0, 0, 1, 7], [7]),
  ('fixmap', [0x81, 0xa1, 0x78, 7], {'x': 7}),
  ('map16', [0xde, 0, 1, 0xa1, 0x78, 7], {'x': 7}),
  ('map32', [0xdf, 0, 0, 0, 1, 0xa1, 0x78, 7], {'x': 7}),
  (
    'nested map and array',
    [0x91, 0x81, 0xa1, 0x78, 0x91, 7],
    [
      {
        'x': [7],
      },
    ],
  ),
];

Uint8List _resultFrame(List<int> value, String padding) => Uint8List.fromList([
  0x94,
  0x32,
  7,
  0x80,
  0x92,
  ...msgpack.serialize(padding),
  ...value,
]);

void main() {
  final serializer = Serializer();
  final malformedFrame = throwsA(
    isA<FormatException>()
        .having(
          (error) => error.message,
          'message',
          anyOf(
            'Invalid MessagePack WAMP message',
            'MessagePack collection length exceeds available bytes',
          ),
        )
        .having((error) => error.source, 'source', isNull)
        .having((error) => error.offset, 'offset', isNull),
  );
  final trailingFrame = throwsA(
    isA<FormatException>()
        .having(
          (error) => error.message,
          'message',
          'Trailing data after MessagePack WAMP message',
        )
        .having((error) => error.source, 'source', isNull)
        .having((error) => error.offset, 'offset', isNull),
  );
  for (final padding in [
    '',
    List.filled(4, 'private-payload-sentinel').join(),
  ]) {
    group(
      'MessagePack ${padding.isEmpty ? 'small' : 'depth-checked'} frames',
      () {
        for (final (name, wire, expected) in _values) {
          test('decodes exact $name bytes without changing the value', () {
            final result =
                serializer.deserialize(_resultFrame(wire, padding)) as Result;
            expect(result.callRequestId, 7);
            expect(result.arguments, [padding, expected]);
            expect(result.argumentsKeywords, isNull);
            if (expected is Uint8List) {
              expect(result.arguments![1], isA<Uint8List>());
            }
            if (expected is int) {
              expect(result.arguments![1], isA<int>());
            }
          });

          test('rejects every truncated $name before exposing a message', () {
            for (var length = 0; length < wire.length; length++) {
              expect(
                () => serializer.deserialize(
                  _resultFrame(wire.sublist(0, length), padding),
                ),
                malformedFrame,
                reason: '$name truncated at byte $length of ${wire.length}',
              );
            }
          });

          test('rejects bytes following a complete $name frame', () {
            expect(
              () => serializer.deserialize(
                Uint8List.fromList([
                  ..._resultFrame(wire, padding),
                  0xc0,
                ]),
              ),
              trailingFrame,
            );
          });
        }

        test('rejects the reserved marker before exposing a message', () {
          expect(
            () => serializer.deserialize(_resultFrame([0xc1], padding)),
            malformedFrame,
          );
        });

        final extensions = <List<int>>[
          for (final (tag, length) in [
            (0xd4, 1),
            (0xd5, 2),
            (0xd6, 4),
            (0xd7, 8),
            (0xd8, 16),
          ])
            [tag, 0, ...List.filled(length, 7)],
          [0xc7, 3, 0, 1, 2, 3],
          [0xc8, 0, 3, 0, 1, 2, 3],
          [0xc9, 0, 0, 0, 3, 0, 1, 2, 3],
        ];
        for (final wire in extensions) {
          test(
            'rejects truncated extension ${wire.first.toRadixString(16)}',
            () {
              for (var length = 0; length < wire.length; length++) {
                expect(
                  () => serializer.deserialize(
                    _resultFrame(wire.sublist(0, length), padding),
                  ),
                  malformedFrame,
                  reason:
                      'extension truncated at byte $length of ${wire.length}',
                );
              }
            },
          );
        }
      },
    );
  }

  for (final header in <List<int>>[
    [0x93],
    [0xdc, 0, 3],
    [0xdd, 0, 0, 0, 3],
  ]) {
    test(
      'accepts REGISTERED array header ${header.first.toRadixString(16)}',
      () {
        final message =
            serializer.deserialize(
                  Uint8List.fromList([
                    ...header,
                    0x41,
                    0xcd,
                    0x01,
                    0x02,
                    0xce,
                    0,
                    0x03,
                    0x04,
                    0x05,
                  ]),
                )
                as Registered;
        expect(message.registerRequestId, 258);
        expect(message.registrationId, 197637);
      },
    );
  }
}

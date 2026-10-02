import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  final codecs =
      <
        (
          String,
          Uint8List Function(Object?),
          PPTPayload? Function(Uint8List),
          Uint8List Function(PPTPayload),
        )
      >[
        (
          'json',
          (value) => Uint8List.fromList(utf8.encode(jsonEncode(value))),
          json_serializer.Serializer().deserializePPT,
          json_serializer.Serializer().serializePPT,
        ),
        (
          'msgpack',
          msgpack.serialize,
          msgpack_serializer.Serializer().deserializePPT,
          msgpack_serializer.Serializer().serializePPT,
        ),
        (
          'cbor',
          (value) =>
              Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value))),
          cbor_serializer.Serializer().deserializePPT,
          cbor_serializer.Serializer().serializePPT,
        ),
      ];
  const args = <Object?>[
    null,
    {'nested': null},
  ];
  const kwargs = <String, Object?>{
    'optional': null,
    'nested': {'value': null},
    'list': [null, false, 0, ''],
  };

  for (final (name, encode, decode, _) in codecs) {
    PPTPayload payload() => decode(encode({'args': args, 'kwargs': kwargs}))!;

    group('$name PPT nullable application values', () {
      if (name != 'json') {
        for (final key in <Object?>[
          null,
          true,
          7,
          1.25,
          [1],
        ]) {
          test(
            'rejects a non-string keyword key $key before exposing a payload',
            () {
              final malformed = encode({
                'args': [],
                'kwargs': {'valid': 1, key: 'private-payload-marker'},
              });
              expect(
                () => decode(malformed),
                throwsA(
                  isA<FormatException>()
                      .having(
                        (error) => error.toString(),
                        'redaction',
                        isNot(contains('private-payload-marker')),
                      )
                      .having((error) => error.source, 'source', isNull)
                      .having((error) => error.offset, 'offset', isNull),
                ),
              );
              expect(
                Map<String, dynamic>.from(payload().argumentsKeywords!),
                kwargs,
              );
            },
          );
        }
      }

      test('string keys are preserved without coercion or normalization', () {
        final expected = {'': null, '7': false, 'true': 0, '\u00e4': null};
        final decoded = decode(encode({'kwargs': expected}))!;
        expect(Map<String, dynamic>.from(decoded.argumentsKeywords!), expected);
      });

      test('direct access preserves a present null and nested values', () {
        final decoded = payload();
        expect(decoded.arguments, args);
        expect(decoded.argumentsKeywords!.containsKey('optional'), isTrue);
        expect(decoded.argumentsKeywords!['optional'], isNull);
        expect(decoded.argumentsKeywords!['nested'], {'value': null});
        expect(decoded.argumentsKeywords!['list'], [null, false, 0, '']);
      });

      test(
        'values iteration accepts null rather than casting it to Object',
        () {
          expect(
            payload().argumentsKeywords!.values.toList(),
            kwargs.values.toList(),
          );
        },
      );

      test('entry iteration retains the null-valued entry', () {
        final entries = payload().argumentsKeywords!.entries.toList();
        expect(entries.map((entry) => entry.key), kwargs.keys);
        expect(entries.map((entry) => entry.value), kwargs.values);
      });

      test('forEach delivers every value including null', () {
        final visited = <String, Object?>{};
        payload().argumentsKeywords!.forEach(
          (key, value) => visited[key] = value,
        );
        expect(visited, kwargs);
      });

      test('copying a decoded keyword map preserves null', () {
        expect(Map<String, dynamic>.from(payload().argumentsKeywords!), kwargs);
      });

      test('mapping a decoded keyword map preserves null', () {
        final copied = payload().argumentsKeywords!.map(
          (key, value) => MapEntry(key, value),
        );
        expect(copied, kwargs);
      });

      test(
        'decoded keyword maps continue to accept null application values',
        () {
          final values = payload().argumentsKeywords!;
          values['added'] = null;
          values['nested'] = null;
          expect(values.containsKey('added'), isTrue);
          expect(values['added'], isNull);
          expect(values['nested'], isNull);
          expect(values['list'], kwargs['list']);
        },
      );

      for (final (targetName, _, targetDecode, targetEncode) in codecs) {
        test('forwards null-containing payloads to $targetName', () {
          final forwarded = targetDecode(targetEncode(payload()))!;
          expect(forwarded.arguments, args);
          expect(
            Map<String, dynamic>.from(forwarded.argumentsKeywords!),
            kwargs,
          );
        });
      }
    });
  }
}

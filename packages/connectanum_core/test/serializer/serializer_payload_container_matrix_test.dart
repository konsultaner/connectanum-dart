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

const _marker = 'private-application-payload';

void main() {
  final serializers = <_SerializerHarness>[
    _SerializerHarness(
      'json',
      (value) => Uint8List.fromList(utf8.encode(jsonEncode(_jsonValue(value)))),
      json_serializer.Serializer().deserialize,
    ),
    _SerializerHarness(
      'msgpack',
      msgpack.serialize,
      msgpack_serializer.Serializer().deserialize,
    ),
    _SerializerHarness(
      'cbor',
      (value) => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value))),
      cbor_serializer.Serializer().deserialize,
    ),
  ];
  final prefixes = <String, List<Object?>>{
    'CALL': [48, 17, <String, Object?>{}, 'com.example.procedure'],
    'PUBLISH': [16, 19, <String, Object?>{}, 'com.example.topic'],
    'YIELD': [70, 23, <String, Object?>{}],
    'RESULT': [50, 29, <String, Object?>{}],
    'EVENT': [36, 31, 37, <String, Object?>{}],
    'INVOCATION': [68, 41, 43, <String, Object?>{}],
    'ERROR': [8, 48, 47, <String, Object?>{}, 'com.example.error'],
  };
  final invalidContainers = <String, Object?>{
    'null': null,
    'string': _marker,
    'integer': 1,
    'fraction': 1.5,
    'true': true,
    'false': false,
  };
  final rejected = throwsA(
    isA<FormatException>()
        .having(
          (error) => error.toString(),
          'redaction',
          isNot(contains(_marker)),
        )
        .having((error) => error.source, 'source', isNull)
        .having((error) => error.offset, 'offset', isNull),
  );

  for (final harness in serializers) {
    for (final entry in prefixes.entries) {
      group('${harness.name} ${entry.key} payload containers', () {
        AbstractMessageWithPayload decode(List<Object?> suffix) {
          final message = harness.decode(
            harness.encode([...entry.value, ...suffix]),
          );
          expect(message, isA<AbstractMessageWithPayload>());
          expect(message!.id, entry.value.first);
          return message as AbstractMessageWithPayload;
        }

        test('preserves absent versus explicitly empty payload fields', () {
          final absent = decode([]);
          expect(absent.arguments, isNull);
          expect(absent.argumentsKeywords, isNull);
          final positional = decode([<Object?>[]]);
          expect(positional.arguments, isEmpty);
          expect(positional.argumentsKeywords, isNull);
          final both = decode([<Object?>[], <String, Object?>{}]);
          expect(both.arguments, isEmpty);
          expect(both.argumentsKeywords, isEmpty);
        });

        test(
          'preserves nested null, binary, list and map application values',
          () {
            final binary = Uint8List.fromList([0, 255, 16]);
            final arguments = <Object?>[
              null,
              false,
              1.5,
              {
                'optional': null,
                'bytes': binary,
                'list': [1, 2],
              },
            ];
            final keywords = <String, Object?>{
              'optional': null,
              'bytes': binary,
              'nested': [false, <String, Object?>{}],
            };
            final message = decode([arguments, keywords]);
            expect(message.arguments, arguments);
            expect(message.argumentsKeywords, keywords);
            expect((message.arguments![3] as Map)['bytes'], isA<Uint8List>());
            expect(message.argumentsKeywords!['bytes'], isA<Uint8List>());
          },
        );

        test('preserves transparent binary payload without keyword fields', () {
          final binary = Uint8List.fromList([0, 255, 16]);
          final message = decode([binary]);
          expect(message.transparentBinaryPayload, orderedEquals(binary));
          expect(message.argumentsKeywords, isNull);
        });

        for (final invalid in invalidContainers.entries) {
          test('rejects ${invalid.key} positional container', () {
            expect(() => decode([invalid.value]).arguments, rejected);
          });
          test('rejects ${invalid.key} keyword container', () {
            expect(
              () => decode([<Object?>[], invalid.value]).argumentsKeywords,
              rejected,
            );
          });
        }
        test(
          'rejects a positional dictionary instead of treating it as kwargs',
          () {
            expect(
              () => decode([
                {'secret': _marker},
              ]).arguments,
              rejected,
            );
          },
        );
        for (final invalid in <String, Object?>{
          'empty list': <Object?>[],
          'list': <Object?>[_marker],
          'binary': Uint8List.fromList([0, 255, 16]),
        }.entries) {
          test('rejects ${invalid.key} keyword container', () {
            expect(
              () => decode([<Object?>[], invalid.value]).argumentsKeywords,
              rejected,
            );
          });
        }

        if (harness.name != 'json') {
          for (final invalid in <String, Object?>{
            'integer': 1,
            'fraction': 1.5,
            'boolean': true,
            'null': null,
          }.entries) {
            test('rejects ${invalid.key} keyword keys without coercion', () {
              expect(
                () => decode([
                  <Object?>[],
                  <Object?, Object?>{'valid': null, invalid.value: _marker},
                ]).argumentsKeywords,
                rejected,
              );
            });
          }
          test('rejects keyword keys that collide after stringification', () {
            for (final keywords in [
              <Object?, Object?>{1: _marker, '1': 'other'},
              <Object?, Object?>{'1': 'other', 1: _marker},
            ]) {
              expect(
                () => decode([<Object?>[], keywords]).argumentsKeywords,
                rejected,
              );
            }
          });
        }
      });
    }
  }
}

Object? _jsonValue(Object? value) {
  if (value is Uint8List) {
    return '\u0000${base64Encode(value)}';
  }
  if (value is List) {
    return value.map(_jsonValue).toList();
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _jsonValue(value)));
  }
  return value;
}

class _SerializerHarness {
  const _SerializerHarness(this.name, this.encode, this.decode);

  final String name;
  final Uint8List Function(Object?) encode;
  final AbstractMessage? Function(Uint8List) decode;
}

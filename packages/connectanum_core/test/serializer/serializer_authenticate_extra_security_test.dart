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

const _proof = 'synthetic-private-proof';
const _marker = 'synthetic-private-extra';

void main() {
  final serializers = <_SerializerHarness>[
    _SerializerHarness(
      'json',
      (frame) => Uint8List.fromList(utf8.encode(jsonEncode(frame))),
      json_serializer.Serializer().deserialize,
    ),
    _SerializerHarness(
      'msgpack',
      msgpack.serialize,
      msgpack_serializer.Serializer().deserialize,
    ),
    _SerializerHarness(
      'cbor',
      (frame) => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(frame))),
      cbor_serializer.Serializer().deserialize,
    ),
  ];

  for (final serializer in serializers) {
    group('${serializer.name} AUTHENTICATE Extra', () {
      Authenticate decode(Object? extra, {String signature = _proof}) =>
          serializer.decode(serializer.encode([5, signature, extra]))
              as Authenticate;

      final rejected = throwsA(
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              'AUTHENTICATE.Extra must be a dictionary with string keys',
            )
            .having((error) => error.source, 'source', isNull)
            .having((error) => error.offset, 'offset', isNull),
      );

      test('preserves empty Extra and an empty signature', () {
        final message = decode(<String, Object?>{}, signature: '');
        expect(message.id, 5);
        expect(message.signature, '');
        expect(message.extra, isEmpty);
      });

      test('preserves SCRAM and custom nested nullable metadata', () {
        final extra = <String, Object?>{
          'nonce': 'synthetic-nonce',
          'channel_binding': null,
          'cbind_data': 'biws',
          'x_extension': {
            'optional': null,
            'flags': [true, false],
            'nested': [null, <String, Object?>{}, <Object?>[]],
          },
        };
        final message = decode(extra);
        expect(message.signature, _proof);
        expect(message.extra, extra);
      });

      test('preserves nested binary extension values', () {
        final binary = Uint8List.fromList([0, 255, 16]);
        final message = decode({
          'x_extension': {
            'bytes': serializer.name == 'json' ? '\u0000AP8Q' : binary,
          },
        });
        final extension = message.extra!['x_extension'] as Map;
        expect(extension['bytes'], isA<Uint8List>());
        expect(extension['bytes'], orderedEquals(binary));
        expect(message.signature, _proof);
      });

      final invalidContainers = <String, Object?>{
        'null': null,
        'empty list': <Object?>[],
        'list': <Object?>[_marker],
        'string': _marker,
        'integer': 1,
        'fraction': 1.5,
        'true': true,
        'false': false,
        'binary': Uint8List.fromList([0, 255, 16]),
      };
      for (final entry in invalidContainers.entries) {
        test('rejects ${entry.key} without exposing authentication data', () {
          expect(() => decode(entry.value), rejected);
          final next = decode({'nonce': 'fresh-nonce'});
          expect(next.signature, _proof);
          expect(next.extra, {'nonce': 'fresh-nonce'});
        });
      }

      if (serializer.name != 'json') {
        final invalidKeys = <String, Object?>{
          'integer': 1,
          'fraction': 1.5,
          'null': null,
          'boolean': true,
        };
        for (final entry in invalidKeys.entries) {
          test('rejects ${entry.key} keys instead of stringifying them', () {
            expect(
              () => decode(<Object?, Object?>{
                'nonce': 'synthetic-nonce',
                entry.value: _marker,
              }),
              rejected,
            );
          });
        }
        test('rejects colliding numeric and string keys in either order', () {
          for (final extra in [
            <Object?, Object?>{1: _marker, '1': 'other'},
            <Object?, Object?>{'1': 'other', 1: _marker},
          ]) {
            expect(() => decode(extra), rejected);
          }
        });
      }
    });
  }
}

class _SerializerHarness {
  const _SerializerHarness(this.name, this.encode, this.decode);

  final String name;
  final Uint8List Function(List<Object?>) encode;
  final AbstractMessage? Function(Uint8List) decode;
}

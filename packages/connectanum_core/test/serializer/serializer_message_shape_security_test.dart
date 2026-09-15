import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/src/message/publish.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

const _maximumWampId = 0x20000000000000;
const _maximumUint32 = 0xffffffff;
const _isWeb = bool.fromEnvironment('dart.library.js_interop');

final _serializers = <_SerializerHarness>[
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

const _minimumWampFrames = <List<Object?>>[
  [1, 'com.example.realm', <String, Object?>{}],
  [2, 1, <String, Object?>{}],
  [3, <String, Object?>{}, 'wamp.error.system_shutdown'],
  [4, 'ticket', <String, Object?>{}],
  [5, 'signature', <String, Object?>{}],
  [6, <String, Object?>{}, 'wamp.close.normal'],
  [8, 48, 1, <String, Object?>{}, 'wamp.error.runtime_error'],
  [16, 1, <String, Object?>{}, 'com.example.topic'],
  [17, 1, 1],
  [32, 1, <String, Object?>{}, 'com.example.topic'],
  [33, 1, 1],
  [34, 1, 1],
  [35, 1],
  [36, 1, 1, <String, Object?>{}],
  [48, 1, <String, Object?>{}, 'com.example.procedure'],
  [49, 1, <String, Object?>{}],
  [50, 1, <String, Object?>{}],
  [64, 1, <String, Object?>{}, 'com.example.procedure'],
  [65, 1, 1],
  [66, 1, 1],
  [67, 1],
  [68, 1, 1, <String, Object?>{}],
  [69, 1, <String, Object?>{}],
  [70, 1, <String, Object?>{}],
];

void main() {
  group('WAMP message shape security', () {
    test('accepts each supported minimum message shape', () {
      for (final serializer in _serializers) {
        for (final frame in _minimumWampFrames) {
          expect(
            serializer.decode(serializer.encode(frame)),
            isNotNull,
            reason: '${serializer.name} message type ${frame.first}',
          );
        }
      }
    });

    test('normalizes every recognized short message to a redacted error', () {
      final normalizedError = isA<FormatException>().having(
        (error) => error.message,
        'message',
        'WAMP message contains too few fields',
      );

      for (final serializer in _serializers) {
        for (final frame in _minimumWampFrames) {
          for (var length = 1; length < frame.length; length++) {
            final shortFrame = frame.sublist(0, length);
            expect(
              () => serializer.decode(serializer.encode(shortFrame)),
              throwsA(normalizedError),
              reason:
                  '${serializer.name} message type ${frame.first} '
                  'with $length fields',
            );
          }
        }
      }
    });
  });

  group('PUBLISH recipient filter security', () {
    for (final optionName in const ['exclude', 'eligible']) {
      test('accepts valid $optionName WAMP ID boundaries', () {
        for (final serializer in _serializers) {
          final maximumTestId = _isWeb && serializer.name == 'msgpack'
              ? _maximumUint32
              : _maximumWampId;
          final publish =
              serializer.decode(
                    serializer.encode([
                      16,
                      1,
                      <String, Object?>{
                        optionName: <int>[1, maximumTestId],
                      },
                      'com.example.topic',
                    ]),
                  )
                  as Publish;

          final ids = optionName == 'exclude'
              ? publish.options?.exclude
              : publish.options?.eligible;
          expect(
            ids,
            equals([1, maximumTestId]),
            reason: serializer.name,
          );
        }
      });

      test('rejects malformed $optionName values without disclosure', () {
        const marker = 'attacker-controlled-marker';
        final normalizedError = isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              'PUBLISH.Options.$optionName must be a list of WAMP IDs',
            )
            .having(
              (error) => error.toString(),
              'redacted message',
              isNot(contains(marker)),
            );
        final malformedValues = <Object?>[
          null,
          marker,
          <Object?>[1, marker],
          <Object?>[1, 2.5],
          <int>[0],
          <int>[-1],
          if (!_isWeb) <int>[_maximumWampId + 1],
        ];

        for (final serializer in _serializers) {
          for (final malformedValue in malformedValues) {
            expect(
              () => serializer.decode(
                serializer.encode([
                  16,
                  1,
                  <String, Object?>{optionName: malformedValue},
                  'com.example.topic',
                ]),
              ),
              throwsA(normalizedError),
              reason: '${serializer.name}: ${malformedValue.runtimeType}',
            );
          }
        }
      });
    }

    for (final optionName in const [
      'exclude_authid',
      'exclude_authrole',
      'eligible_authid',
      'eligible_authrole',
    ]) {
      test('accepts valid $optionName strings without coercion', () {
        for (final serializer in _serializers) {
          final publish =
              serializer.decode(
                    serializer.encode([
                      16,
                      1,
                      <String, Object?>{
                        optionName: <String>['alice', 'operator'],
                      },
                      'com.example.topic',
                    ]),
                  )
                  as Publish;

          final values = switch (optionName) {
            'exclude_authid' => publish.options?.excludeAuthId,
            'exclude_authrole' => publish.options?.excludeAuthRole,
            'eligible_authid' => publish.options?.eligibleAuthId,
            'eligible_authrole' => publish.options?.eligibleAuthRole,
            _ => throw StateError('unreachable option $optionName'),
          };
          expect(
            values,
            equals(const ['alice', 'operator']),
            reason: serializer.name,
          );
        }
      });

      test('rejects malformed $optionName values without coercion', () {
        const marker = 'attacker-controlled-marker';
        final normalizedError = isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              'PUBLISH.Options.$optionName must be a list of strings',
            )
            .having(
              (error) => error.toString(),
              'redacted message',
              isNot(contains(marker)),
            );
        final malformedValues = <Object?>[
          null,
          marker,
          123,
          <Object?>['alice', 123],
          <Object?>[true],
          <String, Object?>{'value': marker},
        ];

        for (final serializer in _serializers) {
          for (final malformedValue in malformedValues) {
            expect(
              () => serializer.decode(
                serializer.encode([
                  16,
                  1,
                  <String, Object?>{optionName: malformedValue},
                  'com.example.topic',
                ]),
              ),
              throwsA(normalizedError),
              reason: '${serializer.name}: ${malformedValue.runtimeType}',
            );
          }
        }
      });
    }
  });
}

class _SerializerHarness {
  const _SerializerHarness(this.name, this.encode, this.decode);

  final String name;
  final Uint8List Function(List<Object?> frame) encode;
  final Object? Function(Uint8List bytes) decode;
}

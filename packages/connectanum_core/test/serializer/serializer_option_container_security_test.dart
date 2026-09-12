import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

const _marker = 'attacker-controlled-marker';

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
    supportsNonStringMapKeys: true,
  ),
  _SerializerHarness(
    'cbor',
    (frame) => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(frame))),
    cbor_serializer.Serializer().deserialize,
    supportsNonStringMapKeys: true,
  ),
];

final _optionMessages = <_OptionMessage>[
  _OptionMessage('PUBLISH', [16, 1, <String, Object?>{}, 'com.example.topic']),
  _OptionMessage('SUBSCRIBE', [
    32,
    1,
    <String, Object?>{},
    'com.example.topic',
  ]),
  _OptionMessage('CALL', [
    48,
    1,
    <String, Object?>{},
    'com.example.procedure',
  ]),
  _OptionMessage('CANCEL', [49, 1, <String, Object?>{}]),
  _OptionMessage('REGISTER', [
    64,
    1,
    <String, Object?>{},
    'com.example.procedure',
  ]),
  _OptionMessage('INTERRUPT', [69, 1, <String, Object?>{}]),
  _OptionMessage('YIELD', [70, 1, <String, Object?>{}]),
];

void main() {
  group('WAMP option container security', () {
    test('accepts empty and custom string-keyed option dictionaries', () {
      for (final serializer in _serializers) {
        for (final message in _optionMessages) {
          expect(
            serializer.decode(serializer.encode(message.frame)),
            isNotNull,
            reason: '${serializer.name} ${message.name} empty options',
          );

          final customOptionsFrame = List<Object?>.from(message.frame);
          customOptionsFrame[2] = <String, Object?>{'x_test': _marker};
          expect(
            serializer.decode(serializer.encode(customOptionsFrame)),
            isNotNull,
            reason: '${serializer.name} ${message.name} custom options',
          );
        }
      }
    });

    for (final serializer in _serializers) {
      for (final message in _optionMessages) {
        test(
          '${serializer.name} ${message.name} rejects non-dictionary options',
          () {
            final normalizedError = isA<FormatException>()
                .having(
                  (error) => error.message,
                  'message',
                  '${message.name}.Options must be a dictionary',
                )
                .having(
                  (error) => error.toString(),
                  'redacted message',
                  isNot(contains(_marker)),
                );
            final malformedOptions = <Object?>[
              null,
              _marker,
              <Object?>[_marker],
              42,
              true,
            ];

            for (final malformedOption in malformedOptions) {
              final malformedFrame = List<Object?>.from(message.frame);
              malformedFrame[2] = malformedOption;

              expect(
                () => serializer.decode(serializer.encode(malformedFrame)),
                throwsA(normalizedError),
                reason: malformedOption.runtimeType.toString(),
              );
            }
          },
        );

        if (serializer.supportsNonStringMapKeys) {
          test(
            '${serializer.name} ${message.name} rejects non-string option keys',
            () {
              final malformedFrame = List<Object?>.from(message.frame);
              malformedFrame[2] = <Object?, Object?>{1: _marker};
              final normalizedError = isA<FormatException>()
                  .having(
                    (error) => error.message,
                    'message',
                    '${message.name}.Options keys must be strings',
                  )
                  .having(
                    (error) => error.toString(),
                    'redacted message',
                    isNot(contains(_marker)),
                  );

              expect(
                () => serializer.decode(serializer.encode(malformedFrame)),
                throwsA(normalizedError),
              );
            },
          );
        }
      }
    }
  });
}

class _OptionMessage {
  const _OptionMessage(this.name, this.frame);

  final String name;
  final List<Object?> frame;
}

class _SerializerHarness {
  const _SerializerHarness(
    this.name,
    this.encode,
    this.decode, {
    this.supportsNonStringMapKeys = false,
  });

  final String name;
  final Uint8List Function(List<Object?> frame) encode;
  final Object? Function(Uint8List bytes) decode;
  final bool supportsNonStringMapKeys;
}

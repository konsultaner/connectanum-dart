import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/src/message/call.dart';
import 'package:connectanum_core/src/message/event.dart';
import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

const _marker = 'attacker-controlled-marker';
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

final _fields = <_OptionalNumericField>[
  _OptionalNumericField.wampId(
    'INVOCATION.Details.caller',
    (value) => [
      68,
      1,
      1,
      <String, Object?>{'caller': value},
    ],
    (message) => (message as Invocation).details.caller,
  ),
  _OptionalNumericField.wampId(
    'EVENT.Details.publisher',
    (value) => [
      36,
      1,
      1,
      <String, Object?>{'publisher': value},
    ],
    (message) => (message as Event).details.publisher,
  ),
  _OptionalNumericField.nonNegativeInteger(
    'CALL.Options.timeout',
    (value) => [
      48,
      1,
      <String, Object?>{'timeout': value},
      'com.example.procedure',
    ],
    (message) => (message as Call).options?.timeout,
  ),
  _OptionalNumericField.nonNegativeInteger(
    'INVOCATION.Details.timeout',
    (value) => [
      68,
      1,
      1,
      <String, Object?>{'timeout': value},
    ],
    (message) => (message as Invocation).details.timeout,
  ),
  _OptionalNumericField.nonNegativeInteger(
    'INVOCATION.Details.trustlevel',
    (value) => [
      68,
      1,
      1,
      <String, Object?>{'trustlevel': value},
    ],
    (message) => (message as Invocation).details.custom['trustlevel'],
  ),
  _OptionalNumericField.nonNegativeInteger(
    'EVENT.Details.trustlevel',
    (value) => [
      36,
      1,
      1,
      <String, Object?>{'trustlevel': value},
    ],
    (message) => (message as Event).details.trustlevel,
  ),
];

void main() {
  group('WAMP optional numeric field security', () {
    for (final serializer in _serializers) {
      for (final field in _fields) {
        test('${serializer.name} ${field.path} accepts valid boundaries', () {
          final maximum = field.isWampId
              ? _isWeb && serializer.name == 'msgpack'
                    ? _maximumUint32
                    : _maximumWampId
              : 42;
          final minimum = field.isWampId ? 1 : 0;

          for (final value in [minimum, maximum]) {
            final decoded = serializer.decode(
              serializer.encode(field.frame(value)),
            );
            expect(field.value(decoded), value, reason: value.toString());
          }

          final absent = serializer.decode(
            serializer.encode(field.frameWithoutValue),
          );
          expect(field.value(absent), isNull, reason: 'absent field');
        });

        test(
          '${serializer.name} ${field.path} rejects invalid values',
          () {
            final normalizedError = isA<FormatException>()
                .having(
                  (error) => error.message,
                  'message',
                  field.isWampId
                      ? '${field.path} must be a WAMP ID'
                      : '${field.path} must be a non-negative integer',
                )
                .having(
                  (error) => error.toString(),
                  'redacted message',
                  isNot(contains(_marker)),
                );
            final malformedValues = <Object?>[
              null,
              _marker,
              true,
              1.5,
              <Object?>[_marker],
              <String, Object?>{'value': _marker},
              -1,
              if (field.isWampId) 0,
              if (field.isWampId && !_isWeb) _maximumWampId + 1,
            ];

            for (final malformedValue in malformedValues) {
              expect(
                () => serializer.decode(
                  serializer.encode(field.frame(malformedValue)),
                ),
                throwsA(normalizedError),
                reason: malformedValue.runtimeType.toString(),
              );
            }
          },
        );
      }
    }
  });
}

class _OptionalNumericField {
  const _OptionalNumericField._(
    this.path,
    this.frame,
    this.value, {
    required this.isWampId,
  });

  const _OptionalNumericField.wampId(
    String path,
    List<Object?> Function(Object? value) frame,
    Object? Function(Object? message) value,
  ) : this._(path, frame, value, isWampId: true);

  const _OptionalNumericField.nonNegativeInteger(
    String path,
    List<Object?> Function(Object? value) frame,
    Object? Function(Object? message) value,
  ) : this._(path, frame, value, isWampId: false);

  final String path;
  final List<Object?> Function(Object? value) frame;
  final Object? Function(Object? message) value;
  final bool isWampId;

  List<Object?> get frameWithoutValue {
    final result = frame(null);
    (result[fieldContainerIndex] as Map<String, Object?>).remove(fieldName);
    return result;
  }

  int get fieldContainerIndex => path.startsWith('CALL.') ? 2 : 3;

  String get fieldName => path.substring(path.lastIndexOf('.') + 1);
}

class _SerializerHarness {
  const _SerializerHarness(this.name, this.encode, this.decode);

  final String name;
  final Uint8List Function(List<Object?> frame) encode;
  final Object? Function(Uint8List bytes) decode;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/src/message/call.dart';
import 'package:connectanum_core/src/message/event.dart';
import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/message/publish.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/codec.dart'
    as msgpack_codec;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

const _marker = 'attacker-controlled-marker';
const _maximumWampId = 0x20000000000000;
const _isWeb = bool.fromEnvironment('dart.library.js_interop');

final _serializers = <_SerializerHarness>[
  _SerializerHarness(
    'json',
    (frame) => Uint8List.fromList(utf8.encode(jsonEncode(frame))),
    json_serializer.Serializer().deserialize,
  ),
  _SerializerHarness(
    'msgpack',
    (frame) => _serializeMessagePackFixture(frame),
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
          final maximum = field.isWampId ? _maximumWampId : 42;
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

  group('MessagePack browser WAMP ID compatibility', () {
    final serializer = msgpack_serializer.Serializer();

    test('round-trips max INVOCATION IDs and disclosed caller', () {
      final decoded =
          serializer.deserialize(
                serializer.serialize(
                  Invocation(
                    _maximumWampId,
                    _maximumWampId,
                    InvocationDetails(_maximumWampId, null, null),
                  ),
                ),
              )
              as Invocation;

      expect(decoded.requestId, _maximumWampId);
      expect(decoded.registrationId, _maximumWampId);
      expect(decoded.details.caller, _maximumWampId);
    });

    test('round-trips max EVENT IDs and disclosed publisher', () {
      final decoded =
          serializer.deserialize(
                serializer.serialize(
                  Event(
                    _maximumWampId,
                    _maximumWampId,
                    EventDetails(publisher: _maximumWampId),
                  ),
                ),
              )
              as Event;

      expect(decoded.subscriptionId, _maximumWampId);
      expect(decoded.publicationId, _maximumWampId);
      expect(decoded.details.publisher, _maximumWampId);
    });

    test('accepts a max WAMP ID encoded as positive signed Int64', () {
      final decoded =
          serializer.deserialize(
                Uint8List.fromList(const [
                  0x94,
                  36,
                  1,
                  1,
                  0x81,
                  0xa9,
                  0x70,
                  0x75,
                  0x62,
                  0x6c,
                  0x69,
                  0x73,
                  0x68,
                  0x65,
                  0x72,
                  0xd3,
                  0,
                  0x20,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                ]),
              )
              as Event;

      expect(decoded.details.publisher, _maximumWampId);
    });

    test('round-trips nested wide integers on the slow path', () {
      final decoded =
          serializer.deserialize(
                serializer.serialize(
                  Publish(
                    _maximumWampId,
                    'com.example.topic',
                    options: PublishOptions(
                      eligible: const [_maximumWampId],
                      exclude: const [_maximumWampId],
                    ),
                    arguments: const [_maximumWampId, -_maximumWampId],
                    argumentsKeywords: const {'id': _maximumWampId},
                  ),
                ),
              )
              as Publish;

      expect(decoded.requestId, _maximumWampId);
      expect(decoded.options?.eligible, const [_maximumWampId]);
      expect(decoded.options?.exclude, const [_maximumWampId]);
      expect(decoded.arguments, const [_maximumWampId, -_maximumWampId]);
      expect(decoded.argumentsKeywords, const {'id': _maximumWampId});
    });

    test('rejects over-range WAMP IDs and truncated uint64 values', () {
      expect(
        () => serializer.deserialize(
          Uint8List.fromList(const [
            0x94,
            36,
            1,
            1,
            0x81,
            0xa9,
            0x70,
            0x75,
            0x62,
            0x6c,
            0x69,
            0x73,
            0x68,
            0x65,
            0x72,
            0xcf,
            0,
            0x20,
            0,
            0,
            0,
            0,
            0,
            1,
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => msgpack_codec.deserialize(
          Uint8List.fromList(const [0x91, 0xcf, 0, 0x20]),
        ),
        throwsA(anything),
      );
    });
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

Uint8List _serializeMessagePackFixture(Object? value) {
  if (value is int && value > _maximumUint32) {
    final bytes = Uint8List(9)..[0] = 0xcf;
    final data = ByteData.sublistView(bytes);
    data
      ..setUint32(1, value ~/ _uint32Base)
      ..setUint32(5, value % _uint32Base);
    return bytes;
  }
  if (value is List<Object?>) {
    final builder = BytesBuilder(copy: false)..add([0x90 | value.length]);
    for (final item in value) {
      builder.add(_serializeMessagePackFixture(item));
    }
    return builder.takeBytes();
  }
  if (value is Map<String, Object?>) {
    final builder = BytesBuilder(copy: false)..add([0x80 | value.length]);
    for (final entry in value.entries) {
      builder
        ..add(msgpack.serialize(entry.key))
        ..add(_serializeMessagePackFixture(entry.value));
    }
    return builder.takeBytes();
  }
  return msgpack.serialize(value);
}

const _maximumUint32 = 0xffffffff;
const _uint32Base = 0x100000000;

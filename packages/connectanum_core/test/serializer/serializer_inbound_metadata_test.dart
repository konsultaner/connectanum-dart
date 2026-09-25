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

const _types = ['CALL', 'PUBLISH', 'YIELD', 'RESULT', 'EVENT', 'INVOCATION'];
const _complete = <String, String>{
  'ppt_scheme': 'x_consumer',
  'ppt_serializer': 'cbor',
  'ppt_cipher': 'xsalsa20poly1305',
  'ppt_keyid': 'consumer-key-1',
};

void main() {
  final harnesses = <_Harness>[
    _Harness(
      'json',
      json_serializer.Serializer(),
      (value) => Uint8List.fromList(utf8.encode(jsonEncode(value))),
    ),
    _Harness('msgpack', msgpack_serializer.Serializer(), msgpack.serialize),
    _Harness(
      'cbor',
      cbor_serializer.Serializer(),
      (value) => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value))),
    ),
  ];
  final metadataCases = <String, Map<String, Object?>>{
    'absent': {},
    for (final entry in _complete.entries) entry.key: {entry.key: entry.value},
    'explicit nulls': {for (final key in _complete.keys) key: null},
    'empty strings': {for (final key in _complete.keys) key: ''},
    'complete': _complete,
    'escaped key': {'ppt_keyid': 'key"\\\n\u0000\u00e4\ud83d\udd11'},
  };
  const extension = <String, Object?>{
    'x_consumer': {
      'nested': [false, null, 17, 'value'],
    },
  };

  for (final harness in harnesses) {
    group('${harness.name} independently encoded inbound PPT metadata', () {
      for (final type in _types) {
        for (final entry in metadataCases.entries) {
          test('$type preserves ${entry.key} and extension fields', () {
            final input = {...entry.value, ...extension};
            final options = _readOptions(
              type,
              harness.decodeSuccessfully(type, input),
            );
            _expectPpt(options, entry.value);
            expect((options as CustomFieldContainer).custom, extension);
            expect(input, {...entry.value, ...extension});
          });
        }

        for (final field in _complete.keys) {
          for (final invalid in <Object>[
            0,
            false,
            1.5,
            <Object>[],
            <String, Object>{},
          ]) {
            test('$type rejects $field of type ${invalid.runtimeType}', () {
              expect(
                () => harness.decode(type, {..._complete, field: invalid}),
                throwsA(
                  anyOf(
                    isA<TypeError>(),
                    isA<FormatException>(),
                    isA<ArgumentError>(),
                  ),
                ),
              );
              final recovered = _readOptions(
                type,
                harness.decodeSuccessfully(type, _complete),
              );
              _expectPpt(recovered, _complete);
            });
          }
        }

        test('$type keeps independent metadata across consecutive frames', () {
          final first = _readOptions(
            type,
            harness.decodeSuccessfully(type, {
              ..._complete,
              ...extension,
            }),
          );
          final second = _readOptions(
            type,
            harness.decodeSuccessfully(type, {'x_second': false}),
          );
          expect(second, isNot(same(first)));
          _expectPpt(second, {});
          expect((second as CustomFieldContainer).custom, {'x_second': false});
          second.pptKeyId = 'new-key';
          (second as CustomFieldContainer).custom['new'] = true;
          _expectPpt(first, _complete);
          expect((first as CustomFieldContainer).custom, extension);
        });

        test(
          '$type empty dictionary retains its optional-container contract',
          () {
            final message = harness.decodeSuccessfully(type, {});
            switch (type) {
              case 'CALL':
                expect(message, isA<Call>());
                expect((message! as Call).options, isNull);
              case 'PUBLISH':
                expect(message, isA<Publish>());
                expect((message! as Publish).options, isNull);
              case 'YIELD':
                expect(message, isA<Yield>());
                expect((message! as Yield).options, isNull);
              default:
                final options = _readOptions(type, message);
                _expectPpt(options, {});
                expect((options as CustomFieldContainer).custom, isEmpty);
            }
          },
        );
      }
    });
  }
}

void _expectPpt(PPTOptions options, Map<String, Object?> expected) {
  expect(options.pptScheme, expected['ppt_scheme']);
  expect(options.pptSerializer, expected['ppt_serializer']);
  expect(options.pptCipher, expected['ppt_cipher']);
  expect(options.pptKeyId, expected['ppt_keyid']);
}

PPTOptions _readOptions(String type, AbstractMessage? message) {
  switch (type) {
    case 'CALL':
      expect(message, isA<Call>());
      final call = message! as Call;
      expect(call.requestId, 31);
      expect(call.procedure, 'com.example.procedure');
      return call.options!;
    case 'PUBLISH':
      expect(message, isA<Publish>());
      final publish = message! as Publish;
      expect(publish.requestId, 32);
      expect(publish.topic, 'com.example.topic');
      return publish.options!;
    case 'YIELD':
      expect(message, isA<Yield>());
      final yieldMessage = message! as Yield;
      expect(yieldMessage.invocationRequestId, 33);
      return yieldMessage.options!;
    case 'RESULT':
      expect(message, isA<Result>());
      final result = message! as Result;
      expect(result.callRequestId, 34);
      return result.details;
    case 'EVENT':
      expect(message, isA<Event>());
      final event = message! as Event;
      expect(event.subscriptionId, 35);
      expect(event.publicationId, 36);
      return event.details;
    case 'INVOCATION':
      expect(message, isA<Invocation>());
      final invocation = message! as Invocation;
      expect(invocation.requestId, 37);
      expect(invocation.registrationId, 38);
      return invocation.details;
    default:
      throw ArgumentError.value(type, 'type');
  }
}

class _Harness {
  const _Harness(this.name, this.serializer, this.encode);

  final String name;
  final AbstractSerializer serializer;
  final Uint8List Function(dynamic) encode;

  AbstractMessage? decodeSuccessfully(
    String type,
    Map<String, Object?> metadata,
  ) {
    AbstractMessage? message;
    expect(() => message = decode(type, metadata), returnsNormally);
    return message;
  }

  AbstractMessage? decode(String type, Map<String, Object?> metadata) {
    // Wire constants are independent of the WAMP serializers under test.
    final frame = switch (type) {
      'CALL' => [48, 31, metadata, 'com.example.procedure'],
      'PUBLISH' => [16, 32, metadata, 'com.example.topic'],
      'YIELD' => [70, 33, metadata],
      'RESULT' => [50, 34, metadata],
      'EVENT' => [36, 35, 36, metadata],
      'INVOCATION' => [68, 37, 38, metadata],
      _ => throw ArgumentError.value(type, 'type'),
    };
    return serializer.deserialize(encode(frame));
  }
}

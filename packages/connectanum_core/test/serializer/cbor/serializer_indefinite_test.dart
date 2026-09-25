import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart';
import 'package:test/test.dart';

const _ppt = <String, Object?>{
  'ppt_scheme': 'wamp',
  'ppt_serializer': 'cbor',
  'ppt_cipher': 'xsalsa20poly1305',
  'ppt_keyid': 'consumer-key',
};

class _UnsupportedMessage extends AbstractMessage {}

Uint8List _frame(
  List<Object?> fields, {
  required bool indefinite,
  bool nested = false,
  bool tagged = false,
}) {
  final builder = BytesBuilder();
  if (tagged) builder.add([0xd9, 0xd9, 0xf7]); // RFC 8949 self-described CBOR.
  builder.addByte(indefinite ? 0x9f : 0x80 + fields.length);
  for (final field in fields) {
    builder.add(_value(field, nested));
  }
  if (indefinite) builder.addByte(0xff);
  return builder.takeBytes();
}

List<int> _value(Object? value, bool indefinite) {
  if (indefinite && value is Map) {
    return [
      0xbf,
      for (final entry in value.entries) ...[
        ..._value(entry.key, true),
        ..._value(entry.value, true),
      ],
      0xff,
    ];
  }
  if (indefinite && value is List && value is! Uint8List) {
    return [0x9f, for (final item in value) ..._value(item, true), 0xff];
  }
  return cbor.cbor.encode(cbor.CborValue(value));
}

List<Object?> _payloadPrefix(int id, Map<String, Object?> details) =>
    switch (id) {
      48 => [48, 17, details, 'com.example.work'],
      16 => [16, 17, details, 'com.example.topic'],
      70 => [70, 17, details],
      50 => [50, 17, details],
      36 => [36, 17, 29, details],
      68 => [68, 17, 29, details],
      8 => [8, 48, 17, details, 'wamp.error.not_authorized'],
      _ => throw ArgumentError.value(id),
    };

void main() {
  group('CBOR chunk and scalar wire boundaries', () {
    final serializer = Serializer();
    Uint8List resultWithRawPayload(List<int> payload) => Uint8List.fromList([
      0x9f,
      0x18,
      0x32,
      0x11,
      0xa0,
      ...payload,
      0xff,
    ]);

    for (final (fragment, expected) in <(List<int>, List<int>)>[
      ([0x5f, 0xff], []),
      ([0x5f, 0x40, 0xff], []),
      ([0x5f, 0x42, 0, 255, 0x41, 128, 0xff], [0, 255, 128]),
    ]) {
      test('chunked transparent binary $fragment retains all bytes', () {
        final result =
            serializer.deserialize(resultWithRawPayload(fragment)) as Result;
        expect(result.callRequestId, 17);
        expect(result.transparentBinaryPayload, Uint8List.fromList(expected));
        expect(result.argumentsKeywords, isNull);
      });
    }

    test(
      'chunked UTF-8 text and byte strings retain nested payload values',
      () {
        final result =
            serializer.deserialize(
                  resultWithRawPayload([
                    0x82,
                    0x7f,
                    0x62,
                    0x68,
                    0x69,
                    0x62,
                    0xc3,
                    0xa4,
                    0xff,
                    0x5f,
                    0x41,
                    0,
                    0x41,
                    255,
                    0xff,
                  ]),
                )
                as Result;
        expect(result.arguments, [
          'hi\u00e4',
          Uint8List.fromList([0, 255]),
        ]);
        expect(result.argumentsKeywords, isNull);
      },
    );

    for (final fragment in <List<int>>[
      [0x5f],
      [0x5f, 0x40],
      [0x5f, 0x58, 5, 1],
      [0x7f],
      [0x7f, 0x60],
      [0x7f, 0x78, 5, 0x61],
      [0x9f, 0x9f],
      [0xbf, 0x61, 0x61],
    ]) {
      test('truncated indefinite payload $fragment fails closed', () {
        expect(
          () => serializer.deserialize(resultWithRawPayload(fragment)),
          throwsFormatException,
        );
        expect(
          (serializer.deserialize(resultWithRawPayload([0x80])) as Result)
              .arguments,
          isEmpty,
        );
      });
    }

    for (final fields in <List<Object?>>[
      [3, <String, Object?>{}, 17],
      [4, 17, <String, Object?>{}],
      [50, 17, 'not a dictionary'],
    ]) {
      test('invalid scalar type $fields is rejected', () {
        expect(
          () => serializer.deserialize(_frame(fields, indefinite: false)),
          throwsArgumentError,
        );
      });
    }

    test('unknown incoming message does not poison the next frame', () {
      expect(serializer.deserialize(_frame([999], indefinite: false)), isNull);
      expect(
        (serializer.deserialize(_frame([33, 17, 29], indefinite: false))
                as Subscribed)
            .subscriptionId,
        29,
      );
    });

    test('unsupported outgoing message fails explicitly', () {
      expect(
        () => serializer.serialize(_UnsupportedMessage()),
        throwsUnsupportedError,
      );
    });
  });

  for (final tagged in [false, true]) {
    for (final indefinite in [false, true]) {
      for (final nested in [false, true]) {
        group('CBOR tagged=$tagged indefinite=$indefinite nested=$nested', () {
          final serializer = Serializer();
          AbstractMessage decode(List<Object?> fields) =>
              serializer.deserialize(
                _frame(
                  fields,
                  indefinite: indefinite,
                  nested: nested,
                  tagged: tagged,
                ),
              )!;

          test('handshake and close preserve reason and message', () {
            final abort =
                decode([
                      3,
                      {'message': 'rejected'},
                      'wamp.error.not_authorized',
                    ])
                    as Abort;
            expect(abort.id, 3);
            expect(abort.reason, 'wamp.error.not_authorized');
            expect(abort.message!.message, 'rejected');
            final goodbye =
                decode([
                      6,
                      {'message': 'finished'},
                      'wamp.close.normal',
                    ])
                    as Goodbye;
            expect(goodbye.id, 6);
            expect(goodbye.reason, 'wamp.close.normal');
            expect(goodbye.message!.message, 'finished');
            expect(
              (decode([3, <String, Object?>{}, 'wamp.error.abort']) as Abort)
                  .message,
              isNull,
            );
            expect(
              (decode([6, <String, Object?>{}, 'wamp.close.normal']) as Goodbye)
                  .message
                  ?.message,
              isNull,
            );
          });

          test(
            'challenge preserves SCRAM fields and custom nullable metadata',
            () {
              final challenge =
                  decode([
                        4,
                        'scram',
                        {
                          'nonce': 'server-nonce',
                          'salt': 'c2FsdA==',
                          'kdf': 'argon2id-13',
                          'iterations': 3,
                          'memory': 65536,
                          'custom': null,
                        },
                      ])
                      as Challenge;
              expect(challenge.id, 4);
              expect(challenge.authMethod, 'scram');
              expect(challenge.extra.nonce, 'server-nonce');
              expect(challenge.extra.salt, 'c2FsdA==');
              expect(challenge.extra.kdf, 'argon2id-13');
              expect(challenge.extra.iterations, 3);
              expect(challenge.extra.memory, 65536);
              expect(challenge.extra.custom, containsPair('custom', null));
            },
          );

          test(
            'registration and publication acknowledgements preserve IDs',
            () {
              final registered = decode([65, 17, 29]) as Registered;
              expect(registered.registerRequestId, 17);
              expect(registered.registrationId, 29);
              expect(registered.id, 65);
              final unregistered = decode([67, 17]) as Unregistered;
              expect(unregistered.unregisterRequestId, 17);
              expect(unregistered.id, 67);
              final published = decode([17, 17, 29]) as Published;
              expect(published.publishRequestId, 17);
              expect(published.publicationId, 29);
              final subscribed = decode([33, 17, 29]) as Subscribed;
              expect(subscribed.subscribeRequestId, 17);
              expect(subscribed.subscriptionId, 29);
            },
          );

          test(
            'unsubscribe acknowledgement and revocation remain distinct',
            () {
              final normal = decode([35, 17]) as Unsubscribed;
              expect(normal.unsubscribeRequestId, 17);
              expect(normal.details, isNull);
              final empty =
                  decode([35, 0, <String, Object?>{}]) as Unsubscribed;
              expect(empty.unsubscribeRequestId, 0);
              expect(empty.details!.subscription, isNull);
              expect(empty.details!.reason, isNull);
              final revoked =
                  decode([
                        35,
                        0,
                        {
                          'subscription': 29,
                          'reason': 'wamp.error.not_authorized',
                        },
                      ])
                      as Unsubscribed;
              expect(revoked.unsubscribeRequestId, 0);
              expect(revoked.details!.subscription, 29);
              expect(revoked.details!.reason, 'wamp.error.not_authorized');
            },
          );

          for (final progress in <bool?>[null, false, true]) {
            test('result and invocation preserve progress=$progress', () {
              final metadata = <String, Object?>{
                ..._ppt,
                'progress': progress,
                'custom': [null, false, 7],
              };
              final result = decode([50, 17, metadata]) as Result;
              expect(result.callRequestId, 17);
              expect(result.details.progress, progress);
              expect(result.details.pptScheme, 'wamp');
              expect(result.details.pptSerializer, 'cbor');
              expect(result.details.pptCipher, 'xsalsa20poly1305');
              expect(result.details.pptKeyId, 'consumer-key');
              expect(result.details.custom, {
                'custom': [null, false, 7],
              });
              final invocation =
                  decode([
                        68,
                        17,
                        29,
                        {
                          ...metadata,
                          'caller': 41,
                          'procedure': 'com.example.work',
                          'receive_progress': progress,
                          'timeout': 73,
                        },
                      ])
                      as Invocation;
              expect(invocation.requestId, 17);
              expect(invocation.registrationId, 29);
              expect(invocation.details.caller, 41);
              expect(invocation.details.procedure, 'com.example.work');
              expect(invocation.details.progress, progress);
              expect(invocation.details.receiveProgress, progress);
              expect(invocation.details.timeout, 73);
              expect(invocation.details.pptScheme, 'wamp');
              expect(invocation.details.pptSerializer, 'cbor');
              expect(invocation.details.pptCipher, 'xsalsa20poly1305');
              expect(invocation.details.pptKeyId, 'consumer-key');
              expect(invocation.details.custom, {
                'custom': [null, false, 7],
              });
            });
          }

          test('event metadata preserves publisher, trust level and topic', () {
            final event =
                decode([
                      36,
                      17,
                      29,
                      {
                        ..._ppt,
                        'publisher': 41,
                        'trustlevel': 0,
                        'topic': 'com.example.topic',
                        'custom': null,
                      },
                    ])
                    as Event;
            expect(event.subscriptionId, 17);
            expect(event.publicationId, 29);
            expect(event.details.publisher, 41);
            expect(event.details.trustlevel, 0);
            expect(event.details.topic, 'com.example.topic');
            expect(event.details.pptScheme, 'wamp');
            expect(event.details.pptSerializer, 'cbor');
            expect(event.details.pptCipher, 'xsalsa20poly1305');
            expect(event.details.pptKeyId, 'consumer-key');
            expect(event.details.custom, {'custom': null});
          });

          for (final id in [48, 16, 70, 50, 36, 68, 8]) {
            for (final payload in <List<Object?>>[
              [],
              [<Object?>[]],
              [<Object?>[], <String, Object?>{}],
              [
                [
                  'body',
                  null,
                  Uint8List.fromList([0, 255]),
                  {'nested': false},
                ],
                {
                  'key': ['value', null],
                },
              ],
            ]) {
              test('message $id preserves payload $payload', () {
                final message =
                    decode([
                          ..._payloadPrefix(id, {}),
                          ...payload,
                        ])
                        as AbstractMessageWithPayload;
                expect(message.id, id);
                expect(message.arguments, payload.isEmpty ? null : payload[0]);
                expect(
                  message.argumentsKeywords,
                  payload.length < 2 ? null : payload[1],
                );
              });
            }
          }

          for (final bad in <Object?>[
            'true',
            0,
            1,
            <Object?>[],
            <String, Object?>{},
          ]) {
            for (final (id, key) in [
              (50, 'progress'),
              (68, 'progress'),
              (68, 'receive_progress'),
            ]) {
              test('message $id rejects $key=${bad.runtimeType} $bad', () {
                expect(
                  () => decode(_payloadPrefix(id, {key: bad})),
                  throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
                );
                final recovered = decode(_payloadPrefix(id, {key: false}));
                expect(recovered.id, id);
              });
            }
          }
        });
      }
    }
  }
}

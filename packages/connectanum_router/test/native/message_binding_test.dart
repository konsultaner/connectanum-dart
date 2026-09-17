@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:convert';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_router/src/native/message_binding.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

import '../../../connectanum_core/test/support/native_role_contract.dart';

void main() {
  for (final serializer in [
    NativeMessageSerializer.ubjson,
    NativeMessageSerializer.flatbuffers,
  ]) {
    test('unsupported inbound $serializer fails explicitly', () {
      expect(
        () => bindMessage(serializer, Uint8List.fromList([0xff])),
        throwsUnsupportedError,
      );
    });
  }
  for (final serializer in [
    NativeMessageSerializer.ubjson,
    NativeMessageSerializer.flatbuffers,
  ]) {
    test(
      'unsupported $serializer fails when a deferred fragment is accessed',
      () {
        final value =
            bindMessageFromMetadata(
                  serializer,
                  messageCode: 8,
                  primaryId: 48,
                  secondaryId: 19,
                  detailNumberA: 0,
                  flags: 16,
                  argsBytes: Uint8List.fromList([0xff]),
                  kwargsBytes: Uint8List.fromList([0xff]),
                )
                as Error;
        expect(value.requestTypeId, 48);
        expect(value.requestId, 19);
        expect(() => value.arguments, throwsUnsupportedError);
        expect(() => value.argumentsKeywords, throwsUnsupportedError);
      },
    );
  }
  test(
    'JSON binary tags normalize recursively without changing ordinary strings',
    () {
      final value =
          bindMessage(
                NativeMessageSerializer.json,
                Uint8List.fromList(
                  utf8.encode(
                    jsonEncode([
                      8,
                      48,
                      19,
                      {
                        'actual': '\u0000AQID',
                        'escaped': r'\u0000BAUG',
                        'nested': [
                          {'value': r'\u0000BwgJ'},
                          'ordinary',
                        ],
                        'empty': '',
                        'number': 7,
                      },
                      'com.error',
                    ]),
                  ),
                ),
              )
              as Error;
      expect(value.details, {
        'actual': [1, 2, 3],
        'escaped': [4, 5, 6],
        'nested': [
          {
            'value': [7, 8, 9],
          },
          'ordinary',
        ],
        'empty': '',
        'number': 7,
      });
    },
  );
  for (final serializer in [
    NativeMessageSerializer.json,
    NativeMessageSerializer.messagePack,
    NativeMessageSerializer.cbor,
  ]) {
    Uint8List encode(Object? value) => switch (serializer) {
      NativeMessageSerializer.json => Uint8List.fromList(
        utf8.encode(jsonEncode(value)),
      ),
      NativeMessageSerializer.messagePack => msgpack.serialize(value),
      NativeMessageSerializer.cbor => Uint8List.fromList(
        cbor.cbor.encode(cbor.CborValue(value)),
      ),
      _ => throw StateError('Unsupported test serializer: $serializer'),
    };
    group('full request frames $serializer', () {
      T decode<T extends AbstractMessage>(List<Object?> frame) =>
          bindMessage(serializer, encode(frame)) as T;

      test('rejects non-array and empty frames', () {
        for (final frame in <Object>[{}, 1, 'invalid', []]) {
          expect(
            () => bindMessage(serializer, encode(frame)),
            throwsArgumentError,
          );
        }
      });
      test('AUTHENTICATE preserves signature and channel-binding extra', () {
        final value = decode<Authenticate>([
          5,
          'proof',
          {'channel_binding': 'tls-exporter'},
        ]);
        expect(value.signature, 'proof');
        expect(value.extra, {'channel_binding': 'tls-exporter'});
        final absent = decode<Authenticate>([5]);
        expect(absent.signature, isNull);
        expect(absent.extra, isNull);
      });
      test('AUTHENTICATE without extra retains its proof', () {
        final value = decode<Authenticate>([5, 'proof-only']);
        expect(value.signature, 'proof-only');
        expect(value.extra, isNull);
      });
      for (var length = 1; length <= 5; length++) {
        test('HEARTBEAT preserves exactly $length wire fields', () {
          final frame = <Object?>[
            7,
            {'mode': 'ping'},
            0,
            17,
            29,
          ];
          final value = decode<Heartbeat>(frame.sublist(0, length));
          expect(value.details, length > 1 ? {'mode': 'ping'} : {});
          expect(value.ping, length > 2 ? 0 : null);
          expect(value.incoming, length > 3 ? 17 : null);
          expect(value.outgoing, length > 4 ? 29 : null);
        });
      }
      test('unknown message without fields remains an empty extension', () {
        final value = decode<UnknownMessage>([9999]);
        expect(value.id, 9999);
        expect(value.fields, isEmpty);
      });
      test('ABORT retains reason and message', () {
        final value = decode<Abort>([
          3,
          {'message': 'denied'},
          'wamp.error.not_authorized',
        ]);
        expect(value.reason, 'wamp.error.not_authorized');
        expect(value.message!.message, 'denied');
        expect(decode<Abort>([3]).reason, '');
        expect(decode<Abort>([3, {}]).message, isNull);
      });
      test('ABORT preserves the existing text shorthand', () {
        final value = decode<Abort>([
          3,
          'legacy explanation',
          'wamp.error.not_authorized',
        ]);
        expect(value.reason, 'wamp.error.not_authorized');
        expect(value.message?.message, 'legacy explanation');
        expect(value.details, {'message': 'legacy explanation'});
      });
      test('GOODBYE retains explanation and reason', () {
        final value = decode<Goodbye>([
          6,
          {'message': 'closing'},
          'wamp.close.normal',
        ]);
        expect(value.reason, 'wamp.close.normal');
        expect(value.message!.message, 'closing');
        expect(decode<Goodbye>([6]).message, isNull);
        expect(decode<Goodbye>([6]).reason, '');
      });
      test('GOODBYE without reason preserves its explanation', () {
        final value = decode<Goodbye>([
          6,
          {'message': 'closing'},
        ]);
        expect(value.message?.message, 'closing');
        expect(value.reason, '');
      });
      test('SUBSCRIBE separates known options and extensions', () {
        final value = decode<Subscribe>([
          32,
          23,
          {
            'match': 'prefix',
            'meta_topic': 'com.meta',
            'get_retained': false,
            'extension': {'trace': 'sub'},
          },
          'com.topic',
        ]);
        expect(value.requestId, 23);
        expect(value.topic, 'com.topic');
        expect(value.options!.match, 'prefix');
        expect(value.options!.metaTopic, 'com.meta');
        expect(value.options!.getRetained, isFalse);
        expect(value.options!.custom, {
          'extension': {'trace': 'sub'},
        });
        expect(decode<Subscribe>([32, 24, null, 'com.topic']).options, isNull);
      });
      test(
        'UNSUBSCRIBE and UNREGISTER keep independent request/entity IDs',
        () {
          final subscription = decode<Unsubscribe>([34, 27, 83]);
          expect(subscription.requestId, 27);
          expect(subscription.subscriptionId, 83);
          final registration = decode<Unregister>([66, 28, 84]);
          expect(registration.requestId, 28);
          expect(registration.registrationId, 84);
        },
      );
      for (final mode in <String?>[null, 'skip', 'kill', 'killnowait']) {
        test('CANCEL and INTERRUPT preserve mode $mode', () {
          final options = mode == null ? null : {'mode': mode};
          final cancel = decode<Cancel>([49, 29, options]);
          expect(cancel.requestId, 29);
          expect(cancel.options?.mode, mode);
          final interrupt = decode<Interrupt>([69, 30, options]);
          expect(interrupt.requestId, 30);
          expect(interrupt.options?.mode, mode);
          if (mode == null) {
            expect(cancel.options, isNull);
            expect(interrupt.options, isNull);
          }
        });
      }
      test('CANCEL INTERRUPT and YIELD allow absent optional dictionaries', () {
        final cancel = decode<Cancel>([49, 29]);
        expect(cancel.requestId, 29);
        expect(cancel.options, isNull);
        final interrupt = decode<Interrupt>([69, 30]);
        expect(interrupt.requestId, 30);
        expect(interrupt.options, isNull);
        final yielded = decode<Yield>([70, 31]);
        expect(yielded.invocationRequestId, 31);
        expect(yielded.options, isNull);
        expect(yielded.arguments, isNull);
        expect(yielded.argumentsKeywords, isNull);
      });
      test(
        'REGISTER keeps policy, disclosure, timeout and extension options',
        () {
          final value = decode<Register>([
            64,
            31,
            {
              'match': 'wildcard',
              'invoke': 'roundrobin',
              'disclose_caller': false,
              'forward_timeout': true,
              'extension': 7,
            },
            'com..procedure',
          ]);
          expect(value.requestId, 31);
          expect(value.procedure, 'com..procedure');
          expect(value.options!.match, 'wildcard');
          expect(value.options!.invoke, 'roundrobin');
          expect(value.options!.discloseCaller, isFalse);
          expect(value.options!.forwardTimeout, isTrue);
          expect(value.options!.custom, {'extension': 7});
          expect(decode<Register>([64, 32, null, 'com.proc']).options, isNull);
        },
      );
      test(
        'YIELD retains progress, passthrough metadata and custom fields',
        () {
          final value = decode<Yield>([
            70,
            33,
            {
              'progress': false,
              'ppt_scheme': 'wamp',
              'ppt_serializer': 'cbor',
              'ppt_cipher': 'cipher',
              'ppt_keyid': 'key',
              'extension': 'yield',
            },
          ]);
          expect(value.invocationRequestId, 33);
          expect(value.options!.progress, isFalse);
          expect(value.options!.pptScheme, 'wamp');
          expect(value.options!.pptSerializer, 'cbor');
          expect(value.options!.pptCipher, 'cipher');
          expect(value.options!.pptKeyId, 'key');
          expect(value.options!.custom, {'extension': 'yield'});
        },
      );
      test(
        'ERROR keeps request type, identity, URI, details and lazy payload',
        () {
          final value =
              bindMessage(
                    serializer,
                    encode([
                      8,
                      68,
                      34,
                      {'trace': 'error'},
                      'com.failure',
                    ]),
                    argsBytes: encode([1, 'reason']),
                    kwargsBytes: encode({'code': 2}),
                  )
                  as Error;
          expect(value.requestTypeId, 68);
          expect(value.requestId, 34);
          expect(value.error, 'com.failure');
          expect(value.details, {'trace': 'error'});
          expect(value.arguments, [1, 'reason']);
          expect(value.argumentsKeywords, {'code': 2});
          final absent = decode<Error>([8, 68, 35, null]);
          expect(absent.details, isEmpty);
          expect(absent.error, isNull);
        },
      );
    });
    group('metadata fallback contracts $serializer', () {
      for (final code in [16, 48, 70]) {
        for (final selected in [-1, 0, 1, 2, 3]) {
          for (final text in ['', 'value']) {
            test(
              'code $code preserves sole PPT slot $selected=$text without details bytes',
              () {
                final strings = [
                  for (var i = 0; i < 4; i++) i == selected ? text : null,
                ];
                final value = bindMessageFromMetadata(
                  serializer,
                  messageCode: code,
                  primaryId: 41,
                  secondaryId: 62,
                  detailNumberA: 0,
                  flags: 17,
                  stringA: code == 70 ? strings[0] : 'com.target',
                  stringB: code == 70 ? strings[1] : strings[0],
                  stringC: code == 70 ? strings[2] : strings[1],
                  stringD: code == 70 ? strings[3] : strings[2],
                  stringE: code == 70 ? null : strings[3],
                );
                final PPTOptions? options = switch (value) {
                  Publish() => value.options,
                  Call() => value.options,
                  Yield() => value.options,
                  _ => throw StateError('unexpected PPT type'),
                };
                if (selected < 0) {
                  expect(options, isNull);
                } else {
                  expect(options, isNotNull);
                  expect([
                    options!.pptScheme,
                    options.pptSerializer,
                    options.pptCipher,
                    options.pptKeyId,
                  ], strings);
                }
              },
            );
          }
        }
      }
      for (final code in [32, 64]) {
        for (final selected in [-1, 0, 1]) {
          test(
            'code $code preserves sole policy slot $selected without details bytes',
            () {
              final value = bindMessageFromMetadata(
                serializer,
                messageCode: code,
                primaryId: 41,
                secondaryId: 62,
                detailNumberA: 0,
                flags: 17,
                stringA: 'com.target',
                stringB: selected == 0 ? 'prefix' : null,
                stringC: selected == 1
                    ? (code == 32 ? 'com.meta' : 'roundrobin')
                    : null,
              );
              switch (value) {
                case Subscribe():
                  if (selected < 0) {
                    expect(value.options, isNull);
                  } else {
                    expect(value.options, isNotNull);
                    expect(
                      value.options!.match,
                      selected == 0 ? 'prefix' : null,
                    );
                    expect(
                      value.options!.metaTopic,
                      selected == 1 ? 'com.meta' : null,
                    );
                    expect(value.options!.getRetained, isNull);
                  }
                case Register():
                  if (selected < 0) {
                    expect(value.options, isNull);
                  } else {
                    expect(value.options, isNotNull);
                    expect(
                      value.options!.match,
                      selected == 0 ? 'prefix' : null,
                    );
                    expect(
                      value.options!.invoke,
                      selected == 1 ? 'roundrobin' : null,
                    );
                    expect(value.options!.discloseCaller, isNull);
                    expect(value.options!.forwardTimeout, isNull);
                  }
                default:
                  fail('unexpected policy type');
              }
            },
          );
        }
      }
      final authFields = <String, String? Function(Details)>{
        'authid': (d) => d.authid,
        'authrole': (d) => d.authrole,
        'authmethod': (d) => d.authmethod,
        'authprovider': (d) => d.authprovider,
      };
      for (final selected in authFields.keys) {
        for (final direct in [false, true]) {
          for (final text in ['', 'metadata-$selected']) {
            test(
              'HELLO $selected=$text direct=$direct preserves auth authority',
              () {
                final strings = [
                  for (final field in authFields.keys)
                    field == selected ? text : null,
                ];
                final value =
                    bindMessageFromMetadata(
                          serializer,
                          messageCode: 1,
                          primaryId: 0,
                          secondaryId: 0,
                          detailNumberA: 0,
                          flags: direct ? 17 : 16,
                          stringA: 'realm',
                          stringB: strings[0],
                          stringC: strings[1],
                          stringD: strings[2],
                          stringE: strings[3],
                          detailsBytes: encode({
                            for (final field in authFields.keys)
                              field: 'wire-$field',
                            'roles': {'caller': {}},
                            'extension': 17,
                          }),
                        )
                        as Hello;
                expect(value.realm, 'realm');
                expect(value.details.roles!.caller, isNotNull);
                for (final field in authFields.entries) {
                  expect(
                    field.value(value.details),
                    direct && field.key == selected
                        ? text
                        : 'wire-${field.key}',
                    reason: field.key,
                  );
                }
                expect(value.details.custom, {'extension': 17});
              },
            );
          }
        }
      }
      test(
        'entry point passes metadata IDs, timeout and payload fragments',
        () {
          final value =
              bindMessage(
                    serializer,
                    Uint8List.fromList([0xff]),
                    metadataMessageCode: 48,
                    metadataPrimaryId: 41,
                    metadataSecondaryId: 62,
                    metadataDetailNumberA: 73,
                    metadataFlags: 19,
                    metadataStringA: 'com.proc',
                    argsBytes: encode([12]),
                    kwargsBytes: encode({'key': 13}),
                  )
                  as Call;
          expect(value.requestId, 41);
          expect(value.procedure, 'com.proc');
          expect(value.options!.timeout, 73);
          expect(value.arguments, [12]);
          expect(value.argumentsKeywords, {'key': 13});
          final error =
              bindMessage(
                    serializer,
                    Uint8List.fromList([0xff]),
                    metadataMessageCode: 8,
                    metadataPrimaryId: 48,
                    metadataSecondaryId: 62,
                    metadataFlags: 17,
                    metadataStringA: 'com.error',
                  )
                  as Error;
          expect(error.requestTypeId, 48);
          expect(error.requestId, 62);
          expect(error.error, 'com.error');
        },
      );
      for (final bits in [0, 2, 8, 32, 64, 128, 2 | 8 | 32 | 64 | 128]) {
        test(
          'direct feature bits $bits remain independent between message types',
          () {
            T decodeFlags<T extends AbstractMessage>(int code) =>
                bindMessageFromMetadata(
                      serializer,
                      messageCode: code,
                      primaryId: 41,
                      secondaryId: 62,
                      detailNumberA: 0,
                      flags: 17 | bits,
                      stringA: code == 70 ? null : 'com.target',
                      detailsBytes: encode({'extension': 1}),
                    )
                    as T;
            final publish = decodeFlags<Publish>(16).options!;
            expect(publish.acknowledge, bits & 8 != 0 ? true : null);
            expect(publish.excludeMe, bits & 32 != 0 ? true : null);
            expect(publish.discloseMe, bits & 64 != 0 ? true : null);
            expect(publish.retain, bits & 128 != 0 ? true : null);
            final call = decodeFlags<Call>(48).options!;
            expect(call.timeout, bits & 2 != 0 ? 0 : null);
            expect(call.receiveProgress, bits & 8 != 0 ? true : null);
            expect(call.discloseMe, bits & 32 != 0 ? true : null);
            expect(call.progress, bits & 64 != 0 ? true : null);
            final register = decodeFlags<Register>(64).options!;
            expect(register.discloseCaller, bits & 8 != 0 ? true : null);
            expect(register.forwardTimeout, bits & 32 != 0 ? true : null);
            final sub = decodeFlags<Subscribe>(32).options!;
            expect(sub.getRetained, bits & 8 != 0 ? true : null);
            final result = decodeFlags<Yield>(70).options!;
            expect(result.progress, bits & 8 != 0);
            for (final options in <CustomFieldContainer>[
              publish,
              call,
              register,
              sub,
              result,
            ]) {
              expect(options.custom, {'extension': 1});
            }
          },
        );
      }
      test(
        'direct ERROR message precedes a conflicting lazy details value',
        () {
          final error =
              bindMessageFromMetadata(
                    serializer,
                    messageCode: 8,
                    primaryId: 48,
                    secondaryId: 62,
                    detailNumberA: 0,
                    flags: 17,
                    stringA: 'com.error',
                    stringB: 'metadata',
                    detailsBytes: encode({
                      'message': 'ignored',
                      'extension': 1,
                    }),
                  )
                  as Error;
          expect(error.requestTypeId, 48);
          expect(error.requestId, 62);
          expect(error.error, 'com.error');
          expect(error.details, {'message': 'metadata', 'extension': 1});
        },
      );
      for (final explanation in ['', 'authoritative']) {
        test('direct ABORT uses authoritative message $explanation', () {
          final value =
              bindMessageFromMetadata(
                    serializer,
                    messageCode: 3,
                    primaryId: 0,
                    secondaryId: 0,
                    detailNumberA: 0,
                    flags: 17,
                    stringA: 'wamp.error.not_authorized',
                    stringB: explanation,
                    detailsBytes: encode({
                      'message': 'not authoritative',
                      'extension': 1,
                    }),
                  )
                  as Abort;
          expect(value.reason, 'wamp.error.not_authorized');
          expect(value.message?.message, explanation);
          expect(value.details, {'message': explanation, 'extension': 1});
        });
      }
      for (final direct in [false, true]) {
        test(
          'AUTHENTICATE distinguishes absent and empty extra direct=$direct',
          () {
            for (final present in [false, true]) {
              final value =
                  bindMessageFromMetadata(
                        serializer,
                        messageCode: 5,
                        primaryId: 0,
                        secondaryId: 0,
                        detailNumberA: 0,
                        flags: direct ? 17 : 16,
                        stringA: 'proof',
                        detailsBytes: present ? encode({}) : null,
                      )
                      as Authenticate;
              expect(value.signature, 'proof');
              expect(value.extra, present ? isEmpty : isNull);
            }
          },
        );
      }
      for (final message in <String?>[null, '', 'closing']) {
        test('direct GOODBYE keeps nullable message $message', () {
          final value =
              bindMessageFromMetadata(
                    serializer,
                    messageCode: 6,
                    primaryId: 0,
                    secondaryId: 0,
                    detailNumberA: 0,
                    flags: 17,
                    stringA: 'wamp.close.normal',
                    stringB: message,
                    detailsBytes: encode({'message': 'ignored'}),
                  )
                  as Goodbye;
          expect(value.reason, 'wamp.close.normal');
          expect(value.message?.message, message);
          if (message == null) expect(value.message, isNull);
        });
      }
      test('UNREGISTER retains independent request and registration IDs', () {
        final value =
            bindMessageFromMetadata(
                  serializer,
                  messageCode: 66,
                  primaryId: 41,
                  secondaryId: 62,
                  detailNumberA: 0,
                  flags: 16,
                )
                as Unregister;
        expect(value.requestId, 41);
        expect(value.registrationId, 62);
      });
      for (final code in [16, 32, 48, 64, 70]) {
        test(
          'direct code $code keeps extension-only options with no feature flags',
          () {
            final value = bindMessageFromMetadata(
              serializer,
              messageCode: code,
              primaryId: 41,
              secondaryId: 62,
              detailNumberA: 99,
              flags: 17,
              stringA: code == 70 ? null : 'com.target',
              detailsBytes: encode({'extension': 1}),
            );
            final options = switch (value) {
              Publish() => value.options,
              Subscribe() => value.options,
              Call() => value.options,
              Register() => value.options,
              Yield() => value.options,
              _ => throw StateError('unexpected options type'),
            };
            expect(options, isNotNull);
            expect(options!.custom, {'extension': 1});
            switch (value) {
              case Publish():
                expect(value.options!.acknowledge, isNull);
              case Subscribe():
                expect(value.options!.match, isNull);
              case Call():
                expect(value.options!.timeout, isNull);
              case Register():
                expect(value.options!.discloseCaller, isNull);
              case Yield():
                expect(value.options!.progress, isFalse);
            }
          },
        );
      }
      for (final present in [false, true]) {
        test(
          'direct revocation flag preserves a zero subscription present=$present',
          () {
            final value =
                bindMessageFromMetadata(
                      serializer,
                      messageCode: 35,
                      primaryId: 0,
                      secondaryId: 0,
                      detailNumberA: 0,
                      flags: present ? 19 : 17,
                    )
                    as Unsubscribed;
            expect(value.unsubscribeRequestId, 0);
            expect(value.details?.subscription, present ? 0 : null);
            expect(value.details?.reason, isNull);
            if (!present) expect(value.details, isNull);
          },
        );
      }
      T decode<T extends AbstractMessage>(
        int code,
        Object? details, {
        String? stringA = 'com.target',
      }) =>
          bindMessageFromMetadata(
                serializer,
                messageCode: code,
                primaryId: 41,
                secondaryId: 62,
                detailNumberA: 999,
                flags: 16,
                stringA: stringA,
                stringB: 'ignored',
                stringC: 'ignored',
                stringD: 'ignored',
                stringE: 'ignored',
                detailsBytes: encode(details),
              )
              as T;

      for (final flags in [0, 1]) {
        test(
          'missing metadata flag $flags returns null without reading fragments',
          () {
            expect(
              bindMessageFromMetadata(
                serializer,
                messageCode: 1,
                primaryId: 41,
                secondaryId: 62,
                detailNumberA: 0,
                flags: flags,
                stringA: 'realm',
                detailsBytes: Uint8List.fromList([0xff]),
              ),
              isNull,
            );
          },
        );
      }
      final frames = <int, List<Object?>>{
        1: [1, 'realm', {}],
        16: [16, 41, {}, 'com.topic'],
        32: [32, 41, {}, 'com.topic'],
        48: [48, 41, {}, 'com.proc'],
        64: [64, 41, {}, 'com.proc'],
      };
      for (final frame in frames.entries) {
        for (final direct in [false, true]) {
          test(
            'code ${frame.key} without required metadata string falls back direct=$direct',
            () {
              expect(
                bindMessageFromMetadata(
                  serializer,
                  messageCode: frame.key,
                  primaryId: 99,
                  secondaryId: 98,
                  detailNumberA: 97,
                  flags: direct ? 17 : 16,
                ),
                isNull,
              );
              final value = bindMessage(
                serializer,
                encode(frame.value),
                metadataMessageCode: frame.key,
                metadataPrimaryId: 99,
                metadataSecondaryId: 98,
                metadataFlags: direct ? 17 : 16,
              );
              expect(value.id, frame.key);
              switch (value) {
                case Hello():
                  expect(value.realm, 'realm');
                case Publish():
                  expect(value.requestId, 41);
                  expect(value.topic, 'com.topic');
                case Subscribe():
                  expect(value.requestId, 41);
                  expect(value.topic, 'com.topic');
                case Call():
                  expect(value.requestId, 41);
                  expect(value.procedure, 'com.proc');
                case Register():
                  expect(value.requestId, 41);
                  expect(value.procedure, 'com.proc');
                default:
                  fail('unexpected fallback type ${value.runtimeType}');
              }
            },
          );
        }
      }
      for (final options in <Map<String, Object?>?>[
        null,
        {},
        {'mode': 'killnowait'},
      ]) {
        test(
          'CANCEL and INTERRUPT read options $options, not string slots',
          () {
            final cancel = decode<Cancel>(49, options);
            final interrupt = decode<Interrupt>(69, options);
            expect(cancel.requestId, 41);
            expect(interrupt.requestId, 41);
            expect(cancel.options?.mode, options?['mode']);
            expect(interrupt.options?.mode, options?['mode']);
            if (options == null) expect(cancel.options, isNull);
            if (options?['mode'] == null) expect(interrupt.options, isNull);
          },
        );
      }
      for (final present in [false, true]) {
        test('optional fields and extensions present=$present', () {
          final publish = decode<Publish>(
            16,
            present
                ? {
                    'acknowledge': false,
                    'exclude_me': false,
                    'disclose_me': false,
                    'retain': false,
                    'exclude': [11, 12],
                    'eligible': [21],
                    'exclude_authid': ['alice'],
                    'exclude_authrole': ['guest'],
                    'eligible_authid': ['bob'],
                    'eligible_authrole': ['member'],
                    'ppt_scheme': 'scheme',
                    'ppt_serializer': 'cbor',
                    'ppt_cipher': 'cipher',
                    'ppt_keyid': 'key',
                    'extension': 1,
                  }
                : null,
          );
          expect(publish.requestId, 41);
          expect(publish.topic, 'com.target');
          if (present) {
            final o = publish.options!;
            expect(o.acknowledge, isFalse);
            expect(o.excludeMe, isFalse);
            expect(o.discloseMe, isFalse);
            expect(o.retain, isFalse);
            expect(o.exclude, [11, 12]);
            expect(o.eligible, [21]);
            expect(o.excludeAuthId, ['alice']);
            expect(o.excludeAuthRole, ['guest']);
            expect(o.eligibleAuthId, ['bob']);
            expect(o.eligibleAuthRole, ['member']);
            expect(o.pptScheme, 'scheme');
            expect(o.pptSerializer, 'cbor');
            expect(o.pptCipher, 'cipher');
            expect(o.pptKeyId, 'key');
            expect(o.custom, {'extension': 1});
          } else {
            expect(publish.options, isNull);
          }

          final sub = decode<Subscribe>(
            32,
            present
                ? {
                    'match': 'prefix',
                    'meta_topic': 'com.meta',
                    'get_retained': false,
                    'extension': 2,
                  }
                : null,
          );
          expect(sub.requestId, 41);
          expect(sub.topic, 'com.target');
          expect(sub.options?.match, present ? 'prefix' : null);
          expect(sub.options?.metaTopic, present ? 'com.meta' : null);
          expect(sub.options?.getRetained, present ? false : null);
          expect(sub.options?.custom, present ? {'extension': 2} : null);
          if (!present) expect(sub.options, isNull);

          final call = decode<Call>(
            48,
            present
                ? {
                    'progress': false,
                    'receive_progress': false,
                    'timeout': 0,
                    'disclose_me': false,
                    'ppt_scheme': 'scheme',
                    'ppt_serializer': 'cbor',
                    'ppt_cipher': 'cipher',
                    'ppt_keyid': 'key',
                    'extension': 3,
                  }
                : null,
          );
          expect(call.requestId, 41);
          expect(call.procedure, 'com.target');
          expect(call.options?.progress, present ? false : null);
          expect(call.options?.receiveProgress, present ? false : null);
          expect(call.options?.timeout, present ? 0 : null);
          expect(call.options?.discloseMe, present ? false : null);
          expect(call.options?.pptScheme, present ? 'scheme' : null);
          expect(call.options?.pptSerializer, present ? 'cbor' : null);
          expect(call.options?.pptCipher, present ? 'cipher' : null);
          expect(call.options?.pptKeyId, present ? 'key' : null);
          expect(call.options?.custom, present ? {'extension': 3} : null);
          if (!present) expect(call.options, isNull);

          final reg = decode<Register>(
            64,
            present
                ? {
                    'match': 'wildcard',
                    'invoke': 'roundrobin',
                    'disclose_caller': false,
                    'forward_timeout': false,
                    'extension': 4,
                  }
                : null,
          );
          expect(reg.requestId, 41);
          expect(reg.procedure, 'com.target');
          expect(reg.options?.match, present ? 'wildcard' : null);
          expect(reg.options?.invoke, present ? 'roundrobin' : null);
          expect(reg.options?.discloseCaller, present ? false : null);
          expect(reg.options?.forwardTimeout, present ? false : null);
          expect(reg.options?.custom, present ? {'extension': 4} : null);
          if (!present) expect(reg.options, isNull);

          final result = decode<Yield>(
            70,
            present
                ? {
                    'progress': false,
                    'ppt_scheme': 'scheme',
                    'ppt_serializer': 'cbor',
                    'ppt_cipher': 'cipher',
                    'ppt_keyid': 'key',
                    'extension': 5,
                  }
                : null,
          );
          expect(result.invocationRequestId, 41);
          expect(result.options?.progress, present ? false : null);
          expect(result.options?.pptScheme, present ? 'scheme' : null);
          expect(result.options?.pptSerializer, present ? 'cbor' : null);
          expect(result.options?.pptCipher, present ? 'cipher' : null);
          expect(result.options?.pptKeyId, present ? 'key' : null);
          expect(result.options?.custom, present ? {'extension': 5} : null);
          if (!present) expect(result.options, isNull);

          final ack = decode<Unsubscribed>(
            35,
            present ? {'subscription': 0, 'reason': 'com.revoked'} : null,
          );
          expect(ack.unsubscribeRequestId, 41);
          expect(ack.details?.subscription, present ? 0 : null);
          expect(ack.details?.reason, present ? 'com.revoked' : null);
          if (!present) expect(ack.details, isNull);
        });
      }
      for (final details in <Map<String, Object?>?>[
        null,
        {},
        {'message': ''},
        {'message': 'closing'},
      ]) {
        test('GOODBYE and ERROR read nullable detail map $details', () {
          final goodbye = decode<Goodbye>(6, details);
          expect(goodbye.reason, 'com.target');
          expect(goodbye.message?.message, details?['message']);
          if (details?['message'] == null) expect(goodbye.message, isNull);
          final error = decode<Error>(8, details);
          expect(error.requestTypeId, 41);
          expect(error.requestId, 62);
          expect(error.error, 'com.target');
          expect(error.details, details ?? {});
        });
      }
      test('unknown metadata retains fields and request correlation', () {
        final value = decode<UnknownMessage>(9999, {
          'fields': ['opaque', 1],
          'request_id': 72,
        });
        expect(value.id, 9999);
        expect(value.requestId, 72);
        expect(value.fields, ['opaque', 1]);
      });
      test('unknown metadata without a fields list is not materialized', () {
        expect(
          bindMessageFromMetadata(
            serializer,
            messageCode: 9999,
            primaryId: 41,
            secondaryId: 62,
            detailNumberA: 0,
            flags: 16,
            detailsBytes: encode({'fields': 'invalid'}),
          ),
          isNull,
        );
      });
    });
    group('fragment boundaries $serializer', () {
      AbstractMessage metadata(int code, bool direct, Uint8List? bytes) =>
          bindMessageFromMetadata(
            serializer,
            messageCode: code,
            primaryId: 48,
            secondaryId: 19,
            detailNumberA: 0,
            flags: direct ? 17 : 16,
            stringA: 'com.reason',
            detailsBytes: bytes,
          )!;
      for (final code in [3, 8]) {
        for (final direct in [false, true]) {
          for (final encodedNull in [false, true]) {
            test(
              'code $code absent details direct=$direct encodedNull=$encodedNull',
              () {
                final value = metadata(
                  code,
                  direct,
                  encodedNull ? encode(null) : null,
                );
                if (value is Abort) {
                  expect(value.details, isEmpty);
                  expect(value.message, isNull);
                  expect(value.reason, 'com.reason');
                } else {
                  final error = value as Error;
                  expect(error.details, isEmpty);
                  expect(error.error, 'com.reason');
                  expect(error.requestTypeId, 48);
                  expect(error.requestId, 19);
                }
              },
            );
          }
          test('code $code rejects non-map details direct=$direct', () {
            expect(() {
              final value = metadata(code, direct, encode(['not a map']));
              if (value is Abort) {
                value.details.length;
              } else {
                (value as Error).details.length;
              }
            }, throwsArgumentError);
          });
        }
      }
      test(
        'malformed full-frame details and positional payload fail closed',
        () {
          expect(
            () => bindMessage(
              serializer,
              encode([
                8,
                48,
                19,
                ['not a map'],
                'com.error',
              ]),
            ),
            throwsArgumentError,
          );
          expect(
            () => bindMessage(
              serializer,
              encode([
                3,
                {},
                'com.reason',
                {'not': 'a list'},
              ]),
            ),
            throwsArgumentError,
          );
        },
      );
      test('integer-valued numeric heartbeat counters remain compatible', () {
        final value =
            bindMessage(serializer, encode([7, {}, 1.0, 2.0, 3.0]))
                as Heartbeat;
        expect(value.ping, 1);
        expect(value.incoming, 2);
        expect(value.outgoing, 3);
      });
      test(
        'empty frame reports a protocol shape error, not an index error',
        () {
          expect(
            () => bindMessage(serializer, encode([])),
            throwsA(
              isA<ArgumentError>().having(
                (error) => error.message,
                'message',
                'WAMP message cannot be empty',
              ),
            ),
          );
        },
      );
      for (final selection in [(true, false), (false, true), (true, true)]) {
        test('ABORT overlays only selected fragments $selection', () {
          final value =
              bindMessage(
                    serializer,
                    encode([
                      3,
                      {'message': 'denied'},
                      'com.denied',
                      [101],
                      {'source': 'frame'},
                    ]),
                    argsBytes: selection.$1 ? encode([202]) : null,
                    kwargsBytes: selection.$2
                        ? encode({'source': 'fragment'})
                        : null,
                  )
                  as Abort;
          expect(value.arguments, selection.$1 ? [202] : [101]);
          expect(value.argumentsKeywords, {
            'source': selection.$2 ? 'fragment' : 'frame',
          });
          expect(value.details, {'message': 'denied'});
          expect(value.message?.message, 'denied');
          expect(value.reason, 'com.denied');
        });
      }
      test('encoded null payload fragments normalize to empty containers', () {
        final value =
            bindMessage(
                  serializer,
                  encode([8, 48, 19, {}, 'com.failure']),
                  argsBytes: encode(null),
                  kwargsBytes: encode(null),
                )
                as Error;
        expect(value.arguments, isEmpty);
        expect(value.argumentsKeywords, isEmpty);
      });
      test('malformed argument fragments reject when accessed', () {
        final value =
            bindMessage(
                  serializer,
                  encode([8, 48, 19, {}, 'com.failure']),
                  argsBytes: encode({'not': 'a list'}),
                )
                as Error;
        expect(() => value.arguments, throwsArgumentError);
      });
      test('malformed keyword fragments reject when accessed', () {
        final value =
            bindMessage(
                  serializer,
                  encode([8, 48, 19, {}, 'com.failure']),
                  kwargsBytes: encode(['not', 'a map']),
                )
                as Error;
        expect(() => value.argumentsKeywords, throwsArgumentError);
      });
    });
    for (final mode in ['frame', 'fragments', 'metadata']) {
      group('ABORT $serializer $mode', () {
        nativeAbortContracts(
          (details, args, kwargs) =>
              bindMessage(
                    serializer,
                    mode == 'metadata'
                        ? Uint8List.fromList([0xff])
                        : encode([
                            3,
                            details,
                            'wamp.error.not_authorized',
                            if (mode == 'frame' && args != null) args,
                            if (mode == 'frame' && kwargs != null) kwargs,
                          ]),
                    argsBytes: mode != 'frame' && args != null
                        ? encode(args)
                        : null,
                    kwargsBytes: mode != 'frame' && kwargs != null
                        ? encode(kwargs)
                        : null,
                    metadataMessageCode: mode == 'metadata' ? 3 : null,
                    metadataFlags: mode == 'metadata' ? 1 << 4 : null,
                    metadataStringA: mode == 'metadata'
                        ? 'wamp.error.not_authorized'
                        : null,
                    metadataDetailsBytes: mode == 'metadata'
                        ? encode(details)
                        : null,
                  )
                  as Abort,
        );
      });
    }
    for (final fromMetadata in [false, true]) {
      group('HELLO roles $serializer metadata=$fromMetadata', () {
        nativeRoleContracts((details) {
          final message =
              bindMessage(
                    serializer,
                    fromMetadata
                        ? Uint8List.fromList([0xff])
                        : encode([
                            MessageTypes.codeHello,
                            'consumer.realm',
                            details,
                          ]),
                    metadataMessageCode: fromMetadata
                        ? MessageTypes.codeHello
                        : null,
                    metadataFlags: fromMetadata ? 1 << 4 : null,
                    metadataStringA: fromMetadata ? 'consumer.realm' : null,
                    metadataDetailsBytes: fromMetadata ? encode(details) : null,
                  )
                  as Hello;
          expect(message.realm, 'consumer.realm');
          return message.details;
        });
      });
    }
  }
  group('bindMessage', () {
    test('decodes standard Subscriber feature keys from Hello', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              MessageTypes.codeHello,
              'bench.realm',
              {
                'roles': {
                  'subscriber': {
                    'features': {'publication_trustlevels': true},
                  },
                },
              },
            ]),
          ),
        ),
      );

      expect(message, isA<Hello>());
      expect(
        (message as Hello)
            .details
            .roles
            ?.subscriber
            ?.features
            ?.publicationTrustLevels,
        isTrue,
      );
    });

    test('decodes CBOR payloads with lazy args and kwargs', () {
      final frameBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codePublish,
            42,
            <String, Object?>{},
            'bench.topic',
          ]),
        ),
      );
      final argsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue(['payload'])),
      );
      final kwargsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'flag': true})),
      );

      final message = bindMessage(
        NativeMessageSerializer.cbor,
        frameBytes,
        argsBytes: argsBytes,
        kwargsBytes: kwargsBytes,
      );

      expect(message, isA<Publish>());
      final publish = message as Publish;
      expect(publish.topic, 'bench.topic');
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      expect(publish.arguments, ['payload']);
      expect(publish.argumentsKeywords, {'flag': true});
    });

    test('preserves custom option fields on inbound control messages', () {
      final publishBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codePublish,
            42,
            <String, Object?>{
              'acknowledge': true,
              'trace_id': 'pub-1',
              'blob': Uint8List.fromList(const [1, 2, 3]),
            },
            'bench.topic',
          ]),
        ),
      );
      final callBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codeCall,
            44,
            <String, Object?>{
              'progress': true,
              'receive_progress': true,
              'trace_id': 'call-1',
              'nested': {'flag': true},
            },
            'bench.proc',
          ]),
        ),
      );
      final yieldBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codeYield,
            45,
            <String, Object?>{
              'progress': false,
              'trace_id': 'yield-1',
              'nested': {
                'blob': Uint8List.fromList(const [4, 5]),
              },
            },
          ]),
        ),
      );

      final publish =
          bindMessage(NativeMessageSerializer.cbor, publishBytes) as Publish;
      final call = bindMessage(NativeMessageSerializer.cbor, callBytes) as Call;
      final yield =
          bindMessage(NativeMessageSerializer.cbor, yieldBytes) as Yield;

      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.custom['trace_id'], equals('pub-1'));
      expect(
        publish.options?.custom['blob'],
        orderedEquals(Uint8List.fromList(const [1, 2, 3])),
      );

      expect(call.options?.progress, isTrue);
      expect(call.options?.receiveProgress, isTrue);
      expect(call.options?.custom['trace_id'], equals('call-1'));
      expect(call.options?.custom['nested'], equals(const {'flag': true}));

      expect(yield.options?.progress, isFalse);
      expect(yield.options?.custom['trace_id'], equals('yield-1'));
      expect(
        (yield.options?.custom['nested'] as Map)['blob'],
        orderedEquals(Uint8List.fromList(const [4, 5])),
      );
    });

    test('normalizes JSON binary sentinels inside custom option fields', () {
      final frameBytes = Uint8List.fromList(
        utf8.encode(
          '[48,44,{"trace_id":"call-1","blob":"\\\\u0000AQID","nested":{"payload":"\\\\u0000BAUG"}},"bench.proc"]',
        ),
      );

      final call =
          bindMessage(NativeMessageSerializer.json, frameBytes) as Call;

      expect(call.options?.custom['trace_id'], equals('call-1'));
      expect(
        call.options?.custom['blob'],
        orderedEquals(Uint8List.fromList(const [1, 2, 3])),
      );
      expect(
        (call.options?.custom['nested'] as Map)['payload'],
        orderedEquals(Uint8List.fromList(const [4, 5, 6])),
      );
    });

    test('decodes Heartbeat and Unknown messages from full frames', () {
      final heartbeat = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              MessageTypes.codeHeartbeat,
              {'mode': 'ping'},
              7,
              8,
              9,
            ]),
          ),
        ),
      );
      final unknown = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              999,
              321,
              {'trace_id': 'unknown-router'},
            ]),
          ),
        ),
      );

      expect(heartbeat, isA<Heartbeat>());
      expect((heartbeat as Heartbeat).details, {'mode': 'ping'});
      expect(heartbeat.ping, 7);
      expect(heartbeat.incoming, 8);
      expect(heartbeat.outgoing, 9);

      expect(unknown, isA<UnknownMessage>());
      expect((unknown as UnknownMessage).id, 999);
      expect(unknown.requestId, 321);
      expect(unknown.fields, [
        321,
        {'trace_id': 'unknown-router'},
      ]);
    });

    test('binds request metadata without a full frame', () {
      final helloDetailsBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue({
            'authid': 'bench-user',
            'authrole': 'bench-role',
            'authmethod': 'ticket',
            'authprovider': 'native',
            'authmethods': ['ticket'],
            'roles': {'dealer': {}},
            'authextra': {'nonce': 'abc123'},
            '_trace': 'hello-custom',
          }),
        ),
      );
      final authenticateExtraBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'nonce': 'abc123'})),
      );
      final publishDetailsBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue({'acknowledge': true, 'trace_id': 'pub-1'}),
        ),
      );
      final argsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue(['payload'])),
      );
      final kwargsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'flag': true})),
      );

      final hello =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeHello,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0),
                detailsBytes: helloDetailsBytes,
                stringA: 'bench.realm',
                stringB: 'bench-user',
                stringC: 'bench-role',
                stringD: 'ticket',
                stringE: 'native',
              )
              as Hello;
      final authenticate =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeAuthenticate,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: authenticateExtraBytes,
                stringA: 'sig',
              )
              as Authenticate;
      final publish =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codePublish,
                primaryId: 42,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: publishDetailsBytes,
                stringA: 'bench.topic',
                argsBytes: argsBytes,
                kwargsBytes: kwargsBytes,
              )
              as Publish;

      expect(hello.realm, 'bench.realm');
      expect(hello.details.authid, 'bench-user');
      expect(hello.details.authrole, 'bench-role');
      expect(hello.details.authmethod, 'ticket');
      expect(hello.details.authprovider, 'native');
      expect(hello.details.authmethods, ['ticket']);
      expect(hello.details.roles?.dealer, isNotNull);
      expect(hello.details.authextra?['nonce'], 'abc123');
      expect(hello.details.custom['_trace'], 'hello-custom');

      expect(authenticate.signature, 'sig');
      expect(authenticate.extra, {'nonce': 'abc123'});

      expect(publish.topic, 'bench.topic');
      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.custom['trace_id'], 'pub-1');
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      expect(publish.arguments, ['payload']);
      expect(publish.argumentsKeywords, {'flag': true});
    });

    test('binds unsubscribe metadata without a full frame', () {
      final message =
          bindMessageFromMetadata(
                NativeMessageSerializer.json,
                messageCode: MessageTypes.codeUnsubscribe,
                primaryId: 7,
                secondaryId: 9,
                detailNumberA: 0,
                flags: 1 << 4,
              )
              as Unsubscribe;

      expect(message.requestId, 7);
      expect(message.subscriptionId, 9);
    });

    test('binds direct control metadata without decoding details maps', () {
      final publish =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codePublish,
                primaryId: 7,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3) | (1 << 6),
                stringA: 'bench.topic',
                stringB: 'wamp',
                stringC: 'cbor',
              )
              as Publish;
      final subscribe =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeSubscribe,
                primaryId: 8,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'bench.topic',
                stringB: 'prefix',
                stringC: 'meta.topic',
              )
              as Subscribe;
      final call =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeCall,
                primaryId: 9,
                secondaryId: 0,
                detailNumberA: 1500,
                flags:
                    (1 << 4) |
                    (1 << 0) |
                    (1 << 1) |
                    (1 << 3) |
                    (1 << 5) |
                    (1 << 6),
                stringA: 'bench.proc',
                stringB: 'wamp',
                stringC: 'cbor',
              )
              as Call;
      final cancel =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeCancel,
                primaryId: 10,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0),
                stringA: 'killnowait',
              )
              as Cancel;
      final interrupt =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeInterrupt,
                primaryId: 10,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0),
                stringA: 'kill',
              )
              as Interrupt;
      final register =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeRegister,
                primaryId: 11,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3) | (1 << 5),
                stringA: 'bench.proc',
                stringB: 'prefix',
                stringC: 'roundrobin',
              )
              as Register;
      final yield =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeYield,
                primaryId: 12,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'wamp',
                stringB: 'cbor',
                stringC: 'aes',
                stringD: 'key-1',
              )
              as Yield;
      final unsubscribed =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeUnsubscribed,
                primaryId: 13,
                secondaryId: 0,
                detailNumberA: 99,
                flags: (1 << 4) | (1 << 0) | (1 << 1),
                stringA: 'wamp.close.normal',
              )
              as Unsubscribed;

      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.discloseMe, isTrue);
      expect(publish.options?.pptScheme, 'wamp');
      expect(publish.options?.pptSerializer, 'cbor');

      expect(subscribe.options?.match, 'prefix');
      expect(subscribe.options?.metaTopic, 'meta.topic');
      expect(subscribe.options?.getRetained, isTrue);

      expect(call.options?.progress, isTrue);
      expect(call.options?.receiveProgress, isTrue);
      expect(call.options?.discloseMe, isTrue);
      expect(call.options?.timeout, 1500);
      expect(call.options?.pptScheme, 'wamp');
      expect(call.options?.pptSerializer, 'cbor');

      expect(cancel.options?.mode, 'killnowait');
      expect(interrupt.options?.mode, 'kill');

      expect(register.options?.discloseCaller, isTrue);
      expect(register.options?.match, 'prefix');
      expect(register.options?.invoke, 'roundrobin');
      expect(register.options?.forwardTimeout, isTrue);

      expect(yield.options?.progress, isTrue);
      expect(yield.options?.pptScheme, 'wamp');
      expect(yield.options?.pptSerializer, 'cbor');
      expect(yield.options?.pptCipher, 'aes');
      expect(yield.options?.pptKeyId, 'key-1');

      expect(unsubscribed.unsubscribeRequestId, 13);
      expect(unsubscribed.details?.subscription, 99);
      expect(unsubscribed.details?.reason, 'wamp.close.normal');
    });

    test('binds direct control metadata with lazy custom details', () {
      final publish =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codePublish,
                primaryId: 7,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'bench.topic',
                detailsBytes: Uint8List.fromList(
                  cbor.cborEncode(
                    cbor.CborValue({
                      'acknowledge': true,
                      '_trace': 'publish-custom',
                    }),
                  ),
                ),
              )
              as Publish;
      final register =
          bindMessageFromMetadata(
                NativeMessageSerializer.messagePack,
                messageCode: MessageTypes.codeRegister,
                primaryId: 11,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0) | (1 << 3),
                stringA: 'bench.proc',
                detailsBytes: Uint8List.fromList(
                  msgpack.serialize({
                    'disclose_caller': true,
                    '_trace': 'register-custom',
                  }),
                ),
              )
              as Register;
      final abort =
          bindMessageFromMetadata(
                NativeMessageSerializer.json,
                messageCode: MessageTypes.codeAbort,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: (1 << 4) | (1 << 0),
                stringA: 'wamp.error.abort',
                stringB: 'boom',
                detailsBytes: Uint8List.fromList(
                  utf8.encode(
                    jsonEncode({'message': 'boom', '_trace': 'abort-custom'}),
                  ),
                ),
              )
              as Abort;

      expect(publish.options?.acknowledge, isTrue);
      expect(publish.options?.custom['_trace'], 'publish-custom');
      expect(register.options?.discloseCaller, isTrue);
      expect(register.options?.custom['_trace'], 'register-custom');
      expect(abort.message?.message, 'boom');
      expect(abort.details['_trace'], 'abort-custom');
    });

    test('binds Heartbeat and Unknown metadata without a full frame', () {
      final heartbeat =
          bindMessageFromMetadata(
                NativeMessageSerializer.cbor,
                messageCode: MessageTypes.codeHeartbeat,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: Uint8List.fromList(
                  cbor.cborEncode(
                    cbor.CborValue({
                      'details': {'mode': 'ping'},
                      'ping': 7,
                      'incoming': 8,
                      'outgoing': 9,
                    }),
                  ),
                ),
              )
              as Heartbeat;
      final unknown =
          bindMessageFromMetadata(
                NativeMessageSerializer.messagePack,
                messageCode: 999,
                primaryId: 0,
                secondaryId: 0,
                detailNumberA: 0,
                flags: 1 << 4,
                detailsBytes: Uint8List.fromList(
                  msgpack.serialize({
                    'fields': [
                      321,
                      {'trace_id': 'unknown-router'},
                    ],
                    'request_id': 321,
                  }),
                ),
              )
              as UnknownMessage;

      expect(heartbeat.details, {'mode': 'ping'});
      expect(heartbeat.ping, 7);
      expect(heartbeat.incoming, 8);
      expect(heartbeat.outgoing, 9);

      expect(unknown.id, 999);
      expect(unknown.requestId, 321);
      expect(unknown.fields, [
        321,
        {'trace_id': 'unknown-router'},
      ]);
    });
  });
}

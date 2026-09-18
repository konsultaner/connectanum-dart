@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/src/transport/native/message_binding.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

import '../../../../connectanum_core/test/support/native_role_contract.dart';

void main() {
  _bindingBoundaryContracts();
  _metadataDispatchContracts();
  _validFrameContracts();
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
            bindMessage(
                  serializer,
                  Uint8List.fromList([0xff]),
                  metadata: _metadata(
                    messageCode: 8,
                    primaryId: 48,
                    secondaryId: 19,
                    flags: NativeMessageMetadata.flagMetadataBind,
                  ),
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
      final value = _expectMessage<Error>(
        _validFrame(
          () => bindMessage(
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
          ),
        ),
      );
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
    group('full response frames $serializer', () {
      T decode<T extends AbstractMessage>(List<Object?> frame) {
        final bytes = encode(frame);
        return _expectMessage<T>(
          _validFrame(() => bindMessage(serializer, bytes)),
        );
      }

      test('omitted optional control fields keep their defaults', () {
        final abort = decode<Abort>([3]);
        expect(abort.reason, '');
        expect(abort.details, isEmpty);
        expect(abort.message, isNull);
        expect(abort.arguments, isNull);
        final goodbye = decode<Goodbye>([6]);
        expect(goodbye.reason, '');
        expect(goodbye.message, isNull);
        final challenge = decode<Challenge>([4, 'ticket']);
        expect(challenge.authMethod, 'ticket');
        expect(challenge.extra.challenge, isNull);
        final unknown = decode<UnknownMessage>([9999]);
        expect(unknown.id, 9999);
        expect(unknown.fields, isEmpty);
        expect(unknown.requestId, isNull);
        final emptyArgs = decode<Abort>([3, {}, 'com.reason', null]);
        expect(emptyArgs.arguments, isEmpty);
        expect(emptyArgs.argumentsKeywords, isNull);
      });
      test(
        'closing details without a reason preserve message and extensions',
        () {
          final abort = decode<Abort>([
            3,
            {'message': 'unavailable', 'retry': true},
          ]);
          expect(abort.reason, '');
          expect(abort.message?.message, 'unavailable');
          expect(abort.details, {'message': 'unavailable', 'retry': true});
          expect(abort.arguments, isNull);
          expect(abort.argumentsKeywords, isNull);
          final goodbye = decode<Goodbye>([
            6,
            {'message': 'finished'},
          ]);
          expect(goodbye.reason, '');
          expect(goodbye.message?.message, 'finished');
        },
      );
      for (final count in [0, 1, 2, 3, 4]) {
        test(
          'HEARTBEAT accepts $count optional fields without reading beyond them',
          () {
            final fields = <Object?>[{}, 11, 12, 13].take(count).toList();
            final heartbeat = decode<Heartbeat>([7, ...fields]);
            expect(heartbeat.details, isEmpty);
            expect(heartbeat.ping, count > 1 ? 11 : null);
            expect(heartbeat.incoming, count > 2 ? 12 : null);
            expect(heartbeat.outgoing, count > 3 ? 13 : null);
          },
        );
      }
      test('rejects non-array and empty frames', () {
        for (final frame in <Object>[{}, 1, 'invalid', []]) {
          expect(
            () => bindMessage(serializer, encode(frame)),
            throwsArgumentError,
          );
        }
      });
      test('acknowledgements preserve request and resource IDs', () {
        final published = decode<Published>([17, 12, 45]);
        expect(published.publishRequestId, 12);
        expect(published.publicationId, 45);
        final subscribed = decode<Subscribed>([33, 13, 46]);
        expect(subscribed.subscribeRequestId, 13);
        expect(subscribed.subscriptionId, 46);
        final registered = decode<Registered>([65, 14, 47]);
        expect(registered.registerRequestId, 14);
        expect(registered.registrationId, 47);
        expect(decode<Unregistered>([67, 15]).unregisterRequestId, 15);
      });
      test('UNSUBSCRIBED distinguishes acknowledgement from revocation', () {
        final normal = decode<Unsubscribed>([35, 16]);
        expect(normal.unsubscribeRequestId, 16);
        expect(normal.details, isNull);
        final revoked = decode<Unsubscribed>([
          35,
          0,
          {'subscription': 48, 'reason': 'wamp.error.not_authorized'},
        ]);
        expect(revoked.unsubscribeRequestId, 0);
        expect(revoked.details, isNotNull);
        expect(revoked.details!.subscription, 48);
        expect(revoked.details!.reason, 'wamp.error.not_authorized');
      });
      for (final progress in <bool?>[null, false, true]) {
        test('RESULT preserves progress $progress and passthrough fields', () {
          final value = decode<Result>([
            50,
            17,
            {
              'progress': progress,
              'ppt_scheme': 'wamp',
              'ppt_serializer': 'cbor',
              'ppt_cipher': 'cipher',
              'ppt_keyid': 'key',
              'extension': 3,
            },
          ]);
          expect(value.callRequestId, 17);
          expect(value.details.progress, progress);
          expect(value.details.pptScheme, 'wamp');
          expect(value.details.pptSerializer, 'cbor');
          expect(value.details.pptCipher, 'cipher');
          expect(value.details.pptKeyId, 'key');
          expect(value.details.custom, {'extension': 3});
        });
      }
      for (final mode in <String?>[null, 'skip', 'kill', 'killnowait']) {
        test('INTERRUPT retains mode $mode', () {
          final value = decode<Interrupt>([
            69,
            18,
            if (mode != null) {'mode': mode},
          ]);
          expect(value.requestId, 18);
          expect(value.options?.mode, mode);
          if (mode == null) expect(value.options, isNull);
        });
      }
      test('ERROR preserves lazy payload and request context', () {
        final value =
            bindMessage(
                  serializer,
                  encode([
                    8,
                    48,
                    19,
                    {'trace': 'error'},
                    'com.failure',
                  ]),
                  argsBytes: encode([1]),
                  kwargsBytes: encode({'code': 2}),
                )
                as Error;
        expect(value.requestTypeId, 48);
        expect(value.requestId, 19);
        expect(value.error, 'com.failure');
        expect(value.details, {'trace': 'error'});
        expect(value.arguments, [1]);
        expect(value.argumentsKeywords, {'code': 2});
        final absent = decode<Error>([8, 48, 20, null]);
        expect(absent.details, isEmpty);
        expect(absent.error, isNull);
      });
      test('GOODBYE preserves reason and optional explanation', () {
        final value = decode<Goodbye>([
          6,
          {'message': 'closing'},
          'wamp.close.normal',
        ]);
        expect(value.reason, 'wamp.close.normal');
        expect(value.message?.message, 'closing');
        final absent = decode<Goodbye>([6]);
        expect(absent.reason, '');
        expect(absent.message, isNull);
      });
    });
    group('session materialization $serializer', () {
      final contracts = <int, Matcher>{
        2: isA<Welcome>(),
        3: isA<Abort>(),
        4: isA<Challenge>(),
        6: isA<Goodbye>(),
        8: isA<Error>(),
        17: isA<Published>(),
        33: isA<Subscribed>(),
        35: isA<Unsubscribed>(),
        36: isA<Event>(),
        50: isA<Result>(),
        65: isA<Registered>(),
        67: isA<Unregistered>(),
        68: isA<Invocation>(),
        69: isA<Interrupt>(),
      };
      for (final contract in contracts.entries) {
        test(
          'code ${contract.key} materializes without reading the full frame',
          () {
            final wrapped = bindSessionMessage(
              serializer,
              Uint8List.fromList([0xff]),
              metadata: _metadata(
                messageCode: contract.key,
                primaryId: 81,
                secondaryId: 93,
                flags: NativeMessageMetadata.flagMetadataBind,
                stringA: 'com.value',
                detailsBytes: encode({
                  'message': 'explanation',
                  'mode': 'killnowait',
                }),
              ),
              argsBytes: encode([71]),
              kwargsBytes: encode({'source': 'fragment'}),
            );
            expect(wrapped, isA<NativeSessionMessage>());
            final anchor = Object();
            attachSessionMessageAnchor(wrapped, anchor);
            final value = materializeSessionMessage(wrapped);
            expect(value, contract.value);
            expect(value.id, contract.key);
            expect(sessionMessageAnchorFor(value), same(anchor));
            expect(materializeSessionMessage(value), same(value));
            final primary = switch (value) {
              Welcome() => value.sessionId,
              Published() => value.publishRequestId,
              Subscribed() => value.subscribeRequestId,
              Unsubscribed() => value.unsubscribeRequestId,
              Event() => value.subscriptionId,
              Result() => value.callRequestId,
              Registered() => value.registerRequestId,
              Unregistered() => value.unregisterRequestId,
              Invocation() => value.requestId,
              Interrupt() => value.requestId,
              Error() => value.requestTypeId,
              _ => null,
            };
            if (primary != null) expect(primary, 81);
            final secondary = switch (value) {
              Published() => value.publicationId,
              Subscribed() => value.subscriptionId,
              Event() => value.publicationId,
              Registered() => value.registrationId,
              Invocation() => value.registrationId,
              Error() => value.requestId,
              _ => null,
            };
            if (secondary != null) expect(secondary, 93);
            if (value is AbstractMessageWithPayload) {
              expect(value.arguments, [71]);
              expect(value.argumentsKeywords, {'source': 'fragment'});
            }
            if (value is Abort) {
              expect(value.arguments, [71]);
              expect(value.argumentsKeywords, {'source': 'fragment'});
              expect(value.reason, 'com.value');
            }
          },
        );
      }
      for (final flags in [0, NativeMessageMetadata.flagDirectBind]) {
        test('flags $flags without metadata capability use the full frame', () {
          final metadata = NativeMessageMetadata(
            messageCode: 2,
            primaryId: 999,
            secondaryId: 888,
            detailNumberA: 0,
            detailNumberB: 0,
            flags: flags,
            stringA: 'ignored',
            stringB: null,
            stringC: null,
            stringD: null,
            stringE: null,
            detailsBytes: Uint8List.fromList([0xff]),
          );
          final value = bindSessionMessage(
            serializer,
            encode([17, 42, 63]),
            metadata: metadata,
          );
          expect(value, isA<Published>());
          expect((value as Published).publishRequestId, 42);
          expect(value.publicationId, 63);
          expect(
            () => NativeSessionMessage(
              serializer: serializer,
              metadata: metadata,
            ).materialize(),
            throwsStateError,
          );
        });
      }
      test('unknown metadata code falls back instead of wrapping', () {
        final metadata = _metadata(
          messageCode: 9999,
          flags: NativeMessageMetadata.flagMetadataBind,
        );
        final value = bindSessionMessage(
          serializer,
          encode([17, 42, 63]),
          metadata: metadata,
        );
        expect(value, isA<Published>());
        expect((value as Published).publishRequestId, 42);
        expect(value.publicationId, 63);
        expect(
          () => NativeSessionMessage(
            serializer: serializer,
            metadata: metadata,
          ).materialize(),
          throwsStateError,
        );
      });
    });
    group('metadata authority $serializer', () {
      const metadataFlag = NativeMessageMetadata.flagMetadataBind;
      const directFlag = NativeMessageMetadata.flagDirectBind;
      final identityFields = <String, String? Function(Details)>{
        'realm': (d) => d.realm,
        'authid': (d) => d.authid,
        'authrole': (d) => d.authrole,
        'authmethod': (d) => d.authmethod,
        'authprovider': (d) => d.authprovider,
      };
      for (final selected in identityFields.keys) {
        for (final direct in [false, true]) {
          for (final value in ['', 'metadata-$selected']) {
            test(
              'WELCOME $selected=$value direct=$direct preserves field authority',
              () {
                final strings = [
                  for (final field in identityFields.keys)
                    field == selected ? value : null,
                ];
                final welcome =
                    bindMessage(
                          serializer,
                          Uint8List.fromList([0xff]),
                          metadata: _metadata(
                            messageCode: 2,
                            primaryId: 71,
                            flags: metadataFlag | (direct ? directFlag : 0),
                            stringA: strings[0],
                            stringB: strings[1],
                            stringC: strings[2],
                            stringD: strings[3],
                            stringE: strings[4],
                            detailsBytes: encode({
                              for (final field in identityFields.keys)
                                field: 'wire-$field',
                              'roles': {'dealer': {}},
                              'extension': 'trace',
                            }),
                          ),
                        )
                        as Welcome;
                expect(welcome.sessionId, 71);
                expect(welcome.details.roles, isNotNull);
                expect(welcome.details.roles!.dealer, isNotNull);
                for (final field in identityFields.entries) {
                  expect(
                    field.value(welcome.details),
                    direct && field.key == selected
                        ? value
                        : 'wire-${field.key}',
                    reason: field.key,
                  );
                }
                expect(welcome.details.custom, {'extension': 'trace'});
              },
            );
          }
        }
      }
      for (final direct in [false, true]) {
        for (final flags in [
          0,
          NativeMessageMetadata.flagDetailNumberAPresent,
          NativeMessageMetadata.flagDetailNumberBPresent,
          NativeMessageMetadata.flagDetailNumberAPresent |
              NativeMessageMetadata.flagDetailNumberBPresent,
        ]) {
          test('EVENT numeric presence flags=$flags direct=$direct', () {
            final value =
                bindMessage(
                      serializer,
                      Uint8List.fromList([0xff]),
                      metadata: _metadata(
                        messageCode: 36,
                        primaryId: 71,
                        secondaryId: 92,
                        detailNumberA: 0,
                        detailNumberB: 7,
                        flags: metadataFlag | (direct ? directFlag : 0) | flags,
                        stringA: 'com.direct',
                        stringB: 'direct-scheme',
                        stringC: 'cbor',
                        stringD: 'cipher',
                        stringE: 'key',
                        detailsBytes: encode({
                          'publisher': 21,
                          'trustlevel': 22,
                          'topic': 'com.wire',
                          'ppt_scheme': 'wire-scheme',
                          'ppt_serializer': 'json',
                          'ppt_cipher': 'wire-cipher',
                          'ppt_keyid': 'wire-key',
                          'extension': 'event',
                        }),
                      ),
                    )
                    as Event;
            expect(value.subscriptionId, 71);
            expect(value.publicationId, 92);
            expect(
              value.details.publisher,
              direct ? (flags & 2 != 0 ? 0 : null) : 21,
            );
            expect(
              value.details.trustlevel,
              direct ? (flags & 4 != 0 ? 7 : null) : 22,
            );
            expect(value.details.topic, direct ? 'com.direct' : 'com.wire');
            expect(
              value.details.pptScheme,
              direct ? 'direct-scheme' : 'wire-scheme',
            );
            expect(value.details.pptSerializer, direct ? 'cbor' : 'json');
            expect(value.details.pptCipher, direct ? 'cipher' : 'wire-cipher');
            expect(value.details.pptKeyId, direct ? 'key' : 'wire-key');
            expect(value.details.custom, {'extension': 'event'});
          });
        }
        for (final progress in [false, true]) {
          test('RESULT progress=$progress direct=$direct', () {
            final value =
                bindMessage(
                      serializer,
                      Uint8List.fromList([0xff]),
                      metadata: _metadata(
                        messageCode: 50,
                        primaryId: 71,
                        flags:
                            metadataFlag |
                            (direct ? directFlag : 0) |
                            (progress
                                ? NativeMessageMetadata.flagDetailBoolATrue
                                : 0),
                        stringA: 'direct-scheme',
                        stringB: 'cbor',
                        stringC: 'cipher',
                        stringD: 'key',
                        detailsBytes: encode({
                          'progress': false,
                          'ppt_scheme': 'wire-scheme',
                          'ppt_serializer': 'json',
                          'ppt_cipher': 'wire-cipher',
                          'ppt_keyid': 'wire-key',
                          'extension': 'result',
                        }),
                      ),
                    )
                    as Result;
            expect(value.callRequestId, 71);
            expect(
              value.details.progress,
              direct ? (progress ? true : null) : false,
            );
            expect(
              value.details.pptScheme,
              direct ? 'direct-scheme' : 'wire-scheme',
            );
            expect(value.details.pptSerializer, direct ? 'cbor' : 'json');
            expect(value.details.pptCipher, direct ? 'cipher' : 'wire-cipher');
            expect(value.details.pptKeyId, direct ? 'key' : 'wire-key');
            expect(value.details.custom, {'extension': 'result'});
          });
        }
        for (final text in <String?>[null, '', 'explanation']) {
          test('GOODBYE nullable message=$text direct=$direct', () {
            final value =
                bindMessage(
                      serializer,
                      Uint8List.fromList([0xff]),
                      metadata: _metadata(
                        messageCode: 6,
                        flags: metadataFlag | (direct ? directFlag : 0),
                        stringA: 'wamp.close.normal',
                        stringB: direct ? text : 'ignored',
                        detailsBytes: encode({
                          'message': direct ? 'ignored' : text,
                        }),
                      ),
                    )
                    as Goodbye;
            expect(value.reason, 'wamp.close.normal');
            expect(value.message?.message, text);
            if (text == null) expect(value.message, isNull);
          });
        }
        for (final present in [false, true]) {
          test('UNSUBSCRIBED numeric presence=$present direct=$direct', () {
            final value =
                bindMessage(
                      serializer,
                      Uint8List.fromList([0xff]),
                      metadata: _metadata(
                        messageCode: 35,
                        primaryId: 71,
                        detailNumberA: 0,
                        flags:
                            metadataFlag |
                            (direct ? directFlag : 0) |
                            (present
                                ? NativeMessageMetadata.flagDetailNumberAPresent
                                : 0),
                        stringA: 'com.direct',
                        detailsBytes: encode({
                          'subscription': 73,
                          'reason': 'com.wire',
                        }),
                      ),
                    )
                    as Unsubscribed;
            expect(value.unsubscribeRequestId, 71);
            expect(value.details, isNotNull);
            expect(
              value.details!.subscription,
              direct ? (present ? 0 : null) : 73,
            );
            expect(value.details!.reason, direct ? 'com.direct' : 'com.wire');
          });
        }
      }
      for (final entry in [
        (0, null, null, null, null),
        (NativeMessageMetadata.flagDetailNumberAPresent, 0, null, null, null),
        (NativeMessageMetadata.flagDetailNumberBPresent, null, 73, null, null),
        (NativeMessageMetadata.flagDetailBoolATrue, null, null, true, null),
        (NativeMessageMetadata.flagDetailBoolBTrue, null, null, null, true),
        (
          NativeMessageMetadata.flagDetailNumberAPresent |
              NativeMessageMetadata.flagDetailNumberBPresent |
              NativeMessageMetadata.flagDetailBoolATrue |
              NativeMessageMetadata.flagDetailBoolBTrue,
          0,
          73,
          true,
          true,
        ),
      ]) {
        test('INVOCATION direct flags ${entry.$1} remain independent', () {
          final invocation =
              bindMessage(
                    serializer,
                    Uint8List.fromList([0xff]),
                    metadata: _metadata(
                      messageCode: 68,
                      primaryId: 72,
                      secondaryId: 93,
                      flags: metadataFlag | directFlag | entry.$1,
                      detailNumberA: 0,
                      detailNumberB: 73,
                      stringA: 'com.proc',
                      stringB: 'wamp',
                      stringC: 'cbor',
                      stringD: 'cipher',
                      stringE: 'key',
                      detailsBytes: encode({
                        'caller': 99,
                        'timeout': 98,
                        'progress': true,
                        'receive_progress': true,
                        'procedure': 'ignored.proc',
                        'ppt_scheme': 'ignored',
                        'ppt_serializer': 'ignored',
                        'ppt_cipher': 'ignored',
                        'ppt_keyid': 'ignored',
                        'extension': 17,
                      }),
                    ),
                  )
                  as Invocation;
          expect(invocation.requestId, 72);
          expect(invocation.registrationId, 93);
          expect(invocation.details.caller, entry.$2);
          expect(invocation.details.timeout, entry.$3);
          expect(invocation.details.receiveProgress, entry.$4);
          expect(invocation.details.progress, entry.$5);
          expect(invocation.details.procedure, 'com.proc');
          expect(invocation.details.pptScheme, 'wamp');
          expect(invocation.details.pptSerializer, 'cbor');
          expect(invocation.details.pptCipher, 'cipher');
          expect(invocation.details.pptKeyId, 'key');
          expect(invocation.details.custom, {'extension': 17});
        });
      }
      test(
        'INVOCATION without direct flag reads details, ignoring metadata slots',
        () {
          final invocation =
              bindMessage(
                    serializer,
                    Uint8List.fromList([0xff]),
                    metadata: _metadata(
                      messageCode: 68,
                      primaryId: 72,
                      secondaryId: 93,
                      flags: metadataFlag,
                      detailNumberA: 99,
                      detailNumberB: 98,
                      stringA: 'ignored',
                      stringB: 'ignored',
                      stringC: 'ignored',
                      stringD: 'ignored',
                      stringE: 'ignored',
                      detailsBytes: encode({
                        'caller': 0,
                        'timeout': 73,
                        'procedure': 'com.proc',
                        'progress': false,
                        'receive_progress': false,
                        'ppt_scheme': 'wamp',
                        'ppt_serializer': 'cbor',
                        'ppt_cipher': 'cipher',
                        'ppt_keyid': 'key',
                        'extension': 18,
                      }),
                    ),
                  )
                  as Invocation;
          expect(invocation.requestId, 72);
          expect(invocation.registrationId, 93);
          expect(invocation.details.caller, 0);
          expect(invocation.details.timeout, 73);
          expect(invocation.details.procedure, 'com.proc');
          expect(invocation.details.progress, isFalse);
          expect(invocation.details.receiveProgress, isFalse);
          expect(invocation.details.pptScheme, 'wamp');
          expect(invocation.details.pptSerializer, 'cbor');
          expect(invocation.details.pptCipher, 'cipher');
          expect(invocation.details.pptKeyId, 'key');
          expect(invocation.details.custom, {'extension': 18});
        },
      );
    });
    group('fragment boundaries $serializer', () {
      AbstractMessage metadata(int code, bool direct, Uint8List? bytes) =>
          bindMessage(
            serializer,
            Uint8List.fromList([0xff]),
            metadata: _metadata(
              messageCode: code,
              primaryId: 48,
              secondaryId: 19,
              flags: direct ? 17 : 16,
              stringA: 'com.reason',
              detailsBytes: bytes,
            ),
          );
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
                    metadata: mode == 'metadata'
                        ? NativeMessageMetadata(
                            messageCode: 3,
                            primaryId: 0,
                            secondaryId: 0,
                            detailNumberA: 0,
                            detailNumberB: 0,
                            flags: NativeMessageMetadata.flagMetadataBind,
                            stringA: 'wamp.error.not_authorized',
                            detailsBytes: encode(details),
                          )
                        : null,
                  )
                  as Abort,
        );
      });
    }
    for (final fromMetadata in [false, true]) {
      group('WELCOME roles $serializer metadata=$fromMetadata', () {
        nativeRoleContracts((details) {
          final message =
              bindMessage(
                    serializer,
                    fromMetadata
                        ? Uint8List.fromList([0xff])
                        : encode([MessageTypes.codeWelcome, 741, details]),
                    metadata: fromMetadata
                        ? NativeMessageMetadata(
                            messageCode: MessageTypes.codeWelcome,
                            primaryId: 741,
                            secondaryId: 0,
                            detailNumberA: 0,
                            detailNumberB: 0,
                            flags: NativeMessageMetadata.flagMetadataBind,
                            detailsBytes: encode(details),
                          )
                        : null,
                  )
                  as Welcome;
          expect(message.sessionId, 741);
          return message.details;
        });
      });
    }
  }
  group('bindMessage', () {
    test('direct binds Published acknowledgements from native metadata', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codePublished,
          primaryId: 42,
          secondaryId: 99,
          flags: NativeMessageMetadata.flagDirectBind,
        ),
      );

      expect(message, isA<Published>());
      final published = message as Published;
      expect(published.publishRequestId, 42);
      expect(published.publicationId, 99);
    });

    test('direct binds Subscribed acknowledgements from native metadata', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeSubscribed,
          primaryId: 41,
          secondaryId: 77,
          flags: NativeMessageMetadata.flagDirectBind,
        ),
      );

      expect(message, isA<Subscribed>());
      final subscribed = message as Subscribed;
      expect(subscribed.subscribeRequestId, 41);
      expect(subscribed.subscriptionId, 77);
    });

    test('direct binds Registered and Unregistered acknowledgements', () {
      final registered = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeRegistered,
          primaryId: 55,
          secondaryId: 88,
          flags: NativeMessageMetadata.flagDirectBind,
        ),
      );
      final unregistered = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeUnregistered,
          primaryId: 56,
          flags: NativeMessageMetadata.flagDirectBind,
        ),
      );

      expect(registered, isA<Registered>());
      expect((registered as Registered).registerRequestId, 55);
      expect(registered.registrationId, 88);
      expect(unregistered, isA<Unregistered>());
      expect((unregistered as Unregistered).unregisterRequestId, 56);
    });

    test('direct binds Unsubscribed acknowledgements with details', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeUnsubscribed,
          primaryId: 57,
          detailNumberA: 88,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDetailNumberAPresent,
          stringA: 'wamp.close.normal',
        ),
      );

      expect(message, isA<Unsubscribed>());
      final unsubscribed = message as Unsubscribed;
      expect(unsubscribed.unsubscribeRequestId, 57);
      expect(unsubscribed.details?.subscription, 88);
      expect(unsubscribed.details?.reason, 'wamp.close.normal');
    });

    test('decodes Welcome details and preserves custom fields', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              MessageTypes.codeWelcome,
              42,
              {
                'realm': 'bench.realm',
                'authid': 'bench-user',
                'roles': {
                  'broker': {
                    'features': {'publication_trustlevels': true},
                  },
                  'dealer': {
                    'features': {'call_timeout': true},
                  },
                },
                '_custom_detail': 'value',
              },
            ]),
          ),
        ),
      );

      expect(message, isA<Welcome>());
      final welcome = message as Welcome;
      expect(welcome.sessionId, 42);
      expect(welcome.details.realm, 'bench.realm');
      expect(welcome.details.authid, 'bench-user');
      expect(
        welcome.details.roles?.broker?.features?.publicationTrustLevels,
        isTrue,
      );
      expect(welcome.details.roles?.dealer?.features?.callTimeout, isTrue);
      expect(welcome.details.custom['_custom_detail'], 'value');
    });

    test('decodes Challenge extras', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List.fromList(
          msgpack.serialize([
            MessageTypes.codeChallenge,
            'ticket',
            {
              'challenge': 'abc123',
              'salt': 'salt',
              'iterations': 4096,
              'e2ee': {'required': true},
            },
          ]),
        ),
      );

      expect(message, isA<Challenge>());
      final challenge = message as Challenge;
      expect(challenge.authMethod, 'ticket');
      expect(challenge.extra.challenge, 'abc123');
      expect(challenge.extra.salt, 'salt');
      expect(challenge.extra.iterations, 4096);
      expect(challenge.extra.custom['e2ee'], equals({'required': true}));
    });

    test('decodes Heartbeat and Unknown messages from full frames', () {
      final heartbeat = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              MessageTypes.codeHeartbeat,
              {'mode': 'ping'},
              10,
              11,
              12,
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
              123,
              {'trace_id': 'unknown-1'},
            ]),
          ),
        ),
      );

      expect(heartbeat, isA<Heartbeat>());
      expect((heartbeat as Heartbeat).details, {'mode': 'ping'});
      expect(heartbeat.ping, 10);
      expect(heartbeat.incoming, 11);
      expect(heartbeat.outgoing, 12);

      expect(unknown, isA<UnknownMessage>());
      expect((unknown as UnknownMessage).id, 999);
      expect(unknown.requestId, 123);
      expect(unknown.fields, [
        123,
        {'trace_id': 'unknown-1'},
      ]);
    });

    test('direct binds rich Welcome from native metadata', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeWelcome,
          primaryId: 5150,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind,
          stringA: 'bench.realm',
          stringB: 'bench-user',
          stringC: 'bench-role',
          stringD: 'ticket',
          stringE: 'native',
          detailsBytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'realm': 'bench.realm',
                'authid': 'bench-user',
                'authrole': 'bench-role',
                'authmethod': 'ticket',
                'authprovider': 'native',
                'authmethods': ['ticket'],
                'roles': {
                  'dealer': {
                    'features': {'call_timeout': true},
                  },
                },
                'authextra': {'nonce': 'abc123'},
                '_custom_detail': 'value',
              }),
            ),
          ),
        ),
      );

      expect(message, isA<Welcome>());
      final welcome = message as Welcome;
      expect(welcome.sessionId, 5150);
      expect(welcome.details.realm, 'bench.realm');
      expect(welcome.details.authid, 'bench-user');
      expect(welcome.details.authrole, 'bench-role');
      expect(welcome.details.authmethod, 'ticket');
      expect(welcome.details.authprovider, 'native');
      expect(welcome.details.authmethods, ['ticket']);
      expect(welcome.details.roles?.dealer?.features?.callTimeout, isTrue);
      expect(welcome.details.authextra?['nonce'], 'abc123');
      expect(welcome.details.custom['_custom_detail'], 'value');
    });

    test('metadata binds rich Welcome details from detail bytes', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeWelcome,
          primaryId: 6001,
          flags: NativeMessageMetadata.flagMetadataBind,
          detailsBytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'realm': 'bench.realm',
                'authid': 'bench-user',
                'roles': {
                  'dealer': {
                    'features': {'call_timeout': true},
                  },
                },
                '_custom_detail': 'value',
              }),
            ),
          ),
        ),
      );

      expect(message, isA<Welcome>());
      final welcome = message as Welcome;
      expect(welcome.sessionId, 6001);
      expect(welcome.details.realm, 'bench.realm');
      expect(welcome.details.authid, 'bench-user');
      expect(welcome.details.roles?.dealer?.features?.callTimeout, isTrue);
      expect(welcome.details.custom['_custom_detail'], 'value');
    });

    test('direct binds Abort from native metadata', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeAbort,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind,
          stringA: Error.authorizationFailed,
          stringB: 'Denied',
        ),
      );

      expect(message, isA<Abort>());
      final abort = message as Abort;
      expect(abort.reason, Error.authorizationFailed);
      expect(abort.message?.message, 'Denied');
      expect(abort.details['message'], 'Denied');
    });

    test('metadata binds Challenge extras from native detail bytes', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeChallenge,
          flags: NativeMessageMetadata.flagMetadataBind,
          stringA: 'ticket',
          detailsBytes: Uint8List.fromList(
            msgpack.serialize({
              'challenge': 'abc123',
              'salt': 'salt',
              'iterations': 4096,
              'channel_binding': 'tls-unique',
              'e2ee': {'required': true, 'selected_cipher': 'xsalsa20poly1305'},
            }),
          ),
        ),
      );

      expect(message, isA<Challenge>());
      final challenge = message as Challenge;
      expect(challenge.authMethod, 'ticket');
      expect(challenge.extra.challenge, 'abc123');
      expect(challenge.extra.salt, 'salt');
      expect(challenge.extra.iterations, 4096);
      expect(challenge.extra.channelBinding, 'tls-unique');
      expect(
        challenge.extra.custom['e2ee'],
        equals({'required': true, 'selected_cipher': 'xsalsa20poly1305'}),
      );
    });

    test('direct binds JSON events without decoding the full frame', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeEvent,
          primaryId: 7,
          secondaryId: 99,
          detailNumberA: 55,
          detailNumberB: 9,
          flags:
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagDetailNumberAPresent |
              NativeMessageMetadata.flagDetailNumberBPresent,
          stringA: 'bench.topic',
          stringB: 'wamp',
          stringC: 'cbor',
          stringD: 'aes',
          stringE: 'kid-1',
        ),
        argsBytes: Uint8List.fromList(utf8.encode(jsonEncode(['payload']))),
        kwargsBytes: Uint8List.fromList(
          utf8.encode(jsonEncode({'flag': true})),
        ),
      );

      expect(message, isA<Event>());
      final event = message as Event;
      expect(event.subscriptionId, 7);
      expect(event.publicationId, 99);
      expect(event.details.publisher, 55);
      expect(event.details.trustlevel, 9);
      expect(event.details.topic, 'bench.topic');
      expect(event.details.pptScheme, 'wamp');
      expect(event.details.pptSerializer, 'cbor');
      expect(event.details.pptCipher, 'aes');
      expect(event.details.pptKeyId, 'kid-1');
      expect(event.hasLazyArguments, isTrue);
      expect(event.hasLazyArgumentsKeywords, isTrue);
      expect(event.arguments, ['payload']);
      expect(event.argumentsKeywords, {'flag': true});
    });

    test('normalizes binary JSON arguments on lazy native events', () {
      final encrypted = Uint8List.fromList([0, 1, 2, 127, 128, 255]);
      final message = bindSessionMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeEvent,
          primaryId: 7,
          secondaryId: 99,
          flags:
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDirectBind,
          stringB: 'wamp',
          stringC: 'cbor',
          stringD: 'xsalsa20poly1305',
          stringE: 'benchmark-key',
        ),
        argsBytes: Uint8List.fromList(
          utf8.encode(jsonEncode(['\u0000${base64.encode(encrypted)}'])),
        ),
      );

      expect(message, isA<NativeSessionMessage>());
      final event = materializeSessionMessage(message) as Event;
      expect(event.wireArguments, hasLength(1));
      expect(event.wireArguments!.single, isA<Uint8List>());
      expect(event.wireArguments!.single, orderedEquals(encrypted));
    });

    test(
      'metadata binds JSON events with custom details without full frame',
      () {
        final message = bindMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeEvent,
            primaryId: 7,
            secondaryId: 99,
            flags: NativeMessageMetadata.flagMetadataBind,
            detailsBytes: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'publisher': 55,
                  'topic': 'bench.topic',
                  '_trace': 'ok',
                }),
              ),
            ),
          ),
          argsBytes: Uint8List.fromList(utf8.encode(jsonEncode(['payload']))),
          kwargsBytes: Uint8List.fromList(
            utf8.encode(jsonEncode({'flag': true})),
          ),
        );

        expect(message, isA<Event>());
        final event = message as Event;
        expect(event.subscriptionId, 7);
        expect(event.publicationId, 99);
        expect(event.details.publisher, 55);
        expect(event.details.topic, 'bench.topic');
        expect(event.details.custom['_trace'], 'ok');
        expect(event.arguments, ['payload']);
        expect(event.argumentsKeywords, {'flag': true});
      },
    );

    test(
      'direct binds JSON events with lazy custom details from metadata bytes',
      () {
        final message = bindMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeEvent,
            primaryId: 7,
            secondaryId: 99,
            flags:
                NativeMessageMetadata.flagMetadataBind |
                NativeMessageMetadata.flagDirectBind |
                NativeMessageMetadata.flagDetailNumberAPresent,
            detailNumberA: 55,
            stringA: 'bench.topic',
            detailsBytes: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'publisher': 55,
                  'topic': 'bench.topic',
                  '_trace': 'ok',
                }),
              ),
            ),
          ),
          argsBytes: Uint8List.fromList(utf8.encode(jsonEncode(['payload']))),
          kwargsBytes: Uint8List.fromList(
            utf8.encode(jsonEncode({'flag': true})),
          ),
        );

        expect(message, isA<Event>());
        final event = message as Event;
        expect(event.details.publisher, 55);
        expect(event.details.topic, 'bench.topic');
        expect(event.details.custom['_trace'], 'ok');
        expect(event.arguments, ['payload']);
        expect(event.argumentsKeywords, {'flag': true});
      },
    );

    test(
      'bindSessionMessage keeps direct event payloads as native session messages',
      () {
        final message = bindSessionMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeEvent,
            primaryId: 7,
            secondaryId: 99,
            flags:
                NativeMessageMetadata.flagDirectBind |
                NativeMessageMetadata.flagMetadataBind,
          ),
          argsBytes: Uint8List.fromList(utf8.encode(jsonEncode(['payload']))),
        );

        expect(message, isA<NativeSessionMessage>());
        final materialized = materializeSessionMessage(message) as Event;
        expect(materialized.subscriptionId, 7);
        expect(materialized.publicationId, 99);
        expect(materialized.arguments, ['payload']);
      },
    );

    test(
      'bindSessionMessage keeps direct welcome messages as native session messages',
      () {
        final message = bindSessionMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeWelcome,
            primaryId: 4242,
            flags:
                NativeMessageMetadata.flagDirectBind |
                NativeMessageMetadata.flagMetadataBind,
            stringA: 'bench.realm',
          ),
        );

        expect(message, isA<NativeSessionMessage>());
        final materialized = materializeSessionMessage(message) as Welcome;
        expect(materialized.sessionId, 4242);
        expect(materialized.details.realm, 'bench.realm');
      },
    );

    test(
      'bindSessionMessage keeps metadata-bound welcome messages as native session messages',
      () {
        final message = bindSessionMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeWelcome,
            primaryId: 5150,
            flags: NativeMessageMetadata.flagMetadataBind,
            detailsBytes: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'realm': 'bench.realm',
                  'roles': {
                    'dealer': {
                      'features': {'call_timeout': true},
                    },
                  },
                }),
              ),
            ),
          ),
        );

        expect(message, isA<NativeSessionMessage>());
        final materialized = materializeSessionMessage(message) as Welcome;
        expect(materialized.sessionId, 5150);
        expect(materialized.details.realm, 'bench.realm');
        expect(
          materialized.details.roles?.dealer?.features?.callTimeout,
          isTrue,
        );
      },
    );

    test(
      'materializing native challenge transfers its borrowed metadata anchor',
      () {
        final message = bindSessionMessage(
          NativeMessageSerializer.messagePack,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeChallenge,
            flags: NativeMessageMetadata.flagMetadataBind,
            stringA: 'wamp-scram',
            detailsBytes: Uint8List.fromList(
              msgpack.serialize({
                'challenge': 'abc123',
                'salt': 'salt',
                'iterations': 4096,
                'memory': 65536,
              }),
            ),
          ),
        );
        final anchor = Object();

        expect(message, isA<NativeSessionMessage>());
        attachSessionMessageAnchor(message, anchor);
        final materialized = materializeSessionMessage(message) as Challenge;

        expect(sessionMessageAnchorFor(materialized), same(anchor));
        expect(materialized.authMethod, 'wamp-scram');
        expect(materialized.extra.challenge, 'abc123');
        expect(materialized.extra.salt, 'salt');
        expect(materialized.extra.iterations, 4096);
        expect(materialized.extra.memory, 65536);
      },
    );

    test(
      'bindSessionMessage keeps interrupt control frames as native session messages',
      () {
        final message = bindSessionMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList([0x00]),
          metadata: _metadata(
            messageCode: MessageTypes.codeInterrupt,
            primaryId: 31337,
            flags:
                NativeMessageMetadata.flagDirectBind |
                NativeMessageMetadata.flagMetadataBind,
            stringA: CancelOptions.modeKillNoWait,
          ),
        );

        expect(message, isA<NativeSessionMessage>());
        final materialized = materializeSessionMessage(message) as Interrupt;
        expect(materialized.requestId, 31337);
        expect(
          materialized.options?.mode,
          equals(CancelOptions.modeKillNoWait),
        );
      },
    );

    test('decodes JSON events with lazy args and kwargs', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              MessageTypes.codeEvent,
              7,
              99,
              {'topic': 'bench.topic', '_extra': true},
            ]),
          ),
        ),
        argsBytes: Uint8List.fromList(utf8.encode(jsonEncode(['payload']))),
        kwargsBytes: Uint8List.fromList(
          utf8.encode(jsonEncode({'flag': true})),
        ),
      );

      expect(message, isA<Event>());
      final event = message as Event;
      expect(event.subscriptionId, 7);
      expect(event.publicationId, 99);
      expect(event.details.topic, 'bench.topic');
      expect(event.details.custom['_extra'], isTrue);
      expect(event.hasLazyArguments, isTrue);
      expect(event.hasLazyArgumentsKeywords, isTrue);
      expect(event.arguments, ['payload']);
      expect(event.argumentsKeywords, {'flag': true});
    });

    test(
      'falls back to payload decoding when native metadata is not direct',
      () {
        final message = bindMessage(
          NativeMessageSerializer.json,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode([
                MessageTypes.codeEvent,
                7,
                99,
                {'topic': 'bench.topic', '_extra': true},
              ]),
            ),
          ),
          metadata: _metadata(
            messageCode: MessageTypes.codeEvent,
            primaryId: 7,
            secondaryId: 99,
            stringA: 'ignored-by-fallback',
          ),
        );

        expect(message, isA<Event>());
        final event = message as Event;
        expect(event.details.topic, 'bench.topic');
        expect(event.details.custom['_extra'], isTrue);
      },
    );

    test('direct binds MsgPack results without decoding the full frame', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeResult,
          primaryId: 123,
          flags:
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagDetailBoolATrue,
          stringA: 'wamp',
          stringB: 'msgpack',
          stringC: 'aes',
          stringD: 'kid-2',
        ),
        argsBytes: Uint8List.fromList(msgpack.serialize(['payload'])),
        kwargsBytes: Uint8List.fromList(msgpack.serialize({'flag': true})),
      );

      expect(message, isA<Result>());
      final result = message as Result;
      expect(result.callRequestId, 123);
      expect(result.details.progress, isTrue);
      expect(result.details.pptScheme, 'wamp');
      expect(result.details.pptSerializer, 'msgpack');
      expect(result.details.pptCipher, 'aes');
      expect(result.details.pptKeyId, 'kid-2');
      expect(result.arguments, ['payload']);
      expect(result.argumentsKeywords, {'flag': true});
    });

    test('decodes MsgPack results with lazy payload and custom details', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List.fromList(
          msgpack.serialize([
            MessageTypes.codeResult,
            123,
            {'progress': true, '_hint': 'native'},
          ]),
        ),
        argsBytes: Uint8List.fromList(msgpack.serialize(['payload'])),
        kwargsBytes: Uint8List.fromList(msgpack.serialize({'flag': true})),
      );

      expect(message, isA<Result>());
      final result = message as Result;
      expect(result.callRequestId, 123);
      expect(result.details.progress, isTrue);
      expect(result.details.custom['_hint'], 'native');
      expect(result.arguments, ['payload']);
      expect(result.argumentsKeywords, {'flag': true});
    });

    test('direct binds CBOR invocations without decoding the full frame', () {
      final message = bindMessage(
        NativeMessageSerializer.cbor,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeInvocation,
          primaryId: 77,
          secondaryId: 12,
          detailNumberA: 5,
          detailNumberB: 250,
          flags:
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagDetailNumberAPresent |
              NativeMessageMetadata.flagDetailNumberBPresent |
              NativeMessageMetadata.flagDetailBoolATrue |
              NativeMessageMetadata.flagDetailBoolBTrue,
          stringA: 'bench.rpc.echo',
          stringB: 'wamp',
          stringC: 'cbor',
          stringD: 'aes',
          stringE: 'kid-3',
        ),
        argsBytes: Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue(['payload'])),
        ),
        kwargsBytes: Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue({'flag': true})),
        ),
      );

      expect(message, isA<Invocation>());
      final invocation = message as Invocation;
      expect(invocation.requestId, 77);
      expect(invocation.registrationId, 12);
      expect(invocation.details.caller, 5);
      expect(invocation.details.procedure, 'bench.rpc.echo');
      expect(invocation.details.progress, isTrue);
      expect(invocation.details.receiveProgress, isTrue);
      expect(invocation.details.timeout, 250);
      expect(invocation.details.pptScheme, 'wamp');
      expect(invocation.details.pptSerializer, 'cbor');
      expect(invocation.details.pptCipher, 'aes');
      expect(invocation.details.pptKeyId, 'kid-3');
      expect(invocation.arguments, ['payload']);
      expect(invocation.argumentsKeywords, {'flag': true});
    });

    test('decodes CBOR invocations with lazy payload and custom details', () {
      final message = bindMessage(
        NativeMessageSerializer.cbor,
        Uint8List.fromList(
          cbor.cborEncode(
            cbor.CborValue([
              MessageTypes.codeInvocation,
              77,
              12,
              {
                'caller': 5,
                'procedure': 'bench.rpc.echo',
                'progress': true,
                'receive_progress': true,
                'timeout': 250,
                '_trace': 'ok',
              },
            ]),
          ),
        ),
        argsBytes: Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue(['payload'])),
        ),
        kwargsBytes: Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue({'flag': true})),
        ),
      );

      expect(message, isA<Invocation>());
      final invocation = message as Invocation;
      expect(invocation.requestId, 77);
      expect(invocation.registrationId, 12);
      expect(invocation.details.caller, 5);
      expect(invocation.details.procedure, 'bench.rpc.echo');
      expect(invocation.details.progress, isTrue);
      expect(invocation.details.receiveProgress, isTrue);
      expect(invocation.details.timeout, 250);
      expect(invocation.details.custom['_trace'], 'ok');
      expect(invocation.arguments, ['payload']);
      expect(invocation.argumentsKeywords, {'flag': true});
    });

    test('direct binds Goodbye from native metadata', () {
      final message = bindMessage(
        NativeMessageSerializer.json,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeGoodbye,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind,
          stringA: Goodbye.reasonSystemShutdown,
          stringB: 'bye',
        ),
      );

      expect(message, isA<Goodbye>());
      final goodbye = message as Goodbye;
      expect(goodbye.reason, Goodbye.reasonSystemShutdown);
      expect(goodbye.message?.message, 'bye');
    });

    test('direct binds Error from native metadata with lazy payload', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeError,
          primaryId: MessageTypes.codeCall,
          secondaryId: 777,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind,
          stringA: Error.runtimeError,
          stringB: 'boom',
        ),
        argsBytes: Uint8List.fromList(msgpack.serialize(['payload'])),
        kwargsBytes: Uint8List.fromList(msgpack.serialize({'flag': true})),
      );

      expect(message, isA<Error>());
      final error = message as Error;
      expect(error.requestTypeId, MessageTypes.codeCall);
      expect(error.requestId, 777);
      expect(error.error, Error.runtimeError);
      expect(error.details['message'], 'boom');
      expect(error.arguments, ['payload']);
      expect(error.argumentsKeywords, {'flag': true});
    });

    test('direct binds Error custom details from metadata bytes', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeError,
          primaryId: MessageTypes.codeCall,
          secondaryId: 777,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind,
          stringA: Error.runtimeError,
          stringB: 'boom',
          detailsBytes: Uint8List.fromList(
            msgpack.serialize({'message': 'boom', '_trace': 'native'}),
          ),
        ),
      );

      expect(message, isA<Error>());
      final error = message as Error;
      expect(error.error, Error.runtimeError);
      expect(error.details['message'], 'boom');
      expect(error.details['_trace'], 'native');
    });

    test('metadata binds Error custom details with lazy payload', () {
      final message = bindMessage(
        NativeMessageSerializer.cbor,
        Uint8List.fromList([0x00]),
        metadata: _metadata(
          messageCode: MessageTypes.codeError,
          primaryId: MessageTypes.codeCall,
          secondaryId: 777,
          flags: NativeMessageMetadata.flagMetadataBind,
          stringA: Error.runtimeError,
          detailsBytes: Uint8List.fromList(
            cbor.cborEncode(
              cbor.CborValue({'message': 'boom', '_trace': 'native'}),
            ),
          ),
        ),
        argsBytes: Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue(['payload'])),
        ),
        kwargsBytes: Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue({'flag': true})),
        ),
      );

      expect(message, isA<Error>());
      final error = message as Error;
      expect(error.requestTypeId, MessageTypes.codeCall);
      expect(error.requestId, 777);
      expect(error.error, Error.runtimeError);
      expect(error.details['message'], 'boom');
      expect(error.details['_trace'], 'native');
      expect(error.arguments, ['payload']);
      expect(error.argumentsKeywords, {'flag': true});
    });

    test('metadata binds Heartbeat without a full frame', () {
      final message = bindMessage(
        NativeMessageSerializer.cbor,
        Uint8List(0),
        metadata: _metadata(
          messageCode: MessageTypes.codeHeartbeat,
          flags: NativeMessageMetadata.flagMetadataBind,
          detailsBytes: Uint8List.fromList(
            cbor.cborEncode(
              cbor.CborValue({
                'details': {'mode': 'ping'},
                'ping': 10,
                'incoming': 11,
                'outgoing': 12,
              }),
            ),
          ),
        ),
      );

      expect(message, isA<Heartbeat>());
      final heartbeat = message as Heartbeat;
      expect(heartbeat.details, {'mode': 'ping'});
      expect(heartbeat.ping, 10);
      expect(heartbeat.incoming, 11);
      expect(heartbeat.outgoing, 12);
    });

    test('metadata binds Unknown messages without a full frame', () {
      final message = bindMessage(
        NativeMessageSerializer.messagePack,
        Uint8List(0),
        metadata: _metadata(
          messageCode: 999,
          flags: NativeMessageMetadata.flagMetadataBind,
          detailsBytes: Uint8List.fromList(
            msgpack.serialize({
              'fields': [
                123,
                {'trace_id': 'unknown-1'},
              ],
              'request_id': 123,
            }),
          ),
        ),
      );

      expect(message, isA<UnknownMessage>());
      final unknown = message as UnknownMessage;
      expect(unknown.id, 999);
      expect(unknown.requestId, 123);
      expect(unknown.fields, [
        123,
        {'trace_id': 'unknown-1'},
      ]);
    });
  });
}

void _bindingBoundaryContracts() {
  for (final serializer in [
    NativeMessageSerializer.json,
    NativeMessageSerializer.messagePack,
    NativeMessageSerializer.cbor,
  ]) {
    Uint8List encode(Object value) => switch (serializer) {
      NativeMessageSerializer.json => Uint8List.fromList(
        utf8.encode(jsonEncode(value)),
      ),
      NativeMessageSerializer.messagePack => msgpack.serialize(value),
      NativeMessageSerializer.cbor => Uint8List.fromList(
        cbor.cbor.encode(cbor.CborValue(value)),
      ),
      _ => throw StateError('Unsupported test serializer: $serializer'),
    };

    AbstractMessage bindMetadata(
      int code, {
      required bool direct,
      String? stringA,
      String? stringB,
      Uint8List? detailsBytes,
    }) => bindMessage(
      serializer,
      encode([9999]),
      metadata: _metadata(
        messageCode: code,
        primaryId: 81,
        secondaryId: 93,
        flags:
            NativeMessageMetadata.flagMetadataBind |
            (direct ? NativeMessageMetadata.flagDirectBind : 0),
        stringA: stringA,
        stringB: stringB,
        detailsBytes: detailsBytes,
      ),
    );

    test('minimal unknown extension frame stays unknown $serializer', () {
      final bytes = encode([9999]);
      final value = _expectMessage<UnknownMessage>(
        _validFrame(() => bindMessage(serializer, bytes)),
      );
      expect(value.id, 9999);
      expect(value.fields, isEmpty);
      expect(value.requestId, isNull);
    });
    for (final payloadFields in [0, 1, 2]) {
      test('ABORT optional payload boundary $payloadFields $serializer', () {
        final bytes = encode([
          3,
          {'message': 'unavailable', '_retry': true},
          'com.error.unavailable',
          if (payloadFields > 0) [17, 'reason'],
          if (payloadFields > 1) {'retry_after': 30},
        ]);
        final value = _expectMessage<Abort>(
          _validFrame(() => bindMessage(serializer, bytes)),
        );
        expect(value.id, 3);
        expect(value.reason, 'com.error.unavailable');
        expect(value.message?.message, 'unavailable');
        expect(value.details, {'message': 'unavailable', '_retry': true});
        expect(value.arguments, payloadFields > 0 ? [17, 'reason'] : null);
        expect(
          value.argumentsKeywords,
          payloadFields > 1 ? {'retry_after': 30} : null,
        );
      });
    }
    for (final present in [false, true]) {
      for (final code in [3, 8]) {
        test('direct details loader $code present=$present $serializer', () {
          final value = bindMetadata(
            code,
            direct: true,
            stringA: 'com.error.unavailable',
            stringB: 'metadata message',
            detailsBytes: present
                ? encode({
                    'message': 'encoded message',
                    '_marker': 'encoded',
                    '_local': 'encoded',
                  })
                : null,
          );
          expect(value, code == 3 ? isA<Abort>() : isA<Error>());
          final details = _expectLazyMap(switch (value) {
            Abort() => value.details,
            Error() => value.details,
            _ => fail('Unexpected details container'),
          });
          expect(details.hasPendingLoader, present);
          expect(details['message'], 'metadata message');
          expect(details.hasPendingLoader, present);
          details['_local'] = 'caller';
          expect(details, {
            'message': 'metadata message',
            '_local': 'caller',
            if (present) '_marker': 'encoded',
          });
          expect(details.hasPendingLoader, isFalse);
          expect(details['_local'], 'caller');
        });
      }
    }

    test('full WELCOME preserves session and identity $serializer', () {
      final bytes = encode([
        2,
        81,
        {
          'realm': 'com.realm',
          'authid': 'consumer',
          'roles': {'dealer': {}},
        },
      ]);
      final value = _expectMessage<Welcome>(
        _validFrame(() => bindMessage(serializer, bytes)),
      );
      expect(value.id, 2);
      expect(value.sessionId, 81);
      expect(value.details.realm, 'com.realm');
      expect(value.details.authid, 'consumer');
      expect(value.details.roles?.dealer, isNotNull);
    });
    for (final direct in [false, true]) {
      test('INTERRUPT mode authority direct=$direct $serializer', () {
        final value = _expectMessage<Interrupt>(
          bindMetadata(
            69,
            direct: direct,
            stringA: 'kill',
            detailsBytes: encode({'mode': 'killnowait'}),
          ),
        );
        expect(value.requestId, 81);
        expect(value.options?.mode, direct ? 'kill' : 'killnowait');
      });
      for (final present in [false, true]) {
        for (final code in [36, 50, 68]) {
          test(
            'custom loader $code direct=$direct present=$present $serializer',
            () {
              final value = bindMetadata(
                code,
                direct: direct,
                detailsBytes: present
                    ? encode({'_marker': 'encoded', '_local': 'encoded'})
                    : null,
              );
              expect(value.id, code);
              final custom = _expectLazyMap(switch (value) {
                Event() => value.details.custom,
                Result() => value.details.custom,
                Invocation() => value.details.custom,
                _ => fail('Unexpected payload message'),
              });
              expect(custom.hasPendingLoader, direct && present);
              custom['_local'] = 'caller';
              expect(custom, {
                '_local': 'caller',
                if (present) '_marker': 'encoded',
              });
              expect(custom.hasPendingLoader, isFalse);
              expect(custom['_local'], 'caller');
            },
          );
        }
      }
    }
    for (final present in [false, true]) {
      for (final code in [2, 4]) {
        test('handshake loader $code present=$present $serializer', () {
          final value = bindMetadata(
            code,
            direct: true,
            stringA: code == 2 ? 'com.realm' : 'ticket',
            stringB: 'consumer',
            detailsBytes: present ? encode({'_marker': 'encoded'}) : null,
          );
          expect(value, code == 2 ? isA<Welcome>() : isA<Challenge>());
          final custom = _expectLazyMap(switch (value) {
            Welcome() => value.details.custom,
            Challenge() => value.extra.custom,
            _ => fail('Unexpected handshake'),
          });
          expect(custom.hasPendingLoader, present);
          expect(custom, {if (present) '_marker': 'encoded'});
          expect(custom.hasPendingLoader, isFalse);
        });
      }
    }
  }
  test('JSON normalized nested lists are fixed-length but replaceable', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode([
          8,
          48,
          81,
          {
            '_nested': [1, '\u0000AQID'],
          },
          'com.error',
        ]),
      ),
    );
    final value = _expectMessage<Error>(
      _validFrame(() => bindMessage(NativeMessageSerializer.json, bytes)),
    );
    final nested = value.details['_nested'];
    expect(nested, isA<List>());
    final values = nested as List;
    expect(values[0], 1);
    expect(values[1], isA<Uint8List>());
    expect(values[1], [1, 2, 3]);
    values[0] = 9;
    expect(values[0], 9);
    expect(() => values.add(10), throwsUnsupportedError);
    expect(() => values.removeLast(), throwsUnsupportedError);
    expect(values.length, 2);
    expect(values[1], [1, 2, 3]);
  });
}

LazyStringKeyMap<dynamic> _expectLazyMap(Map<String, dynamic> value) {
  expect(value, isA<LazyStringKeyMap<dynamic>>());
  return value as LazyStringKeyMap<dynamic>;
}

void _metadataDispatchContracts() {
  final contracts = <int, Matcher>{
    2: isA<Welcome>(),
    3: isA<Abort>(),
    4: isA<Challenge>(),
    6: isA<Goodbye>(),
    7: isA<Heartbeat>(),
    8: isA<Error>(),
    17: isA<Published>(),
    33: isA<Subscribed>(),
    35: isA<Unsubscribed>(),
    36: isA<Event>(),
    50: isA<Result>(),
    65: isA<Registered>(),
    67: isA<Unregistered>(),
    68: isA<Invocation>(),
    69: isA<Interrupt>(),
    7777: isA<UnknownMessage>(),
  };
  for (final serializer in [
    NativeMessageSerializer.json,
    NativeMessageSerializer.messagePack,
    NativeMessageSerializer.cbor,
  ]) {
    Uint8List encode(Object value) => switch (serializer) {
      NativeMessageSerializer.json => Uint8List.fromList(
        utf8.encode(jsonEncode(value)),
      ),
      NativeMessageSerializer.messagePack => msgpack.serialize(value),
      NativeMessageSerializer.cbor => Uint8List.fromList(
        cbor.cbor.encode(cbor.CborValue(value)),
      ),
      _ => throw StateError('Unsupported test serializer: $serializer'),
    };
    for (final direct in [false, true]) {
      for (final contract in contracts.entries) {
        test(
          'metadata dispatch ${contract.key} $serializer direct=$direct overrides a valid frame',
          () {
            // A wrong fallback must be observable as a value, not a decode crash.
            final message = bindMessage(
              serializer,
              encode([9999]),
              metadata: _metadata(
                messageCode: contract.key,
                primaryId: 81,
                secondaryId: 93,
                flags:
                    NativeMessageMetadata.flagMetadataBind |
                    (direct ? NativeMessageMetadata.flagDirectBind : 0),
                stringA: 'killnowait',
                stringB: 'exact',
                detailsBytes: encode({
                  'roles': {'dealer': {}, 'caller': {}},
                  'realm': 'wire.realm',
                  'message': 'wire message',
                  'mode': 'killnowait',
                  'fields': ['metadata'],
                  'request_id': 73,
                  'details': {'marker': 'wire'},
                  'ping': 11,
                  'incoming': 12,
                  'outgoing': 13,
                }),
              ),
            );
            expect(message, contract.value);
            expect(message.id, contract.key);
            switch (message) {
              case Welcome():
                expect(message.sessionId, 81);
                expect(
                  message.details.realm,
                  direct ? 'killnowait' : 'wire.realm',
                );
                expect(message.details.roles?.dealer, isNotNull);
              case Abort():
                expect(message.reason, 'killnowait');
                expect(
                  message.message?.message,
                  direct ? 'exact' : 'wire message',
                );
              case Challenge():
                expect(message.authMethod, 'killnowait');
              case Goodbye():
                expect(message.reason, 'killnowait');
                expect(
                  message.message?.message,
                  direct ? 'exact' : 'wire message',
                );
              case Heartbeat():
                expect(message.details, {'marker': 'wire'});
                expect(
                  [message.ping, message.incoming, message.outgoing],
                  [11, 12, 13],
                );
              case Error():
                expect(message.requestTypeId, 81);
                expect(message.requestId, 93);
                expect(message.error, 'killnowait');
                expect(
                  message.details['message'],
                  direct ? 'exact' : 'wire message',
                );
              case Published():
                expect(message.publishRequestId, 81);
                expect(message.publicationId, 93);
              case Subscribed():
                expect(message.subscribeRequestId, 81);
                expect(message.subscriptionId, 93);
              case Unsubscribed():
                expect(message.unsubscribeRequestId, 81);
              case Event():
                expect(message.subscriptionId, 81);
                expect(message.publicationId, 93);
              case Result():
                expect(message.callRequestId, 81);
              case Registered():
                expect(message.registerRequestId, 81);
                expect(message.registrationId, 93);
              case Unregistered():
                expect(message.unregisterRequestId, 81);
              case Invocation():
                expect(message.requestId, 81);
                expect(message.registrationId, 93);
              case Interrupt():
                expect(message.requestId, 81);
                expect(message.options?.mode, 'killnowait');
              case UnknownMessage():
                expect(message.fields, ['metadata']);
                expect(message.requestId, 73);
            }
          },
        );
      }
    }
  }
}

T _expectMessage<T extends AbstractMessage>(AbstractMessage? value) {
  expect(value, isA<T>());
  return value as T;
}

// Only for known-valid, synchronous in-memory frames; never negative fixtures.
T _validFrame<T>(T Function() decode) {
  try {
    return decode();
  } on FormatException catch (error) {
    fail('Known-valid frame was rejected as malformed: $error');
  } on ArgumentError catch (error) {
    fail('Known-valid frame was rejected by the decoder: $error');
  }
}

void _validFrameContracts() {
  test(
    'valid frame assertion evaluates once and preserves result identity',
    () {
      final value = Object();
      var calls = 0;
      expect(
        _validFrame(() {
          calls++;
          return value;
        }),
        same(value),
      );
      expect(calls, 1);
      expect(_validFrame<Object?>(() => null), isNull);
    },
  );
  for (final rejection in <Object>[
    const FormatException('fixture'),
    ArgumentError('fixture'),
    RangeError.index(2, [1]),
  ]) {
    test(
      'valid frame assertion identifies ${rejection.runtimeType} rejection',
      () {
        var calls = 0;
        expect(
          () => _validFrame(() {
            calls++;
            throw rejection;
          }),
          throwsA(isA<TestFailure>()),
        );
        expect(calls, 1);
      },
    );
  }
  for (final failure in <Object>[
    StateError('runtime'),
    UnsupportedError('serializer'),
    TypeError(),
    TimeoutException('deadline'),
    const FileSystemException('filesystem'),
    const SocketException('socket'),
    ProcessException('process', []),
    TestFailure('original assertion'),
    AssertionError('original assertion'),
    StackOverflowError(),
    const OutOfMemoryError(),
  ]) {
    test('valid frame assertion preserves ${failure.runtimeType}', () {
      expect(() => _validFrame(() => throw failure), throwsA(same(failure)));
    });
  }
}

NativeMessageMetadata _metadata({
  required int messageCode,
  int primaryId = 0,
  int secondaryId = 0,
  int detailNumberA = 0,
  int detailNumberB = 0,
  int flags = 0,
  Uint8List? detailsBytes,
  String? stringA,
  String? stringB,
  String? stringC,
  String? stringD,
  String? stringE,
}) {
  final normalizedFlags = (flags & NativeMessageMetadata.flagDirectBind) != 0
      ? (flags | NativeMessageMetadata.flagMetadataBind)
      : flags;
  return NativeMessageMetadata(
    messageCode: messageCode,
    primaryId: primaryId,
    secondaryId: secondaryId,
    detailNumberA: detailNumberA,
    detailNumberB: detailNumberB,
    flags: normalizedFlags,
    detailsBytes: detailsBytes,
    stringA: stringA,
    stringB: stringB,
    stringC: stringC,
    stringD: stringD,
    stringE: stringE,
  );
}

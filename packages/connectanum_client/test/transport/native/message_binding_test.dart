@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/src/transport/native/message_binding.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
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
            {'challenge': 'abc123', 'salt': 'salt', 'iterations': 4096},
          ]),
        ),
      );

      expect(message, isA<Challenge>());
      final challenge = message as Challenge;
      expect(challenge.authMethod, 'ticket');
      expect(challenge.extra.challenge, 'abc123');
      expect(challenge.extra.salt, 'salt');
      expect(challenge.extra.iterations, 4096);
    });

    test('direct binds Welcome from native metadata', () {
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
          flags:
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagDetailNumberAPresent |
              NativeMessageMetadata.flagDetailBoolATrue,
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
      expect(invocation.details.receiveProgress, isTrue);
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
                'receive_progress': true,
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
      expect(invocation.details.receiveProgress, isTrue);
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
  });
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

import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

T _decode<T extends AbstractMessage>(List<Object?> frame) {
  final message = Serializer().deserialize(msgpack.serialize(frame));
  expect(message, isA<T>());
  expect(message!.id, frame.first);
  return message as T;
}

void main() {
  group('MessagePack router ingress', () {
    test('rejects an empty message with a protocol error', () {
      expect(
        () => Serializer().deserialize(msgpack.serialize(<Object?>[])),
        throwsA(isA<FormatException>()),
      );
    });

    for (final invalidType in <Object?>[
      null,
      true,
      false,
      '48',
      48.5,
      <Object?>[],
      <String, Object?>{},
    ]) {
      test('rejects non-integer message type $invalidType', () {
        expect(
          () => Serializer().deserialize(
            msgpack.serialize([invalidType, 1, <String, Object?>{}]),
          ),
          throwsA(
            isA<FormatException>()
                .having(
                  (error) => error.message,
                  'message',
                  'WAMP message type must be an integer',
                )
                .having((error) => error.source, 'source', isNull),
          ),
        );
      });
    }

    test('HELLO preserves authentication, roles and custom details', () {
      final message = _decode<Hello>([
        1,
        'com.example.realm',
        {
          'agent': 'consumer/1',
          'authid': 'alice',
          'authrole': 'user',
          'authmethods': ['scram', 'ticket'],
          'authextra': {'device': 'phone', 'optional': null},
          'roles': {
            'caller': {
              'features': {
                'call_timeout': true,
                'call_canceling': false,
                'progressive_call_invocations': true,
              },
            },
          },
          'application': {
            'name': 'consumer',
            'flags': [true, false],
          },
        },
      ]);
      expect(message.realm, 'com.example.realm');
      expect(message.details.agent, 'consumer/1');
      expect(message.details.authid, 'alice');
      expect(message.details.authrole, 'user');
      expect(message.details.authmethods, ['scram', 'ticket']);
      expect(message.details.authextra, {'device': 'phone', 'optional': null});
      expect(message.details.roles!.caller!.features!.callTimeout, isTrue);
      expect(message.details.roles!.caller!.features!.callCanceling, isFalse);
      expect(
        message.details.roles!.caller!.features!.progressiveCallInvocations,
        isTrue,
      );
      expect(message.details.roles!.callee, isNull);
      expect(message.details.custom, {
        'application': {
          'name': 'consumer',
          'flags': [true, false],
        },
      });
    });

    test('AUTHENTICATE preserves signature and nested nullable extra', () {
      final message = _decode<Authenticate>([
        5,
        'synthetic-proof',
        {
          'channel_binding': 'tls-unique',
          'custom': {
            'optional': null,
            'flags': [1, 2],
          },
        },
      ]);
      expect(message.signature, 'synthetic-proof');
      expect(message.extra, {
        'channel_binding': 'tls-unique',
        'custom': {
          'optional': null,
          'flags': [1, 2],
        },
      });
    });

    test('REGISTER preserves dispatch policy and extension options', () {
      final message = _decode<Register>([
        64,
        13,
        {
          'match': 'prefix',
          'invoke': 'roundrobin',
          'disclose_caller': true,
          'forward_timeout': false,
          'schema': {'type': 'object'},
        },
        'com.example.procedure',
      ]);
      expect(message.requestId, 13);
      expect(message.procedure, 'com.example.procedure');
      expect(message.options!.match, 'prefix');
      expect(message.options!.invoke, 'roundrobin');
      expect(message.options!.discloseCaller, isTrue);
      expect(message.options!.forwardTimeout, isFalse);
      expect(message.options!.custom, {
        'schema': {'type': 'object'},
      });
    });

    test('UNREGISTER keeps request and registration IDs distinct', () {
      final message = _decode<Unregister>([66, 17, 29]);
      expect(message.requestId, 17);
      expect(message.registrationId, 29);
    });

    test('UNSUBSCRIBE keeps request and subscription IDs distinct', () {
      final message = _decode<Unsubscribe>([34, 19, 31]);
      expect(message.requestId, 19);
      expect(message.subscriptionId, 31);
    });

    test(
      'CALL preserves progressive options, timeout and both payload fields',
      () {
        final message = _decode<Call>([
          48,
          23,
          {
            'progress': true,
            'receive_progress': false,
            'timeout': 1234,
            'disclose_me': false,
            'trace': 'call',
          },
          'com.example.call',
          [3, 'request'],
          {'named': true, 'optional': null},
        ]);
        expect(message.requestId, 23);
        expect(message.procedure, 'com.example.call');
        expect(message.options!.progress, isTrue);
        expect(message.options!.receiveProgress, isFalse);
        expect(message.options!.timeout, 1234);
        expect(message.options!.discloseMe, isFalse);
        expect(message.options!.custom, {'trace': 'call'});
        expect(message.arguments, [3, 'request']);
        expect(message.argumentsKeywords, {'named': true, 'optional': null});
      },
    );

    test('YIELD preserves progress, custom metadata and payloads', () {
      final message = _decode<Yield>([
        70,
        37,
        {'progress': true, 'trace': 'yield'},
        [false],
        {'sequence': 4},
      ]);
      expect(message.invocationRequestId, 37);
      expect(message.options!.progress, isTrue);
      expect(message.options!.custom, {'trace': 'yield'});
      expect(message.arguments, [false]);
      expect(message.argumentsKeywords, {'sequence': 4});
    });

    test('PUBLISH preserves independent recipient filters and flags', () {
      final message = _decode<Publish>([
        16,
        41,
        {
          'acknowledge': true,
          'exclude': [43, 47],
          'eligible': [53, 59],
          'exclude_authid': ['excluded-user'],
          'eligible_authid': ['eligible-user'],
          'exclude_authrole': ['excluded-role'],
          'eligible_authrole': ['eligible-role'],
          'exclude_me': false,
          'disclose_me': true,
          'retain': false,
          'trace': 'publish',
        },
        'com.example.topic',
        [5],
        {'event': 'updated'},
      ]);
      expect(message.requestId, 41);
      expect(message.topic, 'com.example.topic');
      expect(message.options!.acknowledge, isTrue);
      expect(message.options!.exclude, [43, 47]);
      expect(message.options!.eligible, [53, 59]);
      expect(message.options!.excludeAuthId, ['excluded-user']);
      expect(message.options!.eligibleAuthId, ['eligible-user']);
      expect(message.options!.excludeAuthRole, ['excluded-role']);
      expect(message.options!.eligibleAuthRole, ['eligible-role']);
      expect(message.options!.excludeMe, isFalse);
      expect(message.options!.discloseMe, isTrue);
      expect(message.options!.retain, isFalse);
      expect(message.options!.custom, {'trace': 'publish'});
      expect(message.arguments, [5]);
      expect(message.argumentsKeywords, {'event': 'updated'});
    });

    test('SUBSCRIBE preserves matching, retention and custom options', () {
      final message = _decode<Subscribe>([
        32,
        61,
        {
          'match': 'wildcard',
          'get_retained': true,
          'meta_topic': 'com.example.meta',
          'trace': 'subscribe',
        },
        'com..topic',
      ]);
      expect(message.requestId, 61);
      expect(message.topic, 'com..topic');
      expect(message.options!.match, 'wildcard');
      expect(message.options!.getRetained, isTrue);
      expect(message.options!.metaTopic, 'com.example.meta');
      expect(message.options!.custom, {'trace': 'subscribe'});
    });

    for (final code in [16, 48, 70]) {
      for (final payload in <Object?>[
        [1, 'list'],
        Uint8List.fromList([0, 0x80, 0xff]),
      ]) {
        test(
          '$code preserves ${payload is Uint8List ? 'binary' : 'list'} payload',
          () {
            final message = _decode<AbstractMessageWithPayload>([
              code,
              67,
              <String, Object?>{},
              if (code != 70) 'com.example.payload',
              payload,
            ]);
            if (payload is Uint8List) {
              expect(message.transparentBinaryPayload, payload);
            } else {
              expect(message.arguments, payload);
              expect(message.transparentBinaryPayload, isNull);
            }
            expect(message.argumentsKeywords, isNull);
          },
        );
      }
    }
  });
}

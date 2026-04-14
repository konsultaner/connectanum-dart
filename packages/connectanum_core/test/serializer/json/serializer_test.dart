import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/abort.dart';
import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/call.dart';
import 'package:connectanum_core/src/message/cancel.dart';
import 'package:connectanum_core/src/message/challenge.dart';
import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/event.dart';
import 'package:connectanum_core/src/message/error.dart';
import 'package:connectanum_core/src/message/goodbye.dart';
import 'package:connectanum_core/src/message/hello.dart';
import 'package:connectanum_core/src/message/interrupt.dart' as interrupt_msg;
import 'package:connectanum_core/src/message/message_types.dart';
import 'package:connectanum_core/src/message/publish.dart';
import 'package:connectanum_core/src/message/published.dart';
import 'package:connectanum_core/src/message/register.dart';
import 'package:connectanum_core/src/message/registered.dart';
import 'package:connectanum_core/src/message/result.dart';
import 'package:connectanum_core/src/message/subscribe.dart';
import 'package:connectanum_core/src/message/subscribed.dart';
import 'package:connectanum_core/src/message/unregister.dart';
import 'package:connectanum_core/src/message/unregistered.dart';
import 'package:connectanum_core/src/message/unsubscribe.dart';
import 'package:connectanum_core/src/message/unsubscribed.dart';
import 'package:connectanum_core/src/message/welcome.dart';
import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/message/yield.dart';
import 'package:connectanum_core/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_core/src/message/ppt_payload.dart';
import 'package:connectanum_core/src/serializer/json/serializer.dart';
import 'package:pinenacl/api.dart';
import 'package:test/test.dart';

void main() {
  var serializer = Serializer();
  group('serialize', () {
    test('Hello', () {
      expect(
        serializer.serializeToString(Hello('my.realm', Details.forHello())),
        equals(
          '[1,"my.realm",{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_passthru_mode":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_passthru_mode":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_passthru_mode":true}}}}]',
        ),
      );
      expect(
        serializer.serializeToString(Hello(null, Details.forHello())),
        equals(
          '[1,null,{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_passthru_mode":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_passthru_mode":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_passthru_mode":true}}}}]',
        ),
      );
    });
    test('Hello with auth information', () {
      var authHello = Hello('my.realm', Details.forHello());
      authHello.details.authid = 'Richard';
      authHello.details.authmethods = ['WAMP-CRA'];
      authHello.details.authextra = HashMap();
      authHello.details.authextra!['nonce'] = 'egVDf3DMJh0=';
      authHello.details.authextra!['channel_binding'] = null;
      var message = serializer.serializeToString(authHello);
      expect(
        message,
        startsWith(
          '[1,"my.realm",{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_passthru_mode":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_passthru_mode":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_passthru_mode":true}}},"authid":"Richard","authmethods":["WAMP-CRA"],"authextra":',
        ),
      );
      expect(message, contains('"channel_binding":null'));
      expect(message, contains('"nonce":"egVDf3DMJh0="'));
    });
    test('Authenticate', () {
      expect(
        serializer.serializeToString(Authenticate()),
        equals('[${MessageTypes.codeAuthenticate},"",{}]'),
      );
      expect(
        serializer.serializeToString(Authenticate.signature('someSignature')),
        equals('[${MessageTypes.codeAuthenticate},"${"someSignature"}",{}]'),
      );
      var authenticate = Authenticate.signature('someSignature');
      authenticate.extra = HashMap<String, Object?>();
      authenticate.extra!['nonce'] = 'abc';
      expect(
        serializer.serializeToString(authenticate),
        equals(
          '[${MessageTypes.codeAuthenticate},"${"someSignature"}",{"nonce":"abc"}]',
        ),
      );
    });
    test('Call serializes binary custom option fields', () {
      final call = Call(
        42,
        'com.myapp.binary',
        options: CallOptions(
          custom: {
            'trace_id': 'abc',
            'blob': Uint8List.fromList(const [1, 2, 3, 4]),
            'nested': {
              'payload': Uint8List.fromList(const [5, 6, 7]),
            },
          },
        ),
      );

      final frame =
          jsonDecode(serializer.serializeToString(call)) as List<dynamic>;
      final options = frame[2] as Map<dynamic, dynamic>;
      expect(options['trace_id'], equals('abc'));
      expect(options['blob'], startsWith('\\u0000'));
      expect(
        (options['nested'] as Map<dynamic, dynamic>)['payload'],
        startsWith('\\u0000'),
      );
    });
    test('Register', () {
      expect(
        serializer.serializeToString(
          Register(25349185, 'com.myapp.myprocedure1'),
        ),
        equals(
          '[${MessageTypes.codeRegister},25349185,{},"com.myapp.myprocedure1"]',
        ),
      );
      expect(
        serializer.serializeToString(
          Register(
            25349185,
            'com.myapp.myprocedure1',
            options: RegisterOptions(
              discloseCaller: true,
              invoke: RegisterOptions.invocationPolicyRandom,
              match: RegisterOptions.matchPrefix,
            ),
          ),
        ),
        equals(
          '[${MessageTypes.codeRegister},25349185,{"match":"prefix","disclose_caller":true,"invoke":"random"},"com.myapp.myprocedure1"]',
        ),
      );
      expect(
        serializer.serializeToString(
          Register(
            25349185,
            'com.myapp.myprocedure2',
            options: RegisterOptions(discloseCaller: false),
          ),
        ),
        equals(
          '[${MessageTypes.codeRegister},25349185,{"disclose_caller":false},"com.myapp.myprocedure2"]',
        ),
      );
    });
    test('Unregister', () {
      expect(
        serializer.serializeToString(Unregister(25349185, 127981236)),
        equals('[${MessageTypes.codeUnregister},25349185,127981236]'),
      );
    });
    test('Call', () {
      expect(
        serializer.serializeToString(Call(7814135, 'com.myapp.ping')),
        equals('[${MessageTypes.codeCall},7814135,{},"com.myapp.ping"]'),
      );
      expect(
        serializer.serializeToString(
          Call(7814135, 'com.myapp.ping', options: CallOptions()),
        ),
        equals('[${MessageTypes.codeCall},7814135,{},"com.myapp.ping"]'),
      );
      expect(
        serializer.serializeToString(
          Call(
            7814135,
            'com.myapp.ping',
            options: CallOptions(
              receiveProgress: true,
              discloseMe: true,
              timeout: 12,
            ),
          ),
        ),
        equals(
          '[${MessageTypes.codeCall},7814135,{"receive_progress":true,"disclose_me":true,"timeout":12},"com.myapp.ping"]',
        ),
      );
      final callWithCustom = Call(
        7814136,
        'com.myapp.ping',
        options: CallOptions(custom: {'_throttle_key': 'abc'}),
      );
      final encoded = serializer.serializeToString(callWithCustom);
      final decoded = json.decode(encoded) as List;
      expect((decoded[2] as Map<String, dynamic>)['_throttle_key'], 'abc');
      expect(
        serializer.serializeToString(
          Call(7814135, 'com.myapp.ping', arguments: ['hi', 2]),
        ),
        equals(
          '[${MessageTypes.codeCall},7814135,{},"com.myapp.ping",["hi",2]]',
        ),
      );
      expect(
        serializer.serializeToString(
          Call(7814135, 'com.myapp.ping', argumentsKeywords: {'hi': 12}),
        ),
        equals(
          '[${MessageTypes.codeCall},7814135,{},"com.myapp.ping",[],{"hi":12}]',
        ),
      );
      expect(
        serializer.serializeToString(
          Call(
            7814135,
            'com.myapp.ping',
            arguments: ['hi', 2],
            argumentsKeywords: {'hi': 12},
          ),
        ),
        equals(
          '[${MessageTypes.codeCall},7814135,{},"com.myapp.ping",["hi",2],{"hi":12}]',
        ),
      );
    });
    test('Call reuses lazy JSON argument bytes without decoding', () {
      final call = Call(7814135, 'com.myapp.ping');
      call.setLazyPayload(
        argumentsBytes: Uint8List.fromList(utf8.encode('["lazy"]')),
        argumentsDecoder: (_) => throw StateError('should not decode args'),
        encoding: LazyPayloadEncoding.json,
      );

      expect(
        json.decode(serializer.serializeToString(call)),
        equals([
          MessageTypes.codeCall,
          7814135,
          {},
          'com.myapp.ping',
          ['lazy'],
        ]),
      );
    });
    test('Call reuses lazy JSON kwargs bytes without decoding', () {
      final call = Call(7814135, 'com.myapp.ping');
      call.setLazyPayload(
        argumentsKeywordsBytes: Uint8List.fromList(utf8.encode('{"worker":1}')),
        argumentsKeywordsDecoder: (_) =>
            throw StateError('should not decode kwargs'),
        encoding: LazyPayloadEncoding.json,
      );

      expect(
        json.decode(serializer.serializeToString(call)),
        equals([
          MessageTypes.codeCall,
          7814135,
          {},
          'com.myapp.ping',
          [],
          {'worker': 1},
        ]),
      );
    });
    test('Call preserves materialized kwargs with lazy JSON args bytes', () {
      final call = Call(
        7814135,
        'com.myapp.ping',
        argumentsKeywords: {'worker': 1},
      );
      call.setLazyPayload(
        argumentsBytes: Uint8List.fromList(utf8.encode('["lazy"]')),
        argumentsDecoder: (_) => throw StateError('should not decode args'),
        encoding: LazyPayloadEncoding.json,
      );

      expect(
        json.decode(serializer.serializeToString(call)),
        equals([
          MessageTypes.codeCall,
          7814135,
          {},
          'com.myapp.ping',
          ['lazy'],
          {'worker': 1},
        ]),
      );
    });
    test('Call preserves materialized args with lazy JSON kwargs bytes', () {
      final call = Call(7814135, 'com.myapp.ping', arguments: ['lazy']);
      call.setLazyPayload(
        argumentsKeywordsBytes: Uint8List.fromList(utf8.encode('{"worker":1}')),
        argumentsKeywordsDecoder: (_) =>
            throw StateError('should not decode kwargs'),
        encoding: LazyPayloadEncoding.json,
      );

      expect(
        json.decode(serializer.serializeToString(call)),
        equals([
          MessageTypes.codeCall,
          7814135,
          {},
          'com.myapp.ping',
          ['lazy'],
          {'worker': 1},
        ]),
      );
    });
    test('Yield', () {
      expect(
        serializer.serializeToString(Yield(6131533)),
        equals('[${MessageTypes.codeYield},6131533,{}]'),
      );
      expect(
        serializer.serializeToString(
          Yield(6131533, options: YieldOptions(progress: false)),
        ),
        equals('[${MessageTypes.codeYield},6131533,{"progress":false}]'),
      );
      expect(
        serializer.serializeToString(
          Yield(6131533, options: YieldOptions(progress: true)),
        ),
        equals('[${MessageTypes.codeYield},6131533,{"progress":true}]'),
      );
      expect(
        serializer.serializeToString(Yield(6131533, arguments: ['hi', 2])),
        equals('[${MessageTypes.codeYield},6131533,{},["hi",2]]'),
      );
      expect(
        serializer.serializeToString(
          Yield(6131533, argumentsKeywords: {'hi': 12}),
        ),
        equals('[${MessageTypes.codeYield},6131533,{},[],{"hi":12}]'),
      );
      expect(
        serializer.serializeToString(
          Yield(6131533, arguments: ['hi', 2], argumentsKeywords: {'hi': 12}),
        ),
        equals('[${MessageTypes.codeYield},6131533,{},["hi",2],{"hi":12}]'),
      );
      final yieldCustom = serializer.serializeToString(
        Yield(6131534, options: YieldOptions(custom: {'_extra': 'value'})),
      );
      final yieldDecoded = json.decode(yieldCustom) as List;
      expect((yieldDecoded[2] as Map<String, dynamic>)['_extra'], 'value');
    });
    test('Result', () {
      expect(
        serializer.serializeToString(
          Result(734572, ResultDetails(progress: false)),
        ),
        equals('[${MessageTypes.codeResult},734572,{"progress":false}]'),
      );
      final detailed = serializer.serializeToString(
        Result(
          734573,
          ResultDetails(
            progress: true,
            pptScheme: 'aes',
            pptSerializer: 'json',
            pptCipher: 'gcm',
            pptKeyId: 'k1',
            custom: {'custom': 1},
          ),
          arguments: ['ok'],
          argumentsKeywords: {'answer': 42},
        ),
      );
      expect(
        json.decode(detailed),
        equals([
          MessageTypes.codeResult,
          734573,
          {
            'progress': true,
            'ppt_scheme': 'aes',
            'ppt_serializer': 'json',
            'ppt_cipher': 'gcm',
            'ppt_keyid': 'k1',
            'custom': 1,
          },
          ['ok'],
          {'answer': 42},
        ]),
      );
    });
    test('Interrupt', () {
      expect(
        serializer.serializeToString(interrupt_msg.Interrupt(99)),
        equals('[${MessageTypes.codeInterrupt},99,{}]'),
      );
      final interrupt = interrupt_msg.Interrupt(
        101,
        options: interrupt_msg.InterruptOptions()
          ..mode = CancelOptions.modeKill,
      );
      expect(
        serializer.serializeToString(interrupt),
        equals('[${MessageTypes.codeInterrupt},101,{"mode":"kill"}]'),
      );
    });
    test('Cancel', () {
      expect(
        serializer.serializeToString(Cancel(99)),
        equals('[${MessageTypes.codeCancel},99,{}]'),
      );
      final cancel = Cancel(
        101,
        options: CancelOptions()..mode = CancelOptions.modeKill,
      );
      expect(
        serializer.serializeToString(cancel),
        equals('[${MessageTypes.codeCancel},101,{"mode":"kill"}]'),
      );
    });
    test('Error', () {
      expect(
        serializer.serializeToString(
          Error(MessageTypes.codeHello, 123422, HashMap(), 'wamp.unknown'),
        ),
        equals(
          '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{},"wamp.unknown"]',
        ),
      );
      expect(
        serializer.serializeToString(
          Error(
            MessageTypes.codeHello,
            123422,
            HashMap.from({'cause': 'some'}),
            'wamp.unknown',
          ),
        ),
        equals(
          '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown"]',
        ),
      );
      expect(
        serializer.serializeToString(
          Error(
            MessageTypes.codeHello,
            123422,
            HashMap.from({'cause': 'some'}),
            'wamp.unknown',
            arguments: ['hi', 2],
          ),
        ),
        equals(
          '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown",["hi",2]]',
        ),
      );
      expect(
        serializer.serializeToString(
          Error(
            MessageTypes.codeHello,
            123422,
            HashMap.from({'cause': 'some'}),
            'wamp.unknown',
            argumentsKeywords: {'hi': 12},
          ),
        ),
        equals(
          '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown",[],{"hi":12}]',
        ),
      );
      expect(
        serializer.serializeToString(
          Error(
            MessageTypes.codeHello,
            123422,
            HashMap.from({'cause': 'some'}),
            'wamp.unknown',
            arguments: ['hi', 2],
            argumentsKeywords: {'hi': 12},
          ),
        ),
        equals(
          '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown",["hi",2],{"hi":12}]',
        ),
      );
    });
    test('Error round-trips binary detail fields', () {
      final message = Error(MessageTypes.codeCall, 77, {
        'trace_id': 'err-1',
        'blob': Uint8List.fromList(const [1, 2, 3, 4]),
        'nested': {
          'payload': Uint8List.fromList(const [5, 6, 7]),
        },
      }, Error.runtimeError);

      final roundTrip =
          serializer.deserializeFromString(
                serializer.serializeToString(message),
              )
              as Error;

      expect(roundTrip.details['trace_id'], equals('err-1'));
      expect(
        roundTrip.details['blob'],
        orderedEquals(Uint8List.fromList(const [1, 2, 3, 4])),
      );
      expect(
        (roundTrip.details['nested'] as Map)['payload'],
        orderedEquals(Uint8List.fromList(const [5, 6, 7])),
      );
    });
    test('Subscribe', () {
      expect(
        serializer.serializeToString(
          Subscribe(713845233, 'com.myapp.mytopic1'),
        ),
        equals('[32,713845233,{},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(),
          ),
        ),
        equals('[32,713845233,{},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(match: SubscribeOptions.matchPlain),
          ),
        ),
        equals('[32,713845233,{},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(match: SubscribeOptions.matchPrefix),
          ),
        ),
        equals('[32,713845233,{"match":"prefix"},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(match: SubscribeOptions.matchWildcard),
          ),
        ),
        equals('[32,713845233,{"match":"wildcard"},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(metaTopic: 'topic'),
          ),
        ),
        equals('[32,713845233,{"meta_topic":"topic"},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(
              getRetained: true,
              match: SubscribeOptions.matchWildcard,
              metaTopic: 'topic',
            ),
          ),
        ),
        equals(
          '[32,713845233,{"get_retained":true,"match":"wildcard","meta_topic":"topic"},"com.myapp.mytopic1"]',
        ),
      );
      expect(
        serializer.serializeToString(
          Subscribe(
            713845233,
            'com.myapp.mytopic1',
            options: SubscribeOptions(match: SubscribeOptions.matchWildcard)
              ..addCustomValue('where', (_) => '12')
              ..addCustomValue('some', (_) => '{"key":"value"}'),
          ),
        ),
        equals(
          '[32,713845233,{"match":"wildcard","some":{"key":"value"},"where":12},"com.myapp.mytopic1"]',
        ),
      );
      final subscribeCustom = Subscribe(
        713845234,
        'com.myapp.mytopic1',
        options: SubscribeOptions(match: SubscribeOptions.matchPrefix)
          ..setCustomField('_debounce', 42),
      );
      final subEncoded = serializer.serializeToString(subscribeCustom);
      final subDecoded = json.decode(subEncoded) as List;
      expect((subDecoded[2] as Map<String, dynamic>)['_debounce'], 42);
    });
    test('Unsubscribe', () {
      expect(
        serializer.serializeToString(Unsubscribe(85346237, 5512315355)),
        equals('[34,85346237,5512315355]'),
      );
    });
    test('Publish', () {
      expect(
        serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1')),
        equals('[16,239714735,{},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Publish(239714735, 'com.myapp.mytopic1', options: PublishOptions()),
        ),
        equals('[16,239714735,{},"com.myapp.mytopic1"]'),
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            options: PublishOptions(
              retain: true,
              discloseMe: true,
              acknowledge: true,
              excludeMe: true,
              eligible: [1],
              eligibleAuthId: ['aaa'],
              eligibleAuthRole: ['role'],
              exclude: [2],
              excludeAuthId: ['bbb'],
              excludeAuthRole: ['admin'],
            ),
          ),
        ),
        equals(
          '[16,239714735,{"retain":true,"disclose_me":true,"acknowledge":true,"exclude_me":true,"exclude":[2],"exclude_authid":["bbb"],"exclude_authrole":["admin"],"eligible":[1],"eligible_authid":["aaa"],"eligible_authrole":["role"]},"com.myapp.mytopic1"]',
        ),
      );
      final publishCustom = Publish(
        239714736,
        'com.myapp.mytopic1',
        options: PublishOptions(custom: {'_debounce_key': 'payload'}),
      );
      final publishEncoded = serializer.serializeToString(publishCustom);
      final publishDecoded = json.decode(publishEncoded) as List;
      expect(
        (publishDecoded[2] as Map<String, dynamic>)['_debounce_key'],
        'payload',
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            arguments: ['Hello, world!'],
          ),
        ),
        equals('[16,239714735,{},"com.myapp.mytopic1",["Hello, world!"]]'),
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            options: PublishOptions(excludeMe: false),
            arguments: ['Hello, world!'],
          ),
        ),
        equals(
          '[16,239714735,{"exclude_me":false},"com.myapp.mytopic1",["Hello, world!"]]',
        ),
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            argumentsKeywords: {
              'color': 'orange',
              'sizes': [23, 42, 7],
            },
          ),
        ),
        equals(
          '[16,239714735,{},"com.myapp.mytopic1",[],{"color":"orange","sizes":[23,42,7]}]',
        ),
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            options: PublishOptions(excludeMe: false),
            argumentsKeywords: {
              'color': 'orange',
              'sizes': [23, 42, 7],
            },
          ),
        ),
        equals(
          '[16,239714735,{"exclude_me":false},"com.myapp.mytopic1",[],{"color":"orange","sizes":[23,42,7]}]',
        ),
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            arguments: ['Hello, world!'],
            argumentsKeywords: {
              'color': 'orange',
              'sizes': [23, 42, 7],
            },
          ),
        ),
        equals(
          '[16,239714735,{},"com.myapp.mytopic1",["Hello, world!"],{"color":"orange","sizes":[23,42,7]}]',
        ),
      );
      expect(
        serializer.serializeToString(
          Publish(
            239714735,
            'com.myapp.mytopic1',
            options: PublishOptions(excludeMe: false),
            arguments: ['Hello, world!'],
            argumentsKeywords: {
              'color': 'orange',
              'sizes': [23, 42, 7],
            },
          ),
        ),
        equals(
          '[16,239714735,{"exclude_me":false},"com.myapp.mytopic1",["Hello, world!"],{"color":"orange","sizes":[23,42,7]}]',
        ),
      );
    });
    test('Event', () {
      expect(
        serializer.serializeToString(
          Event(5512315355, 4429313566, EventDetails(), arguments: ['johnny']),
        ),
        equals('[36,5512315355,4429313566,{},["johnny"]]'),
      );
      expect(
        serializer.serializeToString(
          Event(
            5512315355,
            4429313566,
            EventDetails(),
            arguments: ['johnny'],
            argumentsKeywords: {'karma': 10},
          ),
        ),
        equals('[36,5512315355,4429313566,{},["johnny"],{"karma":10}]'),
      );
    });
    test('Goodbye', () {
      expect(
        serializer.serializeToString(
          Goodbye(GoodbyeMessage('cya'), Goodbye.reasonGoodbyeAndOut),
        ),
        equals('[6,{"message":"cya"},"wamp.error.goodbye_and_out"]'),
      );
      expect(
        serializer.serializeToString(
          Goodbye(GoodbyeMessage(null), Goodbye.reasonCloseRealm),
        ),
        equals('[6,{"message":""},"wamp.error.close_realm"]'),
      );
      expect(
        serializer.serializeToString(
          Goodbye(null, Goodbye.reasonSystemShutdown),
        ),
        equals('[6,{},"wamp.error.system_shutdown"]'),
      );
    });
    test('Abort', () {
      expect(
        serializer.serializeToString(
          Abort(Error.authorizationFailed, message: 'Some Error'),
        ),
        equals('[3,{"message":"Some Error"},"${Error.authorizationFailed}"]'),
      );
      expect(
        serializer.serializeToString(
          Abort(Error.authorizationFailed, message: ''),
        ),
        equals('[3,{"message":""},"${Error.authorizationFailed}"]'),
      );
      expect(
        serializer.serializeToString(Abort(Error.authorizationFailed)),
        equals('[3,{},"${Error.authorizationFailed}"]'),
      );
    });
    test('serializePPT', () {
      var arguments = <dynamic>[100, 'two', true];
      var argumentsKeywords = {'key1': 100, 'key2': 'two', 'key3': true};
      var pptPayload = PPTPayload(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
      var binData = serializer.serializePPT(pptPayload);
      expect(
        Utf8Decoder().convert(binData),
        equals(
          '{"args": [100,"two",true], "kwargs": {"key1":100,"key2":"two","key3":true}}',
        ),
      );
    });
  });
  group('unserialize', () {
    test('Abort', () {
      var abort =
          serializer.deserializeFromString(
                '[${MessageTypes.codeAbort},{"message":"Received HELLO message after session was established."},"wamp.error.protocol_violation"]',
              )
              as Abort;
      expect(abort, isNotNull);
      expect(abort.id, equals(MessageTypes.codeAbort));
      expect(
        abort.message!.message,
        equals('Received HELLO message after session was established.'),
      );
      expect(abort.reason, equals(Error.protocolViolation));
    });
    test('Challenge', () {
      var challenge =
          serializer.deserializeFromString(
                '[${MessageTypes.codeChallenge},"wampcra",{"challenge":"{\\"authid\\":\\"Richi\\",\\"authrole\\":\\"admin\\",\\"authmethod\\":\\"wampcra\\",\\"authprovider\\":\\"server\\",\\"nonce\\":\\"5636117568768122\\",\\"timestamp\\":\\"2018-03-16T07:29Z\\",\\"session\\":\\"5768501099130836\\"}","salt":"fhhi290fh7§)GQ)G)","keylen":35,"iterations":410}]',
              )
              as Challenge;
      expect(challenge, isNotNull);
      expect(challenge.id, equals(MessageTypes.codeChallenge));
      expect(challenge.authMethod, equals('wampcra'));
      expect(
        challenge.extra.challenge,
        equals(
          '{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"server","nonce":"5636117568768122","timestamp":"2018-03-16T07:29Z","session":"5768501099130836"}',
        ),
      );
      expect(challenge.extra.salt, equals('fhhi290fh7§)GQ)G)'));
      expect(challenge.extra.keyLen, equals(35));
      expect(challenge.extra.iterations, equals(410));
    });
    test('Interrupt', () {
      final interrupt =
          serializer.deserializeFromString(
                '[${MessageTypes.codeInterrupt},31337,{"mode":"killnowait"}]',
              )
              as interrupt_msg.Interrupt;
      expect(interrupt.id, equals(MessageTypes.codeInterrupt));
      expect(interrupt.requestId, equals(31337));
      expect(interrupt.options?.mode, equals(CancelOptions.modeKillNoWait));
    });
    test('Cancel', () {
      final cancel =
          serializer.deserializeFromString(
                '[${MessageTypes.codeCancel},31337,{"mode":"killnowait"}]',
              )
              as Cancel;
      expect(cancel.id, equals(MessageTypes.codeCancel));
      expect(cancel.requestId, equals(31337));
      expect(cancel.options?.mode, equals(CancelOptions.modeKillNoWait));
    });
    test('Welcome', () {
      var welcome =
          serializer.deserializeFromString(
                '[${MessageTypes.codeWelcome},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":false,"pattern_based_subscription":false,"subscription_meta_api":false,"subscriber_blackwhite_listing":false,"session_meta_api":false,"publisher_exclusion":false,"event_history":false,"payload_passthru_mode":false}},"dealer":{"features":{"caller_identification":false,"call_trustlevels":false,"pattern_based_registration":false,"registration_meta_api":false,"shared_registration":false,"session_meta_api":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":false}}}}]',
              )
              as Welcome;
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.codeWelcome));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles!.broker, isNotNull);
      expect(welcome.details.roles!.broker!.features, isNotNull);
      expect(
        welcome.details.roles!.broker!.features!.payloadPassThruMode,
        isFalse,
      );
      expect(welcome.details.roles!.broker!.features!.eventHistory, isFalse);
      expect(
        welcome.details.roles!.broker!.features!.patternBasedSubscription,
        isFalse,
      );
      expect(
        welcome.details.roles!.broker!.features!.publicationTrustLevels,
        isFalse,
      );
      expect(
        welcome.details.roles!.broker!.features!.publisherExclusion,
        isFalse,
      );
      expect(
        welcome.details.roles!.broker!.features!.publisherIdentification,
        isFalse,
      );
      expect(welcome.details.roles!.broker!.features!.sessionMetaApi, isFalse);
      expect(
        welcome.details.roles!.broker!.features!.subscriberBlackWhiteListing,
        isFalse,
      );
      expect(
        welcome.details.roles!.broker!.features!.subscriptionMetaApi,
        isFalse,
      );
      expect(welcome.details.roles!.dealer, isNotNull);
      expect(welcome.details.roles!.dealer!.features, isNotNull);
      expect(
        welcome.details.roles!.dealer!.features!.payloadPassThruMode,
        isFalse,
      );
      expect(welcome.details.roles!.dealer!.features!.sessionMetaApi, isFalse);
      expect(
        welcome.details.roles!.dealer!.features!.progressiveCallResults,
        isFalse,
      );
      expect(
        welcome.details.roles!.dealer!.features!.callerIdentification,
        isFalse,
      );
      expect(welcome.details.roles!.dealer!.features!.callTimeout, isFalse);
      expect(welcome.details.roles!.dealer!.features!.callCanceling, isFalse);
      expect(welcome.details.roles!.dealer!.features!.callTrustLevels, isFalse);
      expect(
        welcome.details.roles!.dealer!.features!.patternBasedRegistration,
        isFalse,
      );
      expect(
        welcome.details.roles!.dealer!.features!.registrationMetaApi,
        isFalse,
      );
      expect(
        welcome.details.roles!.dealer!.features!.sharedRegistration,
        isFalse,
      );

      welcome =
          serializer.deserializeFromString(
                '[${MessageTypes.codeWelcome},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":true,"pattern_based_subscription":true,"subscription_meta_api":true,"subscriber_blackwhite_listing":true,"session_meta_api":true,"publisher_exclusion":true,"event_history":true,"payload_passthru_mode":true}},"dealer":{"features":{"caller_identification":true,"call_trustlevels":true,"pattern_based_registration":true,"registration_meta_api":true,"shared_registration":true,"session_meta_api":true,"call_timeout":true,"call_canceling":true,"progressive_call_results":true,"payload_passthru_mode":true}}}}]',
              )
              as Welcome;
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.codeWelcome));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles!.broker, isNotNull);
      expect(welcome.details.roles!.broker!.features, isNotNull);
      expect(
        welcome.details.roles!.broker!.features!.payloadPassThruMode,
        isTrue,
      );
      expect(welcome.details.roles!.broker!.features!.eventHistory, isTrue);
      expect(
        welcome.details.roles!.broker!.features!.patternBasedSubscription,
        isTrue,
      );
      expect(
        welcome.details.roles!.broker!.features!.publicationTrustLevels,
        isFalse,
      ); // not send
      expect(
        welcome.details.roles!.broker!.features!.publisherExclusion,
        isTrue,
      );
      expect(
        welcome.details.roles!.broker!.features!.publisherIdentification,
        isTrue,
      );
      expect(welcome.details.roles!.broker!.features!.sessionMetaApi, isTrue);
      expect(
        welcome.details.roles!.broker!.features!.subscriberBlackWhiteListing,
        isTrue,
      );
      expect(
        welcome.details.roles!.broker!.features!.subscriptionMetaApi,
        isTrue,
      );
      expect(welcome.details.roles!.dealer, isNotNull);
      expect(welcome.details.roles!.dealer!.features, isNotNull);
      expect(
        welcome.details.roles!.dealer!.features!.payloadPassThruMode,
        isTrue,
      );
      expect(welcome.details.roles!.dealer!.features!.sessionMetaApi, isTrue);
      expect(
        welcome.details.roles!.dealer!.features!.progressiveCallResults,
        isTrue,
      );
      expect(
        welcome.details.roles!.dealer!.features!.callerIdentification,
        isTrue,
      );
      expect(welcome.details.roles!.dealer!.features!.callTimeout, isTrue);
      expect(welcome.details.roles!.dealer!.features!.callCanceling, isTrue);
      expect(welcome.details.roles!.dealer!.features!.callTrustLevels, isTrue);
      expect(
        welcome.details.roles!.dealer!.features!.patternBasedRegistration,
        isTrue,
      );
      expect(
        welcome.details.roles!.dealer!.features!.registrationMetaApi,
        isTrue,
      );
      expect(
        welcome.details.roles!.dealer!.features!.sharedRegistration,
        isTrue,
      );
    });
    test('Registered', () {
      var registered =
          serializer.deserializeFromString('[65, 25349185, 2103333224]')
              as Registered;
      expect(registered, isNotNull);
      expect(registered.id, equals(MessageTypes.codeRegistered));
      expect(registered.registerRequestId, equals(25349185));
      expect(registered.registrationId, equals(2103333224));
    });
    test('Unregistered', () {
      var unregistered =
          serializer.deserializeFromString('[67, 788923562]') as Unregistered;
      expect(unregistered, isNotNull);
      expect(unregistered.id, equals(MessageTypes.codeUnregistered));
      expect(unregistered.unregisterRequestId, equals(788923562));
    });
    test('Invocation', () {
      var invocation =
          serializer.deserializeFromString('[68, 6131533, 9823526, {}]')
              as Invocation;
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.codeInvocation));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823526));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receiveProgress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments, isNull);
      expect(invocation.argumentsKeywords, isNull);

      invocation =
          serializer.deserializeFromString(
                '[68, 6131533, 9823527, {}, ["Hello, world!"]]',
              )
              as Invocation;
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.codeInvocation));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823527));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receiveProgress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments![0], equals('Hello, world!'));
      expect(invocation.argumentsKeywords, isNull);

      invocation =
          serializer.deserializeFromString(
                '[68, 6131533, 9823529, {}, ["johnny"], {"firstname": "John","surname": "Doe"}]',
              )
              as Invocation;
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.codeInvocation));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823529));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receiveProgress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments![0], equals('johnny'));
      expect(invocation.argumentsKeywords!['firstname'], equals('John'));
      expect(invocation.argumentsKeywords!['surname'], equals('Doe'));

      invocation =
          serializer.deserializeFromString(
                '[68, 6131533, 9823529, {"receive_progress": true, "caller": 13123, "procedure":"my.procedure.com"}, ["johnny"], {"firstname": "John","surname": "Doe"}]',
              )
              as Invocation;
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.codeInvocation));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823529));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receiveProgress, isTrue);
      expect(invocation.details.caller, equals(13123));
      expect(invocation.details.procedure, equals('my.procedure.com'));
      expect(invocation.arguments![0], equals('johnny'));
      expect(invocation.argumentsKeywords!['firstname'], equals('John'));
      expect(invocation.argumentsKeywords!['surname'], equals('Doe'));

      invocation =
          serializer.deserializeFromString(
                '[68, 6131533, 9823529, {"_extra": 5}, []]',
              )
              as Invocation;
      expect(invocation.details.custom['_extra'], equals(5));
    });
    test('Result', () {
      var result =
          serializer.deserializeFromString('[50, 7814135, {}]') as Result;
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.codeResult));
      expect(result.callRequestId, equals(7814135));
      expect(result.details, isNotNull);
      expect(result.details.progress, false);
      expect(result.arguments, isNull);
      expect(result.argumentsKeywords, isNull);

      result =
          serializer.deserializeFromString('[50, 7814135, {}, [30]]') as Result;
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.codeResult));
      expect(result.callRequestId, equals(7814135));
      expect(result.details, isNotNull);
      expect(result.details.progress, false);
      expect(result.arguments![0], equals(30));
      expect(result.argumentsKeywords, isNull);

      result =
          serializer.deserializeFromString(
                '[50, 6131533, {}, ["johnny"], {"userid": 123, "karma": 10}]',
              )
              as Result;
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.codeResult));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, false);
      expect(result.arguments![0], equals('johnny'));
      expect(result.argumentsKeywords!['userid'], equals(123));
      expect(result.argumentsKeywords!['karma'], equals(10));

      result =
          serializer.deserializeFromString(
                '[50, 6131533, {"progress": true}, ["johnny"], {"firstname": "John","surname": "Doe"}]',
              )
              as Result;
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.codeResult));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, isTrue);
      expect(result.arguments![0], equals('johnny'));
      expect(result.argumentsKeywords!['firstname'], equals('John'));
      expect(result.argumentsKeywords!['surname'], equals('Doe'));

      result =
          serializer.deserializeFromString('[50, 6131533, {"_extra": "value"}]')
              as Result;
      expect(result.details.custom['_extra'], equals('value'));
    });
    // PUB / SUB
    test('Subscribed', () {
      var subscribed =
          serializer.deserializeFromString('[33, 713845233, 5512315355]')
              as Subscribed;
      expect(subscribed, isNotNull);
      expect(subscribed.id, equals(MessageTypes.codeSubscribed));
      expect(subscribed.subscribeRequestId, equals(713845233));
      expect(subscribed.subscriptionId, equals(5512315355));
    });
    test('Unsubscribed', () {
      var unsubscribed =
          serializer.deserializeFromString('[35, 85346237]') as Unsubscribed;
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.codeUnsubscribed));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details, isNull);

      unsubscribed =
          serializer.deserializeFromString(
                '[35, 85346237, {"subscription": 123322, "reason": "wamp.authentication.lost"}]',
              )
              as Unsubscribed;
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.codeUnsubscribed));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details!.reason, equals('wamp.authentication.lost'));
      expect(unsubscribed.details!.subscription, equals(123322));
    });
    test('Published', () {
      var published =
          serializer.deserializeFromString('[17, 239714735, 4429313566]')
              as Published;
      expect(published, isNotNull);
      expect(published.id, equals(MessageTypes.codePublished));
      expect(published.publishRequestId, equals(239714735));
      expect(published.publicationId, equals(4429313566));
    });
    test('serialize Published', () {
      final serialized = serializer.serializeToString(
        Published(239714735, 4429313566),
      );
      expect(serialized, equals('[17,239714735,4429313566]'));
    });
    test('Event', () {
      var event =
          serializer.deserializeFromString('[36, 5512315355, 4429313566, {}]')
              as Event;
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.codeEvent));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments, isNull);
      expect(event.argumentsKeywords, isNull);

      event =
          serializer.deserializeFromString(
                '[36, 5512315355, 4429313566, {}, [30]]',
              )
              as Event;
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.codeEvent));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments![0], equals(30));
      expect(event.argumentsKeywords, isNull);

      event =
          serializer.deserializeFromString(
                '[36, 5512315355, 4429313566, {}, ["johnny"], {"userid": 123, "karma": 10}]',
              )
              as Event;
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.codeEvent));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments![0], equals('johnny'));
      expect(event.argumentsKeywords!['userid'], equals(123));
      expect(event.argumentsKeywords!['karma'], equals(10));

      event =
          serializer.deserializeFromString(
                '[36, 5512315355, 4429313566, {"publisher": 1231412}, ["johnny"], {"firstname": "John","surname": "Doe"}]',
              )
              as Event;
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.codeEvent));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, equals(1231412));
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments![0], equals('johnny'));
      expect(event.argumentsKeywords!['firstname'], equals('John'));
      expect(event.argumentsKeywords!['surname'], equals('Doe'));

      event =
          serializer.deserializeFromString(
                '[36, 5512315355, 4429313566, {"publisher": 1231412, "topic":"de.de.com", "trustlevel":1}, ["johnny"], {"firstname": "John","surname": "Doe"}]',
              )
              as Event;
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.codeEvent));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, equals(1231412));
      expect(event.details.topic, equals('de.de.com'));
      expect(event.details.trustlevel, equals(1));
      expect(event.arguments![0], equals('johnny'));
      expect(event.argumentsKeywords!['firstname'], equals('John'));
      expect(event.argumentsKeywords!['surname'], equals('Doe'));

      event =
          serializer.deserializeFromString(
                '[36, 5512315355, 4429313566, {"publisher":1,"_debounce":true}]',
              )
              as Event;
      expect(event.details.custom['_debounce'], isTrue);
    });
    test('Invocation retains custom detail fields', () {
      final invocation =
          serializer.deserializeFromString(
                '[68,6131533,9823526,{"caller":1,"procedure":"com.myapp.foo","trace_id":"abc"},["hi"]]',
              )
              as Invocation;

      expect(invocation.details.caller, equals(1));
      expect(invocation.details.procedure, equals('com.myapp.foo'));
      expect(invocation.details.custom, containsPair('trace_id', 'abc'));
      expect(invocation.arguments, equals(['hi']));
    });
    test('Invocation serializes custom detail fields', () {
      final invocation = Invocation(
        6131533,
        9823526,
        InvocationDetails(1, 'com.myapp.foo', true, null, null, null, null, {
          'trace_id': 'abc',
        }),
        arguments: const ['hi'],
      );

      final roundTrip =
          serializer.deserializeFromString(
                serializer.serializeToString(invocation),
              )
              as Invocation;

      expect(roundTrip.details.caller, equals(1));
      expect(roundTrip.details.procedure, equals('com.myapp.foo'));
      expect(roundTrip.details.receiveProgress, isTrue);
      expect(roundTrip.details.custom, containsPair('trace_id', 'abc'));
      expect(roundTrip.arguments, equals(['hi']));
    });
    test('Invocation retains binary custom detail fields', () {
      final invocation =
          serializer.deserializeFromString(
                '[68,6131533,9823526,{"caller":1,"trace_id":"abc","blob":"\\\\u0000AQID","nested":{"payload":"\\\\u0000BAUG"}},["hi"]]',
              )
              as Invocation;

      expect(invocation.details.custom['trace_id'], equals('abc'));
      expect(
        invocation.details.custom['blob'],
        orderedEquals(Uint8List.fromList(const [1, 2, 3])),
      );
      expect(
        (invocation.details.custom['nested'] as Map)['payload'],
        orderedEquals(Uint8List.fromList(const [4, 5, 6])),
      );
    });
    test('Result retains custom detail fields', () {
      final result =
          serializer.deserializeFromString(
                '[50,6131533,{"progress":false,"trace_id":"abc"},["hi"]]',
              )
              as Result;

      expect(result.details.progress, isFalse);
      expect(result.details.custom, containsPair('trace_id', 'abc'));
      expect(result.arguments, equals(['hi']));
    });
    test('Result round-trips binary custom detail fields', () {
      final result = Result(
        6131533,
        ResultDetails(
          custom: {
            'trace_id': 'abc',
            'blob': Uint8List.fromList(const [7, 8, 9]),
            'nested': {
              'payload': Uint8List.fromList(const [10, 11]),
            },
          },
        ),
        arguments: const ['hi'],
      );

      final roundTrip =
          serializer.deserializeFromString(serializer.serializeToString(result))
              as Result;

      expect(roundTrip.details.custom['trace_id'], equals('abc'));
      expect(
        roundTrip.details.custom['blob'],
        orderedEquals(Uint8List.fromList(const [7, 8, 9])),
      );
      expect(
        (roundTrip.details.custom['nested'] as Map)['payload'],
        orderedEquals(Uint8List.fromList(const [10, 11])),
      );
    });
    test('Event retains custom detail fields', () {
      final event =
          serializer.deserializeFromString(
                '[36,123,456,{"publisher":1,"trace_id":"abc"},["hi"]]',
              )
              as Event;

      expect(event.details.publisher, equals(1));
      expect(event.details.custom, containsPair('trace_id', 'abc'));
      expect(event.arguments, equals(['hi']));
    });
    test('Event round-trips binary custom detail fields', () {
      final event = Event(
        123,
        456,
        EventDetails(
          publisher: 1,
          custom: {
            'trace_id': 'abc',
            'blob': Uint8List.fromList(const [12, 13, 14]),
            'nested': {
              'payload': Uint8List.fromList(const [15, 16]),
            },
          },
        ),
        arguments: const ['hi'],
      );

      final roundTrip =
          serializer.deserializeFromString(serializer.serializeToString(event))
              as Event;

      expect(roundTrip.details.publisher, equals(1));
      expect(roundTrip.details.custom['trace_id'], equals('abc'));
      expect(
        roundTrip.details.custom['blob'],
        orderedEquals(Uint8List.fromList(const [12, 13, 14])),
      );
      expect(
        (roundTrip.details.custom['nested'] as Map)['payload'],
        orderedEquals(Uint8List.fromList(const [15, 16])),
      );
    });
    test('deserializePPT', () {
      var binData = Utf8Encoder().convert(
        '{"args": [100, "two", true], "kwargs": {"key1": 100, "key2": "two", "key3": true}}',
      );
      var pptPayload = serializer.deserializePPT(binData);

      expect(pptPayload, isNotNull);
      expect(pptPayload?.arguments, isNotNull);
      expect(pptPayload?.argumentsKeywords, isNotNull);
      expect(pptPayload!.arguments, isA<List>());
      expect(pptPayload.arguments!.length, equals(3));
      expect(pptPayload.arguments![0], equals(100));
      expect(pptPayload.arguments![1], equals('two'));
      expect(pptPayload.arguments![2], equals(true));
      expect(pptPayload.argumentsKeywords, isA<Map>());
      expect(pptPayload.argumentsKeywords!['key1'], equals(100));
      expect(pptPayload.argumentsKeywords!['key2'], equals('two'));
      expect(pptPayload.argumentsKeywords!['key3'], equals(true));
    });
  });
  group('string conversion', () {
    test('convert UTF-8', () {
      var invocation = Invocation(
        10,
        10,
        InvocationDetails(1, '', false),
        arguments: [
          '𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!',
        ],
      );
      var serializedInvocation =
          serializer.deserialize(
                utf8.encoder.convert(serializer.serialize(invocation)),
              )
              as Invocation;
      expect(
        serializedInvocation.arguments![0],
        equals('𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'),
      );
    });
    test('convert json binary string', () {
      var result =
          serializer.deserializeFromString(
                '[50, 1, {}, [{"binary":"\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="}],{"binary":{"content":["\\\\u0000EOP/kFMHXFJvX8BtT+N82w==","EOP/kFMHXFJvX8BtT+N82w=="]}}]',
              )
              as Result;
      expect(result.arguments![0]['binary'], isA<Uint8List>());
      expect(result.arguments![0]['binary'].length, equals(16));
      expect(
        result.argumentsKeywords!['binary']['content'][0],
        isA<Uint8List>(),
      );
      expect(
        result.argumentsKeywords!['binary']['content'][0].length,
        equals(16),
      );
      expect(result.argumentsKeywords!['binary']['content'][1], isA<String>());
      result =
          serializer.deserializeFromString(
                '[50, 1, {}, "\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="]',
              )
              as Result;
      expect(result.transparentBinaryPayload, isA<Uint8List>());
      expect(result.transparentBinaryPayload!.length, equals(16));

      var event = Event(
        1,
        2,
        EventDetails(),
        arguments: [
          {
            'binary': {
              'content': [result.transparentBinaryPayload, 'some'],
            },
          },
        ],
        argumentsKeywords: {'binary': result.transparentBinaryPayload},
      );
      expect(
        serializer.serializeToString(event),
        equals(
          '[36,1,2,{},[{"binary":{"content":["\\\\u0000EOP/kFMHXFJvX8BtT+N82w==","some"]}}],{"binary":"\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="}]',
        ),
      );
      event.transparentBinaryPayload = result.transparentBinaryPayload;
      expect(
        serializer.serializeToString(event),
        equals('[36,1,2,{},"\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="]'),
      );
    });
  });
}

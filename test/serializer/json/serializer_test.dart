import 'dart:collection';
import 'dart:convert';

import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/authenticate.dart';
import 'package:connectanum/src/message/call.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/event.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/goodbye.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/publish.dart';
import 'package:connectanum/src/message/published.dart';
import 'package:connectanum/src/message/register.dart';
import 'package:connectanum/src/message/registered.dart';
import 'package:connectanum/src/message/result.dart';
import 'package:connectanum/src/message/subscribe.dart';
import 'package:connectanum/src/message/subscribed.dart';
import 'package:connectanum/src/message/unregister.dart';
import 'package:connectanum/src/message/unregistered.dart';
import 'package:connectanum/src/message/unsubscribe.dart';
import 'package:connectanum/src/message/unsubscribed.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/message/invocation.dart';
import 'package:connectanum/src/message/yield.dart';
import 'package:connectanum/src/message/ppt_payload.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:pinenacl/api.dart';
import 'package:test/test.dart';

void main() {
  var serializer = Serializer();
  group('serialize', () {
    test('Hello', () {
      expect(
          serializer.serializeToString(Hello('my.realm', Details.forHello())),
          equals(
              '[1,"my.realm",{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_passthru_mode":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_passthru_mode":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_passthru_mode":true}}}}]'));
      expect(
          serializer.serializeToString(Hello(null, Details.forHello())),
          equals(
              '[1,null,{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_passthru_mode":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_passthru_mode":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_passthru_mode":true}}}}]'));
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
              '[1,"my.realm",{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_passthru_mode":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_passthru_mode":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_passthru_mode":true}}},"authid":"Richard","authmethods":["WAMP-CRA"],"authextra":'));
      expect(message, contains('"channel_binding":null'));
      expect(message, contains('"nonce":"egVDf3DMJh0="'));
    });
    test('Authenticate', () {
      expect(serializer.serializeToString(Authenticate()),
          equals('[${MessageTypes.codeAuthenticate},"",{}]'));
      expect(
          serializer.serializeToString(Authenticate.signature('someSignature')),
          equals('[${MessageTypes.codeAuthenticate},"${"someSignature"}",{}]'));
      var authenticate = Authenticate.signature('someSignature');
      authenticate.extra = HashMap<String, Object?>();
      authenticate.extra!['nonce'] = 'abc';
      expect(
          serializer.serializeToString(authenticate),
          equals(
              '[${MessageTypes.codeAuthenticate},"${"someSignature"}",{"nonce":"abc"}]'));
    });
    test('Register', () {
      expect(
          serializer
              .serializeToString(Register(25349185, 'com.myapp.myprocedure1')),
          equals(
              '[${MessageTypes.codeRegister},25349185,{},"com.myapp.myprocedure1"]'));
      expect(
          serializer.serializeToString(Register(
              25349185, 'com.myapp.myprocedure1',
              options: RegisterOptions(
                  discloseCaller: true,
                  invoke: RegisterOptions.invocationPolicyRandom,
                  match: RegisterOptions.matchPrefix))),
          equals(
              '[${MessageTypes.codeRegister},25349185,{"match":"prefix","disclose_caller":true,"invoke":"random"},"com.myapp.myprocedure1"]'));
      expect(
          serializer.serializeToString(Register(
              25349185, 'com.myapp.myprocedure2',
              options: RegisterOptions(discloseCaller: false))),
          equals(
              '[${MessageTypes.codeRegister},25349185,{"disclose_caller":false},"com.myapp.myprocedure2"]'));
    });
    test('Unregister', () {
      expect(serializer.serializeToString(Unregister(25349185, 127981236)),
          equals('[${MessageTypes.codeUnregister},25349185,127981236]'));
    });
    test('Call', () {
      expect(serializer.serializeToString(Call(7814135, 'com.myapp.ping')),
          equals('[${MessageTypes.codeCall},7814135,{},"com.myapp.ping"]'));
      expect(
          serializer.serializeToString(
              Call(7814135, 'com.myapp.ping', options: CallOptions())),
          equals('[${MessageTypes.codeCall},7814135,{},"com.myapp.ping"]'));
      expect(
          serializer.serializeToString(Call(7814135, 'com.myapp.ping',
              options: CallOptions(
                  receiveProgress: true, discloseMe: true, timeout: 12))),
          equals(
              '[${MessageTypes.codeCall},7814135,{"receive_progress":true,"disclose_me":true,"timeout":12},"com.myapp.ping"]'));
      expect(
          serializer.serializeToString(
              Call(7814135, 'com.myapp.ping', arguments: ['hi', 2])),
          equals(
              '[${MessageTypes.codeCall},7814135,{},"com.myapp.ping",["hi",2]]'));
      expect(
          serializer.serializeToString(
              Call(7814135, 'com.myapp.ping', argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.codeCall},7814135,{},"com.myapp.ping",[],{"hi":12}]'));
      expect(
          serializer.serializeToString(Call(7814135, 'com.myapp.ping',
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.codeCall},7814135,{},"com.myapp.ping",["hi",2],{"hi":12}]'));
    });
    test('Yield', () {
      expect(serializer.serializeToString(Yield(6131533)),
          equals('[${MessageTypes.codeYield},6131533,{}]'));
      expect(
          serializer.serializeToString(
              Yield(6131533, options: YieldOptions(progress: false))),
          equals('[${MessageTypes.codeYield},6131533,{"progress":false}]'));
      expect(
          serializer.serializeToString(
              Yield(6131533, options: YieldOptions(progress: true))),
          equals('[${MessageTypes.codeYield},6131533,{"progress":true}]'));
      expect(serializer.serializeToString(Yield(6131533, arguments: ['hi', 2])),
          equals('[${MessageTypes.codeYield},6131533,{},["hi",2]]'));
      expect(
          serializer
              .serializeToString(Yield(6131533, argumentsKeywords: {'hi': 12})),
          equals('[${MessageTypes.codeYield},6131533,{},[],{"hi":12}]'));
      expect(
          serializer.serializeToString(Yield(6131533,
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals('[${MessageTypes.codeYield},6131533,{},["hi",2],{"hi":12}]'));
    });
    test('Error', () {
      expect(
          serializer.serializeToString(
              Error(MessageTypes.codeHello, 123422, HashMap(), 'wamp.unknown')),
          equals(
              '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{},"wamp.unknown"]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.codeHello, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown')),
          equals(
              '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown"]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.codeHello, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              arguments: ['hi', 2])),
          equals(
              '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown",["hi",2]]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.codeHello, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown",[],{"hi":12}]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.codeHello, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.codeError},${MessageTypes.codeHello},123422,{"cause":"some"},"wamp.unknown",["hi",2],{"hi":12}]'));
    });
    test('Subscribe', () {
      expect(
          serializer
              .serializeToString(Subscribe(713845233, 'com.myapp.mytopic1')),
          equals('[32,713845233,{},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions())),
          equals('[32,713845233,{},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(match: SubscribeOptions.matchPlain))),
          equals('[32,713845233,{},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(match: SubscribeOptions.matchPrefix))),
          equals('[32,713845233,{"match":"prefix"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options:
                  SubscribeOptions(match: SubscribeOptions.matchWildcard))),
          equals('[32,713845233,{"match":"wildcard"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(metaTopic: 'topic'))),
          equals('[32,713845233,{"meta_topic":"topic"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(
                  getRetained: true,
                  match: SubscribeOptions.matchWildcard,
                  metaTopic: 'topic'))),
          equals(
              '[32,713845233,{"get_retained":true,"match":"wildcard","meta_topic":"topic"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(match: SubscribeOptions.matchWildcard)
                ..addCustomValue('where', (_) => '12')
                ..addCustomValue('some', (_) => '{"key":"value"}'))),
          equals(
              '[32,713845233,{"match":"wildcard","some":{"key":"value"},"where":12},"com.myapp.mytopic1"]'));
    });
    test('Unsubscribe', () {
      expect(serializer.serializeToString(Unsubscribe(85346237, 5512315355)),
          equals('[34,85346237,5512315355]'));
    });
    test('Publish', () {
      expect(
          serializer
              .serializeToString(Publish(239714735, 'com.myapp.mytopic1')),
          equals('[16,239714735,{},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions())),
          equals('[16,239714735,{},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
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
                  excludeAuthRole: ['admin']))),
          equals(
              '[16,239714735,{"retain":true,"disclose_me":true,"acknowledge":true,"exclude_me":true,"exclude":[2],"exclude_authid":["bbb"],"exclude_authrole":["admin"],"eligible":[1],"eligible_authid":["aaa"],"eligible_authrole":["role"]},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              arguments: ['Hello, world!'])),
          equals('[16,239714735,{},"com.myapp.mytopic1",["Hello, world!"]]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(excludeMe: false),
              arguments: ['Hello, world!'])),
          equals(
              '[16,239714735,{"exclude_me":false},"com.myapp.mytopic1",["Hello, world!"]]'));
      expect(
          serializer.serializeToString(
              Publish(239714735, 'com.myapp.mytopic1', argumentsKeywords: {
            'color': 'orange',
            'sizes': [23, 42, 7]
          })),
          equals(
              '[16,239714735,{},"com.myapp.mytopic1",[],{"color":"orange","sizes":[23,42,7]}]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(excludeMe: false),
              argumentsKeywords: {
                'color': 'orange',
                'sizes': [23, 42, 7]
              })),
          equals(
              '[16,239714735,{"exclude_me":false},"com.myapp.mytopic1",[],{"color":"orange","sizes":[23,42,7]}]'));
      expect(
          serializer.serializeToString(
              Publish(239714735, 'com.myapp.mytopic1', arguments: [
            'Hello, world!'
          ], argumentsKeywords: {
            'color': 'orange',
            'sizes': [23, 42, 7]
          })),
          equals(
              '[16,239714735,{},"com.myapp.mytopic1",["Hello, world!"],{"color":"orange","sizes":[23,42,7]}]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(excludeMe: false),
              arguments: [
                'Hello, world!'
              ],
              argumentsKeywords: {
                'color': 'orange',
                'sizes': [23, 42, 7]
              })),
          equals(
              '[16,239714735,{"exclude_me":false},"com.myapp.mytopic1",["Hello, world!"],{"color":"orange","sizes":[23,42,7]}]'));
    });
    test('Goodbye', () {
      expect(
          serializer.serializeToString(
              Goodbye(GoodbyeMessage('cya'), Goodbye.reasonGoodbyeAndOut)),
          equals('[6,{"message":"cya"},"wamp.error.goodbye_and_out"]'));
      expect(
          serializer.serializeToString(
              Goodbye(GoodbyeMessage(null), Goodbye.reasonCloseRealm)),
          equals('[6,{"message":""},"wamp.error.close_realm"]'));
      expect(
          serializer
              .serializeToString(Goodbye(null, Goodbye.reasonSystemShutdown)),
          equals('[6,{},"wamp.error.system_shutdown"]'));
    });
    test('Abort', () {
      expect(
          serializer.serializeToString(
              Abort(Error.authorizationFailed, message: 'Some Error')),
          equals(
              '[3,{"message":"Some Error"},"${Error.authorizationFailed}"]'));
      expect(
          serializer
              .serializeToString(Abort(Error.authorizationFailed, message: '')),
          equals('[3,{"message":""},"${Error.authorizationFailed}"]'));
      expect(serializer.serializeToString(Abort(Error.authorizationFailed)),
          equals('[3,{},"${Error.authorizationFailed}"]'));
    });
    test('serializePPT', () {
      var arguments = <dynamic>[100, 'two', true];
      var argumentsKeywords = {'key1': 100, 'key2': 'two', 'key3': true};
      var pptPayload = PPTPayload(
          arguments: arguments, argumentsKeywords: argumentsKeywords);
      var binData = serializer.serializePPT(pptPayload);
      expect(
          Utf8Decoder().convert(binData),
          equals(
              '{"args": [100,"two",true], "kwargs": {"key1":100,"key2":"two","key3":true}}'));
    });
  });
  group('unserialize', () {
    test('Abort', () {
      var abort = serializer.deserializeFromString(
              '[${MessageTypes.codeAbort},{"message":"Received HELLO message after session was established."},"wamp.error.protocol_violation"]')
          as Abort;
      expect(abort, isNotNull);
      expect(abort.id, equals(MessageTypes.codeAbort));
      expect(abort.message!.message,
          equals('Received HELLO message after session was established.'));
      expect(abort.reason, equals(Error.protocolViolation));
    });
    test('Challenge', () {
      var challenge = serializer.deserializeFromString(
              '[${MessageTypes.codeChallenge},"wampcra",{"challenge":"{\\"authid\\":\\"Richi\\",\\"authrole\\":\\"admin\\",\\"authmethod\\":\\"wampcra\\",\\"authprovider\\":\\"server\\",\\"nonce\\":\\"5636117568768122\\",\\"timestamp\\":\\"2018-03-16T07:29Z\\",\\"session\\":\\"5768501099130836\\"}","salt":"fhhi290fh7§)GQ)G)","keylen":35,"iterations":410}]')
          as Challenge;
      expect(challenge, isNotNull);
      expect(challenge.id, equals(MessageTypes.codeChallenge));
      expect(challenge.authMethod, equals('wampcra'));
      expect(
          challenge.extra.challenge,
          equals(
              '{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"server","nonce":"5636117568768122","timestamp":"2018-03-16T07:29Z","session":"5768501099130836"}'));
      expect(challenge.extra.salt, equals('fhhi290fh7§)GQ)G)'));
      expect(challenge.extra.keyLen, equals(35));
      expect(challenge.extra.iterations, equals(410));
    });
    test('Welcome', () {
      var welcome = serializer.deserializeFromString(
              '[${MessageTypes.codeWelcome},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":false,"pattern_based_subscription":false,"subscription_meta_api":false,"subscriber_blackwhite_listing":false,"session_meta_api":false,"publisher_exclusion":false,"event_history":false,"payload_passthru_mode":false}},"dealer":{"features":{"caller_identification":false,"call_trustlevels":false,"pattern_based_registration":false,"registration_meta_api":false,"shared_registration":false,"session_meta_api":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_passthru_mode":false}}}}]')
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
      expect(welcome.details.roles!.broker!.features!.payloadPassThruMode,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.eventHistory, isFalse);
      expect(welcome.details.roles!.broker!.features!.patternBasedSubscription,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.publicationTrustLevels,
          isFalse);
      expect(
          welcome.details.roles!.broker!.features!.publisherExclusion, isFalse);
      expect(welcome.details.roles!.broker!.features!.publisherIdentification,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.sessionMetaApi, isFalse);
      expect(
          welcome.details.roles!.broker!.features!.subscriberBlackWhiteListing,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.subscriptionMetaApi,
          isFalse);
      expect(welcome.details.roles!.dealer, isNotNull);
      expect(welcome.details.roles!.dealer!.features, isNotNull);
      expect(welcome.details.roles!.dealer!.features!.payloadPassThruMode,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.sessionMetaApi, isFalse);
      expect(welcome.details.roles!.dealer!.features!.progressiveCallResults,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.callerIdentification,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.callTimeout, isFalse);
      expect(welcome.details.roles!.dealer!.features!.callCanceling, isFalse);
      expect(welcome.details.roles!.dealer!.features!.callTrustLevels, isFalse);
      expect(welcome.details.roles!.dealer!.features!.patternBasedRegistration,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.registrationMetaApi,
          isFalse);
      expect(
          welcome.details.roles!.dealer!.features!.sharedRegistration, isFalse);

      welcome = serializer.deserializeFromString(
              '[${MessageTypes.codeWelcome},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":true,"pattern_based_subscription":true,"subscription_meta_api":true,"subscriber_blackwhite_listing":true,"session_meta_api":true,"publisher_exclusion":true,"event_history":true,"payload_passthru_mode":true}},"dealer":{"features":{"caller_identification":true,"call_trustlevels":true,"pattern_based_registration":true,"registration_meta_api":true,"shared_registration":true,"session_meta_api":true,"call_timeout":true,"call_canceling":true,"progressive_call_results":true,"payload_passthru_mode":true}}}}]')
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
          welcome.details.roles!.broker!.features!.payloadPassThruMode, isTrue);
      expect(welcome.details.roles!.broker!.features!.eventHistory, isTrue);
      expect(welcome.details.roles!.broker!.features!.patternBasedSubscription,
          isTrue);
      expect(welcome.details.roles!.broker!.features!.publicationTrustLevels,
          isFalse); // not send
      expect(
          welcome.details.roles!.broker!.features!.publisherExclusion, isTrue);
      expect(welcome.details.roles!.broker!.features!.publisherIdentification,
          isTrue);
      expect(welcome.details.roles!.broker!.features!.sessionMetaApi, isTrue);
      expect(
          welcome.details.roles!.broker!.features!.subscriberBlackWhiteListing,
          isTrue);
      expect(
          welcome.details.roles!.broker!.features!.subscriptionMetaApi, isTrue);
      expect(welcome.details.roles!.dealer, isNotNull);
      expect(welcome.details.roles!.dealer!.features, isNotNull);
      expect(
          welcome.details.roles!.dealer!.features!.payloadPassThruMode, isTrue);
      expect(welcome.details.roles!.dealer!.features!.sessionMetaApi, isTrue);
      expect(welcome.details.roles!.dealer!.features!.progressiveCallResults,
          isTrue);
      expect(welcome.details.roles!.dealer!.features!.callerIdentification,
          isTrue);
      expect(welcome.details.roles!.dealer!.features!.callTimeout, isTrue);
      expect(welcome.details.roles!.dealer!.features!.callCanceling, isTrue);
      expect(welcome.details.roles!.dealer!.features!.callTrustLevels, isTrue);
      expect(welcome.details.roles!.dealer!.features!.patternBasedRegistration,
          isTrue);
      expect(
          welcome.details.roles!.dealer!.features!.registrationMetaApi, isTrue);
      expect(
          welcome.details.roles!.dealer!.features!.sharedRegistration, isTrue);
    });
    test('Registered', () {
      var registered = serializer
          .deserializeFromString('[65, 25349185, 2103333224]') as Registered;
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
      var invocation = serializer
          .deserializeFromString('[68, 6131533, 9823526, {}]') as Invocation;
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

      invocation = serializer.deserializeFromString(
          '[68, 6131533, 9823527, {}, ["Hello, world!"]]') as Invocation;
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

      invocation = serializer.deserializeFromString(
              '[68, 6131533, 9823529, {}, ["johnny"], {"firstname": "John","surname": "Doe"}]')
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

      invocation = serializer.deserializeFromString(
              '[68, 6131533, 9823529, {"receive_progress": true, "caller": 13123, "procedure":"my.procedure.com"}, ["johnny"], {"firstname": "John","surname": "Doe"}]')
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

      result = serializer.deserializeFromString(
              '[50, 6131533, {}, ["johnny"], {"userid": 123, "karma": 10}]')
          as Result;
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.codeResult));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, false);
      expect(result.arguments![0], equals('johnny'));
      expect(result.argumentsKeywords!['userid'], equals(123));
      expect(result.argumentsKeywords!['karma'], equals(10));

      result = serializer.deserializeFromString(
              '[50, 6131533, {"progress": true}, ["johnny"], {"firstname": "John","surname": "Doe"}]')
          as Result;
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.codeResult));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, isTrue);
      expect(result.arguments![0], equals('johnny'));
      expect(result.argumentsKeywords!['firstname'], equals('John'));
      expect(result.argumentsKeywords!['surname'], equals('Doe'));
    });
    // PUB / SUB
    test('Subscribed', () {
      var subscribed = serializer
          .deserializeFromString('[33, 713845233, 5512315355]') as Subscribed;
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

      unsubscribed = serializer.deserializeFromString(
              '[35, 85346237, {"subscription": 123322, "reason": "wamp.authentication.lost"}]')
          as Unsubscribed;
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.codeUnsubscribed));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details!.reason, equals('wamp.authentication.lost'));
      expect(unsubscribed.details!.subscription, equals(123322));
    });
    test('Published', () {
      var published = serializer
          .deserializeFromString('[17, 239714735, 4429313566]') as Published;
      expect(published, isNotNull);
      expect(published.id, equals(MessageTypes.codePublished));
      expect(published.publishRequestId, equals(239714735));
      expect(published.publicationId, equals(4429313566));
    });
    test('Event', () {
      var event = serializer
          .deserializeFromString('[36, 5512315355, 4429313566, {}]') as Event;
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

      event = serializer.deserializeFromString(
          '[36, 5512315355, 4429313566, {}, [30]]') as Event;
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

      event = serializer.deserializeFromString(
              '[36, 5512315355, 4429313566, {}, ["johnny"], {"userid": 123, "karma": 10}]')
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

      event = serializer.deserializeFromString(
              '[36, 5512315355, 4429313566, {"publisher": 1231412}, ["johnny"], {"firstname": "John","surname": "Doe"}]')
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

      event = serializer.deserializeFromString(
              '[36, 5512315355, 4429313566, {"publisher": 1231412, "topic":"de.de.com", "trustlevel":1}, ["johnny"], {"firstname": "John","surname": "Doe"}]')
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
    });
    test('deserializePPT', () {
      var binData = Utf8Encoder().convert(
          '{"args": [100, "two", true], "kwargs": {"key1": 100, "key2": "two", "key3": true}}');
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
      var invocation = Invocation(10, 10, InvocationDetails(1, '', false),
          arguments: [
            '𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'
          ]);
      var serializedInvocation = serializer.deserialize(
          utf8.encoder.convert(serializer.serialize(invocation))) as Invocation;
      expect(serializedInvocation.arguments![0],
          equals('𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'));
    });
    test('convert json binary string', () {
      var result = serializer.deserializeFromString(
              '[50, 1, {}, [{"binary":"\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="}],{"binary":{"content":["\\\\u0000EOP/kFMHXFJvX8BtT+N82w==","EOP/kFMHXFJvX8BtT+N82w=="]}}]')
          as Result;
      expect(result.arguments![0]['binary'], isA<Uint8List>());
      expect(result.arguments![0]['binary'].length, equals(16));
      expect(
          result.argumentsKeywords!['binary']['content'][0], isA<Uint8List>());
      expect(
          result.argumentsKeywords!['binary']['content'][0].length, equals(16));
      expect(result.argumentsKeywords!['binary']['content'][1], isA<String>());
      result = serializer.deserializeFromString(
          '[50, 1, {}, "\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="]') as Result;
      expect(result.transparentBinaryPayload, isA<Uint8List>());
      expect(result.transparentBinaryPayload!.length, equals(16));

      var event = Event(1, 2, EventDetails(), arguments: [
        {
          'binary': {
            'content': [result.transparentBinaryPayload, 'some']
          }
        }
      ], argumentsKeywords: {
        'binary': result.transparentBinaryPayload
      });
      expect(
          serializer.serializeToString(event),
          equals(
              '[36,1,2,[{"binary":{"content":["\\\\u0000EOP/kFMHXFJvX8BtT+N82w==","some"]}}],{"binary":"\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="}]'));
      event.transparentBinaryPayload = result.transparentBinaryPayload;
      expect(serializer.serializeToString(event),
          equals('[36,1,2,"\\\\u0000EOP/kFMHXFJvX8BtT+N82w=="]'));
    });
  });
}

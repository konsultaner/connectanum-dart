import 'dart:collection';

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
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:test/test.dart';

void main() {
  var serializer = Serializer();
  group('serialize', () {
    test('Hello', () {
      expect(
          serializer.serializeToString(Hello('my.realm', Details.forHello())),
          equals(
              '[1,"my.realm",{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_transparency":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_transparency":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_transparency":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_transparency":true}}}}]'));
    });
    test('Hello with auth information', () {
      var authHello = Hello('my.realm', Details.forHello());
      authHello.details.authid = 'Richard';
      authHello.details.authmethods = ['WAMP-CRA'];
      authHello.details.authextra = HashMap();
      authHello.details.authextra['nonce'] = 'egVDf3DMJh0=';
      authHello.details.authextra['channel_binding'] = null;
      var message = serializer.serializeToString(authHello);
      expect(
          message,
          startsWith(
              '[1,"my.realm",{"roles":{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_transparency":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_transparency":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_transparency":true,"subscription_revocation":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_transparency":true}}},"authid":"Richard","authmethods":["WAMP-CRA"],"authextra":'));
      expect(message, contains('"channel_binding":null'));
      expect(message, contains('"nonce":"egVDf3DMJh0="'));
    });
    test('Authenticate', () {
      expect(serializer.serializeToString(Authenticate()),
          equals('[${MessageTypes.CODE_AUTHENTICATE},"",{}]'));
      expect(
          serializer.serializeToString(Authenticate.signature('someSignature')),
          equals(
              '[${MessageTypes.CODE_AUTHENTICATE},"${"someSignature"}",{}]'));
      var authenticate = Authenticate.signature('someSignature');
      authenticate.extra = HashMap<String, Object>();
      authenticate.extra['nonce'] = 'abc';
      expect(
          serializer.serializeToString(authenticate),
          equals(
              '[${MessageTypes.CODE_AUTHENTICATE},"${"someSignature"}",{"nonce":"abc"}]'));
    });
    test('Register', () {
      expect(
          serializer
              .serializeToString(Register(25349185, 'com.myapp.myprocedure1')),
          equals(
              '[${MessageTypes.CODE_REGISTER},25349185,{},"com.myapp.myprocedure1"]'));
      expect(
          serializer.serializeToString(Register(
              25349185, 'com.myapp.myprocedure1',
              options: RegisterOptions(
                  disclose_caller: true,
                  invoke: RegisterOptions.INVOCATION_POLICY_RANDOM,
                  match: RegisterOptions.MATCH_PREFIX))),
          equals(
              '[${MessageTypes.CODE_REGISTER},25349185,{"match":"prefix","disclose_caller":true,"invoke":"random"},"com.myapp.myprocedure1"]'));
      expect(
          serializer.serializeToString(Register(
              25349185, 'com.myapp.myprocedure2',
              options: RegisterOptions(disclose_caller: false))),
          equals(
              '[${MessageTypes.CODE_REGISTER},25349185,{"disclose_caller":false},"com.myapp.myprocedure2"]'));
    });
    test('Unregister', () {
      expect(serializer.serializeToString(Unregister(25349185, 127981236)),
          equals('[${MessageTypes.CODE_UNREGISTER},25349185,127981236]'));
    });
    test('Call', () {
      expect(serializer.serializeToString(Call(7814135, 'com.myapp.ping')),
          equals('[${MessageTypes.CODE_CALL},7814135,{},"com.myapp.ping"]'));
      expect(
          serializer.serializeToString(
              Call(7814135, 'com.myapp.ping', options: CallOptions())),
          equals('[${MessageTypes.CODE_CALL},7814135,{},"com.myapp.ping"]'));
      expect(
          serializer.serializeToString(Call(7814135, 'com.myapp.ping',
              options: CallOptions(
                  receive_progress: true, disclose_me: true, timeout: 12))),
          equals(
              '[${MessageTypes.CODE_CALL},7814135,{"receive_progress":true,"disclose_me":true,"timeout":12},"com.myapp.ping"]'));
      expect(
          serializer.serializeToString(
              Call(7814135, 'com.myapp.ping', arguments: ['hi', 2])),
          equals(
              '[${MessageTypes.CODE_CALL},7814135,{},"com.myapp.ping",["hi",2]]'));
      expect(
          serializer.serializeToString(
              Call(7814135, 'com.myapp.ping', argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.CODE_CALL},7814135,{},"com.myapp.ping",[],{"hi":12}]'));
      expect(
          serializer.serializeToString(Call(7814135, 'com.myapp.ping',
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.CODE_CALL},7814135,{},"com.myapp.ping",["hi",2],{"hi":12}]'));
    });
    test('Yield', () {
      expect(serializer.serializeToString(Yield(6131533)),
          equals('[${MessageTypes.CODE_YIELD},6131533,{}]'));
      expect(
          serializer
              .serializeToString(Yield(6131533, options: YieldOptions(false))),
          equals('[${MessageTypes.CODE_YIELD},6131533,{"progress":false}]'));
      expect(
          serializer
              .serializeToString(Yield(6131533, options: YieldOptions(true))),
          equals('[${MessageTypes.CODE_YIELD},6131533,{"progress":true}]'));
      expect(serializer.serializeToString(Yield(6131533, arguments: ['hi', 2])),
          equals('[${MessageTypes.CODE_YIELD},6131533,{},["hi",2]]'));
      expect(
          serializer
              .serializeToString(Yield(6131533, argumentsKeywords: {'hi': 12})),
          equals('[${MessageTypes.CODE_YIELD},6131533,{},[],{"hi":12}]'));
      expect(
          serializer.serializeToString(Yield(6131533,
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals('[${MessageTypes.CODE_YIELD},6131533,{},["hi",2],{"hi":12}]'));
    });
    test('Error', () {
      expect(
          serializer.serializeToString(Error(
              MessageTypes.CODE_HELLO, 123422, HashMap(), 'wamp.unknown')),
          equals(
              '[${MessageTypes.CODE_ERROR},${MessageTypes.CODE_HELLO},123422,{},"wamp.unknown"]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown')),
          equals(
              '[${MessageTypes.CODE_ERROR},${MessageTypes.CODE_HELLO},123422,{"cause":"some"},"wamp.unknown"]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              arguments: ['hi', 2])),
          equals(
              '[${MessageTypes.CODE_ERROR},${MessageTypes.CODE_HELLO},123422,{"cause":"some"},"wamp.unknown",["hi",2]]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.CODE_ERROR},${MessageTypes.CODE_HELLO},123422,{"cause":"some"},"wamp.unknown",[],{"hi":12}]'));
      expect(
          serializer.serializeToString(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(
              '[${MessageTypes.CODE_ERROR},${MessageTypes.CODE_HELLO},123422,{"cause":"some"},"wamp.unknown",["hi",2],{"hi":12}]'));
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
              options: SubscribeOptions(match: SubscribeOptions.MATCH_PLAIN))),
          equals('[32,713845233,{},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(match: SubscribeOptions.MATCH_PREFIX))),
          equals('[32,713845233,{"match":"prefix"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options:
                  SubscribeOptions(match: SubscribeOptions.MATCH_WILDCARD))),
          equals('[32,713845233,{"match":"wildcard"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(meta_topic: 'topic'))),
          equals('[32,713845233,{"meta_topic":"topic"},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Subscribe(
              713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(
                  get_retained: true,
                  match: SubscribeOptions.MATCH_WILDCARD,
                  meta_topic: 'topic'))),
          equals(
              '[32,713845233,{"get_retained":true,"match":"wildcard","meta_topic":"topic"},"com.myapp.mytopic1"]'));
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
                  disclose_me: true,
                  acknowledge: true,
                  exclude_me: true,
                  eligible: [1],
                  eligible_authid: ['aaa'],
                  eligible_authrole: ['role'],
                  exclude: [2],
                  exclude_authid: ['bbb'],
                  exclude_authrole: ['admin']))),
          equals(
              '[16,239714735,{"retain":true,"disclose_me":true,"acknowledge":true,"exclude_me":true,"exclude":[2],"exclude_authid":["bbb"],"exclude_authrole":["admin"],"eligible":[1],"eligible_authid":["aaa"],"eligible_authrole":["role"]},"com.myapp.mytopic1"]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              arguments: ['Hello, world!'])),
          equals('[16,239714735,{},"com.myapp.mytopic1",["Hello, world!"]]'));
      expect(
          serializer.serializeToString(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(exclude_me: false),
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
              options: PublishOptions(exclude_me: false),
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
              options: PublishOptions(exclude_me: false),
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
              Goodbye(GoodbyeMessage('cya'), Goodbye.REASON_GOODBYE_AND_OUT)),
          equals('[6,{"message":"cya"},"wamp.error.goodbye_and_out"]'));
      expect(
          serializer.serializeToString(
              Goodbye(GoodbyeMessage(null), Goodbye.REASON_CLOSE_REALM)),
          equals('[6,{"message":""},"wamp.error.close_realm"]'));
      expect(
          serializer
              .serializeToString(Goodbye(null, Goodbye.REASON_SYSTEM_SHUTDOWN)),
          equals('[6,{},"wamp.error.system_shutdown"]'));
    });
    test('Abort', () {
      expect(
          serializer.serializeToString(
              Abort(Error.AUTHORIZATION_FAILED, message: 'Some Error')),
          equals(
              '[3,{"message":"Some Error"},"${Error.AUTHORIZATION_FAILED}"]'));
      expect(
          serializer.serializeToString(
              Abort(Error.AUTHORIZATION_FAILED, message: '')),
          equals('[3,{"message":""},"${Error.AUTHORIZATION_FAILED}"]'));
      expect(serializer.serializeToString(Abort(Error.AUTHORIZATION_FAILED)),
          equals('[3,{},"${Error.AUTHORIZATION_FAILED}"]'));
    });
  });
  group('unserialize', () {
    test('Abort', () {
      Abort abort = serializer.deserializeFromString(
          '[${MessageTypes.CODE_ABORT},{"message":"Received HELLO message after session was established."},"wamp.error.protocol_violation"]');
      expect(abort, isNotNull);
      expect(abort.id, equals(MessageTypes.CODE_ABORT));
      expect(abort.message.message,
          equals('Received HELLO message after session was established.'));
      expect(abort.reason, equals(Error.PROTOCOL_VIOLATION));
    });
    test('Challenge', () {
      Challenge challenge = serializer.deserializeFromString(
          '[${MessageTypes.CODE_CHALLENGE},"wampcra",{"challenge":"{\\"authid\\":\\"Richi\\",\\"authrole\\":\\"admin\\",\\"authmethod\\":\\"wampcra\\",\\"authprovider\\":\\"server\\",\\"nonce\\":\\"5636117568768122\\",\\"timestamp\\":\\"2018-03-16T07:29Z\\",\\"session\\":\\"5768501099130836\\"}","salt":"fhhi290fh7§)GQ)G)","keylen":35,"iterations":410}]');
      expect(challenge, isNotNull);
      expect(challenge.id, equals(MessageTypes.CODE_CHALLENGE));
      expect(challenge.authMethod, equals('wampcra'));
      expect(
          challenge.extra.challenge,
          equals(
              '{\"authid\":\"Richi\",\"authrole\":\"admin\",\"authmethod\":\"wampcra\",\"authprovider\":\"server\",\"nonce\":\"5636117568768122\",\"timestamp\":\"2018-03-16T07:29Z\",\"session\":\"5768501099130836\"}'));
      expect(challenge.extra.salt, equals('fhhi290fh7§)GQ)G)'));
      expect(challenge.extra.keylen, equals(35));
      expect(challenge.extra.iterations, equals(410));
    });
    test('Welcome', () {
      Welcome welcome = serializer.deserializeFromString(
          '[${MessageTypes.CODE_WELCOME},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":false,"pattern_based_subscription":false,"subscription_meta_api":false,"subscriber_blackwhite_listing":false,"session_meta_api":false,"publisher_exclusion":false,"event_history":false,"payload_transparency":false}},"dealer":{"features":{"caller_identification":false,"call_trustlevels":false,"pattern_based_registration":false,"registration_meta_api":false,"shared_registration":false,"session_meta_api":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_transparency":false}}}}]');
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles.broker, isNotNull);
      expect(welcome.details.roles.broker.features, isNotNull);
      expect(
          welcome.details.roles.broker.features.payload_transparency, isFalse);
      expect(welcome.details.roles.broker.features.event_history, isFalse);
      expect(welcome.details.roles.broker.features.pattern_based_subscription,
          isFalse);
      expect(welcome.details.roles.broker.features.publication_trustlevels,
          isFalse);
      expect(
          welcome.details.roles.broker.features.publisher_exclusion, isFalse);
      expect(welcome.details.roles.broker.features.publisher_identification,
          isFalse);
      expect(welcome.details.roles.broker.features.session_meta_api, isFalse);
      expect(
          welcome.details.roles.broker.features.subscriber_blackwhite_listing,
          isFalse);
      expect(
          welcome.details.roles.broker.features.subscription_meta_api, isFalse);
      expect(welcome.details.roles.dealer, isNotNull);
      expect(welcome.details.roles.dealer.features, isNotNull);
      expect(
          welcome.details.roles.dealer.features.payload_transparency, isFalse);
      expect(welcome.details.roles.dealer.features.session_meta_api, isFalse);
      expect(welcome.details.roles.dealer.features.progressive_call_results,
          isFalse);
      expect(
          welcome.details.roles.dealer.features.caller_identification, isFalse);
      expect(welcome.details.roles.dealer.features.call_timeout, isFalse);
      expect(welcome.details.roles.dealer.features.call_canceling, isFalse);
      expect(welcome.details.roles.dealer.features.call_trustlevels, isFalse);
      expect(welcome.details.roles.dealer.features.pattern_based_registration,
          isFalse);
      expect(
          welcome.details.roles.dealer.features.registration_meta_api, isFalse);
      expect(
          welcome.details.roles.dealer.features.shared_registration, isFalse);

      welcome = serializer.deserializeFromString(
          '[${MessageTypes.CODE_WELCOME},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":true,"pattern_based_subscription":true,"subscription_meta_api":true,"subscriber_blackwhite_listing":true,"session_meta_api":true,"publisher_exclusion":true,"event_history":true,"payload_transparency":true}},"dealer":{"features":{"caller_identification":true,"call_trustlevels":true,"pattern_based_registration":true,"registration_meta_api":true,"shared_registration":true,"session_meta_api":true,"call_timeout":true,"call_canceling":true,"progressive_call_results":true,"payload_transparency":true}}}}]');
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles.broker, isNotNull);
      expect(welcome.details.roles.broker.features, isNotNull);
      expect(
          welcome.details.roles.broker.features.payload_transparency, isTrue);
      expect(welcome.details.roles.broker.features.event_history, isTrue);
      expect(welcome.details.roles.broker.features.pattern_based_subscription,
          isTrue);
      expect(welcome.details.roles.broker.features.publication_trustlevels,
          isFalse); // not send
      expect(welcome.details.roles.broker.features.publisher_exclusion, isTrue);
      expect(welcome.details.roles.broker.features.publisher_identification,
          isTrue);
      expect(welcome.details.roles.broker.features.session_meta_api, isTrue);
      expect(
          welcome.details.roles.broker.features.subscriber_blackwhite_listing,
          isTrue);
      expect(
          welcome.details.roles.broker.features.subscription_meta_api, isTrue);
      expect(welcome.details.roles.dealer, isNotNull);
      expect(welcome.details.roles.dealer.features, isNotNull);
      expect(
          welcome.details.roles.dealer.features.payload_transparency, isTrue);
      expect(welcome.details.roles.dealer.features.session_meta_api, isTrue);
      expect(welcome.details.roles.dealer.features.progressive_call_results,
          isTrue);
      expect(
          welcome.details.roles.dealer.features.caller_identification, isTrue);
      expect(welcome.details.roles.dealer.features.call_timeout, isTrue);
      expect(welcome.details.roles.dealer.features.call_canceling, isTrue);
      expect(welcome.details.roles.dealer.features.call_trustlevels, isTrue);
      expect(welcome.details.roles.dealer.features.pattern_based_registration,
          isTrue);
      expect(
          welcome.details.roles.dealer.features.registration_meta_api, isTrue);
      expect(welcome.details.roles.dealer.features.shared_registration, isTrue);
    });
    test('Registered', () {
      Registered registered =
          serializer.deserializeFromString('[65, 25349185, 2103333224]');
      expect(registered, isNotNull);
      expect(registered.id, equals(MessageTypes.CODE_REGISTERED));
      expect(registered.registerRequestId, equals(25349185));
      expect(registered.registrationId, equals(2103333224));
    });
    test('Unregistered', () {
      Unregistered unregistered =
          serializer.deserializeFromString('[67, 788923562]');
      expect(unregistered, isNotNull);
      expect(unregistered.id, equals(MessageTypes.CODE_UNREGISTERED));
      expect(unregistered.unregisterRequestId, equals(788923562));
    });
    test('Invocation', () {
      Invocation invocation =
          serializer.deserializeFromString('[68, 6131533, 9823526, {}]');
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823526));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments, isNull);
      expect(invocation.argumentsKeywords, isNull);

      invocation = serializer.deserializeFromString(
          '[68, 6131533, 9823527, {}, ["Hello, world!"]]');
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823527));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments[0], equals('Hello, world!'));
      expect(invocation.argumentsKeywords, isNull);

      invocation = serializer.deserializeFromString(
          '[68, 6131533, 9823529, {}, ["johnny"], {"firstname": "John","surname": "Doe"}]');
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823529));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments[0], equals('johnny'));
      expect(invocation.argumentsKeywords['firstname'], equals('John'));
      expect(invocation.argumentsKeywords['surname'], equals('Doe'));

      invocation = serializer.deserializeFromString(
          '[68, 6131533, 9823529, {"receive_progress": true, "caller": 13123, "procedure":"my.procedure.com"}, ["johnny"], {"firstname": "John","surname": "Doe"}]');
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823529));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isTrue);
      expect(invocation.details.caller, equals(13123));
      expect(invocation.details.procedure, equals('my.procedure.com'));
      expect(invocation.arguments[0], equals('johnny'));
      expect(invocation.argumentsKeywords['firstname'], equals('John'));
      expect(invocation.argumentsKeywords['surname'], equals('Doe'));
    });
    test('Result', () {
      Result result = serializer.deserializeFromString('[50, 7814135, {}]');
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(7814135));
      expect(result.details, isNotNull);
      expect(result.details.progress, isNull);
      expect(result.arguments, isNull);
      expect(result.argumentsKeywords, isNull);

      result = serializer.deserializeFromString('[50, 7814135, {}, [30]]');
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(7814135));
      expect(result.details, isNotNull);
      expect(result.details.progress, isNull);
      expect(result.arguments[0], equals(30));
      expect(result.argumentsKeywords, isNull);

      result = serializer.deserializeFromString(
          '[50, 6131533, {}, ["johnny"], {"userid": 123, "karma": 10}]');
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, isNull);
      expect(result.arguments[0], equals('johnny'));
      expect(result.argumentsKeywords['userid'], equals(123));
      expect(result.argumentsKeywords['karma'], equals(10));

      result = serializer.deserializeFromString(
          '[50, 6131533, {"progress": true}, ["johnny"], {"firstname": "John","surname": "Doe"}]');
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, isTrue);
      expect(result.arguments[0], equals('johnny'));
      expect(result.argumentsKeywords['firstname'], equals('John'));
      expect(result.argumentsKeywords['surname'], equals('Doe'));
    });
    // PUB / SUB
    test('Subscribed', () {
      Subscribed subscribed =
          serializer.deserializeFromString('[33, 713845233, 5512315355]');
      expect(subscribed, isNotNull);
      expect(subscribed.id, equals(MessageTypes.CODE_SUBSCRIBED));
      expect(subscribed.subscribeRequestId, equals(713845233));
      expect(subscribed.subscriptionId, equals(5512315355));
    });
    test('Unsubscribed', () {
      Unsubscribed unsubscribed =
          serializer.deserializeFromString('[35, 85346237]');
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.CODE_UNSUBSCRIBED));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details, isNull);

      unsubscribed = serializer.deserializeFromString(
          '[35, 85346237, {"subscription": 123322, "reason": "wamp.authentication.lost"}]');
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.CODE_UNSUBSCRIBED));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details.reason, equals('wamp.authentication.lost'));
      expect(unsubscribed.details.subscription, equals(123322));
    });
    test('Published', () {
      Published published =
          serializer.deserializeFromString('[17, 239714735, 4429313566]');
      expect(published, isNotNull);
      expect(published.id, equals(MessageTypes.CODE_PUBLISHED));
      expect(published.publishRequestId, equals(239714735));
      expect(published.publicationId, equals(4429313566));
    });
    test('Event', () {
      Event event =
          serializer.deserializeFromString('[36, 5512315355, 4429313566, {}]');
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments, isNull);
      expect(event.argumentsKeywords, isNull);

      event = serializer
          .deserializeFromString('[36, 5512315355, 4429313566, {}, [30]]');
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments[0], equals(30));
      expect(event.argumentsKeywords, isNull);

      event = serializer.deserializeFromString(
          '[36, 5512315355, 4429313566, {}, ["johnny"], {"userid": 123, "karma": 10}]');
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments[0], equals('johnny'));
      expect(event.argumentsKeywords['userid'], equals(123));
      expect(event.argumentsKeywords['karma'], equals(10));

      event = serializer.deserializeFromString(
          '[36, 5512315355, 4429313566, {"publisher": 1231412}, ["johnny"], {"firstname": "John","surname": "Doe"}]');
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, equals(1231412));
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments[0], equals('johnny'));
      expect(event.argumentsKeywords['firstname'], equals('John'));
      expect(event.argumentsKeywords['surname'], equals('Doe'));

      event = serializer.deserializeFromString(
          '[36, 5512315355, 4429313566, {"publisher": 1231412, "topic":"de.de.com", "trustlevel":1}, ["johnny"], {"firstname": "John","surname": "Doe"}]');
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, equals(1231412));
      expect(event.details.topic, equals('de.de.com'));
      expect(event.details.trustlevel, equals(1));
      expect(event.arguments[0], equals('johnny'));
      expect(event.argumentsKeywords['firstname'], equals('John'));
      expect(event.argumentsKeywords['surname'], equals('Doe'));
    });
  });
  group('string conversion', () {
    test('convert UTF-8', () {
      var invocation = Invocation(10, 10, InvocationDetails(1, '', false),
          arguments: [
            '𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'
          ]);
      Invocation serializedInvocation =
          serializer.deserialize(serializer.serialize(invocation));
      expect(serializedInvocation.arguments[0],
          equals('𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'));
    });
  });
}

import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/details.dart';
import 'package:connectanum_dart/src/message/hello.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:connectanum_dart/src/serializer/json/serializer.dart';
import 'package:test/test.dart';

void main() {
  Serializer serializer = new Serializer();
  group('serialize', () {
    test('Hello', () {
      expect(serializer.serialize(new Hello("my.realm", Details.forHello())), equals('[1,"my.realm",{"caller":{"features":{"call_canceling":false,"call_timeout":false,"caller_identification":true,"payload_transparency":true,"progressive_call_results":true}},"callee":{"features":{"caller_identification":true,"call_trustlevels":false,"pattern_based_registration":false,"shared_registration":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":true,"payload_transparency":true}},"subscriber":{"features":{"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_transparency":true}},"publisher":{"features":{"publisher_identification":true,"subscriber_blackwhite_listing":true,"publisher_exclusion":true,"payload_transparency":true}}}]'));
    });
    test('Authenticate', () {
      expect(serializer.serialize(new Authenticate()), equals('[${MessageTypes.CODE_AUTHENTICATE},"",{}]'));
      expect(serializer.serialize(new Authenticate.signature("someSignature")), equals('[${MessageTypes.CODE_AUTHENTICATE},"${"someSignature"}",{}]'));
    });
  });
  group('unserialize', () {
    test('Challenge', () {
      Challenge challenge = serializer.deserialize('[${MessageTypes.CODE_CHALLENGE},"wampcra",{"challenge":"{\\"authid\\":\\"Richi\\",\\"authrole\\":\\"admin\\",\\"authmethod\\":\\"wampcra\\",\\"authprovider\\":\\"server\\",\\"nonce\\":\\"5636117568768122\\",\\"timestamp\\":\\"2018-03-16T07:29Z\\",\\"session\\":\\"5768501099130836\\"}","salt":"fhhi290fh7§)GQ)G)","keylen":35,"iterations":410}]');
      expect(challenge, isNotNull);
      expect(challenge.id, equals(MessageTypes.CODE_CHALLENGE));
      expect(challenge.authMethod, equals("wampcra"));
      expect(challenge.extra.challenge, equals("{\"authid\":\"Richi\",\"authrole\":\"admin\",\"authmethod\":\"wampcra\",\"authprovider\":\"server\",\"nonce\":\"5636117568768122\",\"timestamp\":\"2018-03-16T07:29Z\",\"session\":\"5768501099130836\"}"));
      expect(challenge.extra.salt, equals("fhhi290fh7§)GQ)G)"));
      expect(challenge.extra.keylen, equals(35));
      expect(challenge.extra.iterations, equals(410));
    });
    test('Welcome', () {
      Welcome welcome = serializer.deserialize('[${MessageTypes.CODE_WELCOME},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":false,"pattern_based_subscription":false,"subscription_meta_api":false,"subscriber_blackwhite_listing":false,"session_meta_api":false,"publisher_exclusion":false,"event_history":false,"payload_transparency":false}},"dealer":{"features":{"caller_identification":false,"call_trustlevels":false,"pattern_based_registration":false,"registration_meta_api":false,"shared_registration":false,"session_meta_api":false,"call_timeout":false,"call_canceling":false,"progressive_call_results":false,"payload_transparency":false}}}}]');
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals("Richi"));
      expect(welcome.details.authrole, equals("admin"));
      expect(welcome.details.authmethod, equals("wampcra"));
      expect(welcome.details.authprovider, equals("database"));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles.broker, isNotNull);
      expect(welcome.details.roles.broker.features, isNotNull);
      expect(welcome.details.roles.broker.features.payload_transparency, isFalse);
      expect(welcome.details.roles.broker.features.event_history, isFalse);
      expect(welcome.details.roles.broker.features.pattern_based_subscription, isFalse);
      expect(welcome.details.roles.broker.features.publication_trustlevels, isFalse);
      expect(welcome.details.roles.broker.features.publisher_exclusion, isFalse);
      expect(welcome.details.roles.broker.features.publisher_identification, isFalse);
      expect(welcome.details.roles.broker.features.session_meta_api, isFalse);
      expect(welcome.details.roles.broker.features.subscriber_blackwhite_listing, isFalse);
      expect(welcome.details.roles.broker.features.subscription_meta_api, isFalse);
      expect(welcome.details.roles.dealer, isNotNull);
      expect(welcome.details.roles.dealer.features, isNotNull);
      expect(welcome.details.roles.dealer.features.payload_transparency, isFalse);
      expect(welcome.details.roles.dealer.features.session_meta_api, isFalse);
      expect(welcome.details.roles.dealer.features.progressive_call_results, isFalse);
      expect(welcome.details.roles.dealer.features.caller_identification, isFalse);
      expect(welcome.details.roles.dealer.features.call_timeout, isFalse);
      expect(welcome.details.roles.dealer.features.call_canceling, isFalse);
      expect(welcome.details.roles.dealer.features.call_trustlevels, isFalse);
      expect(welcome.details.roles.dealer.features.pattern_based_registration, isFalse);
      expect(welcome.details.roles.dealer.features.registration_meta_api, isFalse);
      expect(welcome.details.roles.dealer.features.shared_registration, isFalse);

      welcome = serializer.deserialize('[${MessageTypes.CODE_WELCOME},112233,{"authid":"Richi","authrole":"admin","authmethod":"wampcra","authprovider":"database","roles":{"broker":{"features":{"publisher_identification":true,"pattern_based_subscription":true,"subscription_meta_api":true,"subscriber_blackwhite_listing":true,"session_meta_api":true,"publisher_exclusion":true,"event_history":true,"payload_transparency":true}},"dealer":{"features":{"caller_identification":true,"call_trustlevels":true,"pattern_based_registration":true,"registration_meta_api":true,"shared_registration":true,"session_meta_api":true,"call_timeout":true,"call_canceling":true,"progressive_call_results":true,"payload_transparency":true}}}}]');
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals("Richi"));
      expect(welcome.details.authrole, equals("admin"));
      expect(welcome.details.authmethod, equals("wampcra"));
      expect(welcome.details.authprovider, equals("database"));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles.broker, isNotNull);
      expect(welcome.details.roles.broker.features, isNotNull);
      expect(welcome.details.roles.broker.features.payload_transparency, isTrue);
      expect(welcome.details.roles.broker.features.event_history, isTrue);
      expect(welcome.details.roles.broker.features.pattern_based_subscription, isTrue);
      expect(welcome.details.roles.broker.features.publication_trustlevels, isFalse); // not send
      expect(welcome.details.roles.broker.features.publisher_exclusion, isTrue);
      expect(welcome.details.roles.broker.features.publisher_identification, isTrue);
      expect(welcome.details.roles.broker.features.session_meta_api, isTrue);
      expect(welcome.details.roles.broker.features.subscriber_blackwhite_listing, isTrue);
      expect(welcome.details.roles.broker.features.subscription_meta_api, isTrue);
      expect(welcome.details.roles.dealer, isNotNull);
      expect(welcome.details.roles.dealer.features, isNotNull);
      expect(welcome.details.roles.dealer.features.payload_transparency, isTrue);
      expect(welcome.details.roles.dealer.features.session_meta_api, isTrue);
      expect(welcome.details.roles.dealer.features.progressive_call_results, isTrue);
      expect(welcome.details.roles.dealer.features.caller_identification, isTrue);
      expect(welcome.details.roles.dealer.features.call_timeout, isTrue);
      expect(welcome.details.roles.dealer.features.call_canceling, isTrue);
      expect(welcome.details.roles.dealer.features.call_trustlevels, isTrue);
      expect(welcome.details.roles.dealer.features.pattern_based_registration, isTrue);
      expect(welcome.details.roles.dealer.features.registration_meta_api, isTrue);
      expect(welcome.details.roles.dealer.features.shared_registration, isTrue);
    });
  });
}
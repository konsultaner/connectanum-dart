import 'dart:typed_data';

import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/cbor/serializer.dart';
import 'package:test/test.dart';

void main() {
  var serializer = Serializer();
  group('deserialize', () {
    test('Abort', () {
      var abort = serializer.deserialize(Uint8List.fromList([131, 3, 161, 103, 109, 101, 115, 115, 97, 103, 101, 120, 53, 82, 101, 99, 101, 105, 118, 101, 100, 32, 72, 69, 76, 76, 79, 32, 109, 101, 115, 115, 97, 103, 101, 32, 97, 102, 116, 101, 114, 32, 115, 101, 115, 115, 105, 111, 110, 32, 119, 97, 115, 32, 101, 115, 116, 97, 98, 108, 105, 115, 104, 101, 100, 46, 120, 29, 119, 97, 109, 112, 46, 101, 114, 114, 111, 114, 46, 112, 114, 111, 116, 111, 99, 111, 108, 95, 118, 105, 111, 108, 97, 116, 105, 111, 110])
      ) as Abort;
      expect(abort, isNotNull);
      expect(abort.id, equals(MessageTypes.CODE_ABORT));
      expect(abort.message!.message,
          equals('Received HELLO message after session was established.'));
      expect(abort.reason, equals(Error.PROTOCOL_VIOLATION));
    });
    test('Challenge', () {
      var challenge = serializer.deserialize(
          Uint8List.fromList([131, 4, 103, 119, 97, 109, 112, 99, 114, 97, 164, 105, 99, 104, 97, 108, 108, 101, 110, 103, 101, 120, 172, 123, 34, 97, 117, 116, 104, 105, 100, 34, 58, 34, 82, 105, 99, 104, 105, 34, 44, 34, 97, 117, 116, 104, 114, 111, 108, 101, 34, 58, 34, 97, 100, 109, 105, 110, 34, 44, 34, 97, 117, 116, 104, 109, 101, 116, 104, 111, 100, 34, 58, 34, 119, 97, 109, 112, 99, 114, 97, 34, 44, 34, 97, 117, 116, 104, 112, 114, 111, 118, 105, 100, 101, 114, 34, 58, 34, 115, 101, 114, 118, 101, 114, 34, 44, 34, 110, 111, 110, 99, 101, 34, 58, 34, 53, 54, 51, 54, 49, 49, 55, 53, 54, 56, 55, 54, 56, 49, 50, 50, 34, 44, 34, 116, 105, 109, 101, 115, 116, 97, 109, 112, 34, 58, 34, 50, 48, 49, 56, 45, 48, 51, 45, 49, 54, 84, 48, 55, 58, 50, 57, 90, 34, 44, 34, 115, 101, 115, 115, 105, 111, 110, 34, 58, 34, 53, 55, 54, 56, 53, 48, 49, 48, 57, 57, 49, 51, 48, 56, 51, 54, 34, 125, 100, 115, 97, 108, 116, 114, 102, 104, 104, 105, 50, 57, 48, 102, 104, 55, 194, 167, 41, 71, 81, 41, 71, 41, 102, 107, 101, 121, 108, 101, 110, 24, 35, 106, 105, 116, 101, 114, 97, 116, 105, 111, 110, 115, 25, 1, 154])
      ) as Challenge;
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
      var welcome = serializer.deserialize(
          Uint8List.fromList([131, 2, 26, 0, 1, 182, 105, 165, 102, 97, 117, 116, 104, 105, 100, 101, 82, 105, 99, 104, 105, 104, 97, 117, 116, 104, 114, 111, 108, 101, 101, 97, 100, 109, 105, 110, 106, 97, 117, 116, 104, 109, 101, 116, 104, 111, 100, 103, 119, 97, 109, 112, 99, 114, 97, 108, 97, 117, 116, 104, 112, 114, 111, 118, 105, 100, 101, 114, 104, 100, 97, 116, 97, 98, 97, 115, 101, 101, 114, 111, 108, 101, 115, 162, 102, 98, 114, 111, 107, 101, 114, 161, 104, 102, 101, 97, 116, 117, 114, 101, 115, 168, 120, 24, 112, 117, 98, 108, 105, 115, 104, 101, 114, 95, 105, 100, 101, 110, 116, 105, 102, 105, 99, 97, 116, 105, 111, 110, 244, 120, 26, 112, 97, 116, 116, 101, 114, 110, 95, 98, 97, 115, 101, 100, 95, 115, 117, 98, 115, 99, 114, 105, 112, 116, 105, 111, 110, 244, 117, 115, 117, 98, 115, 99, 114, 105, 112, 116, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 244, 120, 29, 115, 117, 98, 115, 99, 114, 105, 98, 101, 114, 95, 98, 108, 97, 99, 107, 119, 104, 105, 116, 101, 95, 108, 105, 115, 116, 105, 110, 103, 244, 112, 115, 101, 115, 115, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 244, 115, 112, 117, 98, 108, 105, 115, 104, 101, 114, 95, 101, 120, 99, 108, 117, 115, 105, 111, 110, 244, 109, 101, 118, 101, 110, 116, 95, 104, 105, 115, 116, 111, 114, 121, 244, 116, 112, 97, 121, 108, 111, 97, 100, 95, 116, 114, 97, 110, 115, 112, 97, 114, 101, 110, 99, 121, 244, 102, 100, 101, 97, 108, 101, 114, 161, 104, 102, 101, 97, 116, 117, 114, 101, 115, 170, 117, 99, 97, 108, 108, 101, 114, 95, 105, 100, 101, 110, 116, 105, 102, 105, 99, 97, 116, 105, 111, 110, 244, 112, 99, 97, 108, 108, 95, 116, 114, 117, 115, 116, 108, 101, 118, 101, 108, 115, 244, 120, 26, 112, 97, 116, 116, 101, 114, 110, 95, 98, 97, 115, 101, 100, 95, 114, 101, 103, 105, 115, 116, 114, 97, 116, 105, 111, 110, 244, 117, 114, 101, 103, 105, 115, 116, 114, 97, 116, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 244, 115, 115, 104, 97, 114, 101, 100, 95, 114, 101, 103, 105, 115, 116, 114, 97, 116, 105, 111, 110, 244, 112, 115, 101, 115, 115, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 244, 108, 99, 97, 108, 108, 95, 116, 105, 109, 101, 111, 117, 116, 244, 110, 99, 97, 108, 108, 95, 99, 97, 110, 99, 101, 108, 105, 110, 103, 244, 120, 24, 112, 114, 111, 103, 114, 101, 115, 115, 105, 118, 101, 95, 99, 97, 108, 108, 95, 114, 101, 115, 117, 108, 116, 115, 244, 116, 112, 97, 121, 108, 111, 97, 100, 95, 116, 114, 97, 110, 115, 112, 97, 114, 101, 110, 99, 121, 244])
      ) as Welcome;
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles!.broker, isNotNull);
      expect(welcome.details.roles!.broker!.features, isNotNull);
      expect(welcome.details.roles!.broker!.features!.payload_transparency,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.event_history, isFalse);
      expect(
          welcome.details.roles!.broker!.features!.pattern_based_subscription,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.publication_trustlevels,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.publisher_exclusion,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.publisher_identification,
          isFalse);
      expect(
          welcome.details.roles!.broker!.features!.session_meta_api, isFalse);
      expect(
          welcome
              .details.roles!.broker!.features!.subscriber_blackwhite_listing,
          isFalse);
      expect(welcome.details.roles!.broker!.features!.subscription_meta_api,
          isFalse);
      expect(welcome.details.roles!.dealer, isNotNull);
      expect(welcome.details.roles!.dealer!.features, isNotNull);
      expect(welcome.details.roles!.dealer!.features!.payload_transparency,
          isFalse);
      expect(
          welcome.details.roles!.dealer!.features!.session_meta_api, isFalse);
      expect(welcome.details.roles!.dealer!.features!.progressive_call_results,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.caller_identification,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.call_timeout, isFalse);
      expect(welcome.details.roles!.dealer!.features!.call_canceling, isFalse);
      expect(
          welcome.details.roles!.dealer!.features!.call_trustlevels, isFalse);
      expect(
          welcome.details.roles!.dealer!.features!.pattern_based_registration,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.registration_meta_api,
          isFalse);
      expect(welcome.details.roles!.dealer!.features!.shared_registration,
          isFalse);

      welcome = serializer.deserialize(
          Uint8List.fromList([131, 2, 26, 0, 1, 182, 105, 165, 102, 97, 117, 116, 104, 105, 100, 101, 82, 105, 99, 104, 105, 104, 97, 117, 116, 104, 114, 111, 108, 101, 101, 97, 100, 109, 105, 110, 106, 97, 117, 116, 104, 109, 101, 116, 104, 111, 100, 103, 119, 97, 109, 112, 99, 114, 97, 108, 97, 117, 116, 104, 112, 114, 111, 118, 105, 100, 101, 114, 104, 100, 97, 116, 97, 98, 97, 115, 101, 101, 114, 111, 108, 101, 115, 162, 102, 98, 114, 111, 107, 101, 114, 161, 104, 102, 101, 97, 116, 117, 114, 101, 115, 168, 120, 24, 112, 117, 98, 108, 105, 115, 104, 101, 114, 95, 105, 100, 101, 110, 116, 105, 102, 105, 99, 97, 116, 105, 111, 110, 245, 120, 26, 112, 97, 116, 116, 101, 114, 110, 95, 98, 97, 115, 101, 100, 95, 115, 117, 98, 115, 99, 114, 105, 112, 116, 105, 111, 110, 245, 117, 115, 117, 98, 115, 99, 114, 105, 112, 116, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 245, 120, 29, 115, 117, 98, 115, 99, 114, 105, 98, 101, 114, 95, 98, 108, 97, 99, 107, 119, 104, 105, 116, 101, 95, 108, 105, 115, 116, 105, 110, 103, 245, 112, 115, 101, 115, 115, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 245, 115, 112, 117, 98, 108, 105, 115, 104, 101, 114, 95, 101, 120, 99, 108, 117, 115, 105, 111, 110, 245, 109, 101, 118, 101, 110, 116, 95, 104, 105, 115, 116, 111, 114, 121, 245, 116, 112, 97, 121, 108, 111, 97, 100, 95, 116, 114, 97, 110, 115, 112, 97, 114, 101, 110, 99, 121, 245, 102, 100, 101, 97, 108, 101, 114, 161, 104, 102, 101, 97, 116, 117, 114, 101, 115, 170, 117, 99, 97, 108, 108, 101, 114, 95, 105, 100, 101, 110, 116, 105, 102, 105, 99, 97, 116, 105, 111, 110, 245, 112, 99, 97, 108, 108, 95, 116, 114, 117, 115, 116, 108, 101, 118, 101, 108, 115, 245, 120, 26, 112, 97, 116, 116, 101, 114, 110, 95, 98, 97, 115, 101, 100, 95, 114, 101, 103, 105, 115, 116, 114, 97, 116, 105, 111, 110, 245, 117, 114, 101, 103, 105, 115, 116, 114, 97, 116, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 245, 115, 115, 104, 97, 114, 101, 100, 95, 114, 101, 103, 105, 115, 116, 114, 97, 116, 105, 111, 110, 245, 112, 115, 101, 115, 115, 105, 111, 110, 95, 109, 101, 116, 97, 95, 97, 112, 105, 245, 108, 99, 97, 108, 108, 95, 116, 105, 109, 101, 111, 117, 116, 245, 110, 99, 97, 108, 108, 95, 99, 97, 110, 99, 101, 108, 105, 110, 103, 245, 120, 24, 112, 114, 111, 103, 114, 101, 115, 115, 105, 118, 101, 95, 99, 97, 108, 108, 95, 114, 101, 115, 117, 108, 116, 115, 245, 116, 112, 97, 121, 108, 111, 97, 100, 95, 116, 114, 97, 110, 115, 112, 97, 114, 101, 110, 99, 121, 245])
      ) as Welcome;
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles!.broker, isNotNull);
      expect(welcome.details.roles!.broker!.features, isNotNull);
      expect(welcome.details.roles!.broker!.features!.payload_transparency,
          isTrue);
      expect(welcome.details.roles!.broker!.features!.event_history, isTrue);
      expect(
          welcome.details.roles!.broker!.features!.pattern_based_subscription,
          isTrue);
      expect(welcome.details.roles!.broker!.features!.publication_trustlevels,
          isFalse); // not send
      expect(
          welcome.details.roles!.broker!.features!.publisher_exclusion, isTrue);
      expect(welcome.details.roles!.broker!.features!.publisher_identification,
          isTrue);
      expect(welcome.details.roles!.broker!.features!.session_meta_api, isTrue);
      expect(
          welcome
              .details.roles!.broker!.features!.subscriber_blackwhite_listing,
          isTrue);
      expect(welcome.details.roles!.broker!.features!.subscription_meta_api,
          isTrue);
      expect(welcome.details.roles!.dealer, isNotNull);
      expect(welcome.details.roles!.dealer!.features, isNotNull);
      expect(welcome.details.roles!.dealer!.features!.payload_transparency,
          isTrue);
      expect(welcome.details.roles!.dealer!.features!.session_meta_api, isTrue);
      expect(welcome.details.roles!.dealer!.features!.progressive_call_results,
          isTrue);
      expect(welcome.details.roles!.dealer!.features!.caller_identification,
          isTrue);
      expect(welcome.details.roles!.dealer!.features!.call_timeout, isTrue);
      expect(welcome.details.roles!.dealer!.features!.call_canceling, isTrue);
      expect(welcome.details.roles!.dealer!.features!.call_trustlevels, isTrue);
      expect(
          welcome.details.roles!.dealer!.features!.pattern_based_registration,
          isTrue);
      expect(welcome.details.roles!.dealer!.features!.registration_meta_api,
          isTrue);
      expect(
          welcome.details.roles!.dealer!.features!.shared_registration, isTrue);
    });
  });
}
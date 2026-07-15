import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:test/test.dart';

void main() {
  group('WAMP feature announcements', () {
    test('client roles announce the implemented Advanced Profile subset', () {
      final roles = Details.forHello().roles!;

      final caller = roles.caller!.features!;
      expect(caller.callerIdentification, isTrue);
      expect(caller.callCanceling, isTrue);
      expect(caller.progressiveCallInvocations, isTrue);
      expect(caller.progressiveCallResults, isTrue);
      expect(caller.payloadPassThruMode, isTrue);
      expect(caller.callTimeout, isTrue);

      final callee = roles.callee!.features!;
      expect(callee.callerIdentification, isTrue);
      expect(callee.patternBasedRegistration, isTrue);
      expect(callee.sharedRegistration, isTrue);
      expect(callee.callCanceling, isTrue);
      expect(callee.progressiveCallInvocations, isTrue);
      expect(callee.progressiveCallResults, isTrue);
      expect(callee.payloadPassThruMode, isTrue);
      expect(callee.callTimeout, isTrue);
      expect(callee.callTrustlevels, isFalse);

      final publisher = roles.publisher!.features!;
      expect(publisher.publisherIdentification, isTrue);
      expect(publisher.subscriberBlackWhiteListing, isTrue);
      expect(publisher.publisherExclusion, isTrue);
      expect(publisher.payloadPassThruMode, isTrue);

      final subscriber = roles.subscriber!.features!;
      expect(subscriber.publisherIdentification, isTrue);
      expect(subscriber.publicationTrustLevels, isTrue);
      expect(subscriber.patternBasedSubscription, isTrue);
      expect(subscriber.subscriptionRevocation, isTrue);
      expect(subscriber.payloadPassThruMode, isTrue);
    });

    test(
      'router roles announce only the implemented Advanced Profile subset',
      () {
        final roles = Details.forWelcome().roles!;

        final broker = roles.broker!.features!;
        expect(broker.publisherIdentification, isTrue);
        expect(broker.patternBasedSubscription, isTrue);
        expect(broker.subscriberBlackWhiteListing, isTrue);
        expect(broker.publisherExclusion, isTrue);
        expect(broker.payloadPassThruMode, isTrue);
        expect(broker.publicationTrustLevels, isFalse);
        expect(broker.subscriptionMetaApi, isTrue);
        expect(broker.sessionMetaApi, isFalse);
        expect(broker.eventHistory, isFalse);

        final dealer = roles.dealer!.features!;
        expect(dealer.callerIdentification, isTrue);
        expect(dealer.patternBasedRegistration, isTrue);
        expect(dealer.sharedRegistration, isTrue);
        expect(dealer.callCanceling, isTrue);
        expect(dealer.progressiveCallInvocations, isTrue);
        expect(dealer.progressiveCallResults, isTrue);
        expect(dealer.payloadPassThruMode, isTrue);
        expect(dealer.callTrustLevels, isFalse);
        expect(dealer.registrationMetaApi, isTrue);
        expect(dealer.sessionMetaApi, isFalse);
        expect(dealer.callTimeout, isTrue);
      },
    );

    test('announcements round-trip across every supported serializer', () {
      final json = json_serializer.Serializer();
      final msgpack = msgpack_serializer.Serializer();
      final cbor = cbor_serializer.Serializer();
      final roundTrips = <AbstractMessage Function(AbstractMessage)>[
        (message) => json.deserialize(
          Uint8List.fromList(utf8.encode(json.serializeToString(message))),
        )!,
        (message) => msgpack.deserialize(msgpack.serialize(message))!,
        (message) => cbor.deserialize(cbor.serialize(message))!,
      ];

      for (final roundTrip in roundTrips) {
        final hello = Hello('realm1', Details.forHello());
        final decodedHello = roundTrip(hello) as Hello;
        expect(
          decodedHello
              .details
              .roles!
              .subscriber!
              .features!
              .patternBasedSubscription,
          isTrue,
        );
        expect(
          decodedHello.details.roles!.callee!.features!.callCanceling,
          isTrue,
        );
        expect(
          decodedHello
              .details
              .roles!
              .caller!
              .features!
              .progressiveCallInvocations,
          isTrue,
        );

        final welcome = Welcome(1, Details.forWelcome(realm: 'realm1'));
        final decodedWelcome = roundTrip(welcome) as Welcome;
        expect(
          decodedWelcome
              .details
              .roles!
              .broker!
              .features!
              .patternBasedSubscription,
          isTrue,
        );
        expect(
          decodedWelcome.details.roles!.dealer!.features!.callCanceling,
          isTrue,
        );
        expect(
          decodedWelcome
              .details
              .roles!
              .dealer!
              .features!
              .progressiveCallInvocations,
          isTrue,
        );
        expect(
          decodedWelcome.details.roles!.dealer!.features!.registrationMetaApi,
          isTrue,
        );
      }
    });

    test('decodes the standard Broker publication trust-level key', () {
      final serializer = json_serializer.Serializer();
      final welcome =
          serializer.deserialize(
                Uint8List.fromList(
                  utf8.encode(
                    jsonEncode([
                      MessageTypes.codeWelcome,
                      1,
                      {
                        'roles': {
                          'broker': {
                            'features': {'publication_trustlevels': true},
                          },
                        },
                      },
                    ]),
                  ),
                ),
              )
              as Welcome;

      expect(
        welcome.details.roles!.broker!.features!.publicationTrustLevels,
        isTrue,
      );
    });
  });
}

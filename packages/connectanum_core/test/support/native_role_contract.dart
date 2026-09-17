import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

// Expected wire-to-property contracts, independent of production serializers.
final _features = <String, Map<String, bool Function(Roles)>>{
  'publisher': {
    'publisher_identification': (r) =>
        r.publisher!.features!.publisherIdentification,
    'subscriber_blackwhite_listing': (r) =>
        r.publisher!.features!.subscriberBlackWhiteListing,
    'publisher_exclusion': (r) => r.publisher!.features!.publisherExclusion,
    'payload_passthru_mode': (r) => r.publisher!.features!.payloadPassThruMode,
  },
  'broker': {
    'publisher_identification': (r) =>
        r.broker!.features!.publisherIdentification,
    'publication_trustlevels': (r) =>
        r.broker!.features!.publicationTrustLevels,
    'pattern_based_subscription': (r) =>
        r.broker!.features!.patternBasedSubscription,
    'subscription_meta_api': (r) => r.broker!.features!.subscriptionMetaApi,
    'subscriber_blackwhite_listing': (r) =>
        r.broker!.features!.subscriberBlackWhiteListing,
    'session_meta_api': (r) => r.broker!.features!.sessionMetaApi,
    'publisher_exclusion': (r) => r.broker!.features!.publisherExclusion,
    'event_history': (r) => r.broker!.features!.eventHistory,
    'payload_passthru_mode': (r) => r.broker!.features!.payloadPassThruMode,
  },
  'subscriber': {
    'publisher_identification': (r) =>
        r.subscriber!.features!.publisherIdentification,
    'publication_trustlevels': (r) =>
        r.subscriber!.features!.publicationTrustLevels,
    'pattern_based_subscription': (r) =>
        r.subscriber!.features!.patternBasedSubscription,
    'subscription_revocation': (r) =>
        r.subscriber!.features!.subscriptionRevocation,
    'payload_passthru_mode': (r) => r.subscriber!.features!.payloadPassThruMode,
  },
  'dealer': {
    'caller_identification': (r) => r.dealer!.features!.callerIdentification,
    'call_trustlevels': (r) => r.dealer!.features!.callTrustLevels,
    'pattern_based_registration': (r) =>
        r.dealer!.features!.patternBasedRegistration,
    'registration_meta_api': (r) => r.dealer!.features!.registrationMetaApi,
    'shared_registration': (r) => r.dealer!.features!.sharedRegistration,
    'session_meta_api': (r) => r.dealer!.features!.sessionMetaApi,
    'call_timeout': (r) => r.dealer!.features!.callTimeout,
    'call_canceling': (r) => r.dealer!.features!.callCanceling,
    'progressive_call_invocations': (r) =>
        r.dealer!.features!.progressiveCallInvocations,
    'progressive_call_results': (r) =>
        r.dealer!.features!.progressiveCallResults,
    'payload_passthru_mode': (r) => r.dealer!.features!.payloadPassThruMode,
  },
  'callee': {
    'caller_identification': (r) => r.callee!.features!.callerIdentification,
    'call_trustlevels': (r) => r.callee!.features!.callTrustlevels,
    'pattern_based_registration': (r) =>
        r.callee!.features!.patternBasedRegistration,
    'shared_registration': (r) => r.callee!.features!.sharedRegistration,
    'call_timeout': (r) => r.callee!.features!.callTimeout,
    'call_canceling': (r) => r.callee!.features!.callCanceling,
    'progressive_call_invocations': (r) =>
        r.callee!.features!.progressiveCallInvocations,
    'progressive_call_results': (r) =>
        r.callee!.features!.progressiveCallResults,
    'payload_passthru_mode': (r) => r.callee!.features!.payloadPassThruMode,
  },
  'caller': {
    'caller_identification': (r) => r.caller!.features!.callerIdentification,
    'call_timeout': (r) => r.caller!.features!.callTimeout,
    'call_canceling': (r) => r.caller!.features!.callCanceling,
    'progressive_call_invocations': (r) =>
        r.caller!.features!.progressiveCallInvocations,
    'progressive_call_results': (r) =>
        r.caller!.features!.progressiveCallResults,
    'payload_passthru_mode': (r) => r.caller!.features!.payloadPassThruMode,
  },
};

Map<String, Object?> _roles(Roles r) => {
  'publisher': r.publisher,
  'broker': r.broker,
  'subscriber': r.subscriber,
  'dealer': r.dealer,
  'callee': r.callee,
  'caller': r.caller,
};

Map<String, Object?> _featureObjects(Roles r) => {
  'publisher': r.publisher?.features,
  'broker': r.broker?.features,
  'subscriber': r.subscriber?.features,
  'dealer': r.dealer?.features,
  'callee': r.callee?.features,
  'caller': r.caller?.features,
};

void nativeRoleContracts(Details Function(Map<String, Object?>) decode) {
  for (final role in _features.entries) {
    group(role.key, () {
      for (final field in [null, ...role.value.keys, 'unknown_feature']) {
        for (final value in <bool?>[null, false, true]) {
          test('$field=$value preserves only the announced capability', () {
            final details = decode({
              'roles': {
                role.key: {
                  'features': {if (field != null) field: value},
                },
              },
            });
            final roles = details.roles!;
            expect(
              _roles(
                roles,
              ).entries.where((e) => e.value != null).map((e) => e.key),
              [role.key],
            );
            for (final feature in role.value.entries) {
              expect(
                feature.value(roles),
                feature.key == field && value == true,
                reason: '${role.key}.${feature.key}',
              );
            }
            expect(details.custom, isEmpty);
          });
        }
      }
      for (final body in <Map<String, Object?>>[
        {},
        {'features': null},
      ]) {
        test('role without features $body stays unadvertised', () {
          final roles = decode({
            'roles': {role.key: body},
          }).roles!;
          expect(_roles(roles)[role.key], isNotNull);
          expect(_featureObjects(roles).values, everyElement(isNull));
        });
      }
    });
  }

  for (final reflection in <bool?>[null, false, true]) {
    test('dealer reflection preserves $reflection', () {
      final roles = decode({
        'roles': {
          'dealer': {'reflection': reflection},
        },
      }).roles!;
      expect(roles.dealer!.reflection, reflection);
      expect(roles.dealer!.features, isNull);
    });
  }

  for (final canonical in <bool?>[null, false, true]) {
    for (final alias in [false, true]) {
      test('broker trust-level canonical=$canonical precedes alias=$alias', () {
        final roles = decode({
          'roles': {
            'broker': {
              'features': {
                'publication_trustlevels': canonical,
                'publication_trust_levels': alias,
              },
            },
          },
        }).roles!;
        expect(
          roles.broker!.features!.publicationTrustLevels,
          canonical ?? alias,
        );
      });
    }
  }

  test('absent roles stay absent', () {
    expect(decode({}).roles, isNull);
    expect(decode({'roles': null}).roles, isNull);
  });

  test('empty and unknown roles do not instantiate supported roles', () {
    for (final roles in <Map<String, Object?>>[
      {},
      {
        'unknown': {
          'features': {'call_timeout': true},
        },
      },
    ]) {
      expect(
        _roles(decode({'roles': roles}).roles!).values,
        everyElement(isNull),
      );
    }
  });

  test('each message owns its feature state', () {
    final first = decode({
      'roles': {
        'caller': {
          'features': {'call_timeout': true},
        },
      },
    }).roles!;
    final second = decode({
      'roles': {
        'caller': {'features': {}},
      },
    }).roles!;
    first.caller!.features!.payloadPassThruMode = true;
    expect(second.caller!.features!.callTimeout, isFalse);
    expect(second.caller!.features!.payloadPassThruMode, isFalse);
  });
}

void nativeAbortContracts(
  Abort Function(Map<String, Object?>, List<Object?>?, Map<String, Object?>?)
  decode,
) {
  test('ABORT rejects a non-text message', () {
    expect(
      () => decode({'message': 12}, null, null),
      throwsA(isA<TypeError>()),
    );
  });
  for (final details in <Map<String, Object?>>[
    {},
    {'message': null},
    {'message': ''},
    {'message': 'denied', 'trace': 'abort-1'},
    {
      'retry': false,
      'reason_details': {'attempt': 2},
    },
  ]) {
    test('ABORT preserves optional details $details', () {
      final value = decode(details, null, null);
      expect(value.reason, 'wamp.error.not_authorized');
      expect(value.details, details);
      expect(value.message?.message, details['message']);
      expect(value.arguments, isNull);
      expect(value.argumentsKeywords, isNull);
    });
  }
  for (final args in <List<Object?>>[
    [],
    [1, 'explanation'],
  ]) {
    for (final kwargs in <Map<String, Object?>?>[
      null,
      {},
      {'retry': false},
    ]) {
      test('ABORT preserves payload $args $kwargs', () {
        final value = decode({'message': 'denied'}, args, kwargs);
        expect(value.arguments, args);
        expect(value.argumentsKeywords, kwargs);
        expect(value.reason, 'wamp.error.not_authorized');
      });
    }
  }
}

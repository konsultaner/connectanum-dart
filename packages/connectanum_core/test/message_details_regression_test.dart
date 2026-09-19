import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

class _Field<T> {
  const _Field(
    this.name,
    this.wire,
    this.expected,
    this.preset,
    this.read,
    this._write,
  );

  final String name;
  final Object? wire;
  final Object? expected;
  final T preset;
  final T? Function(Details) read;
  final void Function(Details, T?) _write;

  void write(Details details, Object? value) => _write(details, value as T?);
}

final _featureReaders = <String, Map<String, bool Function(Roles)>>{
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

void main() {
  group('individual remote feature announcements', () {
    for (final role in _featureReaders.entries) {
      for (final key in [null, ...role.value.keys]) {
        for (final value in <bool?>[null, false, true]) {
          test('${role.key} $key=$value never enables another capability', () {
            final details = Details()
              ..setLazyFieldsLoader(
                () => {
                  'roles': {
                    role.key: {
                      'features': {?key: value},
                    },
                  },
                },
              );
            Roles? roles;
            expect(() => roles = details.roles, returnsNormally);
            expect(roles, isNotNull);
            final advertisedFeatures = switch (role.key) {
              'publisher' => roles!.publisher?.features,
              'broker' => roles!.broker?.features,
              'subscriber' => roles!.subscriber?.features,
              'dealer' => roles!.dealer?.features,
              'callee' => roles!.callee?.features,
              'caller' => roles!.caller?.features,
              _ => throw StateError('Unknown test role ${role.key}'),
            };
            expect(advertisedFeatures, isNotNull, reason: role.key);
            for (final feature in role.value.entries) {
              expect(
                feature.value(roles!),
                feature.key == key && value == true,
                reason: '${role.key}.${feature.key}',
              );
            }
          });
        }
      }
    }

    test('deprecated subscriber RPC fields do not announce capabilities', () {
      final features = SubscriberFeatures();
      // These compatibility fields remain readable but do not describe pub/sub.
      // ignore: deprecated_member_use_from_same_package
      expect(features.callTimeout, isFalse);
      // ignore: deprecated_member_use_from_same_package
      expect(features.callCanceling, isFalse);
      // ignore: deprecated_member_use_from_same_package
      expect(features.progressiveCallResults, isFalse);
    });

    for (final canonical in <bool?>[null, false, true]) {
      for (final alias in [false, true]) {
        test(
          'broker trust-level canonical=$canonical takes priority over alias=$alias',
          () {
            final details = Details()
              ..setLazyFieldsLoader(
                () => {
                  'roles': {
                    'broker': {
                      'features': {
                        'publication_trustlevels': canonical,
                        'publication_trust_levels': alias,
                      },
                    },
                  },
                },
              );
            expect(
              details.roles!.broker!.features!.publicationTrustLevels,
              canonical ?? alias,
            );
          },
        );
      }
    }
  });

  final fields = <_Field<dynamic>>[
    _Field<String>(
      'agent',
      'wire-agent',
      'wire-agent',
      'local-agent',
      (d) => d.agent,
      (d, v) => d.agent = v,
    ),
    _Field<String>(
      'realm',
      'wire.realm',
      'wire.realm',
      'local.realm',
      (d) => d.realm,
      (d, v) => d.realm = v,
    ),
    _Field<List<String>>(
      'authmethods',
      ['scram'],
      ['scram'],
      ['ticket'],
      (d) => d.authmethods,
      (d, v) => d.authmethods = v,
    ),
    _Field<String>(
      'authid',
      'wire-user',
      'wire-user',
      'local-user',
      (d) => d.authid,
      (d, v) => d.authid = v,
    ),
    _Field<String>(
      'authrole',
      'wire-role',
      'wire-role',
      'local-role',
      (d) => d.authrole,
      (d, v) => d.authrole = v,
    ),
    _Field<String>(
      'authmethod',
      'scram',
      'scram',
      'ticket',
      (d) => d.authmethod,
      (d, v) => d.authmethod = v,
    ),
    _Field<String>(
      'authprovider',
      'wire-provider',
      'wire-provider',
      'local-provider',
      (d) => d.authprovider,
      (d, v) => d.authprovider = v,
    ),
    _Field<Map<String, dynamic>>(
      'authextra',
      {'nonce': 'wire'},
      {'nonce': 'wire'},
      {'nonce': 'local'},
      (d) => d.authextra,
      (d, v) => d.authextra = v,
    ),
    _Field<String>(
      'nonce',
      'wire-nonce',
      'wire-nonce',
      'local-nonce',
      (d) => d.nonce,
      (d, v) => d.nonce = v,
    ),
    _Field<String>(
      'challenge',
      'wire-challenge',
      'wire-challenge',
      'local-challenge',
      (d) => d.challenge,
      (d, v) => d.challenge = v,
    ),
    _Field<int>(
      'iterations',
      0,
      0,
      73,
      (d) => d.iterations,
      (d, v) => d.iterations = v,
    ),
    _Field<int>('keylen', 0, 0, 32, (d) => d.keylen, (d, v) => d.keylen = v),
    _Field<bool>(
      'progress',
      false,
      false,
      true,
      (d) => d.progress,
      (d, v) => d.progress = v,
    ),
    _Field<String>(
      'salt',
      'wire-salt',
      'wire-salt',
      'local-salt',
      (d) => d.salt,
      (d, v) => d.salt = v,
    ),
    _Field<Uri>(
      'topic',
      'com.example.topic',
      Uri.parse('com.example.topic'),
      Uri.parse('com.example.local_topic'),
      (d) => d.topic,
      (d, v) => d.topic = v,
    ),
    _Field<Uri>(
      'procedure',
      'com.example.work',
      Uri.parse('com.example.work'),
      Uri.parse('com.example.local_work'),
      (d) => d.procedure,
      (d, v) => d.procedure = v,
    ),
    _Field<int>(
      'trustlevel',
      0,
      0,
      7,
      (d) => d.trustlevel,
      (d, v) => d.trustlevel = v,
    ),
    _Field<Roles>(
      'roles',
      {
        'dealer': {
          'features': {'call_timeout': false},
        },
      },
      isA<Roles>().having(
        (r) => r.dealer?.features?.callTimeout,
        'call timeout',
        false,
      ),
      Roles()..dealer = (Dealer()..reflection = true),
      (d) => d.roles,
      (d, v) => d.roles = v,
    ),
  ];

  for (final field in fields) {
    group('Details ${field.name}', () {
      test('empty, explicit assignment and clearing do not need a loader', () {
        final details = Details();
        expect(field.read(details), isNull);
        field.write(details, field.preset);
        expect(field.read(details), field.preset);
        field.write(details, null);
        expect(field.read(details), isNull);
      });

      test('loads once on first read and retains the decoded value', () {
        final details = Details();
        var loads = 0;
        details.setLazyFieldsLoader(() {
          loads++;
          return {field.name: field.wire, 'marker': 'loaded'};
        });
        expect(loads, 0);
        expect(field.read(details), field.expected);
        expect(loads, 1);
        expect(field.read(details), field.expected);
        expect(details.custom, {'marker': 'loaded'});
        expect(loads, 1);
      });

      test(
        'explicit value wins without prematurely loading remaining fields',
        () {
          final details = Details();
          field.write(details, field.preset);
          var loads = 0;
          details.setLazyFieldsLoader(() {
            loads++;
            return {field.name: field.wire, 'marker': 'loaded'};
          });
          expect(field.read(details), field.preset);
          expect(loads, 0);
          expect(details.custom['marker'], 'loaded');
          expect(loads, 1);
          expect(field.read(details), field.preset);
          field.write(details, null);
          expect(field.read(details), isNull);
          expect(loads, 1);
        },
      );

      for (final present in [false, true]) {
        test('missing value is loaded only once, explicitNull=$present', () {
          var loads = 0;
          final details = Details()
            ..setLazyFieldsLoader(() {
              loads++;
              return {if (present) field.name: null};
            });
          expect(field.read(details), isNull);
          expect(field.read(details), isNull);
          expect(details.custom, isEmpty);
          expect(loads, 1);
        });
      }
    });
  }

  group('Details loader composition', () {
    test('queued loaders run in order with later wire values winning', () {
      final calls = <String>[];
      final details = Details();
      details.setLazyFieldsLoader(() {
        calls.add('first');
        return {'realm': 'first.realm', 'authid': 'first-user', 'first': 1};
      });
      details.setLazyFieldsLoader(() {
        calls.add('second');
        return {'realm': 'second.realm', 'second': 2};
      });
      expect(calls, isEmpty);
      expect(details.realm, 'second.realm');
      expect(details.authid, 'first-user');
      expect(details.custom, {'first': 1, 'second': 2});
      expect(calls, ['first', 'second']);
    });

    test(
      'new loader fills cleared fields without replacing materialized fields',
      () {
        final details = Details()
          ..setLazyFieldsLoader(
            () => {
              'realm': 'first.realm',
              'authid': 'first-user',
            },
          );
        expect(details.realm, 'first.realm');
        details.realm = null;
        details.setLazyFieldsLoader(
          () => {
            'realm': 'second.realm',
            'authid': 'second-user',
          },
        );
        expect(details.realm, 'second.realm');
        expect(details.authid, 'first-user');
      },
    );

    test('instances cannot share pending metadata or custom maps', () {
      final calls = <int>[];
      final instances = List.generate(
        2,
        (i) => Details()
          ..setLazyFieldsLoader(() {
            calls.add(i);
            return {'authid': 'user-$i', 'marker': i};
          }),
      );
      expect(instances[1].authid, 'user-1');
      expect(calls, [1]);
      expect(instances[0].custom['marker'], 0);
      expect(instances[0].authid, 'user-0');
      expect(instances[1].custom['marker'], 1);
      expect(calls, [1, 0]);
      instances[0].custom.clear();
      expect(instances[1].custom, {'marker': 1});
    });

    test(
      'auth extra and custom metadata have independent deferred loaders',
      () {
        final calls = <String>[];
        final details = Details();
        details.setLazyAuthExtraLoader(() {
          calls.add('auth');
          return {'nonce': 'loaded-nonce'};
        });
        details.setLazyCustomFieldsLoader(() {
          calls.add('custom');
          return {'marker': 'loaded'};
        });
        details.setLazyFieldsLoader(() {
          calls.add('fields');
          return {'agent': 'consumer-agent'};
        });
        expect(calls, isEmpty);
        expect(details.authextra!['nonce'], 'loaded-nonce');
        expect(calls, ['auth']);
        expect(details.agent, 'consumer-agent');
        expect(calls, ['auth', 'fields']);
        expect(details.custom['marker'], 'loaded');
        expect(calls, ['auth', 'fields', 'custom']);
        expect(details.authextra, {'nonce': 'loaded-nonce'});
        expect(details.custom, {'marker': 'loaded'});
      },
    );

    test('a failed loader propagates and can be replaced explicitly', () {
      final failure = StateError('synthetic loader failure');
      final details = Details()..authid = 'explicit-user';
      details.setLazyFieldsLoader(() => throw failure);
      expect(() => details.realm, throwsA(same(failure)));
      expect(details.authid, 'explicit-user');
      details.setLazyFieldsLoader(() => {'realm': 'recovered.realm'});
      expect(details.realm, 'recovered.realm');
      expect(details.authid, 'explicit-user');
    });
  });

  for (final role in [
    'publisher',
    'broker',
    'subscriber',
    'dealer',
    'callee',
    'caller',
  ]) {
    test('empty $role announcement does not fabricate feature support', () {
      final details = Details()
        ..setLazyFieldsLoader(
          () => {
            'roles': {role: <String, Object?>{}},
          },
        );
      final roles = details.roles!;
      final (Object? selected, Object? features) = switch (role) {
        'publisher' => (roles.publisher, roles.publisher?.features),
        'broker' => (roles.broker, roles.broker?.features),
        'subscriber' => (roles.subscriber, roles.subscriber?.features),
        'dealer' => (roles.dealer, roles.dealer?.features),
        'callee' => (roles.callee, roles.callee?.features),
        _ => (roles.caller, roles.caller?.features),
      };
      expect(selected, isNotNull);
      expect(features, isNull);
    });
  }

  test('malformed optional URIs do not become procedure or topic values', () {
    final details = Details()
      ..setLazyFieldsLoader(
        () => {
          'topic': 'http://[',
          'procedure': 'http://[',
        },
      );
    expect(details.topic, isNull);
    expect(details.procedure, isNull);
  });
}

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

Map<String, dynamic> _profile() => {
  'required': true,
  'version': 1,
  'established': true,
  'scheme': 'wamp',
  'serializer': 'cbor',
  'cipher': 'xsalsa20poly1305',
  'send_key_id': 'send',
  'receive_key_id': 'receive',
};

void main() {
  for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
    test(
      'required profile negotiates exact provider parameters for $cipher',
      () {
        final provider = _ProfileProvider();
        final raw = _profile()..['cipher'] = cipher;
        _expectAccepted(raw, provider);
        expect(provider.calls, [
          {
            'version': 1,
            'scheme': 'wamp',
            'serializer': 'cbor',
            'cipher': cipher,
          },
        ]);
      },
    );
  }

  for (final field in {
    'version': <Object?>[null, 0, 2, '1'],
    'established': <Object?>[null, false, 'true', 1, 1.0],
    'scheme': <Object?>[null, '', 'other'],
    'serializer': <Object?>[null, '', 'json'],
    'cipher': <Object?>[null, '', 'plaintext', 'chacha20poly1305'],
  }.entries) {
    for (final value in field.value) {
      test(
        'required profile rejects ${field.key}=$value before provider use',
        () {
          final provider = _ProfileProvider();
          final raw = _profile()..[field.key] = value;
          expect(
            () => NegotiatedSessionE2ee(
              raw,
            ).verifyRequiredProfile(provider: provider),
            throwsA(isA<SessionE2eeNegotiationException>()),
          );
          expect(provider.calls, isEmpty);
        },
      );
    }
  }

  for (final provider in <WampE2eeProvider?>[null, _NoProfileProvider()]) {
    test(
      'required profile rejects missing capability on ${provider.runtimeType}',
      () {
        expect(
          () => NegotiatedSessionE2ee(
            _profile(),
          ).verifyRequiredProfile(provider: provider),
          throwsA(
            isA<SessionE2eeNegotiationException>().having(
              (error) => error.reason,
              'reason',
              provider == null
                  ? 'Required E2EE has no configured or resolved payload provider'
                  : 'Required E2EE provider does not declare profile support',
            ),
          ),
        );
      },
    );
  }

  for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
    test('provider rejects $cipher and captures read-only profile fields', () {
      final provider = _ProfileProvider(supported: false);
      final raw = _profile()..['cipher'] = cipher;
      SessionE2eeNegotiationException? failure;
      try {
        NegotiatedSessionE2ee(raw).verifyRequiredProfile(provider: provider);
      } on SessionE2eeNegotiationException catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      final reason =
          'Required E2EE provider does not support the negotiated '
          'wamp/cbor/$cipher profile';
      expect(failure!.reason, reason);
      expect(failure.toString(), 'SessionE2eeNegotiationException: $reason');
      raw['cipher'] = 'changed';
      expect(failure.negotiated['cipher'], cipher);
      expect(
        () => failure!.negotiated['cipher'] = 'changed',
        throwsUnsupportedError,
      );
      expect(provider.calls, hasLength(1));
    });
  }

  for (final keys in [
    <String, dynamic>{
      'send_key_id': 's',
      'receive_key_id': 'r',
      'peer_key_id': 'p',
      'accepted_key_id': 'a',
    },
    <String, dynamic>{'peer_key_id': 'p', 'accepted_key_id': 'a'},
    <String, dynamic>{'accepted_key_id': 'a', 'key_id': 'legacy'},
    <String, dynamic>{'peer_key_id': 'p'},
    <String, dynamic>{'key_id': 'legacy'},
    <String, dynamic>{'send_key_id': 's', 'key_id': 'legacy'},
    <String, dynamic>{'receive_key_id': 'r', 'key_id': 'legacy'},
  ].indexed) {
    const expected = [
      ('s', 'r'),
      ('p', 'a'),
      ('a', 'a'),
      ('p', 'p'),
      ('legacy', 'legacy'),
      ('s', 'legacy'),
      ('legacy', 'r'),
    ];
    test('key selection preserves directional precedence case ${keys.$1}', () {
      final raw = _profile()
        ..remove('send_key_id')
        ..remove('receive_key_id');
      raw.addAll(keys.$2);
      final negotiated = NegotiatedSessionE2ee(raw);
      expect(negotiated.outboundKeyId, expected[keys.$1].$1);
      expect(negotiated.inboundKeyId, expected[keys.$1].$2);
      _expectAccepted(raw, _ProfileProvider());
    });
  }

  for (final retained in <String?>[null, 'send_key_id', 'receive_key_id']) {
    test('missing key direction rejects with only $retained retained', () {
      final raw = _profile()
        ..remove('send_key_id')
        ..remove('receive_key_id');
      if (retained != null) raw[retained] = 'one-direction';
      final provider = _ProfileProvider();
      expect(
        () => NegotiatedSessionE2ee(
          raw,
        ).verifyRequiredProfile(provider: provider),
        throwsA(
          isA<SessionE2eeNegotiationException>().having(
            (error) => error.reason,
            'reason',
            'Required E2EE must select outbound and inbound key ids',
          ),
        ),
      );
      expect(provider.calls, isEmpty);
    });
  }

  for (final field in ['scheme', 'serializer', 'cipher']) {
    test('$field prefers canonical metadata over selected alias', () {
      final raw = _profile()..['selected_$field'] = 'fallback';
      String? read() => switch (field) {
        'scheme' => NegotiatedSessionE2ee(raw).scheme,
        'serializer' => NegotiatedSessionE2ee(raw).serializer,
        _ => NegotiatedSessionE2ee(raw).cipher,
      };
      final original = raw[field];
      expect(read(), original);
      raw[field] = null;
      expect(read(), 'fallback');
      raw.remove('selected_$field');
      expect(read(), isNull);
    });
  }

  test('optional absent profile does not require or invoke a provider', () {
    final provider = _ProfileProvider(supported: false);
    _expectAccepted({}, null);
    _expectAccepted({'required': false}, provider);
    expect(provider.calls, isEmpty);
  });

  test('negotiated metadata exposes public key and key-exchange fields', () {
    final negotiated = NegotiatedSessionE2ee({
      'kex': 'x25519',
      'client_pubkey': 'client',
      'server_pubkey': 'server',
      'peer_pubkey': 'peer',
      'custom': 'extension',
    });
    expect(negotiated.kex, 'x25519');
    expect(negotiated.clientPublicKey, 'client');
    expect(negotiated.serverPublicKey, 'server');
    expect(negotiated.peerPublicKey, 'peer');
    expect(negotiated['custom'], 'extension');
    expect(negotiated['absent'], isNull);
  });
}

void _expectAccepted(Map<String, dynamic> raw, WampE2eeProvider? provider) {
  SessionE2eeNegotiationException? rejection;
  try {
    NegotiatedSessionE2ee(raw).verifyRequiredProfile(provider: provider);
  } on SessionE2eeNegotiationException catch (error) {
    rejection = error;
  }
  expect(rejection, isNull, reason: 'A compatible profile must be accepted');
}

class _NoProfileProvider implements WampE2eeProvider {
  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw StateError('Negotiation must not pack payloads');

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw StateError('Negotiation must not unpack payloads');
}

class _ProfileProvider extends _NoProfileProvider
    implements WampE2eeProfileSupport {
  _ProfileProvider({this.supported = true});
  final bool supported;
  final calls = <Map<String, Object>>[];

  @override
  bool supportsE2eeProfile({
    required int version,
    required String scheme,
    required String serializer,
    required String cipher,
  }) {
    calls.add({
      'version': version,
      'scheme': scheme,
      'serializer': serializer,
      'cipher': cipher,
    });
    return supported;
  }
}

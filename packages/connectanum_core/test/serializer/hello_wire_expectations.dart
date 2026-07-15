List<Object?> expectedHelloWire(
  String? realm, {
  String? authId,
  List<String>? authMethods,
  Map<String, dynamic>? authExtra,
}) {
  final details = <String, Object?>{
    'roles': {
      'caller': {
        'features': {
          'call_canceling': true,
          'call_timeout': true,
          'caller_identification': true,
          'payload_passthru_mode': true,
          'progressive_call_invocations': true,
          'progressive_call_results': true,
        },
      },
      'callee': {
        'features': {
          'caller_identification': true,
          'call_trustlevels': false,
          'pattern_based_registration': true,
          'shared_registration': true,
          'call_timeout': true,
          'call_canceling': true,
          'progressive_call_invocations': true,
          'progressive_call_results': true,
          'payload_passthru_mode': true,
        },
      },
      'subscriber': {
        'features': {
          'publisher_identification': true,
          'publication_trustlevels': true,
          'pattern_based_subscription': true,
          'payload_passthru_mode': true,
          'subscription_revocation': true,
        },
      },
      'publisher': {
        'features': {
          'publisher_identification': true,
          'subscriber_blackwhite_listing': true,
          'publisher_exclusion': true,
          'payload_passthru_mode': true,
        },
      },
    },
    'authid': ?authId,
    'authmethods': ?authMethods,
    'authextra': ?authExtra,
  };
  return [1, realm, details];
}

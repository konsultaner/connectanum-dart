import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:test/test.dart';

void main() {
  final flatCodec = flat.Serializer();
  final jsonCodec = json.Serializer();
  const ppt = {
    'ppt_scheme': 'x_profile',
    'ppt_serializer': 'flatbuffers',
    'ppt_cipher': 'x_cipher',
    'ppt_keyid': 'key-1',
  };
  const vendor = {
    'x_vendor': {
      'nested': ['retained', 42],
    },
  };
  for (final enabled in [false, true]) {
    final details = {
      'authid': 'user',
      'authrole': 'role',
      'authmethod': 'ticket',
      'authprovider': 'static',
      'authmethods': ['ticket', 'wampcra'],
      'authextra': {'channel_binding': 'tls-unique'},
      'realm': 'realm',
      'agent': 'consumer',
      'nonce': 'nonce',
      'challenge': 'challenge',
      'iterations': 1000,
      'keylen': 32,
      'progress': enabled,
      'salt': 'salt',
      'topic': 'com.topic',
      'procedure': 'com.proc',
      'trustlevel': 2,
      ...vendor,
      'roles': {
        for (final role in [
          'caller',
          'callee',
          'publisher',
          'subscriber',
          'dealer',
          'broker',
        ])
          role: {
            'features': {
              for (final feature in [
                'call_canceling',
                'call_timeout',
                'caller_identification',
                'payload_passthru_mode',
                'progressive_call_invocations',
                'progressive_call_results',
                'call_trustlevels',
                'pattern_based_registration',
                'shared_registration',
                'publisher_identification',
                'publication_trustlevels',
                'pattern_based_subscription',
                'subscription_revocation',
                'session_meta_api',
                'subscription_meta_api',
                'registration_meta_api',
                'registration_revocation',
                'subscriber_blackwhite_listing',
                'publisher_exclusion',
                'event_retention',
              ])
                feature: enabled,
            },
          },
      },
    };
    final messages = <String, List<Object?>>{
      'hello': [1, 'realm', details],
      'welcome': [2, 123, details],
      'publish': [
        16,
        19,
        {
          'acknowledge': enabled,
          'exclude_me': enabled,
          'disclose_me': enabled,
          'retain': enabled,
          'exclude': [10, 11],
          'eligible': [12, 13],
          'exclude_authid': ['user-a'],
          'exclude_authrole': ['role-a'],
          'eligible_authid': ['user-b'],
          'eligible_authrole': ['role-b'],
          ...ppt,
          ...vendor,
        },
        'com.topic',
      ],
      'subscribe': [
        32,
        19,
        {
          'get_retained': enabled,
          'match': 'prefix',
          'meta_topic': 'com.meta',
          ...vendor,
        },
        'com.topic',
      ],
      'event': [
        36,
        19,
        29,
        {
          'publisher': 39,
          'topic': 'com.topic',
          'trustlevel': 2,
          ...ppt,
          ...vendor,
        },
      ],
      'call': [
        48,
        19,
        {
          'timeout': 1000,
          'receive_progress': enabled,
          'progress': enabled,
          'disclose_me': enabled,
          ...ppt,
          ...vendor,
        },
        'com.proc',
      ],
      'register': [
        64,
        19,
        {
          'match': 'wildcard',
          'invoke': 'roundrobin',
          'disclose_caller': enabled,
          'forward_timeout': enabled,
          ...vendor,
        },
        'com.proc',
      ],
      'invocation': [
        68,
        19,
        29,
        {
          'caller': 39,
          'procedure': 'com.proc',
          'progress': enabled,
          'receive_progress': enabled,
          'timeout': 1000,
          ...ppt,
          ...vendor,
        },
      ],
      'yield': [
        70,
        19,
        {'progress': enabled, ...ppt, ...vendor},
      ],
    };
    for (final entry in messages.entries) {
      test(
        '${entry.key} preserves complete metadata with booleans $enabled',
        () {
          final reference = jsonCodec.deserialize(
            Uint8List.fromList(utf8.encode(jsonEncode(entry.value))),
          )!;
          final expected = jsonDecode(jsonCodec.serialize(reference));
          final decoded = flatCodec.deserialize(
            flatCodec.serialize(reference),
          )!;
          expect(jsonDecode(jsonCodec.serialize(decoded)), expected);
          final repeated = flatCodec.deserialize(flatCodec.serialize(decoded))!;
          expect(jsonDecode(jsonCodec.serialize(repeated)), expected);
        },
      );
    }
  }
  for (final role in [
    'caller',
    'callee',
    'publisher',
    'subscriber',
    'dealer',
    'broker',
  ]) {
    test('empty $role capability remains present through encoding', () {
      final reference = jsonCodec.deserialize(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              1,
              'realm',
              {
                'roles': {role: {}},
              },
            ]),
          ),
        ),
      )!;
      final expected = jsonDecode(jsonCodec.serialize(reference));
      final actual = flatCodec.deserialize(flatCodec.serialize(reference))!;
      expect(jsonDecode(jsonCodec.serialize(actual)), expected);
    });
  }
}

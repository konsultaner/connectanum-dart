import 'dart:typed_data';
import 'dart:collection';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:pinenacl/x25519.dart' show SecretBox;
import 'package:test/test.dart';

import 'support/e2ee_assertions.dart';

Uint8List _key([int seed = 0]) =>
    Uint8List.fromList(List.generate(32, (index) => (seed + index) % 256));

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var index = 0; index < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
]);

WampCborXsalsa20Poly1305Provider _provider({
  bool aes = false,
  Map<String, List<int>>? keys,
  String? defaultKeyId,
  WampE2eeKeySelectionPolicy? policy,
}) => aes
    ? WampCborAes256GcmProvider(
        keys: keys ?? {'key': _key(240)},
        defaultKeyId: defaultKeyId,
        keySelectionPolicy: policy,
      )
    : WampCborXsalsa20Poly1305Provider(
        keys: keys ?? {'key': _key(240)},
        defaultKeyId: defaultKeyId,
        keySelectionPolicy: policy,
      );

const _local = WampE2eePartyContext(
  sessionId: 1,
  authId: 'local',
  authRole: 'caller',
  authMethod: 'scram',
  authProvider: 'local-provider',
  authExtra: {'local': true},
  trustLevel: 8,
  details: {'authid': 'local'},
);
const _peer = WampE2eePartyContext(
  sessionId: 2,
  authId: 'peer',
  authRole: 'callee',
  authProvider: 'peer-provider',
  trustLevel: 5,
);
const _context = WampE2eeRuntimeContext(
  direction: WampE2eeDirection.outbound,
  messageType: WampE2eeMessageType.call,
  realm: 'realm',
  uri: 'app.secret',
  local: _local,
  peer: _peer,
  negotiated: {'key_id': 'negotiated'},
  payloadAnchor: 'anchor',
);

void main() {
  group('E2EE byte validation', () {
    test('validates and owns each key byte in a single read', () {
      final bytes = _ReadOnceBytes(_key(240));
      final provider = expectE2eeSuccess(() => _provider(keys: {'key': bytes}));
      expect(bytes.reads, 32);
      final options = PublishOptions();
      final encoded = expectE2eeSuccess(
        () => provider.packPayload(['payload'], null, options),
      );
      expect(
        expectE2eeSuccess(
          () => _provider().unpackPayload(encoded, options),
        ).arguments,
        [
          'payload',
        ],
      );
    });
    test('validates and copies each encrypted list byte in a single read', () {
      final provider = expectE2eeSuccess(() => _provider());
      final options = PublishOptions();
      final encoded =
          expectE2eeSuccess(
                () => provider.packPayload(['payload'], null, options),
              ).single
              as Uint8List;
      final bytes = _ReadOnceBytes(encoded);
      expect(
        expectE2eeSuccess(
          () => provider.unpackPayload([bytes], options),
        ).arguments,
        ['payload'],
      );
      expect(bytes.reads, encoded.length);
    });
    for (final value in [-1, 256]) {
      test('rejects out-of-range key byte $value without narrowing', () {
        final bytes = _key().toList()..[0] = value;
        expect(
          () => WampCborXsalsa20Poly1305Provider.single(
            keyId: 'key',
            key: bytes,
          ),
          throwsArgumentError,
        );
      });
    }

    test('invalid key length errors do not retain or print key bytes', () {
      final secret = _key().sublist(0, 31);
      Object? caught;
      try {
        WampCborXsalsa20Poly1305Provider.single(keyId: 'key', key: secret);
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<ArgumentError>());
      final error = caught! as ArgumentError;
      expect(error.invalidValue, isNot(isA<List>()));
      expect(error.toString(), isNot(contains(secret.toString())));
    });

    for (final delta in [-256, 256]) {
      test('cannot authenticate an out-of-range byte narrowed by $delta', () {
        final provider = WampCborXsalsa20Poly1305Provider.single(
          keyId: 'key',
          key: _key(),
        );
        final options = PublishOptions();
        final packed = provider.packPayload(['secret'], null, options);
        final bytes = List<int>.from(packed.single as Uint8List);
        bytes[0] += delta;
        expect(
          () => provider.unpackPayload([bytes], options),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
      });
    }

    for (final value in [-1, 256, 'byte', null, 1.5]) {
      test('rejects malformed encrypted byte $value as a payload error', () {
        final provider = WampCborXsalsa20Poly1305Provider.single(
          keyId: 'key',
          key: _key(),
        );
        final options = PublishOptions();
        final packed = provider.packPayload(['secret'], null, options);
        final bytes = List<dynamic>.from(packed.single as Uint8List);
        bytes[0] = value;
        expect(
          () => provider.unpackPayload([bytes], options),
          throwsA(isA<WampE2eeInvalidPayloadException>()),
        );
      });
    }
  });

  group('E2EE context isolation', () {
    test('each party field independently makes the context nonempty', () {
      for (final party in [
        const WampE2eePartyContext(sessionId: 0),
        const WampE2eePartyContext(authId: ''),
        const WampE2eePartyContext(authRole: ''),
        const WampE2eePartyContext(authMethod: ''),
        const WampE2eePartyContext(authProvider: ''),
        const WampE2eePartyContext(authExtra: {}),
        const WampE2eePartyContext(trustLevel: 0),
        const WampE2eePartyContext(details: {}),
      ]) {
        expect(party.isEmpty, isFalse);
      }
    });

    test('party copy preserves omitted values and clears explicit nulls', () {
      final copy = expectE2eeSuccess(() => _local.copyWith());
      expect(copy.sessionId, 1);
      expect(copy.authId, 'local');
      expect(copy.authRole, 'caller');
      expect(copy.authMethod, 'scram');
      expect(copy.authProvider, 'local-provider');
      expect(copy.authExtra, {'local': true});
      expect(copy.trustLevel, 8);
      expect(copy.details, {'authid': 'local'});
      final cleared = expectE2eeSuccess(
        () => copy.copyWith(
          sessionId: null,
          authId: null,
          authRole: null,
          authMethod: null,
          authProvider: null,
          authExtra: null,
          trustLevel: null,
          details: null,
        ),
      );
      expect(cleared.isEmpty, isTrue);
      expect(copy.isEmpty, isFalse);
      final replaced = copy.copyWith(
        sessionId: 3,
        authId: 'other',
        authRole: 'observer',
        authMethod: 'ticket',
        authProvider: 'other-provider',
        authExtra: {'v': 2},
        trustLevel: 0,
        details: {'v': 3},
      );
      expect(replaced.sessionId, 3);
      expect(replaced.authId, 'other');
      expect(replaced.authRole, 'observer');
      expect(replaced.authMethod, 'ticket');
      expect(replaced.authProvider, 'other-provider');
      expect(replaced.authExtra, {'v': 2});
      expect(replaced.trustLevel, 0);
      expect(replaced.details, {'v': 3});
    });

    test('party details are copied and normalize non-string extra keys', () {
      final extras = <Object?, Object?>{7: 'seven'};
      final details = <String, dynamic>{
        'authid': 'fallback',
        'caller_authid': 'caller',
        'authrole': 'fallback-role',
        'caller_authrole': 'caller-role',
        'authmethod': 'scram',
        'authprovider': 'provider',
        'authextra': extras,
      };
      final party = WampE2eePartyContext.fromDetails(
        sessionId: 7,
        trustLevel: 0,
        details: details,
      );
      details['caller_authid'] = 'changed';
      extras[7] = 'changed';
      expect(party.authId, 'caller');
      expect(party.authRole, 'caller-role');
      expect(party.authMethod, 'scram');
      expect(party.authProvider, 'provider');
      expect(party.authExtra, {'7': 'seven'});
      expect(party.sessionId, 7);
      expect(party.trustLevel, 0);
      expect(
        () => party.details!['authid'] = 'changed',
        throwsUnsupportedError,
      );
      expect(() => party.authExtra!['7'] = 'changed', throwsUnsupportedError);
      expect(
        WampE2eePartyContext.fromDetails(details: {'authextra': 3}).authExtra,
        isNull,
      );
      final stringExtras = <String, dynamic>{'session': 7};
      final fallback = WampE2eePartyContext.fromDetails(
        details: {
          'authid': 'fallback',
          'authrole': 'role',
          'authextra': stringExtras,
        },
      );
      stringExtras['session'] = 8;
      expect(fallback.authId, 'fallback');
      expect(fallback.authRole, 'role');
      expect(fallback.authExtra, {'session': 7});
      expect(() => fallback.authExtra!['session'] = 9, throwsUnsupportedError);
      expect(WampE2eePartyContext.fromDetails().isEmpty, isTrue);
      expect(WampE2eePartyContext.fromDetails(details: {}).isEmpty, isTrue);
      expect(WampE2eePartyContext.fromDetails(sessionId: 0).sessionId, 0);
      expect(WampE2eePartyContext.fromDetails(trustLevel: 0).trustLevel, 0);
    });

    test(
      'runtime copy preserves values, replaces values and clears context',
      () {
        final copy = _context.copyWith();
        expect(copy.direction, WampE2eeDirection.outbound);
        expect(copy.messageType, WampE2eeMessageType.call);
        expect(copy.realm, 'realm');
        expect(copy.uri, 'app.secret');
        expect(copy.local, same(_local));
        expect(copy.peer, same(_peer));
        expect(copy.negotiated, {'key_id': 'negotiated'});
        expect(copy.payloadAnchor, 'anchor');
        final cleared = copy.copyWith(
          direction: WampE2eeDirection.inbound,
          messageType: WampE2eeMessageType.event,
          realm: null,
          uri: null,
          local: null,
          peer: null,
          negotiated: null,
          payloadAnchor: null,
        );
        expect(cleared.direction, WampE2eeDirection.inbound);
        expect(cleared.messageType, WampE2eeMessageType.event);
        expect(cleared.realm, isNull);
        expect(cleared.uri, isNull);
        expect(cleared.local, isNull);
        expect(cleared.peer, isNull);
        expect(cleared.negotiated, isNull);
        expect(cleared.payloadAnchor, isNull);
      },
    );
  });

  group('E2EE key selection', () {
    const rule = WampE2eeKeySelectionRule(
      keyId: 'restricted',
      directions: [WampE2eeDirection.outbound],
      messageTypes: [WampE2eeMessageType.call],
      realms: ['realm'],
      uris: ['app.secret'],
      uriPrefixes: ['app.'],
      localAuthIds: ['local'],
      localAuthRoles: ['caller'],
      localAuthProviders: ['local-provider'],
      peerAuthIds: ['peer'],
      peerAuthRoles: ['callee'],
      peerAuthProviders: ['peer-provider'],
      minPeerTrustLevel: 5,
      maxPeerTrustLevel: 10,
    );
    test('all restrictions match and trust boundaries are inclusive', () {
      expect(rule.matches(_context), isTrue);
      expect(
        rule.matches(_context.copyWith(peer: _peer.copyWith(trustLevel: 10))),
        isTrue,
      );
    });
    final rejected = <String, WampE2eeRuntimeContext Function()>{
      'direction': () =>
          _context.copyWith(direction: WampE2eeDirection.inbound),
      'message type': () => _context.copyWith(
        messageType: WampE2eeMessageType.publish,
      ),
      'realm': () => _context.copyWith(realm: 'other'),
      'missing realm': () => _context.copyWith(realm: null),
      'URI': () => _context.copyWith(uri: 'app.other'),
      'missing URI': () => _context.copyWith(uri: null),
      'local authid': () => _context.copyWith(
        local: _local.copyWith(authId: 'other'),
      ),
      'local role': () => _context.copyWith(
        local: _local.copyWith(authRole: 'other'),
      ),
      'local provider': () => _context.copyWith(
        local: _local.copyWith(authProvider: 'other'),
      ),
      'missing local': () => _context.copyWith(local: null),
      'peer authid': () =>
          _context.copyWith(peer: _peer.copyWith(authId: 'other')),
      'peer role': () =>
          _context.copyWith(peer: _peer.copyWith(authRole: 'other')),
      'peer provider': () => _context.copyWith(
        peer: _peer.copyWith(authProvider: 'other'),
      ),
      'missing peer': () => _context.copyWith(peer: null),
      'low trust': () => _context.copyWith(peer: _peer.copyWith(trustLevel: 4)),
      'high trust': () =>
          _context.copyWith(peer: _peer.copyWith(trustLevel: 11)),
      'missing trust': () => _context.copyWith(
        peer: _peer.copyWith(trustLevel: null),
      ),
    };
    for (final entry in rejected.entries) {
      test('rejects independently mismatched ${entry.key}', () {
        expect(rule.matches(entry.value()), isFalse);
      });
    }
    test('prefix-only rules reject missing and unrelated URIs', () {
      const prefix = WampE2eeKeySelectionRule(
        keyId: 'key',
        uriPrefixes: ['private.', 'app.'],
      );
      expect(prefix.matches(_context), isTrue);
      expect(
        expectE2eeSuccess(() => prefix.matches(_context.copyWith(uri: null))),
        isFalse,
      );
      expect(prefix.matches(_context.copyWith(uri: 'apps.secret')), isFalse);
      const maximum = WampE2eeKeySelectionRule(
        keyId: 'key',
        maxPeerTrustLevel: 10,
      );
      expect(maximum.matches(_context.copyWith(peer: null)), isFalse);
      expect(
        maximum.matches(
          _context.copyWith(peer: _peer.copyWith(trustLevel: null)),
        ),
        isFalse,
      );
    });
    test('missing peer roles cannot match a permissive custom role list', () {
      final rule = WampE2eeKeySelectionRule(
        keyId: 'authenticated',
        peerAuthRoles: _WildcardRoles(),
      );
      expect(rule.matches(_context), isTrue);
      expect(
        rule.matches(_context.copyWith(peer: _peer.copyWith(authRole: null))),
        isFalse,
      );
      expect(rule.matches(_context.copyWith(peer: null)), isFalse);
    });
    test(
      'empty filters are unrestricted rather than requiring an identity',
      () {
        const unrestricted = WampE2eeKeySelectionRule(
          keyId: 'key',
          directions: [],
          messageTypes: [],
          realms: [],
          uris: [],
          uriPrefixes: [],
          localAuthIds: [],
          localAuthRoles: [],
          localAuthProviders: [],
          peerAuthIds: [],
          peerAuthRoles: [],
          peerAuthProviders: [],
        );
        expect(
          unrestricted.matches(
            _context.copyWith(local: null, peer: null, realm: null, uri: null),
          ),
          isTrue,
        );
      },
    );
    for (final direction in WampE2eeDirection.values) {
      test(
        'negotiated $direction key precedence and invalid-value fallback',
        () {
          final order = direction == WampE2eeDirection.outbound
              ? ['send_key_id', 'peer_key_id', 'accepted_key_id', 'key_id']
              : ['receive_key_id', 'accepted_key_id', 'key_id', 'peer_key_id'];
          final keys = <String, dynamic>{
            for (final name in order) name: 'value-$name',
          };
          final policy = WampE2eeKeySelectionPolicies.negotiated();
          for (final name in order) {
            expect(
              policy(
                _context.copyWith(direction: direction, negotiated: keys),
                PublishOptions(),
              ),
              'value-$name',
            );
            keys[name] = 7;
          }
          expect(
            policy(
              _context.copyWith(direction: direction, negotiated: keys),
              PublishOptions(),
            ),
            isNull,
          );
          expect(
            policy(_context.copyWith(negotiated: null), PublishOptions()),
            isNull,
          );
          expect(
            policy(
              _context.copyWith(negotiated: <String, dynamic>{}),
              PublishOptions(),
            ),
            isNull,
          );
        },
      );
    }
    test(
      'policy composition snapshots its list and stops at the first key',
      () {
        var calls = 0;
        final options = PublishOptions();
        final policies = <WampE2eeKeySelectionPolicy?>[
          null,
          (context, seenOptions) {
            expect(context, same(_context));
            expect(seenOptions, same(options));
            calls++;
            return null;
          },
          (_, _) => 'selected',
          (_, _) => throw StateError('not called'),
        ];
        final policy = WampE2eeKeySelectionPolicies.firstDefined(policies);
        policies.clear();
        expect(policy(_context, options), 'selected');
        expect(calls, 1);
        expect(
          WampE2eeKeySelectionPolicies.firstDefined([null, (_, _) => null])(
            _context,
            options,
          ),
          isNull,
        );
        final rules = <WampE2eeKeySelectionRule>[rule];
        final selection = WampE2eeKeySelectionPolicies.rules(
          rules,
          fallbackKeyId: 'fallback',
        );
        rules.clear();
        expect(selection(_context, options), 'restricted');
        expect(selection(_context.copyWith(realm: null), options), 'fallback');
        expect(
          WampE2eeKeySelectionPolicies.rules([])(_context, options),
          isNull,
        );
      },
    );
  });

  for (final aes in [false, true]) {
    group(aes ? 'AES-256-GCM' : 'XSalsa20-Poly1305', () {
      test(
        'provider owns key bytes and explicit key overrides policy/default',
        () {
          final key = _key(240);
          final provider = _provider(
            aes: aes,
            keys: {'explicit': key, 'default': _key()},
            defaultKeyId: 'default',
            policy: (_, _) => throw StateError('not called'),
          );
          key.fillRange(0, key.length, 17);
          final options = PublishOptions(pptKeyId: 'explicit');
          final payload = provider.packPayload(
            ['payload'],
            {'n': 3},
            options,
            runtimeContext: _context,
          );
          final independent = _provider(
            aes: aes,
            keys: {'explicit': _key(240)},
          );
          final decoded = independent.unpackPayload(payload, options);
          expect(decoded.arguments, ['payload']);
          expect(decoded.argumentsKeywords, {'n': 3});
          expect(options.pptKeyId, 'explicit');
          expect(provider.defaultKeyId, 'default');
          expect(provider.keySelectionPolicy, isNotNull);
        },
      );
      test('unknown policy key fails closed rather than using the default', () {
        final provider = _provider(aes: aes, policy: (_, _) => 'missing');
        for (final pack in [true, false]) {
          expect(
            () => pack
                ? provider.packPayload(
                    [],
                    null,
                    PublishOptions(),
                    runtimeContext: _context,
                  )
                : provider.unpackPayload(
                    [Uint8List(40)],
                    PublishOptions(),
                    runtimeContext: _context,
                  ),
            throwsA(
              isA<WampE2eeKeyNotFoundException>().having(
                (error) => error.operation,
                'operation',
                pack ? 'pack' : 'unpack',
              ),
            ),
          );
        }
      });
      test('all malformed outer payload shapes fail before decryption', () {
        final provider = _provider(aes: aes);
        for (final payload in <List<dynamic>?>[
          null,
          [],
          [1, 2],
          [null],
          ['secret'],
          [1],
          [{}],
        ]) {
          expect(
            () => provider.unpackPayload(payload, PublishOptions()),
            throwsA(isA<WampE2eeInvalidPayloadException>()),
          );
        }
      });
      test(
        'nonce, authentication tag and ciphertext are all authenticated',
        () {
          final provider = _provider(aes: aes);
          final options = PublishOptions();
          final bytes =
              provider.packPayload(['payload'], null, options).single
                  as Uint8List;
          // Both formats begin with a nonce. GCM appends its tag; secretbox
          // places its authenticator immediately after the nonce.
          final nonceLength = aes ? 12 : 24;
          for (final offset in [
            0,
            nonceLength - 1,
            nonceLength,
            bytes.length - 1,
          ]) {
            final changed = Uint8List.fromList(bytes)..[offset] ^= 1;
            expect(
              () => provider.unpackPayload([changed], options),
              throwsA(isA<WampE2eeDecryptionException>()),
            );
          }
          for (final length in [
            0,
            1,
            nonceLength - 1,
            nonceLength,
            nonceLength + 15,
          ]) {
            expect(
              () => provider.unpackPayload([Uint8List(length)], options),
              throwsA(isA<WampE2eeDecryptionException>()),
            );
          }
          final wrongKey = _provider(aes: aes, keys: {'key': _key(32)});
          expect(
            () => wrongKey.unpackPayload([bytes], options),
            throwsA(isA<WampE2eeDecryptionException>()),
          );
          final valid = provider.unpackPayload([bytes], options);
          expect(valid.arguments, ['payload']);
        },
      );
      test('profile support matches every field and rejects each mismatch', () {
        final provider = _provider(aes: aes);
        final cipher = aes ? 'aes256gcm' : 'xsalsa20poly1305';
        expect(
          provider.supportsE2eeProfile(
            version: 1,
            scheme: 'wamp',
            serializer: 'cbor',
            cipher: cipher,
          ),
          isTrue,
        );
        for (final (version, scheme, serializer, selectedCipher) in [
          (0, 'wamp', 'cbor', cipher),
          (2, 'wamp', 'cbor', cipher),
          (1, 'other', 'cbor', cipher),
          (1, 'wamp', 'json', cipher),
          (1, 'wamp', 'cbor', 'other'),
        ]) {
          expect(
            provider.supportsE2eeProfile(
              version: version,
              scheme: scheme,
              serializer: serializer,
              cipher: selectedCipher,
            ),
            isFalse,
          );
        }
      });
      test('invalid configuration and incompatible metadata are rejected', () {
        for (final keys in <Map<String, List<int>>>[
          {},
          {'': _key()},
          {'key': []},
          {'key': List.filled(33, 1)},
        ]) {
          expect(() => _provider(aes: aes, keys: keys), throwsArgumentError);
        }
        expect(
          () => _provider(aes: aes, defaultKeyId: 'missing'),
          throwsArgumentError,
        );
        final provider = _provider(aes: aes);
        for (final options in [
          PublishOptions(pptScheme: 'other'),
          PublishOptions(pptSerializer: 'json'),
        ]) {
          expect(
            () => provider.packPayload([], null, options),
            throwsArgumentError,
          );
          expect(
            () => provider.unpackPayload([Uint8List(40)], options),
            throwsArgumentError,
          );
        }
        expect(
          () => provider.unpackPayload([
            Uint8List(40),
          ], PublishOptions(pptCipher: 'other')),
          throwsA(isA<WampE2eeUnsupportedCipherException>()),
        );
      });
      test(
        'static payload helpers preserve runtime context and payload fields',
        () {
          final provider = _provider(
            aes: aes,
            policy: (context, _) {
              expect(context, same(_context));
              return 'key';
            },
          );
          final options = PublishOptions();
          final packed = E2EEPayload.packE2EEPayload(
            ['message'],
            {'value': 2},
            options,
            provider: provider,
            runtimeContext: _context,
          );
          final unpacked = E2EEPayload.unpackE2EEPayload(
            packed,
            PublishOptions(),
            provider: provider,
            runtimeContext: _context,
          );
          expect(unpacked.arguments, ['message']);
          expect(unpacked.argumentsKeywords, {'value': 2});
        },
      );
    });
  }

  test(
    'authenticated non-envelope CBOR is rejected without returning plaintext',
    () {
      final provider = _provider(keys: {'key': _key()});
      final encoded = SecretBox(
        _key(),
      ).encrypt(Uint8List.fromList([0x01]), nonce: Uint8List(24));
      expect(
        () => provider.unpackPayload([encoded.toList()], PublishOptions()),
        throwsA(isA<WampE2eeInvalidPayloadException>()),
      );
    },
  );
  test(
    'authenticated malformed CBOR has a payload error without plaintext',
    () {
      final provider = _provider(keys: {'key': _key()});
      for (final plaintext in [
        <int>[],
        [0x81],
        [0xff],
        [0x58],
      ]) {
        final encoded = SecretBox(_key()).encrypt(
          Uint8List.fromList(plaintext),
          nonce: Uint8List(24),
        );
        expect(
          () => provider.unpackPayload([encoded.toList()], PublishOptions()),
          throwsA(
            isA<WampE2eeInvalidPayloadException>().having(
              (error) => error.cause,
              'cause',
              isNull,
            ),
          ),
        );
      }
    },
  );
  test('AES authenticates independent OpenSSL fixtures at the tag boundary', () {
    // Node's OpenSSL-backed createCipheriv('aes-256-gcm', key, nonce),
    // key=00..1f, nonce=00..0b, CBOR={"args":["ok"]}; wire is nonce|data|tag.
    final provider = _provider(aes: true, keys: {'key': _key()});
    final valid = _hex(
      '000102030405060708090a0b'
      'e666b769a2964379e22ab7d8d12632a9504711dbe0251f9ef019',
    );
    expect(provider.unpackPayload([valid], PublishOptions()).arguments, ['ok']);
    // Authenticated empty plaintext has exactly a nonce and tag. It is valid
    // AES-GCM, but invalid CBOR; do not mistake this for a failed authenticator.
    final empty = _hex(
      '000102030405060708090a0b'
      'f4c2db1dc38805a37b92171c5d0a81cc',
    );
    expect(
      () => provider.unpackPayload([empty], PublishOptions()),
      throwsA(isA<WampE2eeInvalidPayloadException>()),
    );
  });
  test('AES rejects short frames before passing them to the cipher', () {
    final provider = _provider(aes: true);
    for (final length in [0, 11, 12, 27]) {
      expect(
        () => provider.unpackPayload([Uint8List(length)], PublishOptions()),
        throwsA(
          isA<WampE2eeDecryptionException>().having(
            (error) => error.cause,
            'cause',
            isA<ArgumentError>()
                .having((error) => error.name, 'name', 'encrypted')
                .having((error) => error.invalidValue, 'length', length),
          ),
        ),
      );
    }
  });
  test('static helpers require an explicit provider in both directions', () {
    final options = PublishOptions();
    for (final pack in [false, true]) {
      expect(
        () => pack
            ? E2EEPayload.packE2EEPayload([], null, options)
            : E2EEPayload.unpackE2EEPayload([], options),
        throwsA(
          isA<WampE2eeProviderUnavailableException>()
              .having(
                (error) => error.operation,
                'operation',
                pack ? 'pack' : 'unpack',
              )
              .having((error) => error.options, 'options', same(options))
              .having(
                (error) => error.reason,
                'reason',
                'No WAMP E2EE provider is attached',
              ),
        ),
      );
    }
  });
  test('valid typed and dynamic byte lists retain boundary bytes', () {
    final provider = _provider(keys: {'key': _key()});
    for (final nonceByte in [0, 255]) {
      final encoded = SecretBox(_key()).encrypt(
        Uint8List.fromList([0xa0]),
        nonce: Uint8List.fromList(List.filled(24, nonceByte)),
      );
      for (final bytes in [encoded.toList(), List<dynamic>.from(encoded)]) {
        final result = expectE2eeSuccess(
          () => provider.unpackPayload([bytes], PublishOptions()),
        );
        expect(result.arguments, isNull);
        expect(result.argumentsKeywords, isNull);
      }
    }
  });
  test('structured diagnostics retain metadata but not decrypted payload', () {
    final options = PublishOptions(
      pptScheme: 'wamp',
      pptSerializer: 'cbor',
      pptCipher: 'aes256gcm',
      pptKeyId: 'key',
    );
    final error = WampE2eeDecryptionException(
      'unpack',
      options: options,
      cause: StateError('authentication failed'),
    );
    final text = error.toString();
    for (final part in [
      'WampE2eeDecryptionException',
      'operation: unpack',
      'pptScheme=wamp',
      'pptSerializer=cbor',
      'pptCipher=aes256gcm',
      'pptKeyId=key',
      'reason:',
      'cause:',
    ]) {
      expect(text, contains(part));
    }
    final minimal = WampE2eeInvalidPayloadException(
      'unpack',
      options: PublishOptions(),
    ).toString();
    expect(minimal, isNot(contains('reason:')));
    expect(minimal, isNot(contains('cause:')));
    for (final metadata in [
      'pptScheme=null',
      'pptSerializer=null',
      'pptCipher=null',
      'pptKeyId=null',
    ]) {
      expect(minimal, contains(metadata));
    }
  });
}

// A public List implementation can customize contains, including for null.
// Missing authentication context must be rejected before invoking that policy.
class _WildcardRoles extends ListBase<String> {
  @override
  int get length => 1;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  String operator [](int index) => const ['*'][index];

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read only');

  @override
  bool contains(Object? element) => true;
}

final class _ReadOnceBytes extends ListBase<int> {
  _ReadOnceBytes(this.bytes);
  final List<int> bytes;
  int reads = 0;
  @override
  int get length => bytes.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  int operator [](int index) {
    reads++;
    if (reads > bytes.length) throw StateError('Byte source was read twice');
    return bytes[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

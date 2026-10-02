import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';

import '../../test_support/native_runtime_support.dart';

void main() {
  final nativeClientRuntimeUnavailableReason = nativeClientRuntimeSkipReason();

  group(
    'NativeWampCborXsalsa20Poly1305Provider',
    () {
      tearDown(NativeClientRuntime.shutdownShared);

      test(
        'publishLazyPayload supports a native session E2EE provider resolver',
        () async {
          final transport = _SessionTransport();
          final inspectingProvider =
              NativeWampCborXsalsa20Poly1305Provider.single(
                keyId: 'kid-server-a',
                key: List<int>.generate(32, (index) => index + 1),
              );
          addTearDown(inspectingProvider.release);
          final client = Client(
            realm: 'test.realm',
            transport: transport,
            e2eeProviderResolver: (_) =>
                NativeWampCborXsalsa20Poly1305Provider.single(
                  keyId: 'kid-server-a',
                  key: List<int>.generate(32, (index) => index + 1),
                ),
          );
          addTearDown(client.disconnect);
          final published = Completer<Publish>();
          transport.outbound.stream.listen((message) {
            if (message is Hello) {
              transport.inbound.add(
                Welcome(
                  42,
                  Details.forWelcome(
                    authExtra: {
                      'e2ee': {
                        'version': ConnectanumE2eeProfile.version,
                        'required': false,
                        'established': true,
                        'scheme': 'wamp',
                        'serializer': 'cbor',
                        'cipher': ConnectanumE2eeProfile.xsalsa20Poly1305,
                        'send_key_id': 'kid-server-a',
                        'receive_key_id': 'kid-client-a',
                        'peer_key_id': 'kid-server-a',
                      },
                    },
                  ),
                ),
              );
            } else if (message is Publish) {
              published.complete(message);
            }
          });
          final session = await client.connect().first;
          await session.publishLazyPayload(
            'ppt.topic',
            payload: LazyMessagePayload.materialized(
              arguments: const ['wrapped'],
              argumentsKeywords: const {'worker': 4},
            ),
            options: PublishOptions(pptScheme: 'wamp'),
          );
          final publish = await published.future.timeout(
            const Duration(seconds: 5),
          );
          expect(publish.options?.pptSerializer, equals('cbor'));
          expect(publish.options?.pptCipher, equals('xsalsa20poly1305'));
          expect(publish.options?.pptKeyId, equals('kid-server-a'));
          final decoded = inspectingProvider.unpackPayload(
            publish.arguments,
            publish.options!,
          );
          expect(decoded.arguments, equals(const ['wrapped']));
          expect(decoded.argumentsKeywords, equals(const {'worker': 4}));
          expect(publish.argumentsKeywords, isNull);
          await session.close(timeout: Duration.zero);
        },
      );

      test('round-trips payloads and populates PPT metadata', () {
        final provider = NativeWampCborXsalsa20Poly1305Provider.single(
          keyId: 'kid-1',
          key: List<int>.generate(32, (index) => index + 1),
        );
        addTearDown(provider.release);

        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        final packed = provider.packPayload(
          const ['wrapped'],
          const {'worker': 4},
          options,
        );

        expect(options.pptCipher, equals('xsalsa20poly1305'));
        expect(options.pptKeyId, equals('kid-1'));
        expect(packed, hasLength(1));
        expect(packed.single, isA<Uint8List>());

        final decoded = provider.unpackPayload(packed, options);
        expect(decoded.arguments, equals(const ['wrapped']));
        expect(decoded.argumentsKeywords, equals(const {'worker': 4}));
      });

      test('selects a key id from runtime context when options omit it', () {
        final provider = NativeWampCborXsalsa20Poly1305Provider(
          keys: {
            'kid-alpha': List<int>.generate(32, (index) => index + 1),
            'kid-beta': List<int>.generate(32, (index) => index + 65),
          },
          keySelectionPolicy: (runtimeContext, _) =>
              runtimeContext.uri == 'policy.topic.beta'
              ? 'kid-beta'
              : 'kid-alpha',
        );
        addTearDown(provider.release);

        final runtimeContext = const WampE2eeRuntimeContext(
          direction: WampE2eeDirection.outbound,
          messageType: WampE2eeMessageType.publish,
          uri: 'policy.topic.beta',
        );
        final packOptions = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );

        final packed = provider.packPayload(
          const ['wrapped'],
          const {'worker': 4},
          packOptions,
          runtimeContext: runtimeContext,
        );

        expect(packOptions.pptKeyId, equals('kid-beta'));

        final unpackOptions = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        final decoded = provider.unpackPayload(
          packed,
          unpackOptions,
          runtimeContext: runtimeContext.copyWith(
            direction: WampE2eeDirection.inbound,
          ),
        );

        expect(unpackOptions.pptKeyId, equals('kid-beta'));
        expect(decoded.arguments, equals(const ['wrapped']));
        expect(decoded.argumentsKeywords, equals(const {'worker': 4}));
      });

      test('interoperates with the pure Dart provider', () {
        final key = List<int>.generate(32, (index) => index + 1);
        final nativeProvider = NativeWampCborXsalsa20Poly1305Provider.single(
          keyId: 'kid-1',
          key: key,
        );
        addTearDown(nativeProvider.release);
        final dartProvider = WampCborXsalsa20Poly1305Provider.single(
          keyId: 'kid-1',
          key: key,
        );

        final nativeOptions = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        final nativePacked = nativeProvider.packPayload(
          const ['native'],
          const {'path': 'dart'},
          nativeOptions,
        );
        final dartDecoded = dartProvider.unpackPayload(
          nativePacked,
          nativeOptions,
        );
        expect(dartDecoded.arguments, equals(const ['native']));
        expect(dartDecoded.argumentsKeywords, equals(const {'path': 'dart'}));

        final dartOptions = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        final dartPacked = dartProvider.packPayload(
          const ['dart'],
          const {'path': 'native'},
          dartOptions,
        );
        final nativeDecoded = nativeProvider.unpackPayload(
          dartPacked,
          dartOptions,
        );
        expect(nativeDecoded.arguments, equals(const ['dart']));
        expect(
          nativeDecoded.argumentsKeywords,
          equals(const {'path': 'native'}),
        );
      });

      test('maps wrong-key decrypts to the core decryption exception', () {
        final encryptingProvider =
            NativeWampCborXsalsa20Poly1305Provider.single(
              keyId: 'kid-1',
              key: List<int>.generate(32, (index) => index + 1),
            );
        final decryptingProvider =
            NativeWampCborXsalsa20Poly1305Provider.single(
              keyId: 'kid-1',
              key: List<int>.generate(32, (index) => index + 33),
            );
        addTearDown(encryptingProvider.release);
        addTearDown(decryptingProvider.release);

        final options = PublishOptions(
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
        );
        final packed = encryptingProvider.packPayload(
          const ['wrapped'],
          null,
          options,
        );

        expect(
          () => decryptingProvider.unpackPayload(packed, options),
          throwsA(isA<WampE2eeDecryptionException>()),
        );
      });
    },
    skip: nativeClientRuntimeUnavailableReason,
  );

  group('NativeWampCborAes256GcmProvider', () {
    tearDown(NativeClientRuntime.shutdownShared);

    test('interoperates between independent native providers', () {
      final key = List<int>.generate(32, (index) => index + 1);
      final encryptingProvider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );
      final decryptingProvider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );
      addTearDown(encryptingProvider.release);
      addTearDown(decryptingProvider.release);
      final options = PublishOptions(pptScheme: 'wamp');

      final packed = encryptingProvider.packPayload(
        const ['native-to-native'],
        const {'path': 'independent'},
        options,
      );
      final decoded = decryptingProvider.unpackPayload(packed, options);

      expect(decoded.arguments, equals(const ['native-to-native']));
      expect(decoded.argumentsKeywords, equals(const {'path': 'independent'}));
    });

    test('interoperates with the pure Dart provider in both directions', () {
      final key = List<int>.generate(32, (index) => index + 1);
      final nativeProvider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );
      addTearDown(nativeProvider.release);
      final dartProvider = WampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: key,
      );

      final nativeOptions = PublishOptions(pptScheme: 'wamp');
      final nativePacked = nativeProvider.packPayload(
        const ['native'],
        const {'path': 'dart'},
        nativeOptions,
      );
      expect(nativeOptions.pptCipher, equals('aes256gcm'));
      final dartDecoded = dartProvider.unpackPayload(
        nativePacked,
        nativeOptions,
      );
      expect(dartDecoded.arguments, equals(const ['native']));
      expect(dartDecoded.argumentsKeywords, equals(const {'path': 'dart'}));

      final dartOptions = PublishOptions(pptScheme: 'wamp');
      final dartPacked = dartProvider.packPayload(
        const ['dart'],
        const {'path': 'native'},
        dartOptions,
      );
      final nativeDecoded = nativeProvider.unpackPayload(
        dartPacked,
        dartOptions,
      );
      expect(nativeDecoded.arguments, equals(const ['dart']));
      expect(nativeDecoded.argumentsKeywords, equals(const {'path': 'native'}));
    });

    test('maps authenticated decrypt failures to the core exception', () {
      final provider = NativeWampCborAes256GcmProvider.single(
        keyId: 'kid-1',
        key: List<int>.generate(32, (index) => index + 1),
      );
      addTearDown(provider.release);
      final options = PublishOptions(pptScheme: 'wamp');
      final packed = provider.packPayload(const ['wrapped'], null, options);
      final tampered = Uint8List.fromList(packed.single as Uint8List);
      tampered[tampered.length - 1] ^= 1;

      expect(
        () => provider.unpackPayload(<dynamic>[tampered], options),
        throwsA(isA<WampE2eeDecryptionException>()),
      );
    });
  }, skip: nativeClientRuntimeUnavailableReason);
}

class _SessionTransport extends AbstractTransport {
  final inbound = StreamController<AbstractMessage>.broadcast();
  final outbound = StreamController<AbstractMessage>();
  var _open = false;

  @override
  final Completer<void> onDisconnect = Completer<void>();

  @override
  final Completer<void> onConnectionLost = Completer<void>();

  @override
  bool get isOpen => _open;

  @override
  bool get isReady => _open;

  @override
  Future<void> get onReady => Future.value();

  @override
  Future<void> open({Duration? pingInterval}) async {
    _open = true;
  }

  @override
  Future<void> close({dynamic error}) async {
    if (!_open) return;
    _open = false;
    unawaited(inbound.close());
    unawaited(outbound.close());
    onDisconnect.complete();
  }

  @override
  Stream<AbstractMessage> receive() => inbound.stream;

  @override
  void send(AbstractMessage message) => outbound.add(message);
}

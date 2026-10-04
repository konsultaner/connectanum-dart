import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:test/test.dart';

void main() {
  for (final cipher in <String?>[null, 'xsalsa20poly1305', 'aes256gcm']) {
    final mode = _PayloadMode(cipher);
    for (final length in [0, 4]) {
      final expected = Uint8List.fromList(
        [0, 255, 37, 1].take(length).toList(),
      );
      final label = '${cipher ?? 'typed'} $length bytes';

      test(
        '$label progressive RPC results retain their opaque wire view',
        () async {
          final (peer, session) = await _start(mode);
          final sent = Completer<Call>();
          peer.onCall = sent.complete;
          final response = session
              .call(
                'app.read',
                options: CallOptions(receiveProgress: true),
              )
              .toList();
          final call = await sent.future;
          for (final progress in [true, false]) {
            peer.deliver(
              mode.attach(
                Result(
                  call.requestId,
                  ResultDetails(
                    progress: progress,
                    pptScheme: mode.scheme,
                    pptSerializer: mode.serializer,
                    pptCipher: cipher,
                    pptKeyId: mode.keyId,
                  ),
                ),
                expected,
              ),
            );
          }
          final results = await response;
          expect(results, hasLength(2));
          for (final result in results) {
            mode.expectApplication(result, expected);
            final encoded = peer.serializer.serialize(result);
            final wire = peer.serializer.deserialize(encoded) as Result;
            expect(
              wire.transparentBinaryPayload,
              result.transparentBinaryPayload,
            );
            expect(wire.arguments, isNull);
            expect(wire.details.pptSerializer, mode.serializer);
            expect(wire.details.pptCipher, cipher);
          }
        },
      );

      test(
        '$label events expose application values through a subscription',
        () async {
          final (peer, session) = await _start(mode);
          final received = Completer<Event>();
          final subscription = await session.subscribeHandler(
            'app.topic',
            received.complete,
          );
          peer.deliver(
            mode.attach(
              Event(
                subscription.subscriptionId,
                73,
                EventDetails(
                  pptScheme: mode.scheme,
                  pptSerializer: mode.serializer,
                  pptCipher: cipher,
                  pptKeyid: mode.keyId,
                ),
              ),
              expected,
            ),
          );
          mode.expectApplication(await received.future, expected);
        },
      );

      test(
        '$label invocation values remain available while replying',
        () async {
          final (peer, session) = await _start(mode);
          final received = Completer<Invocation>();
          final registration = await session.registerHandler(
            'app.read',
            received.complete,
          );
          peer.deliver(
            mode.attach(
              Invocation(
                74,
                registration.registrationId,
                InvocationDetails(
                  null,
                  null,
                  false,
                  mode.scheme,
                  mode.serializer,
                  cipher,
                  mode.keyId,
                ),
              ),
              expected,
            ),
          );
          final invocation = await received.future;
          mode.expectApplication(invocation, expected);
          invocation.respondWith(arguments: ['reply']);
          expect(peer.sent.whereType<Yield>().single.arguments, ['reply']);
          mode.expectApplication(invocation, expected);
        },
      );

      test('$label RPC errors retain decrypted application details', () async {
        final (peer, session) = await _start(mode);
        final sent = Completer<Call>();
        peer.onCall = sent.complete;
        final response = session.call('app.fail').toList();
        final assertion = expectLater(
          response,
          throwsA(
            isA<core.Error>()
                .having(
                  (error) => error.arguments,
                  'application bytes',
                  [expected],
                )
                .having(
                  (error) => error.argumentsKeywords,
                  'application keywords',
                  mode.keywords,
                ),
          ),
        );
        final call = await sent.future;
        peer.deliver(
          mode.attach(
            core.Error(
              MessageTypes.codeCall,
              call.requestId,
              {
                'ppt_scheme': mode.scheme,
                'ppt_serializer': mode.serializer,
                if (cipher != null) 'ppt_cipher': cipher,
                if (mode.keyId != null) 'ppt_keyid': mode.keyId,
              },
              'app.error',
            ),
            expected,
          ),
        );
        await assertion;
      });
    }
  }
}

class _PayloadMode {
  _PayloadMode(this.cipher) {
    final key = List<int>.filled(32, 19);
    provider = switch (cipher) {
      'xsalsa20poly1305' => WampCborXsalsa20Poly1305Provider.single(
        keyId: 'key',
        key: key,
      ),
      'aes256gcm' => WampCborAes256GcmProvider.single(keyId: 'key', key: key),
      _ => null,
    };
  }
  final String? cipher;
  late final WampE2eeProvider? provider;
  String get scheme => cipher == null ? 'x_app' : 'wamp';
  String get serializer => cipher == null ? 'flatbuffers' : 'cbor';
  String? get keyId => cipher == null ? null : 'key';
  Map<String, dynamic>? get keywords =>
      cipher == null ? null : {'marker': 'encrypted'};

  T attach<T extends AbstractMessageWithPayload>(T message, Uint8List bytes) {
    message.transparentBinaryPayload = provider == null
        ? bytes
        : provider!
                  .packPayload(
                    [bytes],
                    keywords,
                    PublishOptions(pptScheme: 'wamp'),
                  )
                  .single
              as Uint8List;
    return message;
  }

  void expectApplication(AbstractMessageWithPayload message, Uint8List bytes) {
    expect(message.arguments, [bytes]);
    expect(message.argumentsKeywords, keywords);
    expect(message.hasDecodedPptPayload, isTrue);
    if (cipher == null) {
      expect(message.arguments!.single, same(message.transparentBinaryPayload));
    }
    final wire = message.toLazyPayload();
    expect(
      wire.transparentBinaryPayload,
      same(message.transparentBinaryPayload),
    );
    expect(wire.arguments, isNull);
    expect(wire.argumentsKeywords, isNull);
  }
}

Future<(_Peer, Session)> _start(_PayloadMode mode) async {
  final peer = _Peer();
  final client = Client(
    realm: 'app.realm',
    transport: peer,
    e2eeProvider: mode.provider,
  );
  addTearDown(client.disconnect);
  final session = await client.connect().first;
  return (peer, session);
}

// A portable peer still exchanges encoded FlatBuffers. No native handle or
// network-router behavior is claimed by this Session boundary test.
class _Peer extends AbstractTransport {
  final serializer = flat.Serializer();
  final inbound = StreamController<AbstractMessage>.broadcast(sync: true);
  final sent = <AbstractMessage>[];
  void Function(Call)? onCall;
  bool _open = false;
  @override
  final onDisconnect = Completer<void>();
  @override
  final onConnectionLost = Completer<void>();
  @override
  bool get isOpen => _open;
  @override
  bool get isReady => _open;
  @override
  Future<void> get onReady => Future.value();
  @override
  Future<void> open({Duration? pingInterval}) async => _open = true;
  @override
  Future<void> close({dynamic error}) async {
    if (!_open) return;
    _open = false;
    onDisconnect!.complete();
    unawaited(inbound.close());
  }

  void deliver(AbstractMessage message) {
    inbound.add(serializer.deserialize(serializer.serialize(message))!);
  }

  @override
  Stream<AbstractMessage> receive() => inbound.stream;
  @override
  void send(AbstractMessage message) {
    sent.add(message);
    switch (message) {
      case Hello():
        deliver(Welcome(42, Details.forWelcome()));
      case Subscribe():
        deliver(Subscribed(message.requestId, 71));
      case Register():
        deliver(Registered(message.requestId, 72));
      case Call():
        onCall?.call(message);
    }
  }
}

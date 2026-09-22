part of '../router_worker_session_test.dart';

void _workerPublishFailureCases(
  RouterSettings Function() settings,
  RouterStateStore Function() store,
) {
  group('Publish worker failure boundaries', () {
    WorkerConnectionState publisher() {
      final state =
          createWorkerStateForTest(
                listener: _buildListener(),
                listenerSettings: settings().listeners.first,
              )
              as WorkerConnectionState;
      return state
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = settings().realms.first
        ..sessionId = 912;
    }

    Future<void> publish(
      WorkerConnectionState state,
      _PublishProbePort boss,
      _PublishProbeContext context,
      publish_msg.Publish message,
    ) async {
      final cache = _StaticRealmContextCache(
        statePort: store().commandPort,
        overrides: {'realm1': context},
      );
      addTearDown(cache.dispose);
      await handleSessionMessageForTest(
        bossPort: boss,
        statePort: store().commandPort,
        realmContexts: cache,
        state: state,
        message: message,
        connectionId: 24,
      );
    }

    for (final asynchronous in [false, true]) {
      for (final kind in ['argument', 'state', 'other']) {
        test(
          'routing $kind failure async=$asynchronous permits retry',
          () async {
            final failure = switch (kind) {
              'argument' => ArgumentError('invalid publish option'),
              'state' => StateError('publisher session missing'),
              _ => Exception('routing unavailable'),
            };
            final reason = switch (kind) {
              'argument' => wamp_core.Error.invalidArgument,
              'state' => wamp_core.Error.noSuchSession,
              _ => wamp_core.Error.unknown,
            };
            final detail = switch (kind) {
              'argument' => 'invalid publish option',
              'state' => 'publisher session missing',
              _ => '${failure.runtimeType}: $failure',
            };
            final context = _PublishProbeContext(store().commandPort)
              ..failure = failure
              ..asynchronousFailure = asynchronous;
            final boss = _PublishProbePort();
            final state = publisher();
            await publish(
              state,
              boss,
              context,
              publish_msg.Publish(
                1202,
                'app.events',
                options: publish_msg.PublishOptions(acknowledge: true),
              ),
            );
            final sends = _collectWorkerSends(boss.messages);
            expect(sends, hasLength(1));
            expect(sends.single['connectionId'], 24);
            expect(
              jsonDecode(utf8.decode(sends.single['payload'] as Uint8List)),
              [
                MessageTypes.codeError,
                MessageTypes.codePublish,
                1202,
                {'message': detail},
                reason,
              ],
            );
            expect(context.calls, 1);
            expect(
              boss.messages.where((event) => event['stage'] == 'error'),
              hasLength(1),
            );
            expect(
              boss.messages.where((event) => event['stage'] == 'acked'),
              isEmpty,
            );
            expect(
              boss.messages.where(
                (event) => event['type'] == 'worker_forward_message',
              ),
              isEmpty,
            );
            expect(state.phase, HandshakePhase.open);

            context.failure = null;
            boss.messages.clear();
            await publish(
              state,
              boss,
              context,
              publish_msg.Publish(
                1203,
                'app.events',
                options: publish_msg.PublishOptions(acknowledge: true),
              ),
            );
            final recovered = _collectWorkerSends(boss.messages);
            expect(recovered, hasLength(1));
            expect(
              jsonDecode(utf8.decode(recovered.single['payload'] as Uint8List)),
              [MessageTypes.codePublished, 1203, 7001],
            );
            expect(context.calls, 2);
            expect(context.publisherSessionId, 912);
            expect(context.topic, 'app.events');
            expect(context.options, containsPair('acknowledge', true));
            expect(
              boss.messages.where((event) => event['stage'] == 'error'),
              isEmpty,
            );
          },
        );
      }
    }

    for (final disclose in [false, true]) {
      test(
        'PPT and custom metadata reach both destinations disclose=$disclose',
        () async {
          final internal = _PublishProbePort();
          final context = _PublishProbeContext(store().commandPort)
            ..matches = [
              SubscriptionMatch(
                subscriptionId: 41,
                sessionId: 913,
                connectionId: 0,
                details: {'match': 'prefix'},
                internalSendPort: internal,
              ),
              SubscriptionMatch(
                subscriptionId: 42,
                sessionId: 914,
                connectionId: 25,
                details: {'match': 'wildcard'},
              ),
            ];
          final payload = Uint8List.fromList([0, 1, 127, 128, 255]);
          final encoded = Uint8List.fromList(
            cbor.cborEncode(cbor.CborValue([payload])),
          );
          final message =
              publish_msg.Publish(
                1204,
                'app.events',
                options: publish_msg.PublishOptions(
                  acknowledge: true,
                  discloseMe: disclose,
                  pptScheme: 'wamp',
                  pptSerializer: 'cbor',
                  pptCipher: 'aes256gcm',
                  pptKeyId: 'public-test-key',
                  custom: {'trace': 'publish-test'},
                ),
              )..setLazyPayload(
                argumentsBytes: encoded,
                argumentsDecoder: (_) => [payload],
                encoding: LazyPayloadEncoding.cbor,
              );
          final boss = _PublishProbePort();
          await publish(publisher(), boss, context, message);
          expect(internal.messages, hasLength(1));
          final event = internal.messages.single;
          expect(event['type'], 'event');
          expect(event['subscriptionId'], 41);
          expect(event['publicationId'], 7001);
          expect(event['publisherSessionId'], disclose ? 912 : null);
          expect(event['topic'], 'app.events');
          expect(event['details'], {
            'match': 'prefix',
            'trace': 'publish-test',
            'ppt_scheme': 'wamp',
            'ppt_serializer': 'cbor',
            'ppt_cipher': 'aes256gcm',
            'ppt_keyid': 'public-test-key',
          });
          expect((event['lazyPayload'] as Map)['encoding'], 'cbor');
          expect((event['lazyPayload'] as Map)['argumentsBytes'], encoded);
          final forwards = _extractForwardMessages(boss.messages);
          expect(forwards, hasLength(1));
          expect(forwards.single['connectionId'], 25);
          final forwarded = forwards.single['message'] as event_msg.Event;
          expect(forwarded.subscriptionId, 42);
          expect(forwarded.publicationId, 7001);
          expect(forwarded.details.publisher, disclose ? 912 : null);
          expect(forwarded.details.topic, 'app.events');
          expect(forwarded.details.pptScheme, 'wamp');
          expect(forwarded.details.pptSerializer, 'cbor');
          expect(forwarded.details.pptCipher, 'aes256gcm');
          expect(forwarded.details.pptKeyId, 'public-test-key');
          expect(forwarded.details.custom, {'trace': 'publish-test'});
          expect(forwarded.lazyPayloadEncoding, LazyPayloadEncoding.cbor);
          expect(forwarded.debugEncodedArgumentsBytes, encoded);
          expect(_collectWorkerSends(boss.messages), hasLength(1));
        },
      );
    }

    test(
      'failed PUBLISHED send is reported without duplicate routing',
      () async {
        final boss = _PublishProbePort()..rejectWorkerSend = true;
        final context = _PublishProbeContext(store().commandPort);
        final state = publisher();
        await publish(
          state,
          boss,
          context,
          publish_msg.Publish(
            1205,
            'app.events',
            options: publish_msg.PublishOptions(acknowledge: true),
          ),
        );
        await Future<void>.value();
        expect(_collectWorkerSends(boss.messages), isEmpty);
        expect(context.calls, 1);
        final diagnostics = boss.messages.where(
          (event) => event['stage'] == 'ack_error_async',
        );
        expect(diagnostics, hasLength(1));
        final diagnostic = diagnostics.single;
        expect(diagnostic['connectionId'], 24);
        expect(diagnostic['requestId'], 1205);
        expect(diagnostic['publicationId'], 7001);
        expect(diagnostic['topic'], 'app.events');
        expect(diagnostic['error'], contains('ack transport failure'));
        expect(diagnostic['stackTrace'], isNotEmpty);
        expect(
          boss.messages.where((event) => event['stage'] == 'acked'),
          isEmpty,
        );
        expect(state.phase, HandshakePhase.open);
      },
    );
  });
}

class _PublishProbeContext extends RealmContext {
  _PublishProbeContext(SendPort port)
    : super(realmUri: 'realm1', statePort: port);

  Object? failure;
  bool asynchronousFailure = false;
  int calls = 0;
  int? publisherSessionId;
  String? topic;
  Map<String, Object?>? options;
  List<SubscriptionMatch> matches = [];

  @override
  Future<PublicationRouting> matchSubscriptions({
    required int publisherSessionId,
    required String topic,
    Map<String, Object?> options = const {},
  }) {
    calls++;
    this.publisherSessionId = publisherSessionId;
    this.topic = topic;
    this.options = Map.of(options);
    final error = failure;
    if (error != null) {
      if (asynchronousFailure) return Future<PublicationRouting>.error(error);
      throw error;
    }
    return Future.value(
      PublicationRouting(publicationId: 7001, matches: matches),
    );
  }
}

class _PublishProbePort implements SendPort {
  final messages = <Map<String, Object?>>[];
  bool rejectWorkerSend = false;

  @override
  void send(Object? message) {
    final event = Map<String, Object?>.from(message as Map);
    if (rejectWorkerSend && event['type'] == 'worker_send') {
      throw StateError('ack transport failure');
    }
    messages.add(event);
  }
}

part of '../router_runtime_test.dart';

class _ProgressiveFailureRuntime extends _HandleRuntime {
  _ProgressiveFailureRuntime(this.stage);

  final String stage;
  final failure = NativeTransportException(
    -1,
    'controlled progressive failure',
  );
  final opens = <int>[];
  final closes = <int>[];
  final chunks = <int, List<int>>{};

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    opens.add(handshakeHandle);
    if (handshakeHandle == 9601 && stage == 'open') throw failure;
    return _FakeHttpResponseStream(
      handle: handshakeHandle,
      onChunk: (chunk) {
        if (handshakeHandle == 9601 && stage == 'write') throw failure;
        chunks.putIfAbsent(handshakeHandle, () => []).addAll(chunk);
      },
      onClose: () => closes.add(handshakeHandle),
    );
  }
}

void _httpProgressiveFailureCases() {
  for (final stage in ['open', 'write']) {
    test('progressive HTTP $stage failure cleans up and recovers', () async {
      final runtime = _ProgressiveFailureRuntime(stage);
      final events = <Map<String, Object?>>[];
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: _buildRouterSettingsWithPendingProtocols(),
      );
      final binding = router.start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) events.add(event);
        },
      );
      addTearDown(binding.dispose);
      final session = await binding.createInternalSession(realmUri: 'realm1');
      final registration = await session.register('com.example.api.stream');
      final contexts = <HttpInvocationContext>[];
      registration.onInvoke((invocation) {
        contexts.add(HttpInvocationContext.maybeFromInvocation(invocation)!);
      });
      final first = _TrackedHttpHandshake(9601);
      final second = _TrackedHttpHandshake(9602);
      for (final (index, handshake) in [first, second].indexed) {
        runtime.setConnectionProtocol(
          70 + index,
          NativeConnectionProtocol.http,
        );
        runtime.enqueueHttpHandshake(
          binding.listeners.single.listenerId,
          70 + index,
          handshake,
        );
        await _waitUntil(() => contexts.length == index + 1);
        final context = contexts[index];
        HttpResponseUtil.respond(
          context.invocation,
          HttpResponseUtil.bytes(
            requestId: context.requestId,
            status: 200,
            body: Uint8List.fromList([index + 1]),
          ),
          progress: true,
        );
        if (index == 0) {
          await _waitUntil(() => first.releases == 1);
        } else {
          await _waitUntil(() => runtime.chunks.containsKey(second.handle));
        }
        HttpResponseUtil.respond(
          context.invocation,
          HttpResponseUtil.bytes(
            requestId: context.requestId,
            status: 200,
            body: Uint8List.fromList([9]),
          ),
        );
      }
      await _waitUntil(() => second.releases == 1);
      final failureEvents = events.where(
        (event) =>
            event['type'] ==
            (stage == 'open'
                ? 'http_response_stream_open_error'
                : 'http_response_stream_error'),
      );
      expect(failureEvents, hasLength(1));
      expect(failureEvents.single['connectionId'], 70);
      expect(failureEvents.single['error'], runtime.failure.toString());
      expect(failureEvents.single['httpRequestId'], contexts.first.requestId);
      expect(runtime.opens, [9601, 9602]);
      expect(runtime.chunks, {
        9602: [2, 9],
      });
      expect(runtime.closes, stage == 'open' ? [9602] : [9601, 9602]);
      await binding.dispose();
      expect([first.releases, second.releases], [1, 1]);
      expect(runtime.closes, stage == 'open' ? [9602] : [9601, 9602]);
    });
  }
}

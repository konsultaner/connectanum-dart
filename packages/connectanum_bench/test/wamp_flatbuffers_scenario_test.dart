import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/native_buffers.dart' as native_buffers;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  test('parses outer and peer FlatBuffers independently of PPT', () {
    final scenario = WampScenario.fromJson({
      'transport': 'rawsocket',
      'serializer': 'flatbuffers',
      'peer_serializer': 'cbor',
      'mode': 'rpc',
      'uri': 'bench.rpc.echo',
    });
    expect(scenario.serializer.name, 'flatbuffers');
    expect(scenario.peerSerializer, WampSerializer.cbor);
    expect(scenario.pptSerializer, isNull);
    expect(e2eeProviderFactoryForScenario(scenario), isNull);
    expect(WampSerializer.parse('FLATBUFFERS').name, 'flatbuffers');
  });

  for (final scheme in [null, 'x_custom_scheme']) {
    test('ordinary FlatBuffers args use CBOR with PPT=$scheme', () async {
      final session = _RecordingSession();
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async => session,
        logger: Logger.detached('flatbuffers-fragments'),
      );
      final samples = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.flatbuffers,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 1,
          concurrency: 1,
          payloadBytes: 16,
          pptScheme: scheme,
        ),
      );
      expect(samples, hasLength(1));
      final payload = session.request!;
      expect(payload.encoding, core.LazyPayloadEncoding.cbor);
      expect(payload.hasEncodedArguments, isTrue);
      expect(
        flatbuffers.Serializer().deserializeApplication(
          payload.argumentsBytes!,
        ),
        ['ABCDEFGHIJKLMNOP'],
      );
      expect(payload.argumentsKeywordsBytes, isNull);
      expect(session.options?.pptScheme, scheme);
      expect(session.options?.pptSerializer, scheme == null ? null : 'cbor');
      expect(session.closed, isTrue);
    });
  }

  test(
    'native typed payload owner lives through the result then is disposed',
    () async {
      final session = _RecordingSession();
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async => session,
        logger: Logger.detached('flatbuffers-native-owner'),
        nativeBufferAllocator: native_buffers.NativeBufferAllocator.instance(),
      );

      final samples = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 1,
          concurrency: 1,
          payloadBytes: 128,
          pptScheme: 'x_connectanum_bench_typed',
          pptSerializer: 'flatbuffers',
          payloadConstruction: WampPayloadConstruction.nativeBuffer,
        ),
      );

      expect(samples, hasLength(1));
      final owner = session.requestOwner!;
      expect(session.ownerWasLiveDuringCall, isTrue);
      expect(owner.isDisposed, isTrue);
      expect(session.closed, isTrue);
    },
  );
}

class _RecordingSession implements WampSession {
  core.LazyMessagePayload? request;
  native_buffers.NativeOwnedBuffer? requestOwner;
  bool ownerWasLiveDuringCall = false;
  core.CallOptions? options;
  bool closed = false;
  final _disconnected = Completer<void>();

  @override
  int get id => 1;

  @override
  Future<void> get onDisconnect => _disconnected.future;

  @override
  Future<core.LazyResultPayload> callSingleWithLazyPayload(
    String procedure, {
    required core.LazyMessagePayload payload,
    core.CallOptions? options,
  }) async {
    request = payload;
    requestOwner = payload.anchor as native_buffers.NativeOwnedBuffer?;
    ownerWasLiveDuringCall = requestOwner?.isDisposed == false;
    this.options = options;
    return core.LazyResultPayload(
      callRequestId: 1,
      progress: false,
      payload: payload,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
    _disconnected.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

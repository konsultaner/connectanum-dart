import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_bench/src/bench_payload/codec.dart';
import 'package:connectanum_client/native_buffers.dart' as native_buffers;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'support/native_library.dart';

void main() {
  final nativeLibrary = nativeBenchTestLibrary();
  final skipNative = nativeLibrary == null
      ? 'Native transport artifact unavailable'
      : false;
  test(
    'pre-encoded FlatBuffers copies its encoded parts into native storage once',
    () async {
      final session = _RecordingSession();
      final runner = WampWorkloadRunner(
        sessionFactory: (_) async => session,
        logger: Logger.detached('pre-encoded-parts'),
        nativeBufferAllocator: native_buffers.NativeBufferAllocator.instance(
          libraryPath: nativeLibrary,
        ),
      );
      OwnedCopyMetrics.enable();
      final before = OwnedCopyMetrics.snapshot()!;
      final samples = await runner.run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.flatbuffers,
          mode: WampMode.rpc,
          uri: 'bench.rpc.echo',
          iterations: 1,
          concurrency: 1,
          payloadBytes: 65536,
          pptScheme: 'x_connectanum_bench_typed',
          pptSerializer: 'flatbuffers',
          payloadConstruction: WampPayloadConstruction.preEncodedSpan,
        ),
      );
      final after = OwnedCopyMetrics.snapshot()!;
      expect(
        after['flatbuffer_vector_copy_bytes']! -
            before['flatbuffer_vector_copy_bytes']!,
        0,
      );
      expect(
        after['coalescing_copy_bytes']! - before['coalescing_copy_bytes']!,
        0,
      );
      expect(
        samples.single.nativeBuilderInputCopiedBytes,
        session.requestBytes!.length,
      );
      expect(samples.single.nativeBuilderGrowthCopiedBytes, 0);
      expect(session.requestLease, isA<native_buffers.NativePptPayloadLease>());
      expect(session.requestOwner!.isDisposed, isTrue);
      BenchPayloadCodec.verify(
        bytes: session.requestBytes!,
        worker: 0,
        iteration: 0,
        bodyBytes: 65536,
      );
    },
    skip: skipNative,
  );
  test(
    'pre-encoded parts preserve padding and native ownership at boundaries',
    () async {
      for (final length in [0, 1, 7, 8, 65535, 65537]) {
        final session = _RecordingSession();
        final runner = WampWorkloadRunner(
          sessionFactory: (_) async => session,
          logger: Logger.detached('pre-encoded-boundaries'),
          nativeBufferAllocator: native_buffers.NativeBufferAllocator.instance(
            libraryPath: nativeLibrary,
          ),
        );
        final samples = await runner.run(
          WampScenario(
            transport: WampTransport.rawsocket,
            serializer: WampSerializer.flatbuffers,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 1,
            concurrency: 1,
            payloadBytes: length,
            pptScheme: 'x_connectanum_bench_typed',
            pptSerializer: 'flatbuffers',
            payloadConstruction: WampPayloadConstruction.preEncodedSpan,
          ),
        );
        expect(
          session.requestBytes,
          BenchPayloadCodec.encodeDart(
            worker: 0,
            iteration: 0,
            bodyBytes: length,
          ),
        );
        expect(
          samples.single.nativeBuilderInputCopiedBytes,
          session.requestBytes!.length,
        );
        expect(session.requestOwner!.isDisposed, isTrue);
      }
    },
    skip: skipNative,
  );
  for (final construction in [
    WampPayloadConstruction.dartValues,
    WampPayloadConstruction.preEncodedSpan,
    WampPayloadConstruction.nativeBuffer,
  ]) {
    test(
      'typed $construction retains its declared construction source',
      () async {
        final session = _RecordingSession();
        final runner = WampWorkloadRunner(
          sessionFactory: (_) async => session,
          logger: Logger.detached('typed-source'),
          nativeBufferAllocator:
              construction == WampPayloadConstruction.dartValues
              ? null
              : native_buffers.NativeBufferAllocator.instance(
                  libraryPath: nativeLibrary,
                ),
        );
        final samples = await runner.run(
          WampScenario(
            transport: WampTransport.rawsocket,
            serializer: WampSerializer.flatbuffers,
            mode: WampMode.rpc,
            uri: 'bench.rpc.echo',
            iterations: 1,
            concurrency: 1,
            payloadBytes: 65536,
            pptScheme: 'x_connectanum_bench_typed',
            pptSerializer: 'flatbuffers',
            payloadConstruction: construction,
          ),
        );
        expect(samples, hasLength(1));
        final source = core.packedPayloadSourceOf(session.request!);
        if (construction == WampPayloadConstruction.dartValues) {
          expect(source, isA<core.PackedPayloadParts>());
          expect(session.requestOwner, isNull);
          expect(session.requestLease, isNull);
          final parts = (source as core.PackedPayloadParts).fragments;
          expect(parts[1].length, 65536);
          expect(parts[1].buffer.lengthInBytes, 65536);
        } else {
          expect(source, isA<native_buffers.NativePptPayloadLease>());
        }
        BenchPayloadCodec.verify(
          bytes: session.requestBytes!,
          worker: 0,
          iteration: 0,
          bodyBytes: 65536,
        );
      },
      skip: construction == WampPayloadConstruction.dartValues
          ? false
          : skipNative,
    );
  }
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
        nativeBufferAllocator: native_buffers.NativeBufferAllocator.instance(
          libraryPath: nativeLibrary,
        ),
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
    skip: skipNative,
  );

  for (final codec in [
    (
      'flatbuffers',
      WampSerializer.flatbuffers,
      core.LazyPayloadEncoding.flatbuffers,
    ),
    ('cbor', WampSerializer.cbor, core.LazyPayloadEncoding.cbor),
    ('msgpack', WampSerializer.msgpack, core.LazyPayloadEncoding.messagePack),
  ]) {
    for (final construction in [
      WampPayloadConstruction.nativeBuffer,
      WampPayloadConstruction.preEncodedSpan,
    ]) {
      test(
        'native ${codec.$1} $construction leases its exact PPT span owner',
        () async {
          final session = _RecordingSession();
          final runner = WampWorkloadRunner(
            sessionFactory: (_) async => session,
            logger: Logger.detached('flatbuffers-owned-span'),
            nativeBufferAllocator:
                native_buffers.NativeBufferAllocator.instance(
                  libraryPath: nativeLibrary,
                ),
          );

          final samples = await runner.run(
            WampScenario(
              transport: WampTransport.rawsocket,
              clientImplementation: WampClientImplementation.native,
              serializer: codec.$2,
              mode: WampMode.rpc,
              uri: 'bench.rpc.echo',
              iterations: 1,
              concurrency: 1,
              payloadBytes: 128,
              pptScheme: 'x_connectanum_bench_typed',
              pptSerializer: codec.$1,
              payloadConstruction: construction,
            ),
          );

          expect(samples, hasLength(1));
          final payload = session.request!;
          expect(payload.encoding, codec.$3);
          final lease = session.requestLease!;
          expect(core.packedPayloadSourceOf(payload), same(lease));
          expect(payload.storageOwner, same(lease));
          expect(session.ownerWasLiveDuringCall, isTrue);
          expect(session.exportedViewBeforeCall, isFalse);
          expect(payload.packedPayloadBytes, same(session.requestBytes));
          expect(lease.hasExportedByteView, isTrue);
          expect(lease.isDisposed, isTrue);
          expect(session.requestOwner!.isDisposed, isTrue);
          expect(session.closed, isTrue);
        },
        skip: skipNative,
      );
    }
  }

  for (final codec in [
    ('FlatBuffers', WampSerializer.flatbuffers),
    ('cbor', WampSerializer.cbor),
    ('msgpack', WampSerializer.msgpack),
  ]) {
    for (final construction in [
      WampPayloadConstruction.nativeBuffer,
      WampPayloadConstruction.preEncodedSpan,
    ]) {
      test(
        'native ${codec.$1} $construction PPT owner is disposed when a call is rejected',
        () async {
          final session = _RecordingSession()..throwOnCall = true;
          final runner = WampWorkloadRunner(
            sessionFactory: (_) async => session,
            logger: Logger.detached('flatbuffers-owned-span-error'),
            nativeBufferAllocator:
                native_buffers.NativeBufferAllocator.instance(
                  libraryPath: nativeLibrary,
                ),
          );

          await expectLater(
            runner.run(
              WampScenario(
                transport: WampTransport.rawsocket,
                clientImplementation: WampClientImplementation.native,
                serializer: codec.$2,
                mode: WampMode.rpc,
                uri: 'bench.rpc.echo',
                iterations: 1,
                concurrency: 1,
                payloadBytes: 128,
                pptScheme: 'x_connectanum_bench_typed',
                pptSerializer: codec.$1 == 'FlatBuffers'
                    ? 'flatbuffers'
                    : codec.$1,
                payloadConstruction: construction,
              ),
            ),
            throwsA(isA<StateError>()),
          );

          expect(session.ownerWasLiveDuringCall, isTrue);
          expect(session.requestOwner!.isDisposed, isTrue);
          expect(session.requestLease!.isDisposed, isTrue);
          expect(session.requestLease!.hasExportedByteView, isFalse);
          expect(session.exportedViewBeforeCall, isFalse);
          expect(session.closed, isTrue);
        },
        skip: skipNative,
      );
    }
  }
}

class _RecordingSession implements WampSession {
  core.LazyMessagePayload? request;
  native_buffers.NativeOwnedBuffer? requestOwner;
  native_buffers.NativePptPayloadLease? requestLease;
  bool? exportedViewBeforeCall;
  Uint8List? requestBytes;
  bool ownerWasLiveDuringCall = false;
  bool throwOnCall = false;
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
    final source = core.packedPayloadSourceOf(payload);
    if (source is native_buffers.NativePptPayloadLease) {
      requestLease = source;
      requestOwner = source.nativeOwnerFor(payload);
      exportedViewBeforeCall = source.hasExportedByteView;
    } else {
      requestOwner = payload.anchor as native_buffers.NativeOwnedBuffer?;
    }
    ownerWasLiveDuringCall = requestOwner?.isDisposed == false;
    this.options = options;
    if (throwOnCall) throw StateError('Simulated Session send rejection');
    // Simulate a consumer reading the result, after recording that construction
    // itself did not export a view. This view must survive lease disposal.
    requestBytes = payload.packedPayloadBytes;
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

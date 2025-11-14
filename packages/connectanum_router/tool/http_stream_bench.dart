import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:http2/transport.dart';
import 'dart:convert';

Future<void> main(List<String> rawArgs) async {
  final options = BenchOptions.parse(rawArgs);
  final runtime = NativeTransportRuntime(libraryPath: options.nativeLib);
  runtime.start();

  final router = Router(_buildRouterConfig(), settings: _buildRouterSettings());
  final binding = router.start(
    runtime,
    onEvent: options.verbose ? _logEvent : null,
  );

  // Give the boss/worker loop time to spawn.
  await Future<void>.delayed(const Duration(milliseconds: 200));

  final listener = binding.listeners.single;
  final session = await binding.createInternalSession(
    realmUri: 'realm1',
    authId: 'http-bench',
    authRole: 'internal',
  );
  final registration = await session.register('com.example.http.stream');
  final responseChunk = _buildPatternChunk(options.responseChunkSize);
  registration.onInvoke((invocation) async {
    final context = HttpInvocationContext.maybeFromInvocation(invocation);
    if (context == null) {
      return;
    }
    final received = context.request.body?.length ?? 0;
    if (options.verbose) {
      stderr.writeln('[handler] received ${_formatBytes(received)}');
    }
    final stream = context.streamResponse(
      status: 206,
      headers: const {
        'content-type': 'application/octet-stream',
        'x-bench': 'http2',
      },
    );
    var remaining = options.responseBytes;
    while (remaining > 0) {
      final toSend = math.min(remaining, responseChunk.length).toInt();
      stream.add(Uint8List.sublistView(responseChunk, 0, toSend));
      remaining -= toSend;
    }
    stream.close();
  });

  final bench = Http2StreamBench(
    host: listener.endpoint.host,
    port: listener.port,
    iterations: options.iterations,
    requestBytes: options.requestBytes,
    responseBytes: options.responseBytes,
  );

  final startMetrics = await binding.collectMetrics();
  try {
    final summary = await bench.run();
    final endMetrics = await binding.collectMetrics();
    _printSummary(summary, options, startMetrics, endMetrics);
  } finally {
    await session.unregister(registration.registrationId);
    await session.close();
    await binding.dispose();
    runtime.shutdown();
  }
}

void _logEvent(Object event) {
  if (event is Map) {
    final type = event['type'];
    if (type == 'worker_ready' || type == 'worker_registered') {
      stderr.writeln('[router] $event');
    }
  }
}

class BenchOptions {
  BenchOptions({
    required this.iterations,
    required this.requestBytes,
    required this.responseBytes,
    required this.responseChunkSize,
    required this.nativeLib,
    required this.verbose,
  });

  final int iterations;
  final int requestBytes;
  final int responseBytes;
  final int responseChunkSize;
  final String? nativeLib;
  final bool verbose;

  static BenchOptions parse(List<String> rawArgs) {
    final parser = ArgParser()
      ..addOption(
        'iterations',
        abbr: 'n',
        defaultsTo: '8',
        help: 'Number of HTTP/2 requests to run sequentially.',
      )
      ..addOption(
        'upload-mib',
        defaultsTo: '1',
        help: 'Request payload size in mebibytes.',
      )
      ..addOption(
        'download-mib',
        defaultsTo: '1',
        help: 'Response payload size in mebibytes.',
      )
      ..addOption(
        'chunk-kib',
        defaultsTo: '64',
        help: 'Size of each streamed response chunk in KiB.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        defaultsTo: false,
        help: 'Print router worker lifecycle events.',
      )
      ..addOption(
        'native-lib',
        help: 'Path to libct_ffi.so; defaults to CONNECTANUM_NATIVE_LIB.',
      );

    final args = parser.parse(rawArgs);
    final iterations = math.max(
      1,
      int.tryParse(args['iterations'] as String? ?? '') ?? 8,
    );
    final uploadMiB = math.max(
      0,
      int.tryParse(args['upload-mib'] as String? ?? '') ?? 1,
    );
    final downloadMiB = math.max(
      0,
      int.tryParse(args['download-mib'] as String? ?? '') ?? 1,
    );
    final chunkKiB = math.max(
      1,
      int.tryParse(args['chunk-kib'] as String? ?? '') ?? 64,
    );
    final nativeLib =
        (args['native-lib'] as String?) ??
        Platform.environment['CONNECTANUM_NATIVE_LIB'];
    if (nativeLib == null || nativeLib.isEmpty) {
      throw StateError(
        'CONNECTANUM_NATIVE_LIB must be set or pass --native-lib',
      );
    }
    return BenchOptions(
      iterations: iterations,
      requestBytes: uploadMiB * 1024 * 1024,
      responseBytes: downloadMiB * 1024 * 1024,
      responseChunkSize: chunkKiB * 1024,
      nativeLib: nativeLib,
      verbose: args['verbose'] as bool? ?? false,
    );
  }
}

class Http2StreamBench {
  Http2StreamBench({
    required this.host,
    required this.port,
    required this.iterations,
    required this.requestBytes,
    required this.responseBytes,
  });

  final String host;
  final int port;
  final int iterations;
  final int requestBytes;
  final int responseBytes;

  Future<BenchSummary> run() async {
    final socket = await Socket.connect(host, port);
    final connection = ClientTransportConnection.viaSocket(socket);
    final samples = <BenchSample>[];
    try {
      for (var i = 0; i < iterations; i++) {
        samples.add(await _runSingleRequest(connection));
      }
    } finally {
      await connection.finish();
      await socket.close();
    }
    return BenchSummary(samples: samples);
  }

  Future<BenchSample> _runSingleRequest(
    ClientTransportConnection connection,
  ) async {
    final headers = <Header>[
      Header.ascii(':method', 'POST'),
      Header.ascii(':path', '/api/stream'),
      Header.ascii(':scheme', 'http'),
      Header.ascii(':authority', '$host:$port'),
      Header.ascii('content-type', 'application/octet-stream'),
      Header.ascii('content-length', requestBytes.toString()),
    ];

    final stream = connection.makeRequest(
      headers,
      endStream: requestBytes == 0,
    );
    if (requestBytes > 0) {
      final chunk = _buildPatternChunk(64 * 1024);
      var remaining = requestBytes;
      while (remaining > 0) {
        final toSend = math.min(remaining, chunk.length).toInt();
        stream.outgoingMessages.add(
          DataStreamMessage(Uint8List.sublistView(chunk, 0, toSend)),
        );
        remaining -= toSend;
      }
      await stream.outgoingMessages.close();
    }

    var statusCode = 0;
    var responseLen = 0;
    final sw = Stopwatch()..start();
    await for (final message in stream.incomingMessages) {
      if (message is HeadersStreamMessage) {
        for (final header in message.headers) {
          final name = utf8.decode(header.name);
          if (name == ':status') {
            final value = utf8.decode(header.value);
            statusCode = int.tryParse(value) ?? statusCode;
          }
        }
      } else if (message is DataStreamMessage) {
        responseLen += message.bytes.length;
      }
    }
    sw.stop();
    return BenchSample(
      elapsed: sw.elapsed,
      status: statusCode,
      requestBytes: requestBytes,
      responseBytes: responseLen,
    );
  }
}

class BenchSample {
  const BenchSample({
    required this.elapsed,
    required this.status,
    required this.requestBytes,
    required this.responseBytes,
  });

  final Duration elapsed;
  final int status;
  final int requestBytes;
  final int responseBytes;
}

class BenchSummary {
  BenchSummary({required this.samples});

  final List<BenchSample> samples;

  Duration get totalDuration =>
      samples.fold(Duration.zero, (acc, sample) => acc + sample.elapsed);

  int get totalRequestBytes =>
      samples.fold(0, (value, sample) => value + sample.requestBytes);

  int get totalResponseBytes =>
      samples.fold(0, (value, sample) => value + sample.responseBytes);

  double get throughputMbps {
    final totalBits = (totalRequestBytes + totalResponseBytes) * 8;
    final seconds = totalDuration.inMicroseconds / 1e6;
    if (seconds == 0) {
      return 0;
    }
    return totalBits / seconds / (1024 * 1024);
  }
}

void _printSummary(
  BenchSummary summary,
  BenchOptions options,
  RouterMetricsSnapshot startMetrics,
  RouterMetricsSnapshot endMetrics,
) {
  stdout.writeln('HTTP/2 streaming benchmark');
  stdout.writeln('Iterations     : ${options.iterations}');
  stdout.writeln('Upload         : ${_formatBytes(summary.totalRequestBytes)}');
  stdout.writeln(
    'Download       : ${_formatBytes(summary.totalResponseBytes)}',
  );
  stdout.writeln('Total duration : ${summary.totalDuration.inMilliseconds} ms');
  stdout.writeln(
    'Throughput     : ${summary.throughputMbps.toStringAsFixed(2)} Mbit/s',
  );
  final startTransport = startMetrics.transport;
  final endTransport = endMetrics.transport;
  if (startTransport != null && endTransport != null) {
    final delta = _transportDelta(startTransport, endTransport);
    stdout.writeln(
      'HTTP events    : +${delta.totalEvents} total '
      '(graceful ${delta.gracefulEvents}, goaway ${delta.goAwayEvents}, '
      'idle ${delta.idleTimeoutEvents}, body ${delta.bodyTimeoutEvents})',
    );
    stdout.writeln(
      'Backpressure   : +${delta.backpressureEvents} (max depth ${delta.maxBackpressureDepth})',
    );
  }
}

Uint8List _buildPatternChunk(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31) & 0xFF;
  }
  return bytes;
}

RouterConfig _buildRouterConfig() => RouterConfig(
  endpoints: [
    Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
    ),
  ],
);

RouterSettings _buildRouterSettings() {
  final realm = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('anonymous')..allowOperations(const [
          'register',
          'unregister',
          'subscribe',
          'unsubscribe',
          'publish',
          'call',
        ]),
      ),
    );

  final listener = ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
    ..addAuthMethod('anonymous')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..addProtocol(ListenerProtocol.http)
    ..addProtocol(ListenerProtocol.http2)
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      const HttpListenerSettings(
        alpn: ['h2', 'http/1.1'],
        routes: [
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/api/stream'),
            action: HttpRouteAction(
              type: HttpRouteActionType.rpc,
              procedure: 'com.example.http.stream',
            ),
          ),
        ],
      ),
    );

  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(realm)
        ..addListenerFromBuilder(listener)
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        ))
      .build();
}

RouterTransportMetrics _transportDelta(
  RouterTransportMetrics start,
  RouterTransportMetrics end,
) {
  return RouterTransportMetrics(
    totalEvents: end.totalEvents - start.totalEvents,
    gracefulEvents: end.gracefulEvents - start.gracefulEvents,
    goAwayEvents: end.goAwayEvents - start.goAwayEvents,
    idleTimeoutEvents: end.idleTimeoutEvents - start.idleTimeoutEvents,
    bodyTimeoutEvents: end.bodyTimeoutEvents - start.bodyTimeoutEvents,
    protocolErrorEvents: end.protocolErrorEvents - start.protocolErrorEvents,
    internalErrorEvents: end.internalErrorEvents - start.internalErrorEvents,
    backpressureEvents: end.backpressureEvents - start.backpressureEvents,
    maxBackpressureDepth: end.maxBackpressureDepth,
  );
}

String _formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(2)} ${units[unit]}';
}

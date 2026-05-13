@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketWampSessionFactory', () {
    test(
      'allowInsecureCertificates permits secure Dart websocket sessions against self-signed bench certs',
      () async {
        final server = await _startSecureWebSocketServer();
        addTearDown(() => server.close(force: true));

        final factory = WebSocketWampSessionFactory(
          url: 'wss://localhost:${server.port}/wamp',
          realmUri: 'bench.control',
          serializer: WampSerializer.json,
          clientImplementation: WampClientImplementation.dart,
          allowInsecureCertificates: true,
        );

        final session = await factory.call();
        expect(session, isNotNull);
      },
    );
  });
}

Future<HttpServer> _startSecureWebSocketServer() async {
  final context = SecurityContext()
    ..useCertificateChain(_resolveBenchTlsFixture('bench_tls.crt'))
    ..usePrivateKey(_resolveBenchTlsFixture('bench_tls.key'));
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((request) async {
    if (request.uri.path != '/wamp') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((message) {
      if (message is String && message.contains('[1,')) {
        socket.add('[2,1234,{}]');
      }
    });
  });
  return server;
}

String _resolveBenchTlsFixture(String fileName) {
  final candidates = [
    File('native/bench/$fileName'),
    File('../../native/bench/$fileName'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  throw StateError(
    'Failed to locate native/bench/$fileName from ${Directory.current.path}.',
  );
}

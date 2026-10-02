@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';
import '../support/native_lib.dart';

void main() {
  final libraryPath = resolveOrBuildNativeLib();
  test(
    'HTTP3 wrapper preserves payload and UTF8 header byte lengths',
    () async {
      final package = Directory('test/certs').existsSync()
          ? Directory.current
          : Directory('packages/connectanum_router').absolute;
      final server = await Process.start(Platform.resolvedExecutable, [
        'run',
        '${package.path}/test/support/http3_wrapper_server.dart',
        File(libraryPath!).absolute.path,
        '${package.path}/test/certs',
      ]);
      final errors = <String>[];
      final errorSubscription = server.stderr.transform(utf8.decoder).listen((
        chunk,
      ) {
        errors.add(chunk);
        // Preserve server-side diagnostics when a later client call fails.
        stderr.write(chunk);
      });
      addTearDown(() async {
        server.kill();
        await server.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () async {
            server.kill(ProcessSignal.sigkill);
            return server.exitCode.timeout(const Duration(seconds: 5));
          },
        );
        await errorSubscription.cancel();
      });
      final ready = Completer<int>();
      final output = server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final port = int.tryParse(line);
            if (port != null && !ready.isCompleted) ready.complete(port);
          });
      addTearDown(output.cancel);
      final port = await Future.any([
        ready.future,
        server.exitCode.then<int>(
          (code) => throw StateError('Server exited $code: ${errors.join()}'),
        ),
      ]).timeout(const Duration(seconds: 30));
      expect(port, greaterThan(0));
      final runtime = NativeTransportRuntime(libraryPath: libraryPath);
      addTearDown(runtime.dispose);
      expect(runtime.supportsHttp3TestClient, isTrue);
      final certificate = File(
        '${package.path}/test/certs/http3_ca_cert.pem',
      ).readAsStringSync();
      for (final value in ['ascii', '\u00e9']) {
        final body = Uint8List.fromList([0, 127, 128, 255]);
        late NativeHttpTestResponse response;
        expect(
          () => response = runtime.runHttp3StreamRequest(
            host: '127.0.0.1',
            port: port,
            path: '/echo',
            method: 'POST',
            headers: {'x-client': value},
            body: body,
            certificatePem: certificate,
          ),
          returnsNormally,
          reason: 'Valid header value $value must reach server',
        );
        expect(response.status, 207);
        expect(response.headers['x-fixture'], 'echo');
        expect(response.body, body);
      }
      for (final body in <Uint8List?>[
        null,
        Uint8List(0),
        Uint8List.fromList(List.generate(65537, (index) => index % 251)),
      ]) {
        final response = runtime.runHttp3StreamRequest(
          host: '127.0.0.1',
          port: port,
          path: '/echo',
          method: 'POST',
          certificatePem: certificate,
          body: body,
        );
        expect(response.status, 207);
        expect(response.headers['x-fixture'], 'echo');
        expect(response.body, body ?? isEmpty);
      }
      for (final headers in [
        {'bad header': 'value'},
        {'x-client': 'injected\r\nheader: value'},
        {'\u00e9': 'value'},
      ]) {
        expect(
          () => runtime.runHttp3StreamRequest(
            host: '127.0.0.1',
            port: port,
            path: '/echo',
            method: 'POST',
            certificatePem: certificate,
            headers: headers,
          ),
          throwsA(
            isA<NativeTransportException>().having(
              (error) => error.code,
              'error code',
              NativeTransportErrorCode.invalidArgument,
            ),
          ),
        );
      }
      expect(
        () => runtime.runHttp3StreamRequest(
          host: '127.0.0.1',
          port: 0,
          path: '/echo',
          method: 'POST',
          certificatePem: certificate,
        ),
        throwsA(
          isA<NativeTransportException>().having(
            (error) => error.code,
            'error code',
            NativeTransportErrorCode.invalidArgument,
          ),
        ),
      );
      final recovered = runtime.runHttp3StreamRequest(
        host: '127.0.0.1',
        port: port,
        path: '/echo',
        method: 'POST',
        certificatePem: certificate,
        body: Uint8List.fromList([42]),
      );
      expect(recovered.status, 207);
      expect(recovered.body, [42]);
      server.stdin.writeln('stop');
      expect(await server.exitCode.timeout(const Duration(seconds: 10)), 0);
    },
    skip: libraryPath == null ? 'Native library unavailable' : false,
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectanum_mcp/src/cli/router_hosted_client.dart';

class Capture implements Stdout {
  final text = StringBuffer();
  @override
  void writeln([Object? value = '']) => text.writeln(value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Record the complete, real public-router protocol used by CLI regressions.
/// Run after bin/bootstrap and a fresh ffi-test native build, from the repo root.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError(
      'Usage: dart run packages/connectanum_mcp/tool/record_router_protocol_fixture.dart OUTPUT.json.gz',
    );
  }
  final libraryName = Platform.isWindows
      ? 'ct_ffi.dll'
      : Platform.isMacOS
      ? 'libct_ffi.dylib'
      : 'libct_ffi.so';
  final native = File(
    Platform.environment['CONNECTANUM_NATIVE_LIB'] ??
        'native/transport/target/ffi-test/release/$libraryName',
  );
  if (!native.existsSync()) {
    throw StateError('Build the current ffi-test native library first.');
  }
  final child = await Process.start(Platform.resolvedExecutable, [
    'run',
    'packages/connectanum_router/example/router_hosted_mcp.dart',
    native.absolute.path,
  ]);
  final ready = Completer<Uri>();
  final errors = StringBuffer();
  Uri? address;
  final outSub = child.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        const prefix = 'Router-hosted MCP endpoint is running at ';
        if (line.startsWith(prefix)) {
          address = Uri.parse(line.substring(prefix.length));
        }
        if (line == 'Press Ctrl+C to stop.' &&
            address != null &&
            !ready.isCompleted) {
          ready.complete(address!);
        }
      });
  final errSub = child.stderr.transform(utf8.decoder).listen(errors.write);
  HttpServer? server;
  final client = HttpClient();
  final records = <Map<String, Object?>>[];
  final pending = <Future<void>>{};
  try {
    final endpoint = await ready.future.timeout(const Duration(seconds: 20));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      late Future<void> operation;
      operation = (() async {
        final body = await utf8.decoder.bind(request).join();
        final reqHeaders = <String, List<String>>{};
        request.headers.forEach((n, v) => reqHeaders[n] = v);
        final row = <String, Object?>{
          'method': request.method,
          'path': request.uri.toString(),
          'headers': reqHeaders,
          'body': body,
        };
        records.add(row);
        final outgoing = await client.openUrl(
          request.method,
          endpoint.replace(query: request.uri.query),
        );
        request.headers.forEach((n, v) {
          if (![
            'host',
            'content-length',
            'transfer-encoding',
            'connection',
          ].contains(n)) {
            outgoing.headers.set(n, v);
          }
        });
        final encodedBody = utf8.encode(body);
        outgoing.contentLength = encodedBody.length;
        outgoing.add(encodedBody);
        final response = await outgoing.close();
        row['status'] = response.statusCode;
        final headers = <String, List<String>>{};
        response.headers.forEach((n, v) {
          headers[n] = v;
          if (![
            'content-length',
            'transfer-encoding',
            'connection',
          ].contains(n)) {
            request.response.headers.set(n, v);
          }
        });
        row['responseHeaders'] = headers;
        request.response.statusCode = response.statusCode;
        final text = await utf8.decoder.bind(response).join();
        row['responseBody'] = text;
        request.response.write(text);
        await request.response.close();
      })().whenComplete(() => pending.remove(operation));
      pending.add(operation);
    });
    final captured = Capture();
    await IOOverrides.runZoned(
      () => runRouterHostedClient([
        '--endpoint',
        'http://127.0.0.1:${server!.port}/mcp',
        '--protocol-version',
        '2025-06-18',
        '--rejected-origin',
        'https://rejected.example',
        '--tool',
        'example.task.lookup',
        '--tool-arguments',
        '{"taskId":"T-cli-regression"}',
        '--resource-uri',
        'app://example/context/live',
        '--resource-update-topic',
        'example.events.context.updated',
        '--prompt',
        'summarize-task',
        '--prompt-arguments',
        '{"taskId":"T-cli-regression"}',
        '--wamp-procedure',
        'example.task.configured.lookup',
        '--wamp-topic',
        'example.events.task',
        '--pubsub-topic',
        'example.events.task',
        '--pubsub-event',
        '{"taskId":"T-cli-regression","status":"open"}',
      ]).timeout(const Duration(seconds: 20)),
      stdout: () => captured,
      stderr: () => captured,
    );
    final output = args.single;
    final encoded = utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'protocol': '2025-06-18',
        'requests': records,
        'transcript': captured.text.toString(),
      }),
    );
    await File(output).writeAsBytes(gzip.encode(encoded));
    stdout.writeln('Recorded ${records.length} exchanges in $output');
  } finally {
    client.close(force: true);
    await server?.close(force: true);
    await Future.wait(pending);
    child.kill(ProcessSignal.sigterm);
    final code = await child.exitCode.timeout(const Duration(seconds: 10));
    await outSub.cancel();
    await errSub.cancel();
    if (code != 0) throw StateError('Example failed ($code): $errors');
  }
}

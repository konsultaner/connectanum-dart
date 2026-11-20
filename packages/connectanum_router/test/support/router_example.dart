import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp.dart' as mcp;
import 'package:test/test.dart';

import 'native_lib.dart';

/// A completed Dart process rejected MCP behavior in the public example.
/// Compiler, native/preflight, signal and deadline failures are not this type.
class RouterExampleSmokeFailure implements Exception {
  RouterExampleSmokeFailure(
    this.diagnostics, {
    this.declarationError,
    this.responseError,
  });

  final String diagnostics;
  final Object? declarationError;
  final Object? responseError;

  static bool _completedMcpFailure(int code, String report) =>
      code == 255 &&
      report.startsWith('Unhandled exception:') &&
      !RegExp(
        r'TimeoutException|SocketException|NativeTransportException|'
        r'ProcessException|FileSystemException|OutOfMemoryError|'
        r'Failed to load dynamic library|Native library|Native ABI',
      ).hasMatch(report);

  static bool needsDeclarationCheck(int code, String report) =>
      _completedMcpFailure(code, report) &&
      report.startsWith(
        'Unhandled exception:\nMcpStreamableHttpException(500):',
      ) &&
      (report.contains('MCP catalog could not be refreshed') ||
          report.contains('http request cancelled'));

  static bool needsResponseCheck(int code, String report) {
    if (!_completedMcpFailure(code, report)) return false;
    final lines = const LineSplitter().convert(report);
    if (lines.length < 2) return false;
    final missingResponse =
        lines[1] == 'FormatException: JSON-RPC response was not returned' &&
        RegExp(
          r'^#\d+\s+McpStreamableHttpClient\._validatePostResponseShape '
          r'\(package:connectanum_client/src/mcp/streamable_http_client\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report);
    final missingDeclaredTool =
        RegExp(
          r'^McpJsonRpcException\((?:connectanum\.tool\.call|tools/call), '
          r'id: public-direct-[^)]*\): Unknown MCP tool: '
          r'connectanum\.(?:pubsub\.(?:publish|subscribe|unsubscribe|poll)|api\.(?:list|describe))$',
        ).hasMatch(lines[1]) &&
        RegExp(
          r'^#\d+\s+_jsonRpcResultFrom '
          r'\(package:connectanum_client/src/mcp/streamable_http_client\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report) &&
        RegExp(
          r'^#\d+\s+_smoke\w+ .*'
          r'/packages/connectanum_router/example/router_hosted_mcp\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report);
    return missingResponse || missingDeclaredTool;
  }

  static RouterExampleSmokeFailure? fromExit(
    int code,
    String report, {
    Object? declarationError,
    Object? responseError,
  }) {
    if (!_completedMcpFailure(code, report)) return null;
    final smokeFrame = RegExp(
      r'^#\d+\s+_(?:smoke|expect|assert)\w+ .*'
      r'/packages/connectanum_router/example/router_hosted_mcp\.dart:\d+:\d+\)',
      multiLine: true,
    );
    final lines = const LineSplitter().convert(report);
    final productValidation =
        lines.length > 1 &&
        (lines[1].startsWith('Bad state:') ||
            lines[1].startsWith('Invalid argument') ||
            lines[1].startsWith('FormatException:') ||
            lines[1].startsWith('McpException(') ||
            lines[1].startsWith('McpStreamableWampToolException('));
    final routeValidation =
        lines.length > 1 &&
        lines[1].startsWith('Bad state: Invalid MCP route options:') &&
        RegExp(
          r'^#\d+\s+_validateMcpRouteOptions '
          r'\(package:connectanum_router/src/router/router_instance/'
          r'router_mcp\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report);
    final responseIdValidation =
        lines.length > 1 &&
        RegExp(
          r'^FormatException: JSON-RPC (?:SSE event data )?response id '
          r'must be a string or integer$',
        ).hasMatch(lines[1]) &&
        RegExp(
          r'^#\d+\s+_validateJsonRpcResponseId '
          r'\(package:connectanum_client/src/mcp/'
          r'streamable_http_client\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report);
    final responseShapeValidation =
        lines.length > 1 &&
        lines[1] ==
            'FormatException: JSON-RPC response error must be a JSON object' &&
        RegExp(
          r'^#\d+\s+_validateJsonRpcResponseObject '
          r'\(package:connectanum_client/src/mcp/'
          r'streamable_http_client\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report);
    final jsonRpcRejection =
        lines.length > 1 &&
        RegExp(
          r'^McpJsonRpcException\((?:tools/call|tools/list|resources/list|prompts/get|connectanum\.tool\.call), '
          r'id: public-direct-[^)]*\): '
          r'(?:Client does not support required MCP form elicitation|'
          r'(?:tools|resources)/list\.params\.cursor is invalid or stale|'
          r'Missing required MCP prompt argument: taskId|'
          r'connectanum\.api\.list\.arguments\.cursor is invalid or stale|'
          r'tools/call\.params\.requestState must be a string|'
          r'tools/call\.params\.inputResponses must be an object|'
          r'Unknown MCP tool: connectanum\.api\.list)$',
        ).hasMatch(lines[1]) &&
        smokeFrame.hasMatch(report);
    final bufferedEventFailure =
        lines.length > 1 &&
        lines[1] ==
            'RangeError (length): Invalid value: Valid value range is empty: 0' &&
        RegExp(
          r'^#\d+\s+_BufferedSubscription\._dropOldest '
          r'\(package:connectanum_mcp/src/tools/wamp_api\.dart:\d+:\d+\)',
          multiLine: true,
        ).hasMatch(report);
    if (routeValidation ||
        responseIdValidation ||
        responseShapeValidation ||
        jsonRpcRejection ||
        bufferedEventFailure ||
        (productValidation &&
            (report.contains('package:connectanum_mcp/') ||
                smokeFrame.hasMatch(report)))) {
      return RouterExampleSmokeFailure(report);
    }
    if (needsResponseCheck(code, report) && responseError is TestFailure) {
      return RouterExampleSmokeFailure(report, responseError: responseError);
    }
    if (needsDeclarationCheck(code, report) &&
        (declarationError is ArgumentError ||
            declarationError is FormatException)) {
      return RouterExampleSmokeFailure(
        report,
        declarationError: declarationError,
      );
    }
    return null;
  }

  @override
  String toString() =>
      'Public MCP example smoke failed: $diagnostics'
      '${responseError == null ? '' : '\nValid MCP response contract failed: $responseError'}'
      '${declarationError == null ? '' : '\nValid MCP declaration rejected: $declarationError'}';
}

/// Corroborate a missing response using public in-process server behavior.
/// Runtime errors remain runtime errors; only explicit response assertions count.
Future<Object?> checkRouterExampleMcpResponses() async {
  mcp.McpServer? server;
  try {
    final tools =
        mcp.McpWampApi(
          procedures: [mcp.McpWampProcedure(procedure: 'com.example.echo')],
          topics: [mcp.McpWampTopic(topic: 'com.example.events')],
        ).toTools(
          call: (_) => throw StateError('Catalog callback invoked'),
          publish: (_) => throw StateError('Catalog callback invoked'),
          subscribe: (_, _) => throw StateError('Catalog callback invoked'),
          unsubscribe: (_) => throw StateError('Catalog callback invoked'),
        );
    server = mcp.McpServer(
      tools: tools,
      serverInfo: const mcp.McpServerInfo(
        name: 'example-response-probe',
        version: '1',
      ),
    );
    final response = await server.handleMessage({
      'jsonrpc': '2.0',
      'id': 'diagnostic-initialize',
      'method': 'initialize',
      'params': {'protocolVersion': mcp.mcpLatestSessionProtocolVersion},
    });
    expect(response, isA<Map>());
    expect(response, containsPair('id', 'diagnostic-initialize'));
    expect(response, containsPair('result', isA<Map>()));
    expect(
      response['result'],
      containsPair('protocolVersion', mcp.mcpLatestSessionProtocolVersion),
    );
    expect(
      await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
      isNull,
    );
    expect(server.state, mcp.McpServerState.initialized);
    final catalogResponse = await server.handleMessage({
      'jsonrpc': '2.0',
      'id': 'diagnostic-tools',
      'method': 'tools/list',
    });
    expect(catalogResponse, isA<Map>());
    expect(catalogResponse, containsPair('result', isA<Map>()));
    final catalog = catalogResponse['result']['tools'];
    expect(catalog, isA<List>());
    expect(catalog, everyElement(isA<Map>()));
    for (final name in [
      'connectanum.api.list',
      'connectanum.api.describe',
      'connectanum.pubsub.publish',
      'connectanum.pubsub.subscribe',
      'connectanum.pubsub.unsubscribe',
      'connectanum.pubsub.poll',
    ]) {
      expect(
        catalog,
        contains(containsPair('name', name)),
        reason: 'Declared default MCP tool must be listed',
      );
    }
    return null;
  } catch (error) {
    return error;
  } finally {
    server?.shutdown();
  }
}

/// Pure declarations distinguish invalid product validation from an ambiguous
/// HTTP 500. No callback is invoked and no network/native operation is retried.
Object? checkRouterExampleMcpDeclarations() {
  try {
    final resources = [
      mcp.McpResource(
        uri: 'app://example/context/live',
        name: 'example-context',
        read: (_) => throw StateError('Declaration callback invoked'),
      ),
    ];
    for (final configured in [false, true]) {
      final tools =
          mcp.McpWampApi(
            listPageSize: configured ? 1 : null,
            procedures: [mcp.McpWampProcedure(procedure: 'com.example.echo')],
            topics: [mcp.McpWampTopic(topic: 'com.example.events')],
          ).toTools(
            maxBufferedEventBytes: configured ? 1024 : null,
            call: (_) => throw StateError('Declaration callback invoked'),
            publish: (_) => throw StateError('Declaration callback invoked'),
            subscribe: (_, _) =>
                throw StateError('Declaration callback invoked'),
            unsubscribe: (_) =>
                throw StateError('Declaration callback invoked'),
          );
      for (final capabilities in [
        null,
        const mcp.McpServerCapabilities(
          prompts: mcp.McpPromptCapabilities(),
          resources: mcp.McpResourceCapabilities(subscribe: true),
          completions: mcp.McpCompletionCapabilities(),
        ),
      ]) {
        mcp.McpServer(
          capabilities: capabilities,
          serverInfo: const mcp.McpServerInfo(name: 'example', version: '1.0'),
          tools: tools,
          resources: resources,
          resourceTemplates: [
            mcp.McpResourceTemplate(
              uriTemplate: 'app://example/context/{id}',
              name: 'example-template',
              read: (_, _) => throw StateError('Declaration callback invoked'),
            ),
          ],
          prompts: [
            mcp.McpPrompt(
              name: 'example-prompt',
              complete: (_) => throw StateError('Declaration callback invoked'),
              handler: (_) => throw StateError('Declaration callback invoked'),
            ),
          ],
          toolListPageSize: 1,
          promptListPageSize: 1,
          resourceListPageSize: 1,
          resourceTemplateListPageSize: 1,
          onSubscribeResource: (_) =>
              throw StateError('Declaration callback invoked'),
          onUnsubscribeResource: (_) =>
              throw StateError('Declaration callback invoked'),
        );
      }
    }
  } on ArgumentError catch (error) {
    return error;
  } on FormatException catch (error) {
    return error;
  }
  return null;
}

class RouterExample {
  RouterExample(this.process);
  final Process process;
  final ready = Completer<void>();
  final subscriptions = <StreamSubscription<String>>[];
  Uri? address;
  Future<int>? _closing;

  Uri endpoint(String route) => address!.replace(path: route);

  static Future<RouterExample> start() async {
    final native = resolveOrBuildNativeLib();
    if (native == null) {
      throw StateError('Native library is required for CLI integration tests.');
    }
    var root = Directory.current.absolute;
    while (!File(
      '${root.path}/packages/connectanum_router/example/router_hosted_mcp.dart',
    ).existsSync()) {
      if (root.parent.path == root.path) {
        throw StateError('Router example workspace not found.');
      }
      root = root.parent;
    }
    final fixture = RouterExample(
      await Process.start(Platform.resolvedExecutable, [
        'run',
        'packages/connectanum_router/example/router_hosted_mcp.dart',
        File(native).absolute.path,
      ], workingDirectory: root.path),
    );
    // Register before awaiting readiness so test timeouts still reap the child.
    addTearDown(() => fixture.close(expectSuccess: false));
    fixture.subscriptions.add(
      fixture.process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            const prefix = 'Router-hosted MCP endpoint is running at ';
            if (line.startsWith(prefix)) {
              fixture.address = Uri.parse(line.substring(prefix.length));
            }
            if (line == 'Press Ctrl+C to stop.' &&
                fixture.address != null &&
                !fixture.ready.isCompleted) {
              fixture.ready.complete();
            }
          }),
    );
    final diagnostics = StringBuffer();
    final stderrDone = Completer<void>();
    fixture.subscriptions.add(
      fixture.process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(diagnostics.writeln, onDone: stderrDone.complete),
    );
    try {
      await Future.any([
        fixture.ready.future,
        fixture.process.exitCode.then((code) async {
          await stderrDone.future;
          final report = diagnostics.toString();
          final declarationError =
              RouterExampleSmokeFailure.needsDeclarationCheck(code, report)
              ? checkRouterExampleMcpDeclarations()
              : null;
          final responseError =
              RouterExampleSmokeFailure.needsResponseCheck(code, report)
              ? await checkRouterExampleMcpResponses()
              : null;
          final smoke = RouterExampleSmokeFailure.fromExit(
            code,
            report,
            declarationError: declarationError,
            responseError: responseError,
          );
          if (smoke != null) throw smoke;
          throw StateError(
            'Router example exited before readiness ($code).\n$report',
          );
        }),
      ]).timeout(const Duration(seconds: 20));
      return fixture;
    } catch (_) {
      await fixture.close(expectSuccess: false);
      rethrow;
    }
  }

  Future<void> close({
    bool expectSuccess = true,
    ProcessSignal signal = ProcessSignal.sigterm,
  }) async {
    final code = await (_closing ??= _stop(signal));
    if (expectSuccess) expect(code, 0, reason: 'Router must shut down cleanly');
  }

  Future<int> _stop(ProcessSignal signal) async {
    process.kill(signal);
    try {
      return await process.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          process.kill(ProcessSignal.sigkill);
          return process.exitCode.timeout(const Duration(seconds: 2));
        },
      );
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }
}

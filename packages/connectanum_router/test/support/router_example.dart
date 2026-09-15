import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'native_lib.dart';

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
    fixture.subscriptions.add(
      fixture.process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {}),
    );
    try {
      await Future.any([
        fixture.ready.future,
        fixture.process.exitCode.then(
          (code) => throw StateError(
            'Router example exited before readiness ($code).',
          ),
        ),
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

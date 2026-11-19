@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/router_example.dart';

void main() {
  const smoke = '''Unhandled exception:
Bad state: Direct JSON-RPC topic API list missed topic metadata.
#0      _smokeDirectJsonTopicMetaApi (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2989:5)
<asynchronous suspension>
''';
  const library = '''Unhandled exception:
Invalid argument (pageSize): MCP resource list page size must be positive.
#0      McpServer (package:connectanum_mcp/src/server/mcp_server.dart:71:7)
''';
  for (final report in [smoke, library]) {
    test('recognizes completed product rejection ${report.split('\n')[1]}', () {
      expect(
        RouterExampleSmokeFailure.fromExit(255, report),
        isA<RouterExampleSmokeFailure>().having(
          (failure) => failure.diagnostics,
          'original diagnostic',
          report,
        ),
      );
    });
    for (final exit in [0, 1, 254, -9, -11]) {
      test('exit $exit retains infrastructure classification', () {
        expect(RouterExampleSmokeFailure.fromExit(exit, report), isNull);
      });
    }
    test('a nested deadline is never product assertion evidence', () {
      expect(
        RouterExampleSmokeFailure.fromExit(
          255,
          '$report\nTimeoutException after 20 seconds',
        ),
        isNull,
      );
    });
  }
  for (final report in [
    'packages/connectanum_mcp/example.dart: Error: Compilation failed',
    'Unhandled exception:\nBad state: Native library missing.\n'
        '#0 loadNative (package:connectanum_router/src/runtime.dart:1:1)',
    'Unhandled exception:\nSocketException: Connection refused.\n'
        '#0 McpServer (package:connectanum_mcp/src/server/mcp_server.dart:71:7)',
    'Unhandled exception:\nNativeTransportException: Native ABI unavailable.\n'
        '#0 McpServer (package:connectanum_mcp/src/server/mcp_server.dart:71:7)',
    'Unhandled exception:\nBad state: Unknown runtime failure.',
    'Unhandled exception:\nBad state: Invalid settings.\n'
        '#0 main (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:42:1)',
  ]) {
    test('unclassified startup errors remain setup errors: $report', () {
      expect(RouterExampleSmokeFailure.fromExit(255, report), isNull);
    });
  }
}

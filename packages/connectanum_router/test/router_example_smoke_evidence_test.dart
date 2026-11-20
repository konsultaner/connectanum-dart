@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/router_example.dart';

void main() {
  test('the independent MCP declaration check accepts valid catalogs', () {
    expect(checkRouterExampleMcpDeclarations(), isNull);
  });
  const smoke = '''Unhandled exception:
Bad state: Direct JSON-RPC topic API list missed topic metadata.
#0      _smokeDirectJsonTopicMetaApi (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2989:5)
<asynchronous suspension>
''';
  const library = '''Unhandled exception:
Invalid argument (pageSize): MCP resource list page size must be positive.
#0      McpServer (package:connectanum_mcp/src/server/mcp_server.dart:71:7)
''';
  const tool = '''Unhandled exception:
McpStreamableWampToolException(connectanum.pubsub.publish): arguments.options must be an object
#0      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2199:23)
''';
  const route = '''Unhandled exception:
Bad state: Invalid MCP route options: Duplicate MCP prompt argument
#0      _validateMcpRouteOptions (package:connectanum_router/src/router/router_instance/router_mcp.dart:6180:5)
''';
  const responseId = '''Unhandled exception:
FormatException: JSON-RPC SSE event data response id must be a string or integer
#0      _validateJsonRpcResponseId (package:connectanum_client/src/mcp/streamable_http_client.dart:250:5)
''';
  const responseShape = '''Unhandled exception:
FormatException: JSON-RPC response error must be a JSON object
#0      _jsonMapFrom (package:connectanum_client/src/mcp/streamable_http_client.dart:5686:5)
#1      _validateJsonRpcResponseObject (package:connectanum_client/src/mcp/streamable_http_client.dart:318:19)
''';
  const jsonRpc = '''Unhandled exception:
McpJsonRpcException(tools/call, id: public-direct-call): Client does not support required MCP form elicitation
#0      _jsonRpcResultFrom (package:connectanum_client/src/mcp/streamable_http_client.dart:5415:5)
#1      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2238:24)
''';
  const resourceCursor = '''Unhandled exception:
McpJsonRpcException(resources/list, id: public-direct-resources): resources/list.params.cursor is invalid or stale
#0      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2238:24)
''';
  const toolCursor = '''Unhandled exception:
McpJsonRpcException(tools/list, id: public-direct-tools): tools/list.params.cursor is invalid or stale
#0      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2238:24)
''';
  const inputResponses = '''Unhandled exception:
McpJsonRpcException(tools/call, id: public-direct-call): tools/call.params.inputResponses must be an object
#0      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2238:24)
''';
  const apiTool = '''Unhandled exception:
McpJsonRpcException(connectanum.tool.call, id: public-direct-generic-api-list): Unknown MCP tool: connectanum.api.list
#0      _smokeDirectJsonGenericMetaApi (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2831:24)
''';
  const requestState = '''Unhandled exception:
McpJsonRpcException(tools/call, id: public-direct-call): tools/call.params.requestState must be a string
#0      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2238:24)
''';
  const apiCursor = '''Unhandled exception:
McpJsonRpcException(connectanum.tool.call, id: public-direct-generic-api-list): connectanum.api.list.arguments.cursor is invalid or stale
#0      _smokeDirectJsonGenericMetaApi (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2831:24)
''';
  const promptArgument = '''Unhandled exception:
McpJsonRpcException(prompts/get, id: public-direct-protocol-prompt): Missing required MCP prompt argument: taskId
#0      _smokeMcpEndpoint (file:///workspace/packages/connectanum_router/example/router_hosted_mcp.dart:2238:24)
''';
  const buffer = '''Unhandled exception:
RangeError (length): Invalid value: Valid value range is empty: 0
#0      List.removeAt (dart:core-patch/growable_array.dart:23:22)
#1      _BufferedSubscription._dropOldest (package:connectanum_mcp/src/tools/wamp_api.dart:1340:29)
''';
  for (final report in [
    responseShape.replaceAll('_validateJsonRpcResponseObject', '_parseInput'),
    jsonRpc.replaceAll('public-direct-call', 'unknown-client'),
    jsonRpc.replaceAll(
      'Client does not support required MCP form elicitation',
      'Internal error',
    ),
    buffer.replaceAll(
      '_BufferedSubscription._dropOldest',
      '_NativeBuffer.read',
    ),
  ]) {
    test('unproven similar failure remains an infrastructure failure', () {
      expect(RouterExampleSmokeFailure.fromExit(255, report), isNull);
    });
  }
  for (final report in [
    smoke,
    library,
    tool,
    route,
    responseId,
    responseShape,
    jsonRpc,
    resourceCursor,
    toolCursor,
    promptArgument,
    apiCursor,
    requestState,
    inputResponses,
    apiTool,
    buffer,
  ]) {
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
    for (final diagnostic in [
      'SocketException: Connection refused',
      'NativeTransportException: Native ABI unavailable',
      'FileSystemException: Missing fixture',
    ]) {
      test('nested infrastructure remains setup failure: $diagnostic', () {
        expect(
          RouterExampleSmokeFailure.fromExit(255, '$report\n$diagnostic'),
          isNull,
        );
      });
    }
  }
  for (final detail in [
    'MCP catalog could not be refreshed',
    'http request cancelled',
  ]) {
    final report =
        'Unhandled exception:\nMcpStreamableHttpException(500): $detail';
    test('HTTP 500 needs an independent declaration rejection: $detail', () {
      expect(RouterExampleSmokeFailure.fromExit(255, report), isNull);
      expect(
        RouterExampleSmokeFailure.fromExit(
          255,
          report,
          declarationError: ArgumentError('A valid catalog was rejected'),
        ),
        isA<RouterExampleSmokeFailure>().having(
          (failure) => failure.declarationError,
          'independent product rejection',
          isArgumentError,
        ),
      );
      for (final code in [0, 254, -9]) {
        expect(
          RouterExampleSmokeFailure.fromExit(
            code,
            report,
            declarationError: ArgumentError('A valid catalog was rejected'),
          ),
          isNull,
        );
      }
      expect(
        RouterExampleSmokeFailure.fromExit(
          255,
          '$report\nTimeoutException after 20 seconds',
          declarationError: ArgumentError('A valid catalog was rejected'),
        ),
        isNull,
      );
      expect(
        RouterExampleSmokeFailure.fromExit(
          255,
          report,
          declarationError: StateError('Unclassified checker failure'),
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
    responseId.replaceAll('_validateJsonRpcResponseId', '_unknownParser'),
    route.replaceAll('_validateMcpRouteOptions', '_unknownConfiguration'),
    'Unhandled exception:\nMcpStreamableHttpException(500): Unknown server error',
  ]) {
    test('unclassified startup errors remain setup errors: $report', () {
      expect(RouterExampleSmokeFailure.fromExit(255, report), isNull);
    });
  }
}

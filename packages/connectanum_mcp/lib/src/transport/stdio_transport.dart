import 'dart:async';
import 'dart:convert';

import '../protocol/errors.dart';
import '../protocol/json_rpc.dart';
import '../server/mcp_server.dart';

class McpStdioTransport {
  McpStdioTransport({
    required this.server,
    required Stream<List<int>> input,
    required this.output,
    this.shutdownServerOnDone = true,
  }) : _inputLines = input
           .transform(utf8.decoder)
           .transform(const LineSplitter());

  final McpServer server;
  final StringSink output;
  final bool shutdownServerOnDone;
  final Stream<String> _inputLines;

  Future<void> run() async {
    try {
      await for (final line in _inputLines) {
        await handleLine(line);
      }
    } finally {
      if (shutdownServerOnDone) {
        server.shutdown();
      }
    }
  }

  Future<void> handleLine(String line) async {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      _writeResponse(
        JsonRpcResponse.error(
          null,
          McpException(McpErrorCodes.parseError, 'Invalid JSON-RPC message'),
        ).toJson(),
      );
      return;
    }

    final response = await server.handleMessage(message);
    if (response != null) {
      _writeResponse(response);
    }
  }

  void _writeResponse(JsonMap response) {
    output.writeln(jsonEncode(response));
  }
}

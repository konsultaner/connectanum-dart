import 'dart:async';

import '../protocol/capabilities.dart';
import '../protocol/constants.dart';
import '../protocol/errors.dart';
import '../protocol/json_rpc.dart';
import '../tools/tool.dart';

enum McpServerState { created, initialized, closed }

class McpServer {
  McpServer({
    required this.serverInfo,
    Iterable<McpTool> tools = const [],
    this.instructions,
    McpServerCapabilities? capabilities,
  }) : tools = McpToolRegistry(tools),
       capabilities = capabilities ?? const McpServerCapabilities();

  final McpServerInfo serverInfo;
  final String? instructions;
  final McpToolRegistry tools;
  final McpServerCapabilities capabilities;

  McpServerState _state = McpServerState.created;

  McpServerState get state => _state;

  Future<JsonMap?> handleMessage(Object? rawMessage) async {
    final _ParsedJsonRpcRequest request;
    try {
      request = _requestFrom(rawMessage);
    } on McpException catch (error) {
      return JsonRpcResponse.error(
        _recoverRequestId(rawMessage),
        error,
      ).toJson();
    }
    final id = request.id;
    final method = request.method;

    if (request.isNotification) {
      _handleNotification(method);
      return null;
    }

    try {
      final result = await _handleRequest(id, method, request.params);
      return JsonRpcResponse.result(id, result).toJson();
    } on McpException catch (error) {
      return JsonRpcResponse.error(id, error).toJson();
    } catch (error) {
      return JsonRpcResponse.error(
        id,
        McpException(McpErrorCodes.internalError, error.toString()),
      ).toJson();
    }
  }

  void shutdown() {
    _state = McpServerState.closed;
  }

  Future<JsonMap> _handleRequest(
    Object? id,
    String method,
    JsonMap params,
  ) async {
    if (_state == McpServerState.closed) {
      throw McpException(McpErrorCodes.serverClosed, 'MCP server is closed');
    }
    switch (method) {
      case 'initialize':
        return _initialize(params);
      case 'tools/list':
        _requireInitialized(method);
        return _listTools(params);
      case 'tools/call':
        _requireInitialized(method);
        return _callTool(params);
      default:
        throw McpException(
          McpErrorCodes.methodNotFound,
          'Unknown MCP method: $method',
        );
    }
  }

  void _handleNotification(String method) {
    if (method == 'notifications/initialized' &&
        _state == McpServerState.created) {
      _state = McpServerState.initialized;
    }
  }

  JsonMap _initialize(JsonMap params) {
    final protocolVersion = params['protocolVersion'];
    if (protocolVersion is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'initialize.params.protocolVersion must be a string',
      );
    }
    final result = <String, Object?>{
      'protocolVersion': mcpLatestProtocolVersion,
      'capabilities': capabilities.toJson(),
      'serverInfo': serverInfo.toJson(),
    };
    final instructions = this.instructions;
    if (instructions != null) {
      result['instructions'] = instructions;
    }
    return result;
  }

  JsonMap _listTools(JsonMap params) {
    final cursor = params['cursor'];
    if (cursor != null && cursor is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'tools/list.params.cursor must be a string',
      );
    }
    return <String, Object?>{
      'tools': [
        for (final tool in tools.list(cursor: cursor as String?)) tool.toJson(),
      ],
    };
  }

  Future<JsonMap> _callTool(JsonMap params) async {
    final name = params['name'];
    if (name is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'tools/call.params.name must be a string',
      );
    }
    final arguments = jsonMapFrom(params['arguments'], label: 'arguments');
    final tool = tools[name];
    if (tool == null) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'Unknown MCP tool: $name',
      );
    }
    try {
      final result = await tool.handler(
        McpToolRequest(name: name, arguments: arguments),
      );
      return result.toJson();
    } catch (error) {
      return McpToolResult.error(error.toString()).toJson();
    }
  }

  void _requireInitialized(String method) {
    if (_state != McpServerState.initialized) {
      throw McpException(
        McpErrorCodes.serverNotInitialized,
        '$method requires notifications/initialized first',
      );
    }
  }
}

_ParsedJsonRpcRequest _requestFrom(Object? rawMessage) {
  if (rawMessage is! Map) {
    throw McpException(
      McpErrorCodes.invalidRequest,
      'JSON-RPC message must be an object',
    );
  }
  final message = jsonMapFrom(rawMessage, label: 'message');
  if (message['jsonrpc'] != '2.0') {
    throw McpException(
      McpErrorCodes.invalidRequest,
      'JSON-RPC version must be 2.0',
    );
  }
  final method = message['method'];
  if (method is! String || method.isEmpty) {
    throw McpException(
      McpErrorCodes.invalidRequest,
      'JSON-RPC method must be a non-empty string',
    );
  }
  final hasId = message.containsKey('id');
  final id = hasId ? message['id'] : null;
  if (hasId && !isJsonRpcId(id)) {
    throw McpException(
      McpErrorCodes.invalidRequest,
      'JSON-RPC id must be a string, number, or null',
    );
  }
  return _ParsedJsonRpcRequest(
    id: id,
    isNotification: !hasId,
    method: method,
    params: jsonMapFrom(message['params']),
  );
}

Object? _recoverRequestId(Object? rawMessage) {
  if (rawMessage is! Map || !rawMessage.containsKey('id')) {
    return null;
  }
  final id = rawMessage['id'];
  return isJsonRpcId(id) ? id : null;
}

class _ParsedJsonRpcRequest {
  const _ParsedJsonRpcRequest({
    required this.id,
    required this.isNotification,
    required this.method,
    required this.params,
  });

  final Object? id;
  final bool isNotification;
  final String method;
  final JsonMap params;
}

import 'dart:async';

import '../protocol/capabilities.dart';
import '../protocol/constants.dart';
import '../protocol/errors.dart';
import '../protocol/json_rpc.dart';
import '../prompts/prompt.dart';
import '../resources/resource.dart';
import '../tools/tool.dart';

enum McpServerState { created, initialized, closed }

class McpServer {
  McpServer({
    required this.serverInfo,
    Iterable<McpTool> tools = const [],
    Iterable<McpPrompt> prompts = const [],
    Iterable<McpResource> resources = const [],
    Iterable<McpResourceTemplate> resourceTemplates = const [],
    this.instructions,
    McpServerCapabilities? capabilities,
    int? toolListPageSize,
    int? promptListPageSize,
    int? resourceListPageSize,
    int? resourceTemplateListPageSize,
  }) : tools = McpToolRegistry(tools, toolListPageSize),
       prompts = McpPromptRegistry(prompts, promptListPageSize),
       resources = McpResourceRegistry(
         resources: resources,
         templates: resourceTemplates,
         pageSize: resourceListPageSize,
         templatePageSize: resourceTemplateListPageSize,
       ),
       capabilities =
           capabilities ??
           McpServerCapabilities(
             prompts: prompts.isNotEmpty ? const McpPromptCapabilities() : null,
             resources: resources.isNotEmpty || resourceTemplates.isNotEmpty
                 ? const McpResourceCapabilities()
                 : null,
           );

  final McpServerInfo serverInfo;
  final String? instructions;
  final McpToolRegistry tools;
  final McpPromptRegistry prompts;
  final McpResourceRegistry resources;
  final McpServerCapabilities capabilities;

  McpServerState _state = McpServerState.created;

  McpServerState get state => _state;

  Future<dynamic> handleMessage(Object? rawMessage) async {
    if (rawMessage is List) {
      return _handleBatch(rawMessage);
    }
    return _handleSingleMessage(rawMessage);
  }

  Future<dynamic> _handleBatch(List<Object?> rawMessages) async {
    if (rawMessages.isEmpty) {
      return JsonRpcResponse.error(
        null,
        McpException(
          McpErrorCodes.invalidRequest,
          'JSON-RPC batch must not be empty',
        ),
      ).toJson();
    }
    final responses = <JsonMap>[];
    for (final rawMessage in rawMessages) {
      final response = await _handleSingleMessage(rawMessage);
      if (response != null) {
        responses.add(response);
      }
    }
    return responses.isEmpty ? null : responses;
  }

  Future<JsonMap?> _handleSingleMessage(Object? rawMessage) async {
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
      case 'prompts/list':
        _requireInitialized(method);
        return _listPrompts(params);
      case 'prompts/get':
        _requireInitialized(method);
        return _getPrompt(params);
      case 'resources/list':
        _requireInitialized(method);
        return _listResources(params);
      case 'resources/read':
        _requireInitialized(method);
        return _readResource(params);
      case 'resources/templates/list':
        _requireInitialized(method);
        return _listResourceTemplates(params);
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
    final page = tools.listPage(cursor: cursor as String?);
    final result = <String, Object?>{
      'tools': [for (final tool in page.tools) tool.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
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

  JsonMap _listPrompts(JsonMap params) {
    final cursor = params['cursor'];
    if (cursor != null && cursor is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'prompts/list.params.cursor must be a string',
      );
    }
    final page = prompts.listPage(cursor: cursor as String?);
    final result = <String, Object?>{
      'prompts': [for (final prompt in page.prompts) prompt.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  Future<JsonMap> _getPrompt(JsonMap params) async {
    final name = params['name'];
    if (name is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'prompts/get.params.name must be a string',
      );
    }
    final arguments = _promptArgumentsFrom(params['arguments']);
    final prompt = prompts[name];
    if (prompt == null) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'Unknown MCP prompt: $name',
      );
    }
    prompt.validateArguments(arguments);
    final result = await prompt.handler(
      McpPromptRequest(name: name, arguments: arguments),
    );
    return result.toJson();
  }

  JsonMap _listResources(JsonMap params) {
    final cursor = params['cursor'];
    if (cursor != null && cursor is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'resources/list.params.cursor must be a string',
      );
    }
    final page = resources.listPage(cursor: cursor as String?);
    final result = <String, Object?>{
      'resources': [for (final resource in page.resources) resource.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  Future<JsonMap> _readResource(JsonMap params) async {
    final uri = params['uri'];
    if (uri is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'resources/read.params.uri must be a string',
      );
    }
    final resource = resources[uri];
    if (resource == null) {
      throw McpException(
        McpErrorCodes.resourceNotFound,
        'Resource not found',
        data: <String, Object?>{'uri': uri},
      );
    }
    final contents = await resource.read(McpResourceRequest(uri: uri));
    return <String, Object?>{
      'contents': [for (final content in contents) content.toJson()],
    };
  }

  JsonMap _listResourceTemplates(JsonMap params) {
    final cursor = params['cursor'];
    if (cursor != null && cursor is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'resources/templates/list.params.cursor must be a string',
      );
    }
    final page = resources.listTemplatePage(cursor: cursor as String?);
    final result = <String, Object?>{
      'resourceTemplates': [
        for (final template in page.templates) template.toJson(),
      ],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  void _requireInitialized(String method) {
    if (_state != McpServerState.initialized) {
      throw McpException(
        McpErrorCodes.serverNotInitialized,
        '$method requires notifications/initialized first',
      );
    }
  }

  Map<String, String> _promptArgumentsFrom(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    if (value is! Map) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'prompts/get.params.arguments must be an object',
      );
    }
    final arguments = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final argumentValue = entry.value;
      if (key is! String || argumentValue is! String) {
        throw McpException(
          McpErrorCodes.invalidParams,
          'prompts/get.params.arguments must contain only string values',
        );
      }
      arguments[key] = argumentValue;
    }
    return arguments;
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

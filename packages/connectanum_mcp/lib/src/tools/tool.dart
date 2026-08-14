import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol/errors.dart';
import '../protocol/icons.dart';
import '../protocol/json_rpc.dart';
import '../protocol/pagination.dart';
import '../resources/resource.dart';

typedef McpToolHandler = FutureOr<McpToolResult> Function(McpToolRequest);

final RegExp _toolNamePattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');

class McpTool {
  McpTool({
    required this.name,
    required this.handler,
    this.title,
    this.description,
    Map<String, Object?>? inputSchema,
    this.outputSchema,
    this.annotations,
    Iterable<McpIcon> icons = const [],
  }) : inputSchema =
           inputSchema ??
           const <String, Object?>{
             'type': 'object',
             'additionalProperties': false,
           },
       icons = List<McpIcon>.unmodifiable(icons) {
    if (!_toolNamePattern.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'MCP tool names must be 1-128 ASCII letters, digits, underscores, '
            'hyphens, or dots.',
      );
    }
  }

  final String name;
  final String? title;
  final String? description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?>? outputSchema;
  final McpToolAnnotations? annotations;
  final List<McpIcon> icons;
  final McpToolHandler handler;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'name': name, 'inputSchema': inputSchema};
    final title = this.title;
    if (title != null) {
      json['title'] = title;
    }
    final description = this.description;
    if (description != null) {
      json['description'] = description;
    }
    addMcpIconsToJson(json, icons);
    final outputSchema = this.outputSchema;
    if (outputSchema != null) {
      json['outputSchema'] = outputSchema;
    }
    final annotations = this.annotations;
    if (annotations != null && !annotations.isEmpty) {
      json['annotations'] = annotations.toJson();
    }
    return json;
  }
}

class McpToolAnnotations {
  const McpToolAnnotations({
    this.title,
    this.readOnlyHint,
    this.destructiveHint,
    this.idempotentHint,
    this.openWorldHint,
  });

  final String? title;
  final bool? readOnlyHint;
  final bool? destructiveHint;
  final bool? idempotentHint;
  final bool? openWorldHint;

  bool get isEmpty =>
      title == null &&
      readOnlyHint == null &&
      destructiveHint == null &&
      idempotentHint == null &&
      openWorldHint == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (title != null) 'title': title,
      if (readOnlyHint != null) 'readOnlyHint': readOnlyHint,
      if (destructiveHint != null) 'destructiveHint': destructiveHint,
      if (idempotentHint != null) 'idempotentHint': idempotentHint,
      if (openWorldHint != null) 'openWorldHint': openWorldHint,
    };
  }
}

class McpToolRequest {
  const McpToolRequest({
    required this.name,
    required this.arguments,
    this.inputResponses = const <String, JsonMap>{},
    this.requestState,
    this.clientCapabilities = const <String, Object?>{},
  });

  factory McpToolRequest.fromCallParams({
    required String name,
    required JsonMap params,
  }) {
    final rawInputResponses = jsonMapFrom(
      params['inputResponses'],
      label: 'tools/call.params.inputResponses',
    );
    final inputResponses = <String, JsonMap>{
      for (final entry in rawInputResponses.entries)
        entry.key: jsonMapFrom(
          entry.value,
          label: 'tools/call.params.inputResponses.${entry.key}',
        ),
    };
    final requestState = params['requestState'];
    if (requestState != null && requestState is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'tools/call.params.requestState must be a string',
      );
    }
    final metadata = jsonMapFrom(
      params['_meta'],
      label: 'tools/call.params._meta',
    );
    final clientCapabilities = jsonMapFrom(
      metadata['io.modelcontextprotocol/clientCapabilities'],
      label:
          'tools/call.params._meta.'
          'io.modelcontextprotocol/clientCapabilities',
    );
    return McpToolRequest(
      name: name,
      arguments: jsonMapFrom(params['arguments'], label: 'arguments'),
      inputResponses: Map<String, JsonMap>.unmodifiable(inputResponses),
      requestState: requestState as String?,
      clientCapabilities: Map<String, Object?>.unmodifiable(clientCapabilities),
    );
  }

  final String name;
  final JsonMap arguments;
  final Map<String, JsonMap> inputResponses;
  final String? requestState;
  final JsonMap clientCapabilities;
}

typedef McpContentAnnotations = McpResourceAnnotations;

sealed class McpContent {
  const McpContent({this.annotations});

  final McpContentAnnotations? annotations;

  Map<String, Object?> toJson();
}

class McpTextContent extends McpContent {
  const McpTextContent(this.text, {super.annotations});

  final String text;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'type': 'text', 'text': text};
    _addContentAnnotations(json, annotations);
    return json;
  }
}

class McpImageContent extends McpContent {
  McpImageContent({
    required this.data,
    required this.mimeType,
    super.annotations,
  }) {
    _validateRequiredString(mimeType, 'mimeType', 'MCP image MIME type');
  }

  McpImageContent.bytes({
    required Uint8List bytes,
    required String mimeType,
    McpContentAnnotations? annotations,
  }) : this(
         data: base64Encode(bytes),
         mimeType: mimeType,
         annotations: annotations,
       );

  final String data;
  final String mimeType;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': 'image',
      'data': data,
      'mimeType': mimeType,
    };
    _addContentAnnotations(json, annotations);
    return json;
  }
}

class McpAudioContent extends McpContent {
  McpAudioContent({
    required this.data,
    required this.mimeType,
    super.annotations,
  }) {
    _validateRequiredString(mimeType, 'mimeType', 'MCP audio MIME type');
  }

  McpAudioContent.bytes({
    required Uint8List bytes,
    required String mimeType,
    McpContentAnnotations? annotations,
  }) : this(
         data: base64Encode(bytes),
         mimeType: mimeType,
         annotations: annotations,
       );

  final String data;
  final String mimeType;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': 'audio',
      'data': data,
      'mimeType': mimeType,
    };
    _addContentAnnotations(json, annotations);
    return json;
  }
}

class McpResourceLinkContent extends McpContent {
  McpResourceLinkContent({
    required this.uri,
    required this.name,
    this.title,
    this.description,
    this.mimeType,
    this.size,
    super.annotations,
  }) {
    _validateResourceUri(uri, 'uri');
    _validateRequiredString(name, 'name', 'MCP resource link name');
    final size = this.size;
    if (size != null && size < 0) {
      throw ArgumentError.value(
        size,
        'size',
        'MCP resource link size must be non-negative.',
      );
    }
  }

  final String uri;
  final String name;
  final String? title;
  final String? description;
  final String? mimeType;
  final int? size;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': 'resource_link',
      'uri': uri,
      'name': name,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (mimeType != null) 'mimeType': mimeType,
      if (size != null) 'size': size,
    };
    _addContentAnnotations(json, annotations);
    return json;
  }
}

class McpEmbeddedResourceContent extends McpContent {
  const McpEmbeddedResourceContent({required this.resource, super.annotations});

  final McpResourceContent resource;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': 'resource',
      'resource': resource.toJson(),
    };
    _addContentAnnotations(json, annotations);
    return json;
  }
}

class McpToolResult {
  const McpToolResult({
    required this.content,
    this.structuredContent,
    this.isError = false,
    this.meta,
  }) : inputRequests = null,
       requestState = null;

  McpToolResult.text(
    String text, {
    Map<String, Object?>? structuredContent,
    bool isError = false,
    McpContentAnnotations? annotations,
    Map<String, Object?>? meta,
  }) : this(
         content: [McpTextContent(text, annotations: annotations)],
         structuredContent: structuredContent,
         isError: isError,
         meta: meta,
       );

  McpToolResult.error(
    String message, {
    Map<String, Object?>? meta,
  }) : this(
         content: [McpTextContent(message)],
         isError: true,
         meta: meta,
       );

  factory McpToolResult.inputRequired({
    Map<String, Object?> inputRequests = const <String, Object?>{},
    String? requestState,
    Map<String, Object?>? meta,
  }) {
    if (inputRequests.isEmpty && requestState == null) {
      throw ArgumentError(
        'An MCP input-required result needs inputRequests or requestState.',
      );
    }
    for (final entry in inputRequests.entries) {
      if (entry.key.isEmpty) {
        throw ArgumentError.value(
          entry.key,
          'inputRequests',
          'MCP input request identifiers must not be empty.',
        );
      }
      _validateMcpFormInputRequest(
        entry.value,
        label: 'inputRequests.${entry.key}',
      );
    }
    return McpToolResult._inputRequired(
      inputRequests: Map<String, Object?>.unmodifiable(inputRequests),
      requestState: requestState,
      meta: meta,
    );
  }

  const McpToolResult._inputRequired({
    required this.inputRequests,
    required this.requestState,
    required this.meta,
  }) : content = const <McpContent>[],
       structuredContent = null,
       isError = false;

  final List<McpContent> content;
  final Map<String, Object?>? structuredContent;
  final bool isError;
  final Map<String, Object?>? inputRequests;
  final String? requestState;

  /// Optional protocol metadata carried with this result.
  final Map<String, Object?>? meta;

  bool get isInputRequired => inputRequests != null || requestState != null;

  Map<String, Object?> toJson({
    JsonMap clientCapabilities = const <String, Object?>{},
  }) {
    if (isInputRequired) {
      if (!_mcpClientSupportsFormElicitation(clientCapabilities)) {
        throw McpException(
          McpErrorCodes.missingRequiredClientCapability,
          'Client does not support required MCP form elicitation',
          data: const <String, Object?>{
            'requiredCapabilities': <String, Object?>{
              'elicitation': <String, Object?>{'form': <String, Object?>{}},
            },
          },
        );
      }
      return <String, Object?>{
        'resultType': 'input_required',
        'inputRequests': ?inputRequests,
        'requestState': ?requestState,
        '_meta': ?meta,
      };
    }

    final json = <String, Object?>{
      'content': [for (final item in content) item.toJson()],
      'isError': isError,
      '_meta': ?meta,
    };
    final structuredContent = this.structuredContent;
    if (structuredContent != null) {
      json['structuredContent'] = structuredContent;
    }
    return json;
  }
}

bool _mcpClientSupportsFormElicitation(JsonMap capabilities) {
  final elicitation = capabilities['elicitation'];
  if (elicitation is! Map) {
    return false;
  }
  if (elicitation.isEmpty) {
    return true;
  }
  return elicitation['form'] is Map;
}

void _validateMcpFormInputRequest(Object? value, {required String label}) {
  final request = jsonMapFrom(value, label: label);
  if (request['method'] != 'elicitation/create') {
    throw ArgumentError.value(
      request['method'],
      label,
      'This MCP input-required result supports only elicitation/create.',
    );
  }
  final params = jsonMapFrom(request['params'], label: '$label.params');
  final mode = params['mode'];
  if (mode != null && mode != 'form') {
    throw ArgumentError.value(
      mode,
      '$label.params.mode',
      'This MCP input-required result supports only form elicitation.',
    );
  }
  final message = params['message'];
  if (message is! String || message.isEmpty) {
    throw ArgumentError.value(
      message,
      '$label.params.message',
      'MCP form elicitation requires a non-empty message.',
    );
  }
  final schema = jsonMapFrom(
    params['requestedSchema'],
    label: '$label.params.requestedSchema',
  );
  if (schema['type'] != 'object' || schema['properties'] is! Map) {
    throw ArgumentError.value(
      params['requestedSchema'],
      '$label.params.requestedSchema',
      'MCP form elicitation requires a flat object schema.',
    );
  }
}

class McpToolRegistry {
  McpToolRegistry([Iterable<McpTool> tools = const [], this.pageSize]) {
    final pageSize = this.pageSize;
    if (pageSize != null && pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'MCP tool list page size must be greater than zero.',
      );
    }
    registerAll(tools);
  }

  final int? pageSize;
  final Map<String, McpTool> _tools = <String, McpTool>{};
  int _revision = 0;

  bool get isNotEmpty => _tools.isNotEmpty;

  void register(McpTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw ArgumentError.value(tool.name, 'tool.name', 'Duplicate MCP tool');
    }
    _tools[tool.name] = tool;
    _revision += 1;
  }

  void registerAll(Iterable<McpTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  void replaceAll(Iterable<McpTool> tools) {
    _tools.clear();
    _revision += 1;
    registerAll(tools);
  }

  List<McpTool> list({String? cursor}) => listPage(cursor: cursor).tools;

  McpToolListPage listPage({String? cursor}) {
    final tools = List<McpTool>.unmodifiable(
      _tools.values.toList(growable: false)
        ..sort((left, right) => left.name.compareTo(right.name)),
    );
    final pageSize = this.pageSize;
    if (pageSize == null) {
      if (cursor != null) {
        throw McpException(
          McpErrorCodes.invalidParams,
          'tools/list.params.cursor is invalid or stale',
        );
      }
      return McpToolListPage(tools: tools);
    }

    final start = decodeMcpCursor(
      cursor,
      prefix: _toolCursorPrefix,
      expectedRevision: _revision,
      maxOffset: tools.length,
      errorMessage: 'tools/list.params.cursor is invalid or stale',
    );
    final end = math.min(start + pageSize, tools.length);
    return McpToolListPage(
      tools: List<McpTool>.unmodifiable(tools.sublist(start, end)),
      nextCursor: end < tools.length
          ? encodeMcpCursor(
              prefix: _toolCursorPrefix,
              revision: _revision,
              offset: end,
            )
          : null,
    );
  }

  McpTool? operator [](String name) => _tools[name];
}

class McpToolListPage {
  const McpToolListPage({required this.tools, this.nextCursor});

  final List<McpTool> tools;
  final String? nextCursor;
}

const String _toolCursorPrefix = 'tools:';

void _addContentAnnotations(
  Map<String, Object?> json,
  McpContentAnnotations? annotations,
) {
  if (annotations != null && !annotations.isEmpty) {
    json['annotations'] = annotations.toJson();
  }
}

void _validateRequiredString(String value, String name, String label) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, '$label is required.');
  }
}

void _validateResourceUri(String uri, String name) {
  final parsed = Uri.tryParse(uri);
  if (uri.isEmpty || parsed == null || !parsed.hasScheme) {
    throw ArgumentError.value(
      uri,
      name,
      'MCP resource URI must be an absolute URI with a scheme.',
    );
  }
}

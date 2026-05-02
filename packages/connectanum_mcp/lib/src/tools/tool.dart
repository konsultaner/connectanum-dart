import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol/errors.dart';
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
  }) : inputSchema =
           inputSchema ??
           const <String, Object?>{
             'type': 'object',
             'additionalProperties': false,
           } {
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
  const McpToolRequest({required this.name, required this.arguments});

  final String name;
  final JsonMap arguments;
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
  });

  McpToolResult.text(
    String text, {
    Map<String, Object?>? structuredContent,
    bool isError = false,
    McpContentAnnotations? annotations,
  }) : this(
         content: [McpTextContent(text, annotations: annotations)],
         structuredContent: structuredContent,
         isError: isError,
       );

  McpToolResult.error(String message)
    : this(content: [McpTextContent(message)], isError: true);

  final List<McpContent> content;
  final Map<String, Object?>? structuredContent;
  final bool isError;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'content': [for (final item in content) item.toJson()],
      'isError': isError,
    };
    final structuredContent = this.structuredContent;
    if (structuredContent != null) {
      json['structuredContent'] = structuredContent;
    }
    return json;
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
    final tools = List<McpTool>.unmodifiable(_tools.values);
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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../protocol/errors.dart';
import '../protocol/json_rpc.dart';

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
    return json;
  }
}

class McpToolRequest {
  const McpToolRequest({required this.name, required this.arguments});

  final String name;
  final JsonMap arguments;
}

sealed class McpContent {
  const McpContent();

  Map<String, Object?> toJson();
}

class McpTextContent extends McpContent {
  const McpTextContent(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'text',
    'text': text,
  };
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
  }) : this(
         content: [McpTextContent(text)],
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

    final start = _decodeCursor(
      cursor,
      expectedRevision: _revision,
      maxOffset: tools.length,
    );
    final end = math.min(start + pageSize, tools.length);
    return McpToolListPage(
      tools: List<McpTool>.unmodifiable(tools.sublist(start, end)),
      nextCursor: end < tools.length ? _encodeCursor(_revision, end) : null,
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

String _encodeCursor(int revision, int offset) {
  final encoded = base64Url.encode(
    utf8.encode('$_toolCursorPrefix$revision:$offset'),
  );
  return encoded.replaceAll('=', '');
}

int _decodeCursor(
  String? cursor, {
  required int expectedRevision,
  required int maxOffset,
}) {
  if (cursor == null) {
    return 0;
  }
  try {
    final padding = (4 - cursor.length % 4) % 4;
    final normalized = cursor.padRight(cursor.length + padding, '=');
    final decoded = utf8.decode(base64Url.decode(normalized));
    if (!decoded.startsWith(_toolCursorPrefix)) {
      throw const FormatException('wrong prefix');
    }
    final cursorParts = decoded.substring(_toolCursorPrefix.length).split(':');
    if (cursorParts.length != 2) {
      throw const FormatException('wrong cursor shape');
    }
    final revision = int.parse(cursorParts[0]);
    final offset = int.parse(cursorParts[1]);
    if (revision != expectedRevision) {
      throw const FormatException('cursor revision is stale');
    }
    if (offset < 0 || offset > maxOffset) {
      throw const FormatException('cursor offset out of range');
    }
    return offset;
  } on FormatException {
    throw McpException(
      McpErrorCodes.invalidParams,
      'tools/list.params.cursor is invalid or stale',
    );
  }
}

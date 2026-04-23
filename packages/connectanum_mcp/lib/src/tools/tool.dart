import 'dart:async';

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
  McpToolRegistry([Iterable<McpTool> tools = const []]) {
    registerAll(tools);
  }

  final Map<String, McpTool> _tools = <String, McpTool>{};

  bool get isNotEmpty => _tools.isNotEmpty;

  void register(McpTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw ArgumentError.value(tool.name, 'tool.name', 'Duplicate MCP tool');
    }
    _tools[tool.name] = tool;
  }

  void registerAll(Iterable<McpTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  List<McpTool> list({String? cursor}) =>
      List<McpTool>.unmodifiable(_tools.values);

  McpTool? operator [](String name) => _tools[name];
}

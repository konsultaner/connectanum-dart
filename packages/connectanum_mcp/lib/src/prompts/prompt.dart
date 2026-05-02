import 'dart:async';
import 'dart:math' as math;

import '../protocol/errors.dart';
import '../protocol/pagination.dart';
import '../tools/tool.dart';

typedef McpPromptHandler = FutureOr<McpPromptResult> Function(McpPromptRequest);

class McpPrompt {
  McpPrompt({
    required this.name,
    required this.handler,
    this.title,
    this.description,
    Iterable<McpPromptArgument> arguments = const [],
  }) : arguments = List<McpPromptArgument>.unmodifiable(arguments) {
    _validateRequiredString(name, 'name', 'MCP prompt name');
    final names = <String>{};
    for (final argument in this.arguments) {
      if (!names.add(argument.name)) {
        throw ArgumentError.value(
          argument.name,
          'arguments',
          'Duplicate MCP prompt argument',
        );
      }
    }
  }

  final String name;
  final String? title;
  final String? description;
  final List<McpPromptArgument> arguments;
  final McpPromptHandler handler;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'name': name};
    final title = this.title;
    if (title != null) {
      json['title'] = title;
    }
    final description = this.description;
    if (description != null) {
      json['description'] = description;
    }
    if (arguments.isNotEmpty) {
      json['arguments'] = [for (final argument in arguments) argument.toJson()];
    }
    return json;
  }

  void validateArguments(Map<String, String> values) {
    for (final argument in arguments) {
      if (argument.required && !values.containsKey(argument.name)) {
        throw McpException(
          McpErrorCodes.invalidParams,
          'Missing required MCP prompt argument: ${argument.name}',
        );
      }
    }
  }
}

class McpPromptArgument {
  McpPromptArgument({
    required this.name,
    this.title,
    this.description,
    this.required = false,
  }) {
    _validateRequiredString(name, 'name', 'MCP prompt argument name');
  }

  final String name;
  final String? title;
  final String? description;
  final bool required;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (required) 'required': true,
    };
  }
}

class McpPromptRequest {
  const McpPromptRequest({required this.name, required this.arguments});

  final String name;
  final Map<String, String> arguments;
}

class McpPromptResult {
  const McpPromptResult({required this.messages, this.description});

  McpPromptResult.text(
    String text, {
    String? description,
    McpPromptRole role = McpPromptRole.user,
    McpContentAnnotations? annotations,
  }) : this(
         description: description,
         messages: [
           McpPromptMessage(
             role: role,
             content: McpTextContent(text, annotations: annotations),
           ),
         ],
       );

  final String? description;
  final List<McpPromptMessage> messages;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'messages': [for (final message in messages) message.toJson()],
    };
    final description = this.description;
    if (description != null) {
      json['description'] = description;
    }
    return json;
  }
}

class McpPromptMessage {
  const McpPromptMessage({required this.role, required this.content});

  const McpPromptMessage.user(McpContent content)
    : this(role: McpPromptRole.user, content: content);

  const McpPromptMessage.assistant(McpContent content)
    : this(role: McpPromptRole.assistant, content: content);

  final McpPromptRole role;
  final McpContent content;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role.name,
    'content': content.toJson(),
  };
}

enum McpPromptRole { user, assistant }

class McpPromptRegistry {
  McpPromptRegistry([Iterable<McpPrompt> prompts = const [], this.pageSize]) {
    final pageSize = this.pageSize;
    if (pageSize != null && pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'MCP prompt list page size must be greater than zero.',
      );
    }
    registerAll(prompts);
  }

  final int? pageSize;
  final Map<String, McpPrompt> _prompts = <String, McpPrompt>{};
  int _revision = 0;

  bool get isNotEmpty => _prompts.isNotEmpty;

  void register(McpPrompt prompt) {
    if (_prompts.containsKey(prompt.name)) {
      throw ArgumentError.value(
        prompt.name,
        'prompt.name',
        'Duplicate MCP prompt',
      );
    }
    _prompts[prompt.name] = prompt;
    _revision += 1;
  }

  void registerAll(Iterable<McpPrompt> prompts) {
    for (final prompt in prompts) {
      register(prompt);
    }
  }

  void replaceAll(Iterable<McpPrompt> prompts) {
    _prompts.clear();
    _revision += 1;
    registerAll(prompts);
  }

  List<McpPrompt> list({String? cursor}) => listPage(cursor: cursor).prompts;

  McpPromptListPage listPage({String? cursor}) {
    final prompts = List<McpPrompt>.unmodifiable(_prompts.values);
    final pageSize = this.pageSize;
    if (pageSize == null) {
      if (cursor != null) {
        throw McpException(
          McpErrorCodes.invalidParams,
          'prompts/list.params.cursor is invalid or stale',
        );
      }
      return McpPromptListPage(prompts: prompts);
    }

    final start = decodeMcpCursor(
      cursor,
      prefix: _promptCursorPrefix,
      expectedRevision: _revision,
      maxOffset: prompts.length,
      errorMessage: 'prompts/list.params.cursor is invalid or stale',
    );
    final end = math.min(start + pageSize, prompts.length);
    return McpPromptListPage(
      prompts: List<McpPrompt>.unmodifiable(prompts.sublist(start, end)),
      nextCursor: end < prompts.length
          ? encodeMcpCursor(
              prefix: _promptCursorPrefix,
              revision: _revision,
              offset: end,
            )
          : null,
    );
  }

  McpPrompt? operator [](String name) => _prompts[name];
}

class McpPromptListPage {
  const McpPromptListPage({required this.prompts, this.nextCursor});

  final List<McpPrompt> prompts;
  final String? nextCursor;
}

const String _promptCursorPrefix = 'prompts:';

void _validateRequiredString(String value, String name, String label) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, '$label is required.');
  }
}

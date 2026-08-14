import 'dart:async';

import 'resource_uri_template.dart';
import 'text_validation.dart';

/// Produces completion candidates for one prompt or resource-template argument.
typedef McpCompletionHandler =
    FutureOr<McpCompletionResult> Function(McpCompletionRequest request);

/// A prompt or resource-template definition referenced by MCP completion.
sealed class McpCompletionReference {
  const McpCompletionReference();

  Map<String, Object?> toJson();
}

/// Identifies a prompt whose argument is being completed.
final class McpPromptReference extends McpCompletionReference {
  McpPromptReference({required this.name, this.title}) {
    _validateCompletionName(name, 'completion prompt name');
  }

  final String name;
  final String? title;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'ref/prompt',
    'name': name,
    if (title != null) 'title': title,
  };
}

/// Identifies a resource URI or URI-template whose argument is being completed.
final class McpResourceTemplateReference extends McpCompletionReference {
  McpResourceTemplateReference({required this.uri}) {
    McpResourceUriTemplate(uri);
  }

  final String uri;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'ref/resource',
    'uri': uri,
  };
}

/// The argument name and partial value supplied to a completion provider.
final class McpCompletionArgument {
  McpCompletionArgument({required this.name, required this.value}) {
    _validateCompletionName(name, 'completion argument name');
  }

  final String name;
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
  };
}

/// Previously resolved prompt or URI-template arguments.
final class McpCompletionContext {
  McpCompletionContext({Map<String, String> arguments = const {}})
    : arguments = Map<String, String>.unmodifiable(arguments) {
    for (final entry in this.arguments.entries) {
      _validateCompletionName(entry.key, 'completion context argument name');
    }
  }

  final Map<String, String> arguments;

  Map<String, Object?> toJson() => <String, Object?>{
    if (arguments.isNotEmpty) 'arguments': arguments,
  };
}

/// A typed `completion/complete` request body.
final class McpCompletionRequest {
  McpCompletionRequest({
    required this.reference,
    required this.argument,
    this.context,
  });

  factory McpCompletionRequest.fromJson(Map<Object?, Object?> json) {
    final referenceJson = _completionObject(
      json['ref'],
      'completion/complete.params.ref',
    );
    final referenceType = _completionString(
      referenceJson['type'],
      'completion/complete.params.ref.type',
    );
    final McpCompletionReference reference;
    switch (referenceType) {
      case 'ref/prompt':
        final title = referenceJson['title'];
        if (title != null && title is! String) {
          throw const FormatException(
            'completion/complete.params.ref.title must be a string',
          );
        }
        reference = McpPromptReference(
          name: _completionString(
            referenceJson['name'],
            'completion/complete.params.ref.name',
          ),
          title: title as String?,
        );
        break;
      case 'ref/resource':
        reference = McpResourceTemplateReference(
          uri: _completionString(
            referenceJson['uri'],
            'completion/complete.params.ref.uri',
          ),
        );
        break;
      default:
        throw FormatException(
          'completion/complete.params.ref.type must be ref/prompt or '
          'ref/resource',
        );
    }

    final argumentJson = _completionObject(
      json['argument'],
      'completion/complete.params.argument',
    );
    final argument = McpCompletionArgument(
      name: _completionString(
        argumentJson['name'],
        'completion/complete.params.argument.name',
      ),
      value: _completionString(
        argumentJson['value'],
        'completion/complete.params.argument.value',
        allowEmpty: true,
      ),
    );

    McpCompletionContext? context;
    final rawContext = json['context'];
    if (rawContext != null) {
      final contextJson = _completionObject(
        rawContext,
        'completion/complete.params.context',
      );
      final rawArguments = contextJson['arguments'];
      final arguments = <String, String>{};
      if (rawArguments != null) {
        final argumentMap = _completionObject(
          rawArguments,
          'completion/complete.params.context.arguments',
        );
        for (final entry in argumentMap.entries) {
          if (entry.value is! String) {
            throw const FormatException(
              'completion/complete.params.context.arguments values must be '
              'strings',
            );
          }
          arguments[entry.key] = entry.value! as String;
        }
      }
      context = McpCompletionContext(arguments: arguments);
    }

    return McpCompletionRequest(
      reference: reference,
      argument: argument,
      context: context,
    );
  }

  final McpCompletionReference reference;
  final McpCompletionArgument argument;
  final McpCompletionContext? context;

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': reference.toJson(),
    'argument': argument.toJson(),
    if (context != null) 'context': context!.toJson(),
  };
}

/// A bounded completion result as defined by MCP.
final class McpCompletionResult {
  McpCompletionResult({
    Iterable<String> values = const [],
    this.total,
    this.hasMore,
  }) : values = List<String>.unmodifiable(values) {
    if (this.values.length > 100) {
      throw ArgumentError.value(
        this.values.length,
        'values',
        'MCP completion results must contain at most 100 values.',
      );
    }
    final total = this.total;
    if (total != null && total < this.values.length) {
      throw ArgumentError.value(
        total,
        'total',
        'MCP completion total must not be smaller than returned values.',
      );
    }
  }

  factory McpCompletionResult.fromJson(Map<Object?, Object?> json) {
    final completion = _completionObject(
      json['completion'],
      'completion/complete result.completion',
    );
    final rawValues = completion['values'];
    if (rawValues is! List || rawValues.any((value) => value is! String)) {
      throw const FormatException(
        'completion/complete result.completion.values must be a string list',
      );
    }
    final rawTotal = completion['total'];
    if (rawTotal != null && rawTotal is! int) {
      throw const FormatException(
        'completion/complete result.completion.total must be an integer',
      );
    }
    final rawHasMore = completion['hasMore'];
    if (rawHasMore != null && rawHasMore is! bool) {
      throw const FormatException(
        'completion/complete result.completion.hasMore must be a boolean',
      );
    }
    try {
      return McpCompletionResult(
        values: rawValues.cast<String>(),
        total: rawTotal as int?,
        hasMore: rawHasMore as bool?,
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }

  final List<String> values;
  final int? total;
  final bool? hasMore;

  Map<String, Object?> toJson() => <String, Object?>{
    'completion': <String, Object?>{
      'values': values,
      if (total != null) 'total': total,
      if (hasMore != null) 'hasMore': hasMore,
    },
  };
}

void _validateCompletionName(String value, String label) {
  if (value.isEmpty || containsMcpWhitespaceOrControl(value)) {
    throw ArgumentError.value(
      value,
      label,
      'MCP $label must be non-empty and contain no whitespace or control '
      'characters.',
    );
  }
}

Map<String, Object?> _completionObject(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label keys must be strings');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _completionString(
  Object? value,
  String label, {
  bool allowEmpty = false,
}) {
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException(
      '$label must be ${allowEmpty ? 'a' : 'a non-empty'} string',
    );
  }
  return value;
}

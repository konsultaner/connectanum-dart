import 'dart:async';
import 'dart:convert';

import 'package:connectanum_client/connectanum.dart';

import '../protocol/json_rpc.dart';
import 'tool.dart';

typedef McpWampCallInvoker =
    FutureOr<ResultPayload> Function(McpWampToolCall call);

typedef McpWampArgumentsBuilder =
    McpWampCallPayload Function(McpToolRequest request);

typedef McpWampResultMapper =
    McpToolResult Function(McpWampToolCall call, ResultPayload result);

class McpWampToolDelegate {
  McpWampToolDelegate({
    required this.procedure,
    required McpWampCallInvoker call,
    McpWampArgumentsBuilder? argumentsBuilder,
    McpWampResultMapper? resultMapper,
    this.timeout,
  }) : _call = call,
       _argumentsBuilder =
           argumentsBuilder ?? McpWampCallPayload.fromToolArguments,
       _resultMapper = resultMapper ?? mcpWampLosslessJsonResultMapper;

  McpWampToolDelegate.session({
    required Session session,
    required String procedure,
    McpWampArgumentsBuilder? argumentsBuilder,
    McpWampResultMapper? resultMapper,
    Duration? timeout,
  }) : this(
         procedure: procedure,
         argumentsBuilder: argumentsBuilder,
         resultMapper: resultMapper,
         timeout: timeout,
         call: (call) => session.callSinglePayload(
           call.procedure,
           arguments: call.payload.arguments,
           argumentsKeywords: call.payload.argumentsKeywords,
           options: call.payload.options,
         ),
       );

  final String procedure;
  final Duration? timeout;
  final McpWampCallInvoker _call;
  final McpWampArgumentsBuilder _argumentsBuilder;
  final McpWampResultMapper _resultMapper;

  McpTool toTool({
    required String name,
    String? title,
    String? description,
    Map<String, Object?>? inputSchema,
    Map<String, Object?>? outputSchema,
  }) {
    return McpTool(
      name: name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      handler: handle,
    );
  }

  Future<McpToolResult> handle(McpToolRequest request) async {
    final payload = _argumentsBuilder(request);
    final call = McpWampToolCall(
      procedure: procedure,
      request: request,
      payload: payload,
    );
    final resultFuture = Future<ResultPayload>.value(_call(call));
    final timeout = this.timeout;
    final result = timeout == null
        ? await resultFuture
        : await resultFuture.timeout(timeout);
    return _resultMapper(call, result);
  }
}

class McpWampToolCall {
  const McpWampToolCall({
    required this.procedure,
    required this.request,
    required this.payload,
  });

  final String procedure;
  final McpToolRequest request;
  final McpWampCallPayload payload;
}

class McpWampCallPayload {
  const McpWampCallPayload({
    this.arguments,
    this.argumentsKeywords,
    this.options,
  });

  factory McpWampCallPayload.fromToolArguments(McpToolRequest request) {
    return McpWampCallPayload(
      argumentsKeywords: request.arguments.isEmpty
          ? null
          : _copyStringDynamicMap(request.arguments),
    );
  }

  final List<dynamic>? arguments;
  final Map<String, dynamic>? argumentsKeywords;
  final CallOptions? options;
}

McpToolResult mcpWampLosslessJsonResultMapper(
  McpWampToolCall call,
  ResultPayload result,
) {
  final structuredContent = <String, Object?>{};
  final arguments = result.arguments;
  if (arguments != null) {
    structuredContent['arguments'] = _jsonCompatible(arguments);
  }
  final argumentsKeywords = result.argumentsKeywords;
  if (argumentsKeywords != null) {
    structuredContent['argumentsKeywords'] = _jsonCompatible(argumentsKeywords);
  }
  final customDetails = result.customDetails;
  if (customDetails != null) {
    structuredContent['details'] = _jsonCompatible(customDetails);
  }
  if (structuredContent.isEmpty) {
    return McpToolResult.text('');
  }
  return McpToolResult.text(
    jsonEncode(structuredContent),
    structuredContent: structuredContent,
  );
}

Map<String, dynamic> _copyStringDynamicMap(JsonMap source) {
  return <String, dynamic>{
    for (final entry in source.entries) entry.key: entry.value,
  };
}

Object? _jsonCompatible(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    return value.isFinite ? value : value.toString();
  }
  if (value is num) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _jsonCompatible(entry.value),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) _jsonCompatible(item)];
  }
  return value.toString();
}

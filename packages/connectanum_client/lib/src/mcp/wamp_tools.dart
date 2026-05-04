import 'streamable_http_client.dart';

const _apiListTool = 'connectanum.api.list';
const _apiDescribeTool = 'connectanum.api.describe';
const _pubsubPublishTool = 'connectanum.pubsub.publish';
const _pubsubSubscribeTool = 'connectanum.pubsub.subscribe';
const _pubsubPollTool = 'connectanum.pubsub.poll';
const _pubsubUnsubscribeTool = 'connectanum.pubsub.unsubscribe';

/// Convenience helpers for Connectanum router-hosted WAMP MCP tools.
extension McpStreamableConnectanumWampTools on McpStreamableHttpClient {
  Future<McpJsonMap> listWampApi({
    Object? id,
    String? kind,
    String? tag,
    bool streamable = true,
  }) {
    return _callStructuredTool(
      this,
      _apiListTool,
      id: id,
      arguments: <String, Object?>{'kind': ?kind, 'tag': ?tag},
      streamable: streamable,
    );
  }

  Future<McpJsonMap> describeWampApi(
    String uri, {
    Object? id,
    String? kind,
    bool streamable = true,
  }) {
    return _callStructuredTool(
      this,
      _apiDescribeTool,
      id: id,
      arguments: <String, Object?>{'uri': uri, 'kind': ?kind},
      streamable: streamable,
    );
  }

  Future<McpStreamableWampMetaCallResult> callWampMetaProcedure(
    String procedure, {
    Object? id,
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    bool streamable = true,
  }) async {
    if (!procedure.startsWith('wamp.')) {
      throw ArgumentError.value(
        procedure,
        'procedure',
        'must be a WAMP meta procedure',
      );
    }
    final structuredContent = await _callStructuredTool(
      this,
      procedure,
      id: id,
      arguments: _wampMetaArguments(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      streamable: streamable,
    );
    return McpStreamableWampMetaCallResult.fromJson(
      procedure,
      structuredContent,
    );
  }

  Future<McpStreamableWampPublicationResult> publishWampEvent(
    String topic, {
    Object? id,
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    bool? acknowledge,
    McpJsonMap? options,
    bool streamable = true,
  }) async {
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubPublishTool,
      id: id,
      arguments: <String, Object?>{
        'topic': topic,
        'arguments': ?arguments,
        'argumentsKeywords': ?argumentsKeywords,
        'acknowledge': ?acknowledge,
        'options': ?options,
      },
      streamable: streamable,
    );
    return McpStreamableWampPublicationResult.fromJson(structuredContent);
  }

  Future<McpStreamableWampSubscriptionResult> subscribeWampTopic(
    String topic, {
    Object? id,
    int? queueLimit,
    McpJsonMap? options,
    bool streamable = true,
  }) async {
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubSubscribeTool,
      id: id,
      arguments: <String, Object?>{
        'topic': topic,
        'queueLimit': ?queueLimit,
        'options': ?options,
      },
      streamable: streamable,
    );
    return McpStreamableWampSubscriptionResult.fromJson(structuredContent);
  }

  Future<McpStreamableWampEventBatch> pollWampEvents(
    String handle, {
    Object? id,
    int? limit,
    bool streamable = true,
  }) async {
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubPollTool,
      id: id,
      arguments: <String, Object?>{'handle': handle, 'limit': ?limit},
      streamable: streamable,
    );
    return McpStreamableWampEventBatch.fromJson(structuredContent);
  }

  Future<McpStreamableWampUnsubscribeResult> unsubscribeWampTopic(
    String handle, {
    Object? id,
    bool streamable = true,
  }) async {
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubUnsubscribeTool,
      id: id,
      arguments: <String, Object?>{'handle': handle},
      streamable: streamable,
    );
    return McpStreamableWampUnsubscribeResult.fromJson(structuredContent);
  }
}

final class McpStreamableWampMetaCallResult {
  const McpStreamableWampMetaCallResult({
    required this.procedure,
    required this.arguments,
    required this.argumentsKeywords,
    required this.structuredContent,
  });

  factory McpStreamableWampMetaCallResult.fromJson(
    String procedure,
    McpJsonMap structuredContent,
  ) {
    return McpStreamableWampMetaCallResult(
      procedure: procedure,
      arguments: _optionalJsonListFrom(structuredContent, 'arguments'),
      argumentsKeywords: _optionalJsonMapFrom(
        structuredContent,
        'argumentsKeywords',
      ),
      structuredContent: structuredContent,
    );
  }

  final String procedure;
  final List<Object?> arguments;
  final McpJsonMap argumentsKeywords;
  final McpJsonMap structuredContent;
}

final class McpStreamableWampPublicationResult {
  const McpStreamableWampPublicationResult({
    required this.topic,
    required this.acknowledged,
    this.publicationId,
    required this.structuredContent,
  });

  factory McpStreamableWampPublicationResult.fromJson(
    McpJsonMap structuredContent,
  ) {
    return McpStreamableWampPublicationResult(
      topic: _requiredString(structuredContent, 'topic'),
      acknowledged: _boolFrom(structuredContent, 'acknowledged') ?? false,
      publicationId: _optionalInt(structuredContent, 'publicationId'),
      structuredContent: structuredContent,
    );
  }

  final String topic;
  final bool acknowledged;
  final int? publicationId;
  final McpJsonMap structuredContent;
}

final class McpStreamableWampSubscriptionResult {
  const McpStreamableWampSubscriptionResult({
    required this.handle,
    required this.topic,
    required this.queueLimit,
    this.subscriptionId,
    required this.structuredContent,
  });

  factory McpStreamableWampSubscriptionResult.fromJson(
    McpJsonMap structuredContent,
  ) {
    return McpStreamableWampSubscriptionResult(
      handle: _requiredString(structuredContent, 'handle'),
      topic: _requiredString(structuredContent, 'topic'),
      queueLimit: _optionalInt(structuredContent, 'queueLimit') ?? 100,
      subscriptionId: _optionalInt(structuredContent, 'subscriptionId'),
      structuredContent: structuredContent,
    );
  }

  final String handle;
  final String topic;
  final int queueLimit;
  final int? subscriptionId;
  final McpJsonMap structuredContent;
}

final class McpStreamableWampEventBatch {
  const McpStreamableWampEventBatch({
    required this.handle,
    required this.topic,
    required this.events,
    required this.dropped,
    required this.remaining,
    required this.structuredContent,
  });

  factory McpStreamableWampEventBatch.fromJson(McpJsonMap structuredContent) {
    return McpStreamableWampEventBatch(
      handle: _requiredString(structuredContent, 'handle'),
      topic: _requiredString(structuredContent, 'topic'),
      events: _jsonMapListFrom(structuredContent, 'events'),
      dropped: _optionalInt(structuredContent, 'dropped') ?? 0,
      remaining: _optionalInt(structuredContent, 'remaining') ?? 0,
      structuredContent: structuredContent,
    );
  }

  final String handle;
  final String topic;
  final List<McpJsonMap> events;
  final int dropped;
  final int remaining;
  final McpJsonMap structuredContent;
}

final class McpStreamableWampUnsubscribeResult {
  const McpStreamableWampUnsubscribeResult({
    required this.handle,
    required this.topic,
    required this.unsubscribed,
    required this.structuredContent,
  });

  factory McpStreamableWampUnsubscribeResult.fromJson(
    McpJsonMap structuredContent,
  ) {
    return McpStreamableWampUnsubscribeResult(
      handle: _requiredString(structuredContent, 'handle'),
      topic: _requiredString(structuredContent, 'topic'),
      unsubscribed: _boolFrom(structuredContent, 'unsubscribed') ?? false,
      structuredContent: structuredContent,
    );
  }

  final String handle;
  final String topic;
  final bool unsubscribed;
  final McpJsonMap structuredContent;
}

final class McpStreamableWampToolException implements Exception {
  const McpStreamableWampToolException({
    required this.toolName,
    required this.result,
  });

  final String toolName;
  final McpJsonMap result;

  String? get message {
    final content = result['content'];
    if (content is List) {
      for (final item in content) {
        if (item is Map && item['type'] == 'text' && item['text'] is String) {
          return item['text'] as String;
        }
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'McpStreamableWampToolException($toolName): $message';
  }
}

Future<McpJsonMap> _callStructuredTool(
  McpStreamableHttpClient client,
  String toolName, {
  Object? id,
  McpJsonMap arguments = const <String, Object?>{},
  bool streamable = true,
}) async {
  final result = await client.callTool(
    toolName,
    id: id,
    arguments: arguments,
    streamable: streamable,
  );
  if (result['isError'] == true) {
    throw McpStreamableWampToolException(toolName: toolName, result: result);
  }
  return _jsonMapFrom(
    result['structuredContent'],
    label: '$toolName result.structuredContent',
  );
}

McpJsonMap _wampMetaArguments({
  List<Object?>? arguments,
  McpJsonMap? argumentsKeywords,
}) {
  return <String, Object?>{
    'arguments': ?arguments,
    'argumentsKeywords': ?argumentsKeywords,
  };
}

String _requiredString(McpJsonMap json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

int? _optionalInt(McpJsonMap json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('$key must be an integer');
  }
  return value;
}

bool? _boolFrom(McpJsonMap json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! bool) {
    throw FormatException('$key must be a boolean');
  }
  return value;
}

List<Object?> _optionalJsonListFrom(McpJsonMap json, String key) {
  final value = json[key];
  if (value == null) {
    return const <Object?>[];
  }
  if (value is! List) {
    throw FormatException('$key must be an array');
  }
  return List<Object?>.unmodifiable(value);
}

McpJsonMap _optionalJsonMapFrom(McpJsonMap json, String key) {
  final value = json[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  return _jsonMapFrom(value, label: key);
}

List<McpJsonMap> _jsonMapListFrom(McpJsonMap json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be an array');
  }
  return [for (final item in value) _jsonMapFrom(item, label: key)];
}

McpJsonMap _jsonMapFrom(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label must contain only string keys');
    }
    result[key] = entry.value;
  }
  return result;
}

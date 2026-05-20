import 'streamable_http_client.dart';

const _apiListTool = 'connectanum.api.list';
const _apiDescribeTool = 'connectanum.api.describe';
const _pubsubPublishTool = 'connectanum.pubsub.publish';
const _pubsubSubscribeTool = 'connectanum.pubsub.subscribe';
const _pubsubPollTool = 'connectanum.pubsub.poll';
const _pubsubUnsubscribeTool = 'connectanum.pubsub.unsubscribe';
const _wampSessionCountProcedure = 'wamp.session.count';
const _wampSessionListProcedure = 'wamp.session.list';
const _wampSessionGetProcedure = 'wamp.session.get';
const _wampRegistrationListProcedure = 'wamp.registration.list';
const _wampRegistrationLookupProcedure = 'wamp.registration.lookup';
const _wampRegistrationMatchProcedure = 'wamp.registration.match';
const _wampRegistrationGetProcedure = 'wamp.registration.get';
const _wampRegistrationListCalleesProcedure = 'wamp.registration.list_callees';
const _wampRegistrationCountCalleesProcedure =
    'wamp.registration.count_callees';
const _wampSubscriptionListProcedure = 'wamp.subscription.list';
const _wampSubscriptionLookupProcedure = 'wamp.subscription.lookup';
const _wampSubscriptionMatchProcedure = 'wamp.subscription.match';
const _wampSubscriptionGetProcedure = 'wamp.subscription.get';
const _wampSubscriptionListSubscribersProcedure =
    'wamp.subscription.list_subscribers';
const _wampSubscriptionCountSubscribersProcedure =
    'wamp.subscription.count_subscribers';

/// Convenience helpers for Connectanum router-hosted WAMP MCP tools.
extension McpStreamableConnectanumWampTools on McpStreamableHttpClient {
  Future<McpJsonMap> listWampApi({
    Object? id,
    String? kind,
    String? tag,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _callStructuredTool(
      this,
      _apiListTool,
      id: id,
      arguments: <String, Object?>{'kind': ?kind, 'tag': ?tag},
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpJsonMap> describeWampApi(
    String uri, {
    Object? id,
    String? kind,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _callStructuredTool(
      this,
      _apiDescribeTool,
      id: id,
      arguments: <String, Object?>{'uri': uri, 'kind': ?kind},
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> callWampMetaProcedure(
    String procedure, {
    Object? id,
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
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
      directJson: directJson,
      headers: headers,
    );
    return McpStreamableWampMetaCallResult.fromJson(
      procedure,
      structuredContent,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampSessions({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSessionCountProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSessions({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSessionListProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSession(
    int sessionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSessionGetProcedure,
      id: id,
      arguments: <Object?>[sessionId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrations({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationListProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> lookupWampRegistration(
    String procedure, {
    Object? id,
    String? match,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationLookupProcedure,
      id: id,
      arguments: <Object?>[procedure],
      argumentsKeywords: _wampMetaMatchArguments(match),
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampRegistration(
    String procedure, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationMatchProcedure,
      id: id,
      arguments: <Object?>[procedure],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampRegistration(
    int registrationId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationGetProcedure,
      id: id,
      arguments: <Object?>[registrationId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrationCallees(
    int registrationId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationListCalleesProcedure,
      id: id,
      arguments: <Object?>[registrationId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampRegistrationCallees(
    int registrationId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationCountCalleesProcedure,
      id: id,
      arguments: <Object?>[registrationId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptions({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionListProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> lookupWampSubscription(
    String topic, {
    Object? id,
    String? match,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionLookupProcedure,
      id: id,
      arguments: <Object?>[topic],
      argumentsKeywords: _wampMetaMatchArguments(match),
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampSubscription(
    String topic, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionMatchProcedure,
      id: id,
      arguments: <Object?>[topic],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSubscription(
    int subscriptionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionGetProcedure,
      id: id,
      arguments: <Object?>[subscriptionId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptionSubscribers(
    int subscriptionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionListSubscribersProcedure,
      id: id,
      arguments: <Object?>[subscriptionId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampSubscriptionSubscribers(
    int subscriptionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionCountSubscribersProcedure,
      id: id,
      arguments: <Object?>[subscriptionId],
      streamable: streamable,
      directJson: directJson,
      headers: headers,
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
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
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
      directJson: directJson,
      headers: headers,
    );
    return McpStreamableWampPublicationResult.fromJson(structuredContent);
  }

  Future<McpStreamableWampSubscriptionResult> subscribeWampTopic(
    String topic, {
    Object? id,
    int? queueLimit,
    McpJsonMap? options,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
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
      directJson: directJson,
      headers: headers,
    );
    return McpStreamableWampSubscriptionResult.fromJson(structuredContent);
  }

  Future<McpStreamableWampEventBatch> pollWampEvents(
    String handle, {
    Object? id,
    int? limit,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubPollTool,
      id: id,
      arguments: <String, Object?>{'handle': handle, 'limit': ?limit},
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
    return McpStreamableWampEventBatch.fromJson(structuredContent);
  }

  Future<McpStreamableWampUnsubscribeResult> unsubscribeWampTopic(
    String handle, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubUnsubscribeTool,
      id: id,
      arguments: <String, Object?>{'handle': handle},
      streamable: streamable,
      directJson: directJson,
      headers: headers,
    );
    return McpStreamableWampUnsubscribeResult.fromJson(structuredContent);
  }

  Future<McpJsonMap> listWampApiDirect({
    Object? id,
    String? kind,
    String? tag,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampApi(
      id: id,
      kind: kind,
      tag: tag,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpJsonMap> describeWampApiDirect(
    String uri, {
    Object? id,
    String? kind,
    Map<String, String> headers = const <String, String>{},
  }) {
    return describeWampApi(
      uri,
      id: id,
      kind: kind,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> callWampMetaProcedureDirect(
    String procedure, {
    Object? id,
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      procedure,
      id: id,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampSessionsDirect({
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return countWampSessions(id: id, directJson: true, headers: headers);
  }

  Future<McpStreamableWampMetaCallResult> listWampSessionsDirect({
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampSessions(id: id, directJson: true, headers: headers);
  }

  Future<McpStreamableWampMetaCallResult> getWampSessionDirect(
    int sessionId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getWampSession(
      sessionId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrationsDirect({
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampRegistrations(id: id, directJson: true, headers: headers);
  }

  Future<McpStreamableWampMetaCallResult> lookupWampRegistrationDirect(
    String procedure, {
    Object? id,
    String? match,
    Map<String, String> headers = const <String, String>{},
  }) {
    return lookupWampRegistration(
      procedure,
      id: id,
      match: match,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampRegistrationDirect(
    String procedure, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return matchWampRegistration(
      procedure,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampRegistrationDirect(
    int registrationId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getWampRegistration(
      registrationId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrationCalleesDirect(
    int registrationId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampRegistrationCallees(
      registrationId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampRegistrationCalleesDirect(
    int registrationId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return countWampRegistrationCallees(
      registrationId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptionsDirect({
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampSubscriptions(id: id, directJson: true, headers: headers);
  }

  Future<McpStreamableWampMetaCallResult> lookupWampSubscriptionDirect(
    String topic, {
    Object? id,
    String? match,
    Map<String, String> headers = const <String, String>{},
  }) {
    return lookupWampSubscription(
      topic,
      id: id,
      match: match,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampSubscriptionDirect(
    String topic, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return matchWampSubscription(
      topic,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSubscriptionDirect(
    int subscriptionId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getWampSubscription(
      subscriptionId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptionSubscribersDirect(
    int subscriptionId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampSubscriptionSubscribers(
      subscriptionId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult>
  countWampSubscriptionSubscribersDirect(
    int subscriptionId, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return countWampSubscriptionSubscribers(
      subscriptionId,
      id: id,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampPublicationResult> publishWampEventDirect(
    String topic, {
    Object? id,
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    bool? acknowledge,
    McpJsonMap? options,
    Map<String, String> headers = const <String, String>{},
  }) {
    return publishWampEvent(
      topic,
      id: id,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      acknowledge: acknowledge,
      options: options,
      directJson: true,
      headers: headers,
    );
  }

  Future<void> notifyWampEventDirect(
    String topic, {
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    McpJsonMap? options,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notifyConnectanumMethodDirect(
      _pubsubPublishTool,
      params: <String, Object?>{
        'topic': topic,
        'arguments': ?arguments,
        'argumentsKeywords': ?argumentsKeywords,
        'options': ?options,
      },
      headers: headers,
    );
  }

  Future<McpStreamableWampSubscriptionResult> subscribeWampTopicDirect(
    String topic, {
    Object? id,
    int? queueLimit,
    McpJsonMap? options,
    Map<String, String> headers = const <String, String>{},
  }) {
    return subscribeWampTopic(
      topic,
      id: id,
      queueLimit: queueLimit,
      options: options,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampEventBatch> pollWampEventsDirect(
    String handle, {
    Object? id,
    int? limit,
    Map<String, String> headers = const <String, String>{},
  }) {
    return pollWampEvents(
      handle,
      id: id,
      limit: limit,
      directJson: true,
      headers: headers,
    );
  }

  Future<McpStreamableWampUnsubscribeResult> unsubscribeWampTopicDirect(
    String handle, {
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) {
    return unsubscribeWampTopic(
      handle,
      id: id,
      directJson: true,
      headers: headers,
    );
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
  bool directJson = false,
  Map<String, String> headers = const <String, String>{},
}) async {
  final result = directJson
      ? await client.callConnectanumToolDirect(
          toolName,
          id: id,
          arguments: arguments,
          headers: headers,
        )
      : await client.callTool(
          toolName,
          id: id,
          arguments: arguments,
          streamable: streamable,
          headers: headers,
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

McpJsonMap? _wampMetaMatchArguments(String? match) {
  if (match == null) {
    return null;
  }
  return <String, Object?>{'match': match};
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

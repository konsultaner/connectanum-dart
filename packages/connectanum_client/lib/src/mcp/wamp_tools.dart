import 'package:connectanum_core/connectanum_core.dart'
    show containsMcpWhitespaceOrControl;

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

/// Builds a JSON options map for Connectanum MCP WAMP publish helpers.
///
/// Standard WAMP option fields are emitted with canonical wire names, and
/// typed arguments override any same-named entries in [custom].
McpJsonMap mcpWampPublishOptions({
  bool? acknowledge,
  List<int>? exclude,
  List<String>? excludeAuthId,
  List<String>? excludeAuthRole,
  List<int>? eligible,
  List<String>? eligibleAuthId,
  List<String>? eligibleAuthRole,
  bool? excludeMe,
  bool? discloseMe,
  bool? retain,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  McpJsonMap custom = const <String, Object?>{},
}) {
  final options = <String, Object?>{...custom};
  _putWampOption(options, 'acknowledge', acknowledge);
  _putWampOption(options, 'exclude', exclude);
  _putWampOption(options, 'exclude_authid', excludeAuthId);
  _putWampOption(options, 'exclude_authrole', excludeAuthRole);
  _putWampOption(options, 'eligible', eligible);
  _putWampOption(options, 'eligible_authid', eligibleAuthId);
  _putWampOption(options, 'eligible_authrole', eligibleAuthRole);
  _putWampOption(options, 'exclude_me', excludeMe);
  _putWampOption(options, 'disclose_me', discloseMe);
  _putWampOption(options, 'retain', retain);
  _putWampOption(options, 'ppt_scheme', pptScheme);
  _putWampOption(options, 'ppt_serializer', pptSerializer);
  _putWampOption(options, 'ppt_cipher', pptCipher);
  _putWampOption(options, 'ppt_keyid', pptKeyId);
  return options;
}

/// Builds a JSON options map for Connectanum MCP WAMP subscribe helpers.
///
/// Standard WAMP option fields are emitted with canonical wire names, and
/// typed arguments override any same-named entries in [custom].
McpJsonMap mcpWampSubscribeOptions({
  String? match,
  String? metaTopic,
  bool? getRetained,
  McpJsonMap custom = const <String, Object?>{},
}) {
  final options = <String, Object?>{...custom};
  _putWampOption(options, 'match', match);
  _putWampOption(options, 'meta_topic', metaTopic);
  _putWampOption(options, 'get_retained', getRetained);
  return options;
}

/// Convenience helpers for Connectanum router-hosted WAMP MCP tools.
extension McpStreamableConnectanumWampTools on McpStreamableHttpClient {
  Future<McpJsonMap> listWampApi({
    Object? id,
    String? kind,
    String? tag,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _callStructuredTool(
      this,
      _apiListTool,
      id: id,
      arguments: <String, Object?>{'kind': ?kind, 'tag': ?tag},
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpJsonMap> describeWampApi(
    String uri, {
    Object? id,
    String? kind,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedUri = _validatedWampStringArgument(uri, 'uri');
    return _callStructuredTool(
      this,
      _apiDescribeTool,
      id: id,
      arguments: <String, Object?>{'uri': validatedUri, 'kind': ?kind},
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
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
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final validatedProcedure = _validatedWampStringArgument(
      procedure,
      'procedure',
    );
    if (!validatedProcedure.startsWith('wamp.') ||
        validatedProcedure.length == 'wamp.'.length) {
      throw ArgumentError.value(
        procedure,
        'procedure',
        'must be a WAMP meta procedure',
      );
    }
    final structuredContent = await _callStructuredTool(
      this,
      validatedProcedure,
      id: id,
      arguments: _wampMetaArguments(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return McpStreamableWampMetaCallResult.fromJson(
      validatedProcedure,
      structuredContent,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampSessions({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSessionCountProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSessions({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSessionListProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSession(
    int sessionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedSessionId = _validatedPositiveInt(sessionId, 'sessionId');
    return callWampMetaProcedure(
      _wampSessionGetProcedure,
      id: id,
      arguments: <Object?>[validatedSessionId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrations({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampRegistrationListProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> lookupWampRegistration(
    String procedure, {
    Object? id,
    String? match,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedProcedure = _validatedWampStringArgument(
      procedure,
      'procedure',
    );
    return callWampMetaProcedure(
      _wampRegistrationLookupProcedure,
      id: id,
      arguments: <Object?>[validatedProcedure],
      argumentsKeywords: _wampMetaMatchArguments(match),
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampRegistration(
    String procedure, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedProcedure = _validatedWampStringArgument(
      procedure,
      'procedure',
    );
    return callWampMetaProcedure(
      _wampRegistrationMatchProcedure,
      id: id,
      arguments: <Object?>[validatedProcedure],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampRegistration(
    int registrationId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedRegistrationId = _validatedPositiveInt(
      registrationId,
      'registrationId',
    );
    return callWampMetaProcedure(
      _wampRegistrationGetProcedure,
      id: id,
      arguments: <Object?>[validatedRegistrationId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrationCallees(
    int registrationId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedRegistrationId = _validatedPositiveInt(
      registrationId,
      'registrationId',
    );
    return callWampMetaProcedure(
      _wampRegistrationListCalleesProcedure,
      id: id,
      arguments: <Object?>[validatedRegistrationId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampRegistrationCallees(
    int registrationId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedRegistrationId = _validatedPositiveInt(
      registrationId,
      'registrationId',
    );
    return callWampMetaProcedure(
      _wampRegistrationCountCalleesProcedure,
      id: id,
      arguments: <Object?>[validatedRegistrationId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptions({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      _wampSubscriptionListProcedure,
      id: id,
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> lookupWampSubscription(
    String topic, {
    Object? id,
    String? match,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedTopic = _validatedWampStringArgument(topic, 'topic');
    return callWampMetaProcedure(
      _wampSubscriptionLookupProcedure,
      id: id,
      arguments: <Object?>[validatedTopic],
      argumentsKeywords: _wampMetaMatchArguments(match),
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampSubscription(
    String topic, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedTopic = _validatedWampStringArgument(topic, 'topic');
    return callWampMetaProcedure(
      _wampSubscriptionMatchProcedure,
      id: id,
      arguments: <Object?>[validatedTopic],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSubscription(
    int subscriptionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedSubscriptionId = _validatedPositiveInt(
      subscriptionId,
      'subscriptionId',
    );
    return callWampMetaProcedure(
      _wampSubscriptionGetProcedure,
      id: id,
      arguments: <Object?>[validatedSubscriptionId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptionSubscribers(
    int subscriptionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedSubscriptionId = _validatedPositiveInt(
      subscriptionId,
      'subscriptionId',
    );
    return callWampMetaProcedure(
      _wampSubscriptionListSubscribersProcedure,
      id: id,
      arguments: <Object?>[validatedSubscriptionId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampSubscriptionSubscribers(
    int subscriptionId, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedSubscriptionId = _validatedPositiveInt(
      subscriptionId,
      'subscriptionId',
    );
    return callWampMetaProcedure(
      _wampSubscriptionCountSubscribersProcedure,
      id: id,
      arguments: <Object?>[validatedSubscriptionId],
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
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
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final validatedTopic = _validatedWampStringArgument(topic, 'topic');
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubPublishTool,
      id: id,
      arguments: <String, Object?>{
        'topic': validatedTopic,
        'arguments': ?arguments,
        'argumentsKeywords': ?argumentsKeywords,
        'acknowledge': ?acknowledge,
        'options': ?options,
      },
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return McpStreamableWampPublicationResult.fromJson(structuredContent);
  }

  Future<void> notifyWampEvent(
    String topic, {
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    McpJsonMap? options,
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final validatedTopic = _validatedWampStringArgument(topic, 'topic');
    return notifyConnectanumMethod(
      _pubsubPublishTool,
      params: <String, Object?>{
        'topic': validatedTopic,
        'arguments': ?arguments,
        'argumentsKeywords': ?argumentsKeywords,
        'options': ?options,
      },
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampSubscriptionResult> subscribeWampTopic(
    String topic, {
    Object? id,
    int? queueLimit,
    McpJsonMap? options,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final validatedTopic = _validatedWampStringArgument(topic, 'topic');
    final validatedQueueLimit = _validatedOptionalPositiveInt(
      queueLimit,
      'queueLimit',
    );
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubSubscribeTool,
      id: id,
      arguments: <String, Object?>{
        'topic': validatedTopic,
        'queueLimit': ?validatedQueueLimit,
        'options': ?options,
      },
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
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
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final validatedHandle = _validatedWampStringArgument(handle, 'handle');
    final validatedLimit = _validatedOptionalPositiveInt(limit, 'limit');
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubPollTool,
      id: id,
      arguments: <String, Object?>{
        'handle': validatedHandle,
        'limit': ?validatedLimit,
      },
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return McpStreamableWampEventBatch.fromJson(structuredContent);
  }

  Future<McpStreamableWampUnsubscribeResult> unsubscribeWampTopic(
    String handle, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final validatedHandle = _validatedWampStringArgument(handle, 'handle');
    final structuredContent = await _callStructuredTool(
      this,
      _pubsubUnsubscribeTool,
      id: id,
      arguments: <String, Object?>{'handle': validatedHandle},
      streamable: streamable,
      directJson: directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return McpStreamableWampUnsubscribeResult.fromJson(structuredContent);
  }

  Future<McpJsonMap> listWampApiDirect({
    Object? id,
    String? kind,
    String? tag,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampApi(
      id: id,
      kind: kind,
      tag: tag,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpJsonMap> describeWampApiDirect(
    String uri, {
    Object? id,
    String? kind,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return describeWampApi(
      uri,
      id: id,
      kind: kind,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> callWampMetaProcedureDirect(
    String procedure, {
    Object? id,
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return callWampMetaProcedure(
      procedure,
      id: id,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampSessionsDirect({
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return countWampSessions(
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSessionsDirect({
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampSessions(
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSessionDirect(
    int sessionId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getWampSession(
      sessionId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrationsDirect({
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampRegistrations(
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> lookupWampRegistrationDirect(
    String procedure, {
    Object? id,
    String? match,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return lookupWampRegistration(
      procedure,
      id: id,
      match: match,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampRegistrationDirect(
    String procedure, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return matchWampRegistration(
      procedure,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampRegistrationDirect(
    int registrationId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getWampRegistration(
      registrationId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampRegistrationCalleesDirect(
    int registrationId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampRegistrationCallees(
      registrationId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> countWampRegistrationCalleesDirect(
    int registrationId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return countWampRegistrationCallees(
      registrationId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptionsDirect({
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampSubscriptions(
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> lookupWampSubscriptionDirect(
    String topic, {
    Object? id,
    String? match,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return lookupWampSubscription(
      topic,
      id: id,
      match: match,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> matchWampSubscriptionDirect(
    String topic, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return matchWampSubscription(
      topic,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> getWampSubscriptionDirect(
    int subscriptionId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getWampSubscription(
      subscriptionId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult> listWampSubscriptionSubscribersDirect(
    int subscriptionId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listWampSubscriptionSubscribers(
      subscriptionId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampMetaCallResult>
  countWampSubscriptionSubscribersDirect(
    int subscriptionId, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return countWampSubscriptionSubscribers(
      subscriptionId,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
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
    String? protocolVersion,
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
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<void> notifyWampEventDirect(
    String topic, {
    List<Object?>? arguments,
    McpJsonMap? argumentsKeywords,
    McpJsonMap? options,
    String? protocolVersion,
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
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampSubscriptionResult> subscribeWampTopicDirect(
    String topic, {
    Object? id,
    int? queueLimit,
    McpJsonMap? options,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return subscribeWampTopic(
      topic,
      id: id,
      queueLimit: queueLimit,
      options: options,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampEventBatch> pollWampEventsDirect(
    String handle, {
    Object? id,
    int? limit,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return pollWampEvents(
      handle,
      id: id,
      limit: limit,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableWampUnsubscribeResult> unsubscribeWampTopicDirect(
    String handle, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return unsubscribeWampTopic(
      handle,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }
}

void _putWampOption(McpJsonMap options, String key, Object? value) {
  if (value != null) {
    options[key] = value;
  }
}

String _validatedWampStringArgument(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'must be a non-empty string');
  }
  if (containsMcpWhitespaceOrControl(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must not contain whitespace or control characters',
    );
  }
  return value;
}

int _validatedPositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be a positive integer');
  }
  return value;
}

int? _validatedOptionalPositiveInt(int? value, String name) {
  if (value == null) {
    return null;
  }
  return _validatedPositiveInt(value, name);
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
  String? protocolVersion,
  Map<String, String> headers = const <String, String>{},
}) async {
  final result = directJson
      ? await client.callConnectanumToolDirect(
          toolName,
          id: id,
          arguments: arguments,
          protocolVersion: protocolVersion,
          headers: headers,
        )
      : await client.callTool(
          toolName,
          id: id,
          arguments: arguments,
          streamable: streamable,
          protocolVersion: protocolVersion,
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

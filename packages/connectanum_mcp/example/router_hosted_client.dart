import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';

const _supportedMcpProtocolVersions = <String>[
  '2025-03-26',
  '2025-06-18',
  McpStreamableHttpClient.latestProtocolVersion,
];
final _mcpToolNamePattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage(stdout);
    return;
  }

  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage(stderr);
    exitCode = 64;
    return;
  }

  if (options.dryRun) {
    _printDryRunSummary(stdout, options);
    return;
  }

  final client = await _createClient(options);
  try {
    await _runDirectJsonExample(client, options);
    await _runDirectBatchExample(client, options);
    await _runDirectWampMetadataExample(client, options);
    if (options.pubsubTopic != null) {
      await _runDirectPubSubExample(client, options);
    }
    await _runStreamableSessionExample(client, options);
  } finally {
    try {
      await _deleteStreamableSession(client);
    } finally {
      client.close(force: true);
    }
  }
}

Future<McpStreamableHttpClient> _createClient(_Options options) async {
  if (options.authEndpoint != null) {
    final authClient = ConnectanumHttpAuthClient(
      options.authEndpoint!,
      httpClient: _shortLivedHttpClient(),
      closeHttpClient: true,
    );
    try {
      final grant = await authClient.issueTicketToken(
        realm: options.authRealm!,
        authId: options.authId!,
        ticket: options.ticket!,
      );
      return McpStreamableHttpClient.withAuthGrant(
        options.endpoint,
        grant,
        httpClient: _shortLivedHttpClient(),
        defaultProtocolVersion: options.protocolVersion,
        closeHttpClient: true,
      );
    } finally {
      authClient.close(force: true);
    }
  }

  final bearerToken = options.bearerToken;
  if (bearerToken != null) {
    return McpStreamableHttpClient.withBearerToken(
      options.endpoint,
      bearerToken,
      httpClient: _shortLivedHttpClient(),
      defaultProtocolVersion: options.protocolVersion,
      closeHttpClient: true,
    );
  }

  return McpStreamableHttpClient(
    options.endpoint,
    httpClient: _shortLivedHttpClient(),
    defaultProtocolVersion: options.protocolVersion,
    closeHttpClient: true,
  );
}

void _printDryRunSummary(IOSink sink, _Options options) {
  final authMode = switch ((options.bearerToken, options.authEndpoint)) {
    (String(), _) => 'bearer',
    (_, Uri()) => 'ticket',
    _ => 'none',
  };

  sink.writeln(
    jsonEncode({
      'dryRun': true,
      'endpoint': options.endpoint.toString(),
      'authMode': authMode,
      'protocolVersion': options.protocolVersion,
      if (options.authEndpoint != null)
        'authEndpoint': options.authEndpoint.toString(),
      if (options.authRealm != null) 'realm': options.authRealm,
      if (options.authId != null) 'authId': options.authId,
      if (options.toolName != null)
        'tool': {'name': options.toolName, 'arguments': options.toolArguments},
      if (options.resourceUri != null) ...{
        'resourceUri': options.resourceUri,
        'resourceTemplates': true,
      },
      if (options.promptName != null)
        'prompt': {
          'name': options.promptName,
          'arguments': options.promptArguments,
        },
      if (options.wampProcedure != null) 'wampProcedure': options.wampProcedure,
      if (options.wampTopic != null) 'wampTopic': options.wampTopic,
      if (options.pubsubTopic != null)
        'pubsub': {
          'topic': options.pubsubTopic,
          'event': options.pubsubEvent,
          'subscriptionMetadata': true,
        },
    }),
  );
}

// This example is a short-lived CLI, so avoid keeping HTTP sockets alive
// after its final request completes.
HttpClient _shortLivedHttpClient() => HttpClient()..idleTimeout = Duration.zero;

Future<void> _deleteStreamableSession(McpStreamableHttpClient client) async {
  await client.deleteSession();
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Streamable session delete did not clear local session state.',
    );
  }
}

void _expectStreamableStateUnchanged(
  McpStreamableHttpClient client, {
  required String? sessionId,
  required String? lastEventId,
  required String label,
}) {
  if (client.sessionId != sessionId || client.lastEventId != lastEventId) {
    throw StateError('$label changed Streamable state.');
  }
}

Future<void> _runDirectJsonExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final catalog = await client.listConnectanumToolsDirect(id: 'direct-tools');
  stdout.writeln(
    jsonEncode({
      'directTools': [for (final tool in catalog.tools) tool['name']],
      if (catalog.nextCursor != null) 'nextCursor': catalog.nextCursor,
    }),
  );

  final toolName = options.toolName;
  if (toolName != null) {
    _expectCatalogContainsValue(
      catalog: catalog.tools,
      field: 'name',
      value: toolName,
      label: 'Direct tool',
    );
    final methodCatalog = await client.callConnectanumMethodDirect(
      'connectanum.tools.list',
      id: 'direct-tools-method',
    );
    final methodToolCatalog = methodCatalog['tools'];
    _expectCatalogContainsValue(
      catalog: methodToolCatalog,
      field: 'name',
      value: toolName,
      label: 'Direct tool method list',
    );
    final result = _expectToolResultSucceeded(
      await client.callConnectanumToolDirect(
        toolName,
        id: 'direct-tool-call',
        arguments: options.toolArguments,
      ),
      label: 'Direct tool call',
    );
    final methodResult = _expectToolResultSucceeded(
      await client.callConnectanumMethodDirect(
        'connectanum.tool.call',
        id: 'direct-tool-call-method',
        params: <String, Object?>{
          'name': toolName,
          'arguments': options.toolArguments,
        },
      ),
      label: 'Direct tool method call',
    );
    stdout.writeln(
      jsonEncode({
        'directToolResult': result,
        'directToolMethodCatalog': methodToolCatalog,
        'directToolMethodResult': methodResult,
      }),
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    final resources = await client.listResourcesDirect(id: 'direct-resources');
    _expectCatalogContainsValue(
      catalog: resources.resources,
      field: 'uri',
      value: resourceUri,
      label: 'Direct resource',
    );
    final resourceTemplates = await client.listResourceTemplatesDirect(
      id: 'direct-resource-templates',
    );
    final content = await client.readResourceDirect(
      resourceUri,
      id: 'direct-resource-read',
    );
    final methodResources = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-resource-list-method',
        'method': 'resources/list',
        'params': {},
      }),
      'direct-resource-list-method',
      label: 'Direct JSON resource method list',
    );
    _expectCatalogContainsValue(
      catalog: methodResources['resources'],
      field: 'uri',
      value: resourceUri,
      label: 'Direct JSON resource method list',
    );
    final methodResourceTemplates = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-resource-templates-method',
        'method': 'resources/templates/list',
        'params': {},
      }),
      'direct-resource-templates-method',
      label: 'Direct JSON resource template method list',
    );
    final methodContent = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-resource-read-method',
        'method': 'resources/read',
        'params': {'uri': resourceUri},
      }),
      'direct-resource-read-method',
      label: 'Direct JSON resource method read',
    );
    stdout.writeln(
      jsonEncode({
        'directResources': [
          for (final resource in resources.resources) resource['uri'],
        ],
        'directResourceTemplates': [
          for (final template in resourceTemplates.resourceTemplates)
            template['uriTemplate'],
        ],
        if (resourceTemplates.nextCursor != null)
          'directResourceTemplateNextCursor': resourceTemplates.nextCursor,
        'directResourceContent': content,
        'directResourceMethodResources': methodResources['resources'],
        'directResourceMethodTemplates':
            methodResourceTemplates['resourceTemplates'],
        'directResourceMethodContent': methodContent,
      }),
    );
  }

  final promptName = options.promptName;
  if (promptName != null) {
    final prompts = await client.listPromptsDirect(id: 'direct-prompts');
    _expectCatalogContainsValue(
      catalog: prompts.prompts,
      field: 'name',
      value: promptName,
      label: 'Direct prompt',
    );
    final prompt = await client.getPromptDirect(
      promptName,
      id: 'direct-prompt-get',
      arguments: options.promptArguments,
    );
    final methodPrompts = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-prompts-method',
        'method': 'prompts/list',
        'params': {},
      }),
      'direct-prompts-method',
      label: 'Direct JSON prompt method list',
    );
    _expectCatalogContainsValue(
      catalog: methodPrompts['prompts'],
      field: 'name',
      value: promptName,
      label: 'Direct JSON prompt method list',
    );
    final methodPrompt = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-prompt-get-method',
        'method': 'prompts/get',
        'params': {'name': promptName, 'arguments': options.promptArguments},
      }),
      'direct-prompt-get-method',
      label: 'Direct JSON prompt method get',
    );
    stdout.writeln(
      jsonEncode({
        'directPrompts': [for (final prompt in prompts.prompts) prompt['name']],
        'directPrompt': prompt,
        'directPromptMethodCatalog': methodPrompts['prompts'],
        'directPromptMethod': methodPrompt,
      }),
    );
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct JSON',
  );
}

Future<void> _runDirectBatchExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final messages = <McpJsonMap>[
    {
      'jsonrpc': '2.0',
      'id': 'direct-batch-tools',
      'method': 'connectanum.tools.list',
      'params': {},
    },
  ];

  final toolName = options.toolName;
  if (toolName != null) {
    messages.add(
      _toolCallBatchRequest(
        id: 'direct-batch-tool-call',
        name: toolName,
        arguments: options.toolArguments,
        directJson: true,
      ),
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-resources',
      'method': 'resources/list',
      'params': {},
    });
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    });
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': resourceUri},
    });
  }

  final promptName = options.promptName;
  if (promptName != null) {
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    });
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-prompt-get',
      'method': 'prompts/get',
      'params': {'name': promptName, 'arguments': options.promptArguments},
    });
  }

  final wampProcedure = options.wampProcedure;
  if (wampProcedure != null) {
    messages.addAll([
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-procedure-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'procedure'},
        directJson: true,
      ),
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-procedure-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampProcedure, 'kind': 'procedure'},
        directJson: true,
      ),
    ]);
  }

  final wampTopic = options.wampTopic;
  if (wampTopic != null) {
    messages.addAll([
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-topic-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'topic'},
        directJson: true,
      ),
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-topic-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampTopic, 'kind': 'topic'},
        directJson: true,
      ),
    ]);
  }

  final batchResponses = await client.postBatchDirect(
    messages,
    headers: const {'x-consumer-trace': 'router-hosted-client-direct-batch'},
  );
  final responseIds = _expectBatchResponses(batchResponses, [
    for (final message in messages) message['id']! as String,
  ], label: 'Direct JSON');
  if (toolName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-tools',
      catalogKey: 'tools',
      field: 'name',
      value: toolName,
      label: 'Direct JSON batch tool',
    );
  }
  if (resourceUri != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-resources',
      catalogKey: 'resources',
      field: 'uri',
      value: resourceUri,
      label: 'Direct JSON batch resource',
    );
  }
  if (promptName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-prompts',
      catalogKey: 'prompts',
      field: 'name',
      value: promptName,
      label: 'Direct JSON batch prompt',
    );
  }
  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct JSON batch',
  );
  stdout.writeln(
    jsonEncode({
      'directBatch': {'responseIds': responseIds},
    }),
  );
}

McpJsonMap _toolCallBatchRequest({
  required String id,
  required String name,
  required McpJsonMap arguments,
  required bool directJson,
}) {
  return {
    'jsonrpc': '2.0',
    'id': id,
    'method': directJson ? 'connectanum.tool.call' : 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  };
}

List<String> _expectBatchResponses(
  List<McpJsonMap>? responses,
  List<String> expectedIds, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  if (responses.length != expectedIds.length) {
    throw StateError(
      '$label batch returned ${responses.length} responses for '
      '${expectedIds.length} requests.',
    );
  }

  final responseIds = <String>[];
  for (final response in responses) {
    final id = response['id'];
    if (id is! String) {
      throw StateError('$label batch response had a non-string id.');
    }
    if (response.containsKey('error')) {
      throw StateError(
        '$label batch response $id errored: ${response['error']}',
      );
    }
    responseIds.add(id);
  }

  final missingIds = [
    for (final expectedId in expectedIds)
      if (!responseIds.contains(expectedId)) expectedId,
  ];
  if (missingIds.isNotEmpty) {
    throw StateError('$label batch missed responses for $missingIds.');
  }
  return responseIds;
}

void _expectBatchCatalogContains(
  List<McpJsonMap>? responses, {
  required String id,
  required String catalogKey,
  required String field,
  required String value,
  required String label,
}) {
  final result = _batchResult(responses, id, label: label);
  _expectCatalogContainsValue(
    catalog: result[catalogKey],
    field: field,
    value: value,
    label: label,
  );
}

McpJsonMap _batchResult(
  List<McpJsonMap>? responses,
  String id, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  for (final response in responses) {
    if (response['id'] != id) {
      continue;
    }
    final result = response['result'];
    if (result is Map) {
      return result.cast<String, Object?>();
    }
    throw StateError('$label batch response $id had a non-object result.');
  }
  throw StateError('$label batch missed response $id.');
}

McpJsonMap _responseResult(
  McpJsonMap? response,
  String id, {
  required String label,
}) {
  if (response == null) {
    throw StateError('$label returned no response.');
  }
  if (response['id'] != id) {
    throw StateError(
      '$label returned response id ${response['id']} instead of $id.',
    );
  }
  final result = response['result'];
  if (result is Map) {
    return result.cast<String, Object?>();
  }
  if (response.containsKey('error')) {
    throw StateError('$label returned error ${jsonEncode(response['error'])}.');
  }
  throw StateError('$label response had a non-object result.');
}

Future<void> _runDirectWampMetadataExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final procedure = options.wampProcedure;
  final topic = options.wampTopic;
  if (procedure == null && topic == null) {
    return;
  }

  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final metadata = <String, Object?>{};

  final sessionCount = await client.countWampSessionsDirect(
    id: 'direct-wamp-session-count',
  );
  metadata['sessionCount'] = _wampMetaResultJson(sessionCount);

  if (procedure != null) {
    final procedures = await client.listWampApiDirect(
      id: 'direct-wamp-procedure-api-list',
      kind: 'procedure',
    );
    final procedureCatalog = procedures['procedures'];
    _expectWampCatalogContains(
      catalog: procedureCatalog,
      uri: procedure,
      label: 'Direct WAMP procedure',
    );
    final methodProcedures = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.list',
        id: 'direct-wamp-procedure-api-list-method',
        params: const <String, Object?>{'kind': 'procedure'},
      ),
      label: 'Direct WAMP procedure method list',
    );
    final methodProcedureCatalog = methodProcedures['procedures'];
    _expectWampCatalogContains(
      catalog: methodProcedureCatalog,
      uri: procedure,
      label: 'Direct WAMP procedure method',
    );
    final description = await client.describeWampApiDirect(
      procedure,
      id: 'direct-wamp-procedure-api-describe',
      kind: 'procedure',
    );
    final methodDescription = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.describe',
        id: 'direct-wamp-procedure-api-describe-method',
        params: <String, Object?>{'uri': procedure, 'kind': 'procedure'},
      ),
      label: 'Direct WAMP procedure method describe',
    );
    _expectWampCatalogContains(
      catalog: [methodDescription],
      uri: procedure,
      label: 'Direct WAMP procedure method describe',
    );
    final registration = await client.matchWampRegistrationDirect(
      procedure,
      id: 'direct-wamp-registration-match',
    );
    metadata['procedure'] = {
      'name': procedure,
      'catalog': procedureCatalog,
      'methodCatalog': methodProcedureCatalog,
      'description': description,
      'methodDescription': methodDescription,
      'registration': _wampMetaResultJson(registration),
    };
  }

  if (topic != null) {
    final topics = await client.listWampApiDirect(
      id: 'direct-wamp-topic-api-list',
      kind: 'topic',
    );
    final topicCatalog = topics['topics'];
    _expectWampCatalogContains(
      catalog: topicCatalog,
      uri: topic,
      label: 'Direct WAMP topic',
    );
    final methodTopics = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.list',
        id: 'direct-wamp-topic-api-list-method',
        params: const <String, Object?>{'kind': 'topic'},
      ),
      label: 'Direct WAMP topic method list',
    );
    final methodTopicCatalog = methodTopics['topics'];
    _expectWampCatalogContains(
      catalog: methodTopicCatalog,
      uri: topic,
      label: 'Direct WAMP topic method',
    );
    final description = await client.describeWampApiDirect(
      topic,
      id: 'direct-wamp-topic-api-describe',
      kind: 'topic',
    );
    final methodDescription = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.describe',
        id: 'direct-wamp-topic-api-describe-method',
        params: <String, Object?>{'uri': topic, 'kind': 'topic'},
      ),
      label: 'Direct WAMP topic method describe',
    );
    _expectWampCatalogContains(
      catalog: [methodDescription],
      uri: topic,
      label: 'Direct WAMP topic method describe',
    );
    metadata['topic'] = {
      'name': topic,
      'catalog': topicCatalog,
      'methodCatalog': methodTopicCatalog,
      'description': description,
      'methodDescription': methodDescription,
    };
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct WAMP metadata',
  );

  stdout.writeln(jsonEncode({'directWampMetadata': metadata}));
}

McpJsonMap _expectToolResultSucceeded(
  McpJsonMap result, {
  required String label,
}) {
  if (result['isError'] == true) {
    throw StateError('$label returned an error: ${jsonEncode(result)}.');
  }
  return result;
}

McpJsonMap _structuredContentFromToolResult(
  McpJsonMap result, {
  required String label,
}) {
  final toolResult = _expectToolResultSucceeded(result, label: label);
  final structuredContent = toolResult['structuredContent'];
  if (structuredContent is Map) {
    return structuredContent.cast<String, Object?>();
  }
  throw StateError('$label returned no structured content.');
}

Map<String, Object?> _wampMetaResultJson(
  McpStreamableWampMetaCallResult result,
) {
  return {
    'procedure': result.procedure,
    'arguments': result.arguments,
    'argumentsKeywords': result.argumentsKeywords,
  };
}

void _expectWampCatalogContains({
  required Object? catalog,
  required String uri,
  required String label,
}) {
  if (!_wampCatalogContainsUri(catalog, uri)) {
    throw StateError('$label catalog did not include $uri.');
  }
}

bool _wampCatalogContainsUri(Object? catalog, String uri) {
  return _catalogContainsValue(catalog: catalog, field: 'uri', value: uri);
}

void _expectCatalogContainsValue({
  required Object? catalog,
  required String field,
  required String value,
  required String label,
}) {
  if (!_catalogContainsValue(catalog: catalog, field: field, value: value)) {
    throw StateError('$label catalog did not include $value.');
  }
}

void _expectWampSubscription(
  McpStreamableWampSubscriptionResult subscription, {
  required String topic,
  required int queueLimit,
  required String label,
}) {
  if (subscription.topic != topic) {
    throw StateError(
      '$label returned subscription for ${subscription.topic}, expected $topic.',
    );
  }
  if (subscription.handle.isEmpty) {
    throw StateError('$label returned an empty subscription handle.');
  }
  if (subscription.queueLimit != queueLimit) {
    throw StateError(
      '$label returned queue limit ${subscription.queueLimit}, '
      'expected $queueLimit.',
    );
  }
}

void _expectWampPublication(
  McpStreamableWampPublicationResult publication, {
  required String topic,
  required String label,
}) {
  if (publication.topic != topic) {
    throw StateError(
      '$label returned publication for ${publication.topic}, expected $topic.',
    );
  }
  if (!publication.acknowledged) {
    throw StateError('$label did not acknowledge publication to $topic.');
  }
  if (publication.publicationId == null) {
    throw StateError(
      '$label acknowledged publication without a publication id.',
    );
  }
}

void _expectWampEventBatch(
  McpStreamableWampEventBatch events, {
  required String handle,
  required String topic,
  required Object? expectedEvent,
  required String label,
}) {
  if (events.handle != handle) {
    throw StateError(
      '$label returned events for handle ${events.handle}, expected $handle.',
    );
  }
  if (events.topic != topic) {
    throw StateError(
      '$label returned events for ${events.topic}, expected $topic.',
    );
  }
  if (events.dropped != 0) {
    throw StateError(
      '$label reported ${events.dropped} dropped pub/sub events.',
    );
  }
  if (events.remaining != 0) {
    throw StateError(
      '$label left ${events.remaining} pub/sub events queued after polling.',
    );
  }
  final observed = events.events.any(
    (event) => _jsonValueEquals(event['argumentsKeywords'], expectedEvent),
  );
  if (!observed) {
    throw StateError(
      'Published event was not observed on $label topic $topic.',
    );
  }
}

bool _catalogContainsValue({
  required Object? catalog,
  required String field,
  required String value,
}) {
  if (catalog is! Iterable<Object?>) {
    return false;
  }
  for (final entry in catalog) {
    if (entry is Map && entry[field] == value) {
      return true;
    }
  }
  return false;
}

Future<void> _runDirectPubSubExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  const queueLimit = 10;
  final topic = options.pubsubTopic!;
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final subscription = await client.subscribeWampTopicDirect(
    topic,
    id: 'direct-pubsub-subscribe',
    queueLimit: queueLimit,
  );
  _expectWampSubscription(
    subscription,
    topic: topic,
    queueLimit: queueLimit,
    label: 'Direct JSON pub/sub',
  );

  try {
    final subscriptionMeta = await client.matchWampSubscriptionDirect(
      topic,
      id: 'direct-wamp-subscription-match',
    );
    final publication = await client.publishWampEventDirect(
      topic,
      id: 'direct-pubsub-publish',
      argumentsKeywords: options.pubsubEvent,
      acknowledge: true,
    );
    _expectWampPublication(
      publication,
      topic: topic,
      label: 'Direct JSON pub/sub',
    );
    final events = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      events,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: options.pubsubEvent,
      label: 'Direct JSON pub/sub',
    );
    final methodPubsubEvent = <String, Object?>{
      'methodEvent': options.pubsubEvent,
    };
    final methodPublication = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.pubsub.publish',
        id: 'direct-pubsub-publish-method',
        params: <String, Object?>{
          'topic': topic,
          'argumentsKeywords': methodPubsubEvent,
          'acknowledge': true,
        },
      ),
      label: 'Direct JSON pub/sub method publish',
    );
    if (methodPublication['topic'] != topic) {
      throw StateError(
        'Direct JSON pub/sub method publish returned topic '
        '${methodPublication['topic']}, expected $topic.',
      );
    }
    if (methodPublication['acknowledged'] != true) {
      throw StateError(
        'Direct JSON pub/sub method publish did not acknowledge publication.',
      );
    }
    if (methodPublication['publicationId'] == null) {
      throw StateError(
        'Direct JSON pub/sub method publish acknowledged without '
        'a publication id.',
      );
    }
    final methodEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-method-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      methodEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: methodPubsubEvent,
      label: 'Direct JSON pub/sub method poll',
    );
    final notificationEvent = <String, Object?>{
      'notificationEvent': options.pubsubEvent,
    };
    await client.notifyWampEventDirect(
      topic,
      argumentsKeywords: notificationEvent,
    );
    final notificationEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-notification-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      notificationEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: notificationEvent,
      label: 'Direct JSON pub/sub notification poll',
    );
    final methodNotificationEvent = <String, Object?>{
      'methodNotificationEvent': options.pubsubEvent,
    };
    await client.notifyConnectanumMethodDirect(
      'connectanum.pubsub.publish',
      params: <String, Object?>{
        'topic': topic,
        'argumentsKeywords': methodNotificationEvent,
      },
    );
    final methodNotificationEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-method-notification-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      methodNotificationEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: methodNotificationEvent,
      label: 'Direct JSON pub/sub method notification poll',
    );
    stdout.writeln(
      jsonEncode({
        'pubsubTopic': topic,
        'subscription': <String, Object?>{
          'handle': subscription.handle,
          'topic': subscription.topic,
          'queueLimit': subscription.queueLimit,
          if (subscription.subscriptionId != null)
            'subscriptionId': subscription.subscriptionId,
        },
        'subscriptionMetadata': _wampMetaResultJson(subscriptionMeta),
        'publication': <String, Object?>{
          'topic': publication.topic,
          'acknowledged': publication.acknowledged,
          if (publication.publicationId != null)
            'publicationId': publication.publicationId,
        },
        'events': events.events,
        'methodPublication': methodPublication,
        'methodEvents': methodEvents.events,
        'notificationEvents': notificationEvents.events,
        'methodNotificationEvents': methodNotificationEvents.events,
        'dropped': events.dropped,
        'remaining': events.remaining,
      }),
    );
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: 'direct-pubsub-unsubscribe',
    );
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct JSON pub/sub',
  );
}

Future<void> _runStreamableSessionExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final initialize = await client.initialize(
    id: 'streamable-initialize',
    clientInfo: const <String, Object?>{
      'name': 'connectanum-mcp-router-hosted-client-example',
      'version': '0.1.0',
    },
  );
  await client.notifyInitialized();

  final streamableSessionId = client.sessionId;
  if (streamableSessionId == null) {
    throw StateError('Streamable initialize did not establish a session id.');
  }

  final tools = await client.listTools(id: 'streamable-tools');
  final streamable = <String, Object?>{
    'protocolVersion': client.protocolVersion,
    'sessionId': streamableSessionId,
    'initialize': initialize['result'],
    'tools': [for (final tool in tools.tools) tool['name']],
  };

  final toolName = options.toolName;
  final streamableBatchMessages = <McpJsonMap>[
    {
      'jsonrpc': '2.0',
      'id': 'streamable-batch-tools',
      'method': 'tools/list',
      'params': {},
    },
  ];
  if (toolName != null) {
    _expectCatalogContainsValue(
      catalog: tools.tools,
      field: 'name',
      value: toolName,
      label: 'Streamable tool',
    );
    streamableBatchMessages.add(
      _toolCallBatchRequest(
        id: 'streamable-batch-tool-call',
        name: toolName,
        arguments: options.toolArguments,
        directJson: false,
      ),
    );
    final methodCatalog = await client.callConnectanumMethod(
      'connectanum.tools.list',
      id: 'streamable-tools-method',
    );
    final methodToolCatalog = methodCatalog['tools'];
    _expectCatalogContainsValue(
      catalog: methodToolCatalog,
      field: 'name',
      value: toolName,
      label: 'Streamable tool method list',
    );
    streamable['toolResult'] = _expectToolResultSucceeded(
      await client.callTool(
        toolName,
        id: 'streamable-tool-call',
        arguments: options.toolArguments,
      ),
      label: 'Streamable tool call',
    );
    streamable['toolMethodCatalog'] = methodToolCatalog;
    streamable['toolMethodResult'] = _expectToolResultSucceeded(
      await client.callConnectanumMethod(
        'connectanum.tool.call',
        id: 'streamable-tool-call-method',
        params: <String, Object?>{
          'name': toolName,
          'arguments': options.toolArguments,
        },
      ),
      label: 'Streamable tool method call',
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-resources',
      'method': 'resources/list',
      'params': {},
    });
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    });
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': resourceUri},
    });
    final resources = await client.listResources(id: 'streamable-resources');
    _expectCatalogContainsValue(
      catalog: resources.resources,
      field: 'uri',
      value: resourceUri,
      label: 'Streamable resource',
    );
    streamable['resources'] = <String, Object?>{
      'uris': [for (final resource in resources.resources) resource['uri']],
      if (resources.nextCursor != null) 'nextCursor': resources.nextCursor,
    };
    final resourceTemplates = await client.listResourceTemplates(
      id: 'streamable-resource-templates',
    );
    streamable['resourceTemplates'] = <String, Object?>{
      'uriTemplates': [
        for (final template in resourceTemplates.resourceTemplates)
          template['uriTemplate'],
      ],
      if (resourceTemplates.nextCursor != null)
        'nextCursor': resourceTemplates.nextCursor,
    };
    streamable['resourceContent'] = await client.readResource(
      resourceUri,
      id: 'streamable-resource-read',
    );
    final methodResources = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-resource-list-method',
        'method': 'resources/list',
        'params': {},
      }),
      'streamable-resource-list-method',
      label: 'Streamable resource method list',
    );
    _expectCatalogContainsValue(
      catalog: methodResources['resources'],
      field: 'uri',
      value: resourceUri,
      label: 'Streamable resource method list',
    );
    final methodResourceTemplates = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-resource-templates-method',
        'method': 'resources/templates/list',
        'params': {},
      }),
      'streamable-resource-templates-method',
      label: 'Streamable resource template method list',
    );
    final methodContent = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-resource-read-method',
        'method': 'resources/read',
        'params': {'uri': resourceUri},
      }),
      'streamable-resource-read-method',
      label: 'Streamable resource method read',
    );
    streamable['resourceMethods'] = <String, Object?>{
      'resources': methodResources['resources'],
      'resourceTemplates': methodResourceTemplates['resourceTemplates'],
      'content': methodContent,
    };
  }

  final promptName = options.promptName;
  if (promptName != null) {
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    });
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-prompt-get',
      'method': 'prompts/get',
      'params': {'name': promptName, 'arguments': options.promptArguments},
    });
    final prompts = await client.listPrompts(id: 'streamable-prompts');
    _expectCatalogContainsValue(
      catalog: prompts.prompts,
      field: 'name',
      value: promptName,
      label: 'Streamable prompt',
    );
    streamable['prompts'] = <String, Object?>{
      'names': [for (final prompt in prompts.prompts) prompt['name']],
      if (prompts.nextCursor != null) 'nextCursor': prompts.nextCursor,
    };
    streamable['prompt'] = await client.getPrompt(
      promptName,
      id: 'streamable-prompt-get',
      arguments: options.promptArguments,
    );
    final methodPrompts = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-prompts-method',
        'method': 'prompts/list',
        'params': {},
      }),
      'streamable-prompts-method',
      label: 'Streamable prompt method list',
    );
    _expectCatalogContainsValue(
      catalog: methodPrompts['prompts'],
      field: 'name',
      value: promptName,
      label: 'Streamable prompt method list',
    );
    final methodPrompt = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-prompt-get-method',
        'method': 'prompts/get',
        'params': {'name': promptName, 'arguments': options.promptArguments},
      }),
      'streamable-prompt-get-method',
      label: 'Streamable prompt method get',
    );
    streamable['promptMethods'] = <String, Object?>{
      'prompts': methodPrompts['prompts'],
      'prompt': methodPrompt,
    };
  }

  final wampProcedure = options.wampProcedure;
  final wampTopic = options.wampTopic;
  if (wampProcedure != null) {
    streamableBatchMessages.addAll([
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-procedure-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'procedure'},
        directJson: false,
      ),
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-procedure-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampProcedure, 'kind': 'procedure'},
        directJson: false,
      ),
    ]);
  }
  if (wampTopic != null) {
    streamableBatchMessages.addAll([
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-topic-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'topic'},
        directJson: false,
      ),
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-topic-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampTopic, 'kind': 'topic'},
        directJson: false,
      ),
    ]);
  }
  final batchResponses = await client.postBatch(
    streamableBatchMessages,
    headers: const {
      'x-consumer-trace': 'router-hosted-client-streamable-batch',
    },
  );
  final responseIds = _expectBatchResponses(batchResponses, [
    for (final message in streamableBatchMessages) message['id']! as String,
  ], label: 'Streamable');
  if (toolName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-batch-tools',
      catalogKey: 'tools',
      field: 'name',
      value: toolName,
      label: 'Streamable batch tool',
    );
  }
  if (resourceUri != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-batch-resources',
      catalogKey: 'resources',
      field: 'uri',
      value: resourceUri,
      label: 'Streamable batch resource',
    );
  }
  if (promptName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-batch-prompts',
      catalogKey: 'prompts',
      field: 'name',
      value: promptName,
      label: 'Streamable batch prompt',
    );
  }
  streamable['batch'] = <String, Object?>{'responseIds': responseIds};
  if (client.sessionId != streamableSessionId) {
    throw StateError('Streamable batch changed session id.');
  }

  if (wampProcedure != null || wampTopic != null) {
    final metadata = <String, Object?>{};

    final sessionCount = await client.countWampSessions(
      id: 'streamable-wamp-session-count',
    );
    metadata['sessionCount'] = _wampMetaResultJson(sessionCount);

    if (wampProcedure != null) {
      final procedures = await client.listWampApi(
        id: 'streamable-wamp-procedure-api-list',
        kind: 'procedure',
      );
      final procedureCatalog = procedures['procedures'];
      _expectWampCatalogContains(
        catalog: procedureCatalog,
        uri: wampProcedure,
        label: 'Streamable WAMP procedure',
      );
      final methodProcedureCatalog = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.list',
          id: 'streamable-wamp-procedure-api-list-method',
          params: const <String, Object?>{'kind': 'procedure'},
        ),
        label: 'Streamable WAMP procedure method list',
      )['procedures'];
      _expectWampCatalogContains(
        catalog: methodProcedureCatalog,
        uri: wampProcedure,
        label: 'Streamable WAMP procedure method list',
      );
      final description = await client.describeWampApi(
        wampProcedure,
        id: 'streamable-wamp-procedure-api-describe',
        kind: 'procedure',
      );
      final methodDescription = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.describe',
          id: 'streamable-wamp-procedure-api-describe-method',
          params: <String, Object?>{'uri': wampProcedure, 'kind': 'procedure'},
        ),
        label: 'Streamable WAMP procedure method describe',
      );
      final registration = await client.matchWampRegistration(
        wampProcedure,
        id: 'streamable-wamp-registration-match',
      );
      metadata['procedure'] = <String, Object?>{
        'name': wampProcedure,
        'catalog': procedureCatalog,
        'description': description,
        'methodCatalog': methodProcedureCatalog,
        'methodDescription': methodDescription,
        'registration': _wampMetaResultJson(registration),
      };
    }

    if (wampTopic != null) {
      final topics = await client.listWampApi(
        id: 'streamable-wamp-topic-api-list',
        kind: 'topic',
      );
      final topicCatalog = topics['topics'];
      _expectWampCatalogContains(
        catalog: topicCatalog,
        uri: wampTopic,
        label: 'Streamable WAMP topic',
      );
      final methodTopicCatalog = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.list',
          id: 'streamable-wamp-topic-api-list-method',
          params: const <String, Object?>{'kind': 'topic'},
        ),
        label: 'Streamable WAMP topic method list',
      )['topics'];
      _expectWampCatalogContains(
        catalog: methodTopicCatalog,
        uri: wampTopic,
        label: 'Streamable WAMP topic method list',
      );
      final description = await client.describeWampApi(
        wampTopic,
        id: 'streamable-wamp-topic-api-describe',
        kind: 'topic',
      );
      final methodDescription = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.describe',
          id: 'streamable-wamp-topic-api-describe-method',
          params: <String, Object?>{'uri': wampTopic, 'kind': 'topic'},
        ),
        label: 'Streamable WAMP topic method describe',
      );
      metadata['topic'] = <String, Object?>{
        'name': wampTopic,
        'catalog': topicCatalog,
        'description': description,
        'methodCatalog': methodTopicCatalog,
        'methodDescription': methodDescription,
      };
    }

    streamable['wampMetadata'] = metadata;
  }

  final pubsubTopic = options.pubsubTopic;
  if (pubsubTopic != null) {
    const queueLimit = 10;
    final subscription = await client.subscribeWampTopic(
      pubsubTopic,
      id: 'streamable-pubsub-subscribe',
      queueLimit: queueLimit,
    );
    _expectWampSubscription(
      subscription,
      topic: pubsubTopic,
      queueLimit: queueLimit,
      label: 'Streamable pub/sub',
    );

    try {
      final subscriptionMeta = await client.matchWampSubscription(
        pubsubTopic,
        id: 'streamable-wamp-subscription-match',
      );
      final publication = await client.publishWampEvent(
        pubsubTopic,
        id: 'streamable-pubsub-publish',
        argumentsKeywords: options.pubsubEvent,
        acknowledge: true,
      );
      _expectWampPublication(
        publication,
        topic: pubsubTopic,
        label: 'Streamable pub/sub',
      );
      final events = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        events,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: options.pubsubEvent,
        label: 'Streamable pub/sub',
      );
      final methodPubsubEvent = <String, Object?>{
        'methodEvent': options.pubsubEvent,
      };
      final methodPublication = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.pubsub.publish',
          id: 'streamable-pubsub-publish-method',
          params: <String, Object?>{
            'topic': pubsubTopic,
            'argumentsKeywords': methodPubsubEvent,
            'acknowledge': true,
          },
        ),
        label: 'Streamable pub/sub method publish',
      );
      if (methodPublication['topic'] != pubsubTopic) {
        throw StateError(
          'Streamable pub/sub method publish returned topic '
          '${methodPublication['topic']}, expected $pubsubTopic.',
        );
      }
      if (methodPublication['acknowledged'] != true) {
        throw StateError(
          'Streamable pub/sub method publish did not acknowledge publication.',
        );
      }
      if (methodPublication['publicationId'] == null) {
        throw StateError(
          'Streamable pub/sub method publish acknowledged without '
          'a publication id.',
        );
      }
      final methodEvents = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-method-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        methodEvents,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: methodPubsubEvent,
        label: 'Streamable pub/sub method poll',
      );
      final notificationEvent = <String, Object?>{
        'notificationEvent': options.pubsubEvent,
      };
      await client.notifyWampEvent(
        pubsubTopic,
        argumentsKeywords: notificationEvent,
      );
      final notificationEvents = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        notificationEvents,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: notificationEvent,
        label: 'Streamable pub/sub notification poll',
      );
      final methodNotificationEvent = <String, Object?>{
        'methodNotificationEvent': options.pubsubEvent,
      };
      await client.notifyConnectanumMethod(
        'connectanum.pubsub.publish',
        params: <String, Object?>{
          'topic': pubsubTopic,
          'argumentsKeywords': methodNotificationEvent,
        },
      );
      final methodNotificationEvents = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-method-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        methodNotificationEvents,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: methodNotificationEvent,
        label: 'Streamable pub/sub method notification poll',
      );
      streamable['pubsub'] = <String, Object?>{
        'topic': pubsubTopic,
        'subscription': <String, Object?>{
          'handle': subscription.handle,
          'topic': subscription.topic,
          'queueLimit': subscription.queueLimit,
          if (subscription.subscriptionId != null)
            'subscriptionId': subscription.subscriptionId,
        },
        'subscriptionMetadata': _wampMetaResultJson(subscriptionMeta),
        'publication': <String, Object?>{
          'topic': publication.topic,
          'acknowledged': publication.acknowledged,
          if (publication.publicationId != null)
            'publicationId': publication.publicationId,
        },
        'events': events.events,
        'methodPublication': methodPublication,
        'methodEvents': methodEvents.events,
        'notificationEvents': notificationEvents.events,
        'methodNotificationEvents': methodNotificationEvents.events,
        'dropped': events.dropped,
        'remaining': events.remaining,
      };
    } finally {
      await client.unsubscribeWampTopic(
        subscription.handle,
        id: 'streamable-pubsub-unsubscribe',
      );
    }
  }

  stdout.writeln(jsonEncode({'streamable': streamable}));
}

final class _Options {
  const _Options({
    required this.endpoint,
    required this.protocolVersion,
    required this.toolArguments,
    required this.promptArguments,
    required this.pubsubEvent,
    required this.dryRun,
    this.bearerToken,
    this.authEndpoint,
    this.authRealm,
    this.authId,
    this.ticket,
    this.toolName,
    this.resourceUri,
    this.promptName,
    this.wampProcedure,
    this.wampTopic,
    this.pubsubTopic,
  });

  final Uri endpoint;
  final String protocolVersion;
  final String? bearerToken;
  final Uri? authEndpoint;
  final String? authRealm;
  final String? authId;
  final String? ticket;
  final String? toolName;
  final McpJsonMap toolArguments;
  final String? resourceUri;
  final String? promptName;
  final Map<String, String> promptArguments;
  final String? wampProcedure;
  final String? wampTopic;
  final String? pubsubTopic;
  final McpJsonMap pubsubEvent;
  final bool dryRun;

  static _Options parse(List<String> args) {
    final values = _parseOptions(args);
    final endpoint = _requiredUri(values, '--endpoint');
    final protocolVersion = _protocolVersionOption(values);
    final bearerToken = _bearerTokenOption(values);
    final authEndpoint = _optionalUri(values, '--auth-url');
    final authRealm = _mcpSelectorOption(values, '--realm');
    final authId = _mcpSelectorOption(values, '--auth-id');
    final ticket = _nonEmptyStringOption(values, '--ticket');

    if (bearerToken != null && authEndpoint != null) {
      throw const FormatException(
        'Use either --bearer-token or --auth-url, not both.',
      );
    }

    final authValues = [authEndpoint, authRealm, authId, ticket];
    if (authValues.any((value) => value != null) &&
        authValues.any((value) => value == null)) {
      throw const FormatException(
        'Use --auth-url, --realm, --auth-id, and --ticket together.',
      );
    }

    if (values.containsKey('--tool-arguments') &&
        !values.containsKey('--tool')) {
      throw const FormatException('Use --tool-arguments together with --tool.');
    }
    if (values.containsKey('--prompt-arguments') &&
        !values.containsKey('--prompt')) {
      throw const FormatException(
        'Use --prompt-arguments together with --prompt.',
      );
    }
    if (values.containsKey('--pubsub-event') &&
        !values.containsKey('--pubsub-topic')) {
      throw const FormatException(
        'Use --pubsub-event together with --pubsub-topic.',
      );
    }

    return _Options(
      endpoint: endpoint,
      protocolVersion: protocolVersion,
      bearerToken: bearerToken,
      authEndpoint: authEndpoint,
      authRealm: authRealm,
      authId: authId,
      ticket: ticket,
      toolName: _mcpToolNameOption(values, '--tool'),
      toolArguments: _jsonObjectOption(
        values,
        '--tool-arguments',
        const <String, Object?>{},
      ),
      resourceUri: _mcpResourceUriOption(values, '--resource-uri'),
      promptName: _mcpSelectorOption(values, '--prompt'),
      promptArguments: _jsonStringMapOption(
        values,
        '--prompt-arguments',
        const <String, String>{},
      ),
      wampProcedure: _mcpSelectorOption(values, '--wamp-procedure'),
      wampTopic: _mcpSelectorOption(values, '--wamp-topic'),
      pubsubTopic: _mcpSelectorOption(values, '--pubsub-topic'),
      pubsubEvent: _jsonObjectOption(
        values,
        '--pubsub-event',
        const <String, Object?>{'source': 'router-hosted-client-example'},
      ),
      dryRun: values.containsKey('--dry-run'),
    );
  }
}

String _protocolVersionOption(Map<String, String> values) {
  final value =
      values['--protocol-version'] ??
      McpStreamableHttpClient.latestProtocolVersion;
  if (_supportedMcpProtocolVersions.contains(value)) {
    return value;
  }
  throw FormatException(
    'Unsupported MCP protocol version "$value". Supported versions: '
    '${_supportedMcpProtocolVersions.join(', ')}.',
  );
}

String? _bearerTokenOption(Map<String, String> values) {
  final rawToken = values['--bearer-token'];
  if (rawToken == null) {
    return null;
  }
  final token = rawToken.trim();
  if (token.isEmpty) {
    throw const FormatException('Bearer token must not be empty.');
  }
  if (_containsMcpWhitespaceOrControl(token)) {
    throw const FormatException(
      'Bearer token must not contain whitespace or control characters.',
    );
  }
  return token;
}

String? _nonEmptyStringOption(Map<String, String> values, String option) {
  final value = values[option];
  if (value == null) {
    return null;
  }
  if (value.runes.every(_isMcpWhitespaceOrControlRune)) {
    throw FormatException('$option must not be empty.');
  }
  return value;
}

String? _mcpToolNameOption(Map<String, String> values, String option) {
  final value = _nonEmptyStringOption(values, option);
  if (value == null) {
    return null;
  }
  if (!_mcpToolNamePattern.hasMatch(value)) {
    throw FormatException(
      '$option must be 1-128 ASCII letters, digits, underscores, hyphens, '
      'or dots.',
    );
  }
  return value;
}

String? _mcpSelectorOption(Map<String, String> values, String option) {
  final value = _nonEmptyStringOption(values, option);
  if (value == null) {
    return null;
  }
  if (_containsMcpWhitespaceOrControl(value)) {
    throw FormatException(
      '$option must not contain whitespace or control characters.',
    );
  }
  return value;
}

String? _mcpResourceUriOption(Map<String, String> values, String option) {
  final value = _nonEmptyStringOption(values, option);
  if (value == null) {
    return null;
  }
  if (_containsMcpWhitespaceOrControl(value)) {
    throw FormatException(
      '$option must not contain whitespace or control characters.',
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    throw FormatException('$option must be an absolute URI with a scheme.');
  }
  return value;
}

bool _containsMcpWhitespaceOrControl(String value) {
  for (final rune in value.runes) {
    if (_isMcpWhitespaceOrControlRune(rune)) {
      return true;
    }
  }
  return false;
}

bool _isMcpWhitespaceOrControlRune(int rune) {
  return rune <= 0x20 ||
      (rune >= 0x7f && rune <= 0x9f) ||
      rune == 0xa0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200a) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202f ||
      rune == 0x205f ||
      rune == 0x3000 ||
      rune == 0xfeff;
}

Map<String, String> _parseOptions(List<String> args) {
  const valueOptions = {
    '--endpoint',
    '--protocol-version',
    '--bearer-token',
    '--auth-url',
    '--realm',
    '--auth-id',
    '--ticket',
    '--tool',
    '--tool-arguments',
    '--resource-uri',
    '--prompt',
    '--prompt-arguments',
    '--wamp-procedure',
    '--wamp-topic',
    '--pubsub-topic',
    '--pubsub-event',
  };
  const flagOptions = {'--dry-run'};

  final values = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final option = args[index];
    if (flagOptions.contains(option)) {
      if (values.containsKey(option)) {
        throw FormatException('Duplicate option: $option.');
      }
      values[option] = 'true';
      continue;
    }
    if (!valueOptions.contains(option)) {
      throw FormatException('Unknown option: $option');
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw FormatException('Missing value for $option.');
    }
    if (values.containsKey(option)) {
      throw FormatException('Duplicate option: $option.');
    }
    values[option] = args[index + 1];
    index += 1;
  }
  return values;
}

Uri _requiredUri(Map<String, String> values, String option) {
  final value = values[option];
  if (value == null) {
    throw FormatException('Missing required $option.');
  }
  return _httpUri(value, option);
}

Uri? _optionalUri(Map<String, String> values, String option) {
  final value = values[option];
  return value == null ? null : _httpUri(value, option);
}

Uri _httpUri(String value, String option) {
  final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    throw FormatException('$option must be an absolute http or https URL.');
  }
  if ((uri.scheme != 'http' && uri.scheme != 'https') || !uri.hasAuthority) {
    throw FormatException('$option must be an absolute http or https URL.');
  }
  return uri;
}

bool _jsonValueEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonValueEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_jsonValueEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

McpJsonMap _jsonObjectOption(
  Map<String, String> values,
  String option,
  McpJsonMap defaultValue,
) {
  final value = values[option];
  if (value == null) {
    return defaultValue;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(value);
  } on FormatException {
    throw FormatException('$option must be valid JSON.');
  }
  if (decoded is! Map) {
    throw FormatException('$option must be a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}

Map<String, String> _jsonStringMapOption(
  Map<String, String> values,
  String option,
  Map<String, String> defaultValue,
) {
  final decoded = _jsonObjectOption(values, option, defaultValue);
  return decoded.map((key, value) {
    if (value is! String) {
      throw FormatException('$option values must be strings.');
    }
    return MapEntry(key, value);
  });
}

void _printUsage(IOSink sink) {
  sink.writeln('''
Usage:
  dart run packages/connectanum_mcp/example/router_hosted_client.dart \\
    --endpoint http://127.0.0.1:8080/mcp [options]

Options:
  --bearer-token TOKEN              Use a bearer-protected MCP route.
  --protocol-version VERSION        MCP protocol version header to send.
  --auth-url URL                    Issue a ticket auth grant from this URL.
  --realm REALM                     Realm for --auth-url ticket grants.
  --auth-id AUTHID                  Auth id for --auth-url ticket grants.
  --ticket TICKET                   Ticket secret for --auth-url grants.
  --tool NAME                       Call this direct JSON tool.
  --tool-arguments JSON_OBJECT      Arguments for --tool.
  --resource-uri URI                Read this resource and list templates through direct JSON and Streamable HTTP.
  --prompt NAME                     Get this prompt through direct JSON and Streamable HTTP.
  --prompt-arguments JSON_OBJECT    String arguments for --prompt.
  --wamp-procedure URI              Describe and match this WAMP procedure through direct JSON and Streamable HTTP.
  --wamp-topic URI                  Describe this WAMP topic through direct JSON and Streamable HTTP.
  --pubsub-topic TOPIC              Exercise direct JSON and Streamable pub/sub helpers.
  --pubsub-event JSON_OBJECT        Event kwargs for --pubsub-topic.
  --dry-run                         Validate options without HTTP requests.
''');
}

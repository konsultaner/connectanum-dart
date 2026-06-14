import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';

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
    await _runDirectWampMetadataExample(client, options);
    if (options.pubsubTopic != null) {
      await _runDirectPubSubExample(client, options);
    }
    await _runStreamableSessionExample(client, options);
  } finally {
    try {
      await client.deleteSession();
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
      closeHttpClient: true,
    );
  }

  return McpStreamableHttpClient(
    options.endpoint,
    httpClient: _shortLivedHttpClient(),
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
      if (options.authEndpoint != null)
        'authEndpoint': options.authEndpoint.toString(),
      if (options.authRealm != null) 'realm': options.authRealm,
      if (options.authId != null) 'authId': options.authId,
      if (options.toolName != null)
        'tool': {'name': options.toolName, 'arguments': options.toolArguments},
      if (options.resourceUri != null) 'resourceUri': options.resourceUri,
      if (options.promptName != null)
        'prompt': {
          'name': options.promptName,
          'arguments': options.promptArguments,
        },
      if (options.wampProcedure != null) 'wampProcedure': options.wampProcedure,
      if (options.wampTopic != null) 'wampTopic': options.wampTopic,
      if (options.pubsubTopic != null)
        'pubsub': {'topic': options.pubsubTopic, 'event': options.pubsubEvent},
    }),
  );
}

// This example is a short-lived CLI, so avoid keeping HTTP sockets alive
// after its final request completes.
HttpClient _shortLivedHttpClient() => HttpClient()..idleTimeout = Duration.zero;

Future<void> _runDirectJsonExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final catalog = await client.listConnectanumToolsDirect(id: 'direct-tools');
  stdout.writeln(
    jsonEncode({
      'directTools': [for (final tool in catalog.tools) tool['name']],
      if (catalog.nextCursor != null) 'nextCursor': catalog.nextCursor,
    }),
  );

  final toolName = options.toolName;
  if (toolName != null) {
    final result = await client.callConnectanumToolDirect(
      toolName,
      id: 'direct-tool-call',
      arguments: options.toolArguments,
    );
    stdout.writeln(jsonEncode({'directToolResult': result}));
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    final resources = await client.listResourcesDirect(id: 'direct-resources');
    final content = await client.readResourceDirect(
      resourceUri,
      id: 'direct-resource-read',
    );
    stdout.writeln(
      jsonEncode({
        'directResources': [
          for (final resource in resources.resources) resource['uri'],
        ],
        'directResourceContent': content,
      }),
    );
  }

  final promptName = options.promptName;
  if (promptName != null) {
    final prompts = await client.listPromptsDirect(id: 'direct-prompts');
    final prompt = await client.getPromptDirect(
      promptName,
      id: 'direct-prompt-get',
      arguments: options.promptArguments,
    );
    stdout.writeln(
      jsonEncode({
        'directPrompts': [for (final prompt in prompts.prompts) prompt['name']],
        'directPrompt': prompt,
      }),
    );
  }
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
    final description = await client.describeWampApiDirect(
      procedure,
      id: 'direct-wamp-procedure-api-describe',
      kind: 'procedure',
    );
    final registration = await client.matchWampRegistrationDirect(
      procedure,
      id: 'direct-wamp-registration-match',
    );
    metadata['procedure'] = {
      'name': procedure,
      'catalog': procedures['procedures'],
      'description': description,
      'registration': _wampMetaResultJson(registration),
    };
  }

  if (topic != null) {
    final topics = await client.listWampApiDirect(
      id: 'direct-wamp-topic-api-list',
      kind: 'topic',
    );
    final description = await client.describeWampApiDirect(
      topic,
      id: 'direct-wamp-topic-api-describe',
      kind: 'topic',
    );
    metadata['topic'] = {
      'name': topic,
      'catalog': topics['topics'],
      'description': description,
    };
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct WAMP metadata changed Streamable state.');
  }

  stdout.writeln(jsonEncode({'directWampMetadata': metadata}));
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

Future<void> _runDirectPubSubExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final topic = options.pubsubTopic!;
  final subscription = await client.subscribeWampTopicDirect(
    topic,
    id: 'direct-pubsub-subscribe',
    queueLimit: 10,
  );

  try {
    final subscriptionMeta = options.wampTopic == topic
        ? await client.matchWampSubscriptionDirect(
            topic,
            id: 'direct-wamp-subscription-match',
          )
        : null;
    await client.publishWampEventDirect(
      topic,
      id: 'direct-pubsub-publish',
      argumentsKeywords: options.pubsubEvent,
      acknowledge: true,
    );
    final events = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-poll',
      limit: 10,
    );
    final observed = events.events.any(
      (event) =>
          _jsonValueEquals(event['argumentsKeywords'], options.pubsubEvent),
    );
    if (!observed) {
      throw StateError(
        'Published event was not observed on direct JSON pub/sub topic $topic.',
      );
    }
    stdout.writeln(
      jsonEncode({
        'pubsubTopic': topic,
        'events': events.events,
        'dropped': events.dropped,
        'remaining': events.remaining,
        if (subscriptionMeta != null)
          'subscription': _wampMetaResultJson(subscriptionMeta),
      }),
    );
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: 'direct-pubsub-unsubscribe',
    );
  }
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

  final tools = await client.listTools(id: 'streamable-tools');
  final streamable = <String, Object?>{
    'protocolVersion': client.protocolVersion,
    'sessionId': client.sessionId,
    'initialize': initialize['result'],
    'tools': [for (final tool in tools.tools) tool['name']],
  };

  final toolName = options.toolName;
  if (toolName != null) {
    streamable['toolResult'] = await client.callTool(
      toolName,
      id: 'streamable-tool-call',
      arguments: options.toolArguments,
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    streamable['resourceContent'] = await client.readResource(
      resourceUri,
      id: 'streamable-resource-read',
    );
  }

  final promptName = options.promptName;
  if (promptName != null) {
    streamable['prompt'] = await client.getPrompt(
      promptName,
      id: 'streamable-prompt-get',
      arguments: options.promptArguments,
    );
  }

  stdout.writeln(jsonEncode({'streamable': streamable}));
}

final class _Options {
  const _Options({
    required this.endpoint,
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
    final bearerToken = values['--bearer-token'];
    final authEndpoint = _optionalUri(values, '--auth-url');
    final authRealm = values['--realm'];
    final authId = values['--auth-id'];
    final ticket = values['--ticket'];

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
      bearerToken: bearerToken,
      authEndpoint: authEndpoint,
      authRealm: authRealm,
      authId: authId,
      ticket: ticket,
      toolName: values['--tool'],
      toolArguments: _jsonObjectOption(
        values,
        '--tool-arguments',
        const <String, Object?>{},
      ),
      resourceUri: values['--resource-uri'],
      promptName: values['--prompt'],
      promptArguments: _jsonStringMapOption(
        values,
        '--prompt-arguments',
        const <String, String>{},
      ),
      wampProcedure: values['--wamp-procedure'],
      wampTopic: values['--wamp-topic'],
      pubsubTopic: values['--pubsub-topic'],
      pubsubEvent: _jsonObjectOption(
        values,
        '--pubsub-event',
        const <String, Object?>{'source': 'router-hosted-client-example'},
      ),
      dryRun: values.containsKey('--dry-run'),
    );
  }
}

Map<String, String> _parseOptions(List<String> args) {
  const valueOptions = {
    '--endpoint',
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
  final uri = Uri.parse(value);
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
  final decoded = jsonDecode(value);
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
  --auth-url URL                    Issue a ticket auth grant from this URL.
  --realm REALM                     Realm for --auth-url ticket grants.
  --auth-id AUTHID                  Auth id for --auth-url ticket grants.
  --ticket TICKET                   Ticket secret for --auth-url grants.
  --tool NAME                       Call this direct JSON tool.
  --tool-arguments JSON_OBJECT      Arguments for --tool.
  --resource-uri URI                Read this resource through direct JSON and Streamable HTTP.
  --prompt NAME                     Get this prompt through direct JSON and Streamable HTTP.
  --prompt-arguments JSON_OBJECT    String arguments for --prompt.
  --wamp-procedure URI              Describe and match this WAMP procedure through direct JSON.
  --wamp-topic URI                  Describe this WAMP topic through direct JSON.
  --pubsub-topic TOPIC              Exercise direct JSON pub/sub helpers.
  --pubsub-event JSON_OBJECT        Event kwargs for --pubsub-topic.
  --dry-run                         Validate options without HTTP requests.
''');
}

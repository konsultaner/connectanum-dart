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
    if (options.pubsubTopic != null) {
      await _runDirectPubSubExample(client, options);
    }
    await _runStreamableSessionExample(client);
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
  stdout.writeln(
    jsonEncode({
      'streamable': {
        'protocolVersion': client.protocolVersion,
        'sessionId': client.sessionId,
        'initialize': initialize['result'],
        'tools': [for (final tool in tools.tools) tool['name']],
      },
    }),
  );
}

final class _Options {
  const _Options({
    required this.endpoint,
    required this.toolArguments,
    required this.pubsubEvent,
    required this.dryRun,
    this.bearerToken,
    this.authEndpoint,
    this.authRealm,
    this.authId,
    this.ticket,
    this.toolName,
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
  --pubsub-topic TOPIC              Exercise direct JSON pub/sub helpers.
  --pubsub-event JSON_OBJECT        Event kwargs for --pubsub-topic.
  --dry-run                         Validate options without HTTP requests.
''');
}

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_mcp/src/cli/router_hosted_client.dart';
import 'package:test/test.dart';

const _endpoint = 'https://router.example/mcp';
const _secret = 'do-not-print-this-secret';
const _base = ['--endpoint', _endpoint, '--dry-run'];

void main() {
  group('public router-hosted CLI options', () {
    for (final help in ['--help', '-h']) {
      test('$help works without endpoint or network access', () async {
        final output = await _run([help]);
        expect(output.code, 0);
        expect(output.err, isEmpty);
        expect(
          output.out,
          contains('dart run connectanum_mcp:router_hosted_client'),
        );
        expect(output.out, contains('--endpoint'));
        expect(output.out, contains('--scram-secret'));
      });
    }

    test(
      'minimal dry run reports defaults without optional capabilities',
      () async {
        final output = await _run(_base);
        expect(output.code, 0);
        expect(output.err, isEmpty);
        expect(jsonDecode(output.out), {
          'dryRun': true,
          'endpoint': _endpoint,
          'authMode': 'none',
          'protocolVersion':
              McpStreamableHttpClient.latestSessionProtocolVersion,
          'transportMode': 'streamable',
        });
      },
    );

    for (final version in ['2025-03-26', '2025-06-18', '2025-11-25']) {
      test('compatibility protocol $version retains session mode', () async {
        final output = await _run([..._base, '--protocol-version', version]);
        expect(output.code, 0);
        expect(output.err, isEmpty);
        expect(
          jsonDecode(output.out),
          containsPair('protocolVersion', version),
        );
        expect(
          jsonDecode(output.out),
          containsPair('transportMode', 'streamable'),
        );
      });
    }

    test('modern protocol selects stateless mode', () async {
      final output = await _run([
        ..._base,
        '--protocol-version',
        McpStreamableHttpClient.latestProtocolVersion,
      ]);
      expect(output.code, 0);
      expect(output.err, isEmpty);
      expect(
        jsonDecode(output.out),
        containsPair('transportMode', 'stateless'),
      );
    });

    test(
      'all optional selectors and structured values retain their content',
      () async {
        final output = await _run([
          ..._base,
          '--bearer-token',
          ' $_secret ',
          '--rejected-origin',
          'https://untrusted.example',
          '--tool',
          'tools.Echo_1-2',
          '--tool-arguments',
          '{"items":[1,true,null,{"name":"hello"}]}',
          '--resource-uri',
          'app://notes/current',
          '--resource-template',
          'app://notes/{id}',
          '--resource-template-variables',
          '{"id":"a/b"}',
          '--resource-update-topic',
          'notes.updated',
          '--resource-update-event',
          '{"revision":2}',
          '--prompt',
          'inspect-note',
          '--prompt-arguments',
          '{"locale":"de"}',
          '--wamp-procedure',
          'notes.get',
          '--wamp-topic',
          'notes.updated',
          '--pubsub-topic',
          'chat.events',
          '--pubsub-event',
          '{"text":"hello","attachments":[]}',
        ]);
        expect(output.code, 0);
        expect(output.err, isEmpty);
        expect(jsonDecode(output.out), {
          'dryRun': true,
          'endpoint': _endpoint,
          'authMode': 'bearer',
          'protocolVersion':
              McpStreamableHttpClient.latestSessionProtocolVersion,
          'transportMode': 'streamable',
          'rejectedOrigin': 'https://untrusted.example',
          'tool': {
            'name': 'tools.Echo_1-2',
            'arguments': {
              'items': [
                1,
                true,
                null,
                {'name': 'hello'},
              ],
            },
          },
          'resourceUri': 'app://notes/current',
          'resourceTemplates': true,
          'resourceSubscription': {
            'updateTopic': 'notes.updated',
            'updateEvent': {'revision': 2},
          },
          'resourceTemplateExpansion': {
            'uriTemplate': 'app://notes/{id}',
            'variableNames': ['id'],
            'uri': 'app://notes/a%2Fb',
          },
          'prompt': {
            'name': 'inspect-note',
            'arguments': {'locale': 'de'},
          },
          'wampProcedure': 'notes.get',
          'configuredRegistrationMetadata': true,
          'wampTopic': 'notes.updated',
          'configuredSubscriptionMetadata': true,
          'pubsub': {
            'topic': 'chat.events',
            'event': {'text': 'hello', 'attachments': []},
            'subscriptionMetadata': true,
          },
        });
        expect(output.out, isNot(contains(_secret)));
      },
    );

    test('optional payload defaults are independent', () async {
      final output = await _run([
        ..._base,
        '--tool',
        'echo',
        '--prompt',
        'inspect',
        '--resource-uri',
        'app://notes/current',
        '--resource-update-topic',
        'notes.updated',
        '--pubsub-topic',
        'chat.events',
      ]);
      expect(output.code, 0);
      final data = jsonDecode(output.out) as Map;
      expect(data['tool'], {'name': 'echo', 'arguments': {}});
      expect(data['prompt'], {'name': 'inspect', 'arguments': {}});
      expect(data['resourceSubscription'], {
        'updateTopic': 'notes.updated',
        'updateEvent': {'source': 'router-hosted-client-resource-update'},
      });
      expect(data['pubsub'], {
        'topic': 'chat.events',
        'event': {'source': 'router-hosted-client-example'},
        'subscriptionMetadata': true,
      });
    });

    for (final method in {
      '--ticket': 'ticket',
      '--wampcra-secret': 'wampcra',
      '--scram-secret': 'scram',
    }.entries) {
      for (final discover in [false, true]) {
        test(
          '${method.key} ${discover ? 'discovery' : 'explicit endpoint'} never prints credentials',
          () async {
            final output = await _run([
              ..._base,
              '--realm',
              'consumer.realm',
              '--auth-id',
              'consumer',
              method.key,
              _secret,
              '--auth-lifecycle-smoke',
              if (!discover) ...['--auth-url', 'https://router.example/auth'],
            ]);
            expect(output.code, 0);
            expect(output.err, isEmpty);
            expect(jsonDecode(output.out), {
              'dryRun': true,
              'endpoint': _endpoint,
              'authMode': '${method.value}${discover ? '-discovered' : ''}',
              'protocolVersion':
                  McpStreamableHttpClient.latestSessionProtocolVersion,
              'transportMode': 'streamable',
              if (!discover) 'authEndpoint': 'https://router.example/auth',
              'realm': 'consumer.realm',
              if (discover) 'authEndpointDiscovery': true,
              'authId': 'consumer',
              'authLifecycleSmoke': true,
            });
            expect(output.out, isNot(contains(_secret)));
          },
        );
      }
    }

    final invalid = <(String, List<String>, String)>[
      ('missing endpoint', [], 'Missing required --endpoint.'),
      ('unknown option', [..._base, '--wat'], 'Unknown option: --wat'),
      ('positional argument', [..._base, 'value'], 'Unknown option: value'),
      (
        'missing value at end',
        [..._base, '--tool'],
        'Missing value for --tool.',
      ),
      (
        'missing value before flag',
        [..._base, '--tool', '--prompt', 'inspect'],
        'Missing value for --tool.',
      ),
      (
        'duplicate value',
        [..._base, '--tool', 'echo', '--tool', 'inspect'],
        'Duplicate option: --tool.',
      ),
      (
        'duplicate dry run',
        [..._base, '--dry-run'],
        'Duplicate option: --dry-run.',
      ),
      (
        'duplicate lifecycle',
        [..._base, '--auth-lifecycle-smoke', '--auth-lifecycle-smoke'],
        'Duplicate option: --auth-lifecycle-smoke.',
      ),
      (
        'unsupported version',
        [..._base, '--protocol-version', 'invalid'],
        'Unsupported MCP protocol version',
      ),
      (
        'empty bearer',
        [..._base, '--bearer-token', ' '],
        'Bearer token must not be empty.',
      ),
      (
        'auth lifecycle without credentials',
        [..._base, '--auth-lifecycle-smoke'],
        'Use --auth-lifecycle-smoke together with HTTP auth credentials.',
      ),
      (
        'modern origin check',
        [
          ..._base,
          '--protocol-version',
          McpStreamableHttpClient.latestProtocolVersion,
          '--rejected-origin',
          'https://other.example',
        ],
        'Use --rejected-origin only with compatibility Streamable HTTP.',
      ),
      (
        'tool arguments without tool',
        [..._base, '--tool-arguments', '{}'],
        'Use --tool-arguments together with --tool.',
      ),
      (
        'template variables without template',
        [..._base, '--resource-template-variables', '{}'],
        'Use --resource-template-variables together with --resource-template.',
      ),
      (
        'missing template variable',
        [..._base, '--resource-template', 'app://notes/{id}'],
        'id',
      ),
      (
        'invalid template',
        [..._base, '--resource-template', 'app://notes/{+id}'],
        'template',
      ),
      (
        'resource topic without resource',
        [..._base, '--resource-update-topic', 'notes.updated'],
        'Use --resource-update-topic together with --resource-uri.',
      ),
      (
        'resource event without topic',
        [..._base, '--resource-update-event', '{}'],
        'Use --resource-update-event together with --resource-update-topic.',
      ),
      (
        'prompt arguments without prompt',
        [..._base, '--prompt-arguments', '{}'],
        'Use --prompt-arguments together with --prompt.',
      ),
      (
        'pubsub event without topic',
        [..._base, '--pubsub-event', '{}'],
        'Use --pubsub-event together with --pubsub-topic.',
      ),
    ];
    for (final (name, args, message) in invalid) {
      test(
        'rejects $name without network access',
        () => _expectInvalid(args, message),
      );
    }

    for (final option in ['--endpoint', '--auth-url', '--rejected-origin']) {
      for (final uri in [
        'relative/path',
        'ftp://router.example/mcp',
        'https:path',
        'http://[invalid',
      ]) {
        test(
          'rejects invalid $option URL $uri',
          () => _expectInvalid([
            if (option != '--endpoint') ..._base,
            option,
            uri,
          ], '$option must be an absolute http or https URL.'),
        );
      }
    }

    for (final option in [
      '--realm',
      '--auth-id',
      '--ticket',
      '--wampcra-secret',
      '--scram-secret',
      '--auth-url',
    ]) {
      test(
        'rejects incomplete HTTP authentication $option',
        () => _expectInvalid([
          ..._base,
          option,
          option == '--auth-url' ? 'https://router.example/auth' : _secret,
        ], 'Use --realm, --auth-id, and exactly one'),
      );
      test(
        'rejects bearer combined with $option without printing credentials',
        () => _expectInvalid([
          ..._base,
          '--bearer-token',
          _secret,
          option,
          option == '--auth-url' ? 'https://router.example/auth' : _secret,
        ], 'Use either --bearer-token or HTTP auth options, not both.'),
      );
    }
    final secrets = ['--ticket', '--wampcra-secret', '--scram-secret'];
    for (var i = 0; i < secrets.length; i++) {
      test(
        'rejects multiple secrets ${secrets[i]}',
        () => _expectInvalid([
          ..._base,
          secrets[i],
          _secret,
          secrets[(i + 1) % secrets.length],
          _secret,
        ], 'Use exactly one of --ticket, --wampcra-secret, or --scram-secret.'),
      );
    }

    for (final option in [
      '--tool',
      '--realm',
      '--auth-id',
      '--ticket',
      '--wampcra-secret',
      '--scram-secret',
      '--resource-uri',
      '--resource-template',
      '--prompt',
      '--wamp-procedure',
      '--wamp-topic',
      '--pubsub-topic',
    ]) {
      test(
        'rejects empty $option',
        () => _expectInvalid([
          ..._base,
          option,
          '',
        ], '$option must not be empty.'),
      );
    }
    for (final value in [
      'two words',
      'slash/name',
      'unicode-\u00e4',
      'x' * 129,
    ]) {
      test(
        'rejects invalid tool name ${value.length}',
        () => _expectInvalid([
          ..._base,
          '--tool',
          value,
        ], '--tool must be 1-128 ASCII'),
      );
    }
    test('accepts the tool name upper bound', () async {
      final output = await _run([..._base, '--tool', 'x' * 128]);
      expect(output.code, 0);
      expect((jsonDecode(output.out) as Map)['tool'], {
        'name': 'x' * 128,
        'arguments': {},
      });
    });
    for (final uri in ['notes/relative', 'app://[bad', '://missing']) {
      test(
        'rejects malformed resource URI $uri',
        () => _expectInvalid([
          ..._base,
          '--resource-uri',
          uri,
        ], '--resource-uri must be an absolute URI with a scheme.'),
      );
    }

    // Boundary values distinguish every whitespace/control range, not just ASCII space.
    for (final rune in [
      0,
      0x1f,
      0x20,
      0x7f,
      0x80,
      0x9f,
      0xa0,
      0x1680,
      0x2000,
      0x200a,
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
      0xfeff,
    ]) {
      for (final option in ['--bearer-token', '--prompt', '--resource-uri']) {
        test(
          '$option rejects embedded U+${rune.toRadixString(16)}',
          () => _expectInvalid([
            ..._base,
            option,
            'app://before${String.fromCharCode(rune)}after',
          ], 'must not contain whitespace or control characters.'),
        );
      }
      test(
        'secret rejects only-whitespace U+${rune.toRadixString(16)}',
        () => _expectInvalid([
          ..._base,
          '--ticket',
          String.fromCharCode(rune),
        ], '--ticket must not be empty.'),
      );
    }
    for (final rune in [
      0x21,
      0x7e,
      0xa1,
      0x167f,
      0x1681,
      0x1fff,
      0x200b,
      0x2027,
      0x202a,
      0x202e,
      0x2030,
      0x205e,
      0x2060,
      0x2fff,
      0x3001,
      0xfefe,
      0xff00,
      0x1f600,
    ]) {
      test(
        'selector accepts non-whitespace neighbor U+${rune.toRadixString(16)}',
        () async {
          final name = 'before${String.fromCharCode(rune)}after';
          final output = await _run([..._base, '--prompt', name]);
          expect(output.code, 0);
          expect(output.err, isEmpty);
          expect((jsonDecode(output.out) as Map)['prompt'], {
            'name': name,
            'arguments': {},
          });
        },
      );
    }

    for (final (option, parents, stringValues)
        in <(String, List<String>, bool)>[
          ('--tool-arguments', ['--tool', 'echo'], false),
          ('--prompt-arguments', ['--prompt', 'inspect'], true),
          (
            '--resource-template-variables',
            ['--resource-template', 'app://notes/fixed'],
            true,
          ),
          (
            '--resource-update-event',
            [
              '--resource-uri',
              'app://notes/fixed',
              '--resource-update-topic',
              'notes.updated',
            ],
            false,
          ),
          ('--pubsub-event', ['--pubsub-topic', 'notes.updated'], false),
        ]) {
      for (final (value, error) in [
        ('{', 'valid JSON'),
        ('[]', 'a JSON object'),
        ('null', 'a JSON object'),
        ('42', 'a JSON object'),
        ('"$_secret"', 'a JSON object'),
      ]) {
        test(
          '$option rejects $value',
          () => _expectInvalid([
            ..._base,
            ...parents,
            option,
            value,
          ], '$option must be $error.'),
        );
      }
      if (stringValues) {
        for (final value in ['null', '1', 'true', '[]', '{}']) {
          test(
            '$option rejects non-string map value $value',
            () => _expectInvalid([
              ..._base,
              ...parents,
              option,
              '{"key":$value}',
            ], '$option values must be strings.'),
          );
        }
      }
    }
  });
}

Future<void> _expectInvalid(List<String> args, String message) async {
  final output = await _run(args);
  expect(output.code, 64);
  expect(output.out, isEmpty);
  expect(output.err, contains(message));
  expect(output.err, contains('Usage:'));
  expect(output.err, isNot(contains(_secret)));
}

Future<({int code, String out, String err})> _run(List<String> args) async {
  final output = _CapturedStdout();
  final errors = _CapturedStdout();
  final previousCode = exitCode;
  var networkAttempts = 0;
  exitCode = 0;
  try {
    await IOOverrides.runZoned(
      () => HttpOverrides.runZoned(
        () => runRouterHostedClient(args),
        createHttpClient: (_) {
          networkAttempts++;
          fail('Option validation and dry runs must not create an HTTP client');
        },
      ),
      stdout: () => output,
      stderr: () => errors,
    );
    expect(networkAttempts, 0);
    return (
      code: exitCode,
      out: output.text.toString(),
      err: errors.text.toString(),
    );
  } finally {
    exitCode = previousCode;
  }
}

class _CapturedStdout implements Stdout {
  final text = StringBuffer();

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

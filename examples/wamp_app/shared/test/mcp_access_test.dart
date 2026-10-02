import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('each required MCP capability is enforced independently', () {
    const capabilities = [
      'streamable_http',
      'direct_json',
      'tools',
      'resources',
      'prompts',
    ];
    final valid = _configuration().toWampKeywords();
    for (final capability in capabilities) {
      expect(
        () => _configuration(disabled: capability),
        throwsFormatException,
        reason: 'constructor: $capability',
      );
      for (final invalid in <Object?>[false, null, 1, 'true']) {
        expect(
          () => WampAppMcpAccessConfiguration.fromWampKeywords({
            ...valid,
            capability: invalid,
          }),
          throwsFormatException,
          reason: 'wire: $capability=$invalid',
        );
      }
    }
  });

  test('MCP metadata rejects missing keys and independent type changes', () {
    final valid = _configuration().toWampKeywords();
    expect(
      () => WampAppMcpAccessConfiguration.fromWampKeywords(null),
      throwsFormatException,
    );
    for (final key in valid.keys) {
      final missing = {...valid}..remove(key);
      for (final value in [
        missing,
        {...missing, 'unknown_field': true},
      ]) {
        expect(
          () => WampAppMcpAccessConfiguration.fromWampKeywords(value),
          throwsFormatException,
          reason: 'missing $key, keys=${value.keys}',
        );
      }
    }
    for (final key in ['version', 'mcp_path', 'auth_path', 'profile_fields']) {
      for (final invalid in <Object?>[null, false, 42]) {
        expect(
          () => WampAppMcpAccessConfiguration.fromWampKeywords({
            ...valid,
            key: invalid,
          }),
          throwsFormatException,
          reason: '$key=$invalid',
        );
      }
    }
    expect(
      () => WampAppMcpAccessConfiguration.fromWampKeywords({
        ...valid,
        'profile_fields': [..._profileFields.take(5), 42],
      }),
      throwsFormatException,
    );
  });

  test('MCP profile boundary is exact, order independent, and immutable', () {
    final fields = _profileFields.reversed.toList();
    final configuration = _configuration(fields: fields);
    fields.clear();
    expect(configuration.profileFields, orderedEquals(_profileFields.reversed));
    expect(() => configuration.profileFields.clear(), throwsUnsupportedError);
    expect(
      WampAppMcpAccessConfiguration.fromWampKeywords(
        configuration.toWampKeywords(),
      ).profileFields,
      orderedEquals(_profileFields.reversed),
    );
    for (final invalid in [
      <String>[],
      _profileFields.take(5).toList(),
      [..._profileFields.take(5), 'private_key'],
      [..._profileFields.take(5), 'username'],
      [..._profileFields, 'private_key'],
    ]) {
      expect(() => _configuration(fields: invalid), throwsFormatException);
    }
  });

  test('both MCP routes reject origin changes and non-path URI components', () {
    for (final path in [
      '',
      'relative',
      'https://attacker.example/mcp',
      '//attacker.example/mcp',
      '//user@attacker.example/mcp',
      '//[invalid',
      '/mcp?query=value',
      '/mcp?',
      '/mcp#fragment',
      '/mcp with spaces',
      '/mcp/../admin',
    ]) {
      expect(
        () => _configuration(mcpPath: path),
        throwsFormatException,
        reason: 'mcp: $path',
      );
      expect(
        () => _configuration(authPath: path),
        throwsFormatException,
        reason: 'auth: $path',
      );
    }
    final configuration = _configuration(
      mcpPath: '/agent/v1/mcp',
      authPath: '/agent/v1/auth',
    );
    final endpoint = ServerEndpoint.parse('wss://[::1]:9443/wamp');
    expect(
      configuration.mcpUriFor(endpoint).toString(),
      'https://[::1]:9443/agent/v1/mcp',
    );
    expect(
      configuration.authUriFor(endpoint).toString(),
      'https://[::1]:9443/agent/v1/auth',
    );
  });

  test('MCP access configuration round-trips without credentials', () {
    final configuration = WampAppMcpAccessConfiguration.standard(
      mcpPath: '/agent/mcp',
      authPath: '/agent/mcp/auth',
    );

    final encoded = configuration.toWampKeywords();
    final decoded = WampAppMcpAccessConfiguration.fromWampKeywords(encoded);

    expect(decoded.mcpPath, '/agent/mcp');
    expect(decoded.authPath, '/agent/mcp/auth');
    expect(decoded.streamableHttp, isTrue);
    expect(decoded.directJson, isTrue);
    expect(decoded.tools, isTrue);
    expect(decoded.resources, isTrue);
    expect(decoded.prompts, isTrue);
    expect(decoded.profileFields, WampAppMcpAccessContract.profileFields);
    expect(
      encoded.keys,
      isNot(contains(anyOf('password', 'access_token', 'refresh_token'))),
    );
  });

  test('MCP routes resolve against the connected WAMP origin', () {
    final configuration = WampAppMcpAccessConfiguration.standard(
      mcpPath: '/mcp',
      authPath: '/mcp/auth',
    );

    final secure = ServerEndpoint.parse('wss://chat.example:9443/wamp');
    expect(
      configuration.mcpUriFor(secure),
      Uri.parse('https://chat.example:9443/mcp'),
    );
    expect(
      configuration.authUriFor(secure),
      Uri.parse('https://chat.example:9443/mcp/auth'),
    );

    final local = ServerEndpoint.parse('ws://localhost:18080/ws');
    expect(
      configuration.mcpUriFor(local),
      Uri.parse('http://localhost:18080/mcp'),
    );
  });

  test('MCP access configuration rejects unsafe or misleading metadata', () {
    final valid = WampAppMcpAccessConfiguration.standard(
      mcpPath: '/mcp',
      authPath: '/mcp/auth',
    ).toWampKeywords();

    for (final invalid in <Map<String, dynamic>>[
      {...valid, 'mcp_path': 'https://attacker.example/mcp'},
      {...valid, 'auth_path': '/mcp?token=secret'},
      {...valid, 'auth_path': '/mcp'},
      {...valid, 'streamable_http': false},
      {
        ...valid,
        'profile_fields': [...valid['profile_fields'] as List, 'chat'],
      },
      {
        ...valid,
        'profile_fields': const ['username'],
      },
      {
        ...valid,
        'profile_fields': const ['username', 'username'],
      },
      {...valid, 'version': 2},
      {...valid, 'access_token': 'must-not-cross-the-boundary'},
    ]) {
      expect(
        () => WampAppMcpAccessConfiguration.fromWampKeywords(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });
}

const _profileFields = [
  'username',
  'display_name',
  'status',
  'profile_revision',
  'profile_updated_at',
  'consent_revision',
];

WampAppMcpAccessConfiguration _configuration({
  String mcpPath = '/mcp',
  String authPath = '/mcp/auth',
  String? disabled,
  List<String> fields = _profileFields,
}) => WampAppMcpAccessConfiguration(
  mcpPath: mcpPath,
  authPath: authPath,
  streamableHttp: disabled != 'streamable_http',
  directJson: disabled != 'direct_json',
  tools: disabled != 'tools',
  resources: disabled != 'resources',
  prompts: disabled != 'prompts',
  profileFields: fields,
);

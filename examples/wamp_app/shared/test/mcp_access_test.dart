import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
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

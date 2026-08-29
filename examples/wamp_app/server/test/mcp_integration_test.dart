import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test('MCP is authenticated, consent gated, and account scoped', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wamp-app-mcp-smoke-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final server = await WampAppServer.start(
      WampAppServerConfig(
        host: '127.0.0.1',
        port: 0,
        websocketPath: '/ws',
        accountStorePath: '${directory.path}/accounts.json',
        messageStorePath: '${directory.path}/messages.json',
        backupStorePath: '${directory.path}/backups',
        mcp: WampAppMcpConfig(
          enabled: true,
          path: '/agent/mcp',
          authPath: '/agent/mcp/auth',
          consentStorePath: '${directory.path}/mcp-consent.json',
          allowInsecureTransport: true,
        ),
        argonIterations: 2,
        argonMemoryKiB: 8192,
      ),
    );
    addTearDown(server.close);
    final endpoint = server.mcpUri!;

    await _registerAccounts(server.websocketUri);
    final alice = await _connectAccount(
      server.websocketUri,
      username: 'alice',
      password: 'correct horse battery',
    );
    final bob = await _connectAccount(
      server.websocketUri,
      username: 'bob',
      password: 'another correct horse',
    );
    addTearDown(alice.close);
    addTearDown(bob.close);

    final access = WampAppMcpAccessConfiguration.fromWampKeywords(
      (await alice.session.callSingle(
        WampAppProtocol.mcpAccessGet,
      )).argumentsKeywords,
    );
    expect(access.mcpPath, '/agent/mcp');
    expect(access.authPath, '/agent/mcp/auth');
    expect(
      access.mcpUriFor(ServerEndpoint.parse(server.websocketUri.toString())),
      endpoint,
    );
    expect(access.profileFields, WampAppMcpAccessContract.profileFields);
    expect(
      access.toWampKeywords().keys,
      isNot(contains(anyOf('password', 'access_token', 'refresh_token'))),
    );
    await expectLater(
      alice.session.callSingle(
        WampAppProtocol.mcpAccessGet,
        argumentsKeywords: const {'include_secrets': true},
      ),
      throwsA(
        isA<wamp.Error>().having(
          (error) => error.error,
          'error URI',
          WampAppProtocol.errorInvalidMcpAccess,
        ),
      ),
    );

    final unauthenticated = McpStreamableHttpClient.stateless(
      endpoint,
      clientInfo: const {'name': 'wamp-app-smoke', 'version': '0.1.0'},
    );
    addTearDown(() => unauthenticated.close(force: true));
    late final McpBearerChallenge challenge;
    try {
      await unauthenticated.listToolsDirect(id: 'unauthenticated-tools');
      fail('The MCP endpoint accepted an unauthenticated tool request.');
    } on McpStreamableHttpException catch (error) {
      expect(error.statusCode, HttpStatus.unauthorized);
      expect(error.bearerChallenges, hasLength(1));
      challenge = error.bearerChallenges.single;
    }

    final authClient = ConnectanumHttpAuthClient.fromMcpBearerChallenge(
      endpoint,
      challenge,
    );
    addTearDown(() => authClient.close(force: true));
    final aliceGrant = await authClient.issueScramToken(
      realm: WampAppProtocol.appRealm,
      authId: 'alice',
      secret: 'correct horse battery',
    );
    final bobGrant = await authClient.issueScramToken(
      realm: WampAppProtocol.appRealm,
      authId: 'bob',
      secret: 'another correct horse',
    );
    final aliceMcp = McpStreamableHttpClient.withAuthGrant(
      endpoint,
      aliceGrant,
    );
    final bobMcp = McpStreamableHttpClient.statelessWithAuthGrant(
      endpoint,
      bobGrant,
      clientInfo: const {'name': 'wamp-app-smoke', 'version': '0.1.0'},
    );
    addTearDown(() => aliceMcp.close(force: true));
    addTearDown(() => bobMcp.close(force: true));

    await aliceMcp.initialize(id: 'alice-initialize');
    await aliceMcp.notifyInitialized();
    expect(aliceMcp.sessionId, isNotNull);

    final tools = await aliceMcp.listTools(id: 'alice-tools');
    expect(
      tools.tools.map((tool) => tool['name']),
      unorderedEquals([
        'connectanum.api.describe',
        'connectanum.api.list',
        'wampapp_profile_summary',
      ]),
    );
    final apiCatalog = await aliceMcp.callTool(
      'connectanum.api.list',
      id: 'alice-api-catalog',
      arguments: const {'kind': 'procedure'},
    );
    expect(apiCatalog['isError'], isFalse);
    final catalogContent = (apiCatalog['structuredContent'] as Map)
        .cast<String, Object?>();
    final catalogProcedures = (catalogContent['procedures'] as List)
        .cast<Map>();
    expect(catalogProcedures, hasLength(1));
    expect(catalogProcedures.single['uri'], WampAppProtocol.mcpProfileSummary);
    final resources = await aliceMcp.listResources(id: 'alice-resources');
    expect(resources.resources.map((resource) => resource['uri']).toSet(), {
      'wampapp://privacy/mcp',
      'wampapp://account/profile-summary',
    });
    final prompts = await aliceMcp.listPrompts(id: 'alice-prompts');
    expect(prompts.prompts.map((prompt) => prompt['name']), [
      'review-public-profile',
    ]);

    final denied = await aliceMcp.callTool(
      'wampapp_profile_summary',
      id: 'alice-denied',
    );
    expect(denied['isError'], isTrue);

    final enabled = WampAppMcpConsent.fromWampKeywords(
      (await alice.session.callSingle(
        WampAppProtocol.mcpConsentUpdate,
        argumentsKeywords: WampAppMcpConsentUpdate(
          expectedRevision: 0,
          profileReadAllowed: true,
        ).toWampKeywords(),
      )).argumentsKeywords,
    );
    expect(enabled.profileReadAllowed, isTrue);
    expect(enabled.revision, 1);

    final streamableResult = await aliceMcp.callTool(
      'wampapp_profile_summary',
      id: 'alice-streamable-profile',
    );
    _expectAliceSummary(streamableResult);
    final directResult = await aliceMcp.callToolDirect(
      'wampapp_profile_summary',
      id: 'alice-direct-profile',
    );
    _expectAliceSummary(directResult);

    final profileResource = await aliceMcp.readResource(
      'wampapp://account/profile-summary',
      id: 'alice-profile-resource',
    );
    expect(profileResource, hasLength(1));
    expect(profileResource.single['text'], contains('Alice Example'));
    expect(profileResource.single['text'], isNot(contains('avatar')));

    final bobDenied = await bobMcp.callToolDirect(
      'wampapp_profile_summary',
      id: 'bob-denied',
    );
    expect(bobDenied['isError'], isTrue);

    final bobEnabled = WampAppMcpConsent.fromWampKeywords(
      (await bob.session.callSingle(
        WampAppProtocol.mcpConsentUpdate,
        argumentsKeywords: WampAppMcpConsentUpdate(
          expectedRevision: 0,
          profileReadAllowed: true,
        ).toWampKeywords(),
      )).argumentsKeywords,
    );
    expect(bobEnabled.profileReadAllowed, isTrue);

    final externalAcceptance = await _runExternalAcceptance(
      endpoint: endpoint,
      accounts: const [
        {
          'username': 'alice',
          'password': 'correct horse battery',
          'display_name': 'Alice Example',
          'status': '',
        },
        {
          'username': 'bob',
          'password': 'another correct horse',
          'display_name': 'Bob Example',
          'status': '',
        },
      ],
    );
    expect(externalAcceptance.exitCode, 0, reason: externalAcceptance.stderr);
    expect(externalAcceptance.stderr, isEmpty);
    expect(jsonDecode(externalAcceptance.stdout as String), {
      'status': 'ok',
      'accounts': 2,
      'streamable_http': true,
      'direct_json': true,
      'access_grants_revoked': true,
    });
    for (final secret in const [
      'correct horse battery',
      'another correct horse',
      'Alice Example',
      'Bob Example',
    ]) {
      expect(externalAcceptance.stdout, isNot(contains(secret)));
    }

    final revoked = WampAppMcpConsent.fromWampKeywords(
      (await alice.session.callSingle(
        WampAppProtocol.mcpConsentUpdate,
        argumentsKeywords: WampAppMcpConsentUpdate(
          expectedRevision: enabled.revision,
          profileReadAllowed: false,
        ).toWampKeywords(),
      )).argumentsKeywords,
    );
    expect(revoked.profileReadAllowed, isFalse);
    expect(
      (await aliceMcp.callTool(
        'wampapp_profile_summary',
        id: 'alice-revoked-consent',
      ))['isError'],
      isTrue,
    );

    await alice.session.callSingle(
      WampAppProtocol.mcpConsentUpdate,
      argumentsKeywords: WampAppMcpConsentUpdate(
        expectedRevision: revoked.revision,
        profileReadAllowed: true,
      ).toWampKeywords(),
    );
    expect(
      (await aliceMcp.callTool(
        'wampapp_profile_summary',
        id: 'alice-reenabled',
      ))['isError'],
      isFalse,
    );
    await authClient.revokeGrant(
      aliceGrant,
      tokenKind: ConnectanumHttpAuthTokenKind.accessToken,
    );
    await expectLater(
      aliceMcp.listTools(id: 'alice-revoked-token'),
      throwsA(
        isA<McpStreamableHttpException>().having(
          (error) => error.statusCode,
          'status code',
          HttpStatus.unauthorized,
        ),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('MCP acceptance input failures are bounded and redacted', () async {
    final result = await _runExternalAcceptance(
      rawInput: jsonEncode({
        'endpoint': 'http://not-loopback.example/mcp',
        'accounts': const [
          {
            'username': 'alice',
            'password': 'must-never-appear-in-output',
            'display_name': 'Alice Example',
            'status': 'Available',
          },
        ],
      }),
    );

    expect(result.exitCode, 1);
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      'WampApp MCP acceptance failed at endpoint validation.\n',
    );
    expect(result.stderr, isNot(contains('must-never-appear-in-output')));
    expect(result.stderr, isNot(contains('not-loopback.example')));

    final oversized = await _runExternalAcceptance(
      rawInput: 'must-not-be-echoed-${'x' * (64 * 1024)}',
    );
    expect(oversized.exitCode, 1);
    expect(oversized.stdout, isEmpty);
    expect(
      oversized.stderr,
      'WampApp MCP acceptance failed at bounded input validation.\n',
    );
    expect(oversized.stderr, isNot(contains('must-not-be-echoed')));
  });
}

Future<ProcessResult> _runExternalAcceptance({
  Uri? endpoint,
  List<Map<String, String>>? accounts,
  String? rawInput,
}) async {
  final process = await Process.start(Platform.resolvedExecutable, const [
    'tool/mcp_profile_acceptance.dart',
  ], workingDirectory: Directory.current.path);
  final stdoutFuture = utf8.decoder.bind(process.stdout).join();
  final stderrFuture = utf8.decoder.bind(process.stderr).join();
  process.stdin.write(
    rawInput ??
        jsonEncode({'endpoint': endpoint.toString(), 'accounts': accounts}),
  );
  await process.stdin.close();
  final exitCode = await process.exitCode.timeout(const Duration(minutes: 2));
  return ProcessResult(
    process.pid,
    exitCode,
    await stdoutFuture,
    await stderrFuture,
  );
}

void _expectAliceSummary(Map<String, Object?> result) {
  expect(result['isError'], isFalse);
  final structured = (result['structuredContent'] as Map)
      .cast<String, Object?>();
  final keywords = (structured['argumentsKeywords'] as Map)
      .cast<String, Object?>();
  expect(keywords['username'], 'alice');
  expect(keywords['display_name'], 'Alice Example');
  expect(keywords.keys, {
    'username',
    'display_name',
    'status',
    'profile_revision',
    'profile_updated_at',
    'consent_revision',
  });
}

Future<void> _registerAccounts(Uri websocketUri) async {
  final client = wamp.Client(
    transport: wamp.WebSocketTransport.withCborSerializer(
      websocketUri.toString(),
    ),
    realm: WampAppProtocol.registrationRealm,
  );
  final session = await client
      .connect(options: _singleAttempt)
      .first
      .timeout(const Duration(seconds: 15));
  try {
    for (final registration in [
      AccountRegistration(
        username: 'alice',
        displayName: 'Alice Example',
        password: 'correct horse battery',
      ),
      AccountRegistration(
        username: 'bob',
        displayName: 'Bob Example',
        password: 'another correct horse',
      ),
    ]) {
      await session.callSingle(
        WampAppProtocol.accountRegister,
        argumentsKeywords: registration.toWampKeywords(),
      );
    }
  } finally {
    await session.close(timeout: Duration.zero);
    await client.disconnect();
  }
}

Future<_AccountSession> _connectAccount(
  Uri websocketUri, {
  required String username,
  required String password,
}) async {
  final authentication = wamp.ScramAuthentication(
    password,
    derivationTimeout: const Duration(seconds: 30),
  );
  final client = wamp.Client(
    transport: wamp.WebSocketTransport.withCborSerializer(
      websocketUri.toString(),
    ),
    realm: WampAppProtocol.appRealm,
    authId: username,
    authenticationMethods: [authentication],
  );
  try {
    final session = await client
        .connect(options: _singleAttempt)
        .first
        .timeout(const Duration(seconds: 45));
    return _AccountSession(client, session, authentication);
  } catch (_) {
    await client.disconnect();
    await authentication.dispose();
    rethrow;
  }
}

final _singleAttempt = wamp.ClientConnectOptions(
  reconnectCount: 0,
  reconnectTime: Duration(milliseconds: 100),
);

final class _AccountSession {
  _AccountSession(this.client, this.session, this.authentication);

  final wamp.Client client;
  final wamp.Session session;
  final wamp.ScramAuthentication authentication;

  Future<void> close() async {
    await session.close(timeout: Duration.zero);
    await client.disconnect();
    await authentication.dispose();
  }
}

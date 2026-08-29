import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

const _maxInputBytes = 64 * 1024;
const _requestTimeout = Duration(seconds: 30);
const _overallTimeout = Duration(minutes: 2);
const _clientInfo = <String, Object?>{
  'name': 'wamp-app-external-acceptance',
  'version': '0.1.0',
};
const _toolNames = <String>{
  'connectanum.api.describe',
  'connectanum.api.list',
  'wampapp_profile_summary',
};
const _resourceUris = <String>{
  'wampapp://privacy/mcp',
  'wampapp://account/profile-summary',
};
const _promptNames = <String>{'review-public-profile'};
const _profileKeys = <String>{
  'username',
  'display_name',
  'status',
  'profile_revision',
  'profile_updated_at',
  'consent_revision',
};

Future<void> main() async {
  var stage = 'input';
  try {
    final request = await _readRequest();
    stage = 'MCP authentication and profile validation';
    await _runAcceptance(request).timeout(_overallTimeout);
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'ok',
        'accounts': request.accounts.length,
        'streamable_http': true,
        'direct_json': true,
        'access_grants_revoked': true,
      }),
    );
  } on _AcceptanceFailure catch (error) {
    stderr.writeln('WampApp MCP acceptance failed at ${error.stage}.');
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln('WampApp MCP acceptance timed out at $stage.');
    exitCode = 1;
  } on Object {
    stderr.writeln('WampApp MCP acceptance failed at $stage.');
    exitCode = 1;
  }
}

Future<_AcceptanceRequest> _readRequest() async {
  final bytes = <int>[];
  try {
    await for (final chunk in stdin) {
      if (bytes.length + chunk.length > _maxInputBytes) {
        throw const _AcceptanceFailure('bounded input validation');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const _AcceptanceFailure('input validation');
    }
    return _AcceptanceRequest.fromJson(decoded.cast<Object?, Object?>());
  } on _AcceptanceFailure {
    rethrow;
  } on Object {
    throw const _AcceptanceFailure('input validation');
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

Future<void> _runAcceptance(_AcceptanceRequest request) async {
  final unauthenticated = McpStreamableHttpClient.stateless(
    request.endpoint,
    clientInfo: _clientInfo,
    requestTimeout: _requestTimeout,
  );
  late final McpBearerChallenge challenge;
  try {
    try {
      await unauthenticated.listToolsDirect(id: 'unauthenticated-tools');
      throw const _AcceptanceFailure('authentication boundary');
    } on McpStreamableHttpException catch (error) {
      if (error.statusCode != HttpStatus.unauthorized ||
          error.bearerChallenges.length != 1) {
        throw const _AcceptanceFailure('authentication challenge');
      }
      challenge = error.bearerChallenges.single;
    }
  } finally {
    unauthenticated.close(force: true);
  }

  final authClient = ConnectanumHttpAuthClient.fromMcpBearerChallenge(
    request.endpoint,
    challenge,
    requestTimeout: _requestTimeout,
  );
  try {
    for (var index = 0; index < request.accounts.length; index += 1) {
      await _validateAccount(
        request,
        request.accounts[index],
        authClient,
        index,
      );
    }
  } finally {
    authClient.close(force: true);
  }
}

Future<void> _validateAccount(
  _AcceptanceRequest request,
  _AcceptanceAccount account,
  ConnectanumHttpAuthClient authClient,
  int index,
) async {
  ConnectanumHttpAuthGrant? grant;
  McpStreamableHttpClient? client;
  try {
    grant = await authClient.issueScramToken(
      realm: WampAppProtocol.appRealm,
      authId: account.username,
      secret: account.password,
    );
    client = McpStreamableHttpClient.withAuthGrant(
      request.endpoint,
      grant,
      clientInfo: _clientInfo,
      requestTimeout: _requestTimeout,
    );
    await client.initialize(id: 'account-$index-initialize');
    await client.notifyInitialized();
    if (client.sessionId == null) {
      throw const _AcceptanceFailure('Streamable HTTP session creation');
    }

    final tools = await client.listTools(id: 'account-$index-tools');
    _expectExactStrings(
      tools.tools.map((tool) => tool['name']),
      _toolNames,
      'tool catalog',
    );
    final resources = await client.listResources(
      id: 'account-$index-resources',
    );
    _expectExactStrings(
      resources.resources.map((resource) => resource['uri']),
      _resourceUris,
      'resource catalog',
    );
    final prompts = await client.listPrompts(id: 'account-$index-prompts');
    _expectExactStrings(
      prompts.prompts.map((prompt) => prompt['name']),
      _promptNames,
      'prompt catalog',
    );

    final streamableResult = await client.callTool(
      'wampapp_profile_summary',
      id: 'account-$index-streamable-profile',
    );
    _expectProfile(streamableResult, account, 'Streamable profile tool');
    final directResult = await client.callToolDirect(
      'wampapp_profile_summary',
      id: 'account-$index-direct-profile',
    );
    _expectProfile(directResult, account, 'direct JSON profile tool');

    final profileResource = await client.readResource(
      'wampapp://account/profile-summary',
      id: 'account-$index-profile-resource',
    );
    if (profileResource.length != 1 ||
        profileResource.single['text'] is! String ||
        !(profileResource.single['text'] as String).contains(
          account.displayName,
        )) {
      throw const _AcceptanceFailure('profile resource');
    }
    final privacyResource = await client.readResource(
      'wampapp://privacy/mcp',
      id: 'account-$index-privacy-resource',
    );
    if (privacyResource.length != 1 ||
        privacyResource.single['text'] is! String ||
        !(privacyResource.single['text'] as String).contains(
          'cannot access chats, messages, attachments, backups',
        )) {
      throw const _AcceptanceFailure('privacy resource');
    }
    final prompt = await client.getPrompt(
      'review-public-profile',
      id: 'account-$index-profile-prompt',
    );
    if (prompt['messages'] is! List || (prompt['messages'] as List).isEmpty) {
      throw const _AcceptanceFailure('profile prompt');
    }

    await authClient.revokeGrant(
      grant,
      tokenKind: ConnectanumHttpAuthTokenKind.accessToken,
    );
    try {
      await client.listTools(id: 'account-$index-revoked-access');
      throw const _AcceptanceFailure('access-token revocation');
    } on McpStreamableHttpException catch (error) {
      if (error.statusCode != HttpStatus.unauthorized) {
        throw const _AcceptanceFailure('access-token revocation');
      }
    }
  } on _AcceptanceFailure {
    rethrow;
  } on Object {
    throw const _AcceptanceFailure('account-scoped MCP access');
  } finally {
    if (client != null) {
      client.close(force: true);
    }
    if (grant?.refreshToken != null) {
      try {
        await authClient.revokeGrant(
          grant!,
          tokenKind: ConnectanumHttpAuthTokenKind.refreshToken,
        );
      } on Object {
        throw const _AcceptanceFailure('grant cleanup');
      }
    }
  }
}

void _expectExactStrings(
  Iterable<Object?> values,
  Set<String> expected,
  String stage,
) {
  final actual = <String>{};
  for (final value in values) {
    if (value is! String || !actual.add(value)) {
      throw _AcceptanceFailure(stage);
    }
  }
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw _AcceptanceFailure(stage);
  }
}

void _expectProfile(
  Map<String, Object?> result,
  _AcceptanceAccount account,
  String stage,
) {
  if (result['isError'] != false || result['structuredContent'] is! Map) {
    throw _AcceptanceFailure(stage);
  }
  final structured = (result['structuredContent'] as Map)
      .cast<Object?, Object?>();
  if (structured['argumentsKeywords'] is! Map) {
    throw _AcceptanceFailure(stage);
  }
  final profile = (structured['argumentsKeywords'] as Map)
      .cast<Object?, Object?>();
  if (!_sameKeys(profile.keys, _profileKeys) ||
      profile['username'] != account.username ||
      profile['display_name'] != account.displayName ||
      profile['status'] != account.status ||
      profile['profile_revision'] is! int ||
      profile['profile_updated_at'] is! String ||
      profile['consent_revision'] is! int) {
    throw _AcceptanceFailure(stage);
  }
}

bool _sameKeys(Iterable<Object?> actual, Set<String> expected) {
  final keys = actual.whereType<String>().toSet();
  return keys.length == actual.length &&
      keys.length == expected.length &&
      keys.containsAll(expected);
}

final class _AcceptanceRequest {
  const _AcceptanceRequest({required this.endpoint, required this.accounts});

  factory _AcceptanceRequest.fromJson(Map<Object?, Object?> json) {
    if (!_sameKeys(json.keys, const {'endpoint', 'accounts'}) ||
        json['endpoint'] is! String ||
        json['accounts'] is! List) {
      throw const _AcceptanceFailure('input validation');
    }
    final endpoint = Uri.tryParse(json['endpoint'] as String);
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.query.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        endpoint.path.isEmpty ||
        !_endpointTransportAllowed(endpoint)) {
      throw const _AcceptanceFailure('endpoint validation');
    }
    final accountValues = json['accounts'] as List;
    if (accountValues.isEmpty || accountValues.length > 8) {
      throw const _AcceptanceFailure('account input validation');
    }
    final accounts = <_AcceptanceAccount>[];
    for (final value in accountValues) {
      if (value is! Map) {
        throw const _AcceptanceFailure('account input validation');
      }
      accounts.add(_AcceptanceAccount.fromJson(value.cast<Object?, Object?>()));
    }
    return _AcceptanceRequest(
      endpoint: endpoint,
      accounts: List.unmodifiable(accounts),
    );
  }

  final Uri endpoint;
  final List<_AcceptanceAccount> accounts;
}

final class _AcceptanceAccount {
  const _AcceptanceAccount({
    required this.username,
    required this.password,
    required this.displayName,
    required this.status,
  });

  factory _AcceptanceAccount.fromJson(Map<Object?, Object?> json) {
    if (!_sameKeys(json.keys, const {
          'username',
          'password',
          'display_name',
          'status',
        }) ||
        json['username'] is! String ||
        json['password'] is! String ||
        json['display_name'] is! String ||
        json['status'] is! String) {
      throw const _AcceptanceFailure('account input validation');
    }
    final username = json['username'] as String;
    final password = json['password'] as String;
    final displayName = json['display_name'] as String;
    final status = json['status'] as String;
    if (!_accountInputValid(username, password, displayName) ||
        displayName.trim() != displayName ||
        status.trim() != status ||
        status.length > AccountProfileLimits.maxStatusCharacters) {
      throw const _AcceptanceFailure('account input validation');
    }
    return _AcceptanceAccount(
      username: username,
      password: password,
      displayName: displayName,
      status: status,
    );
  }

  final String username;
  final String password;
  final String displayName;
  final String status;
}

bool _accountInputValid(String username, String password, String displayName) {
  try {
    final registration = AccountRegistration(
      username: username,
      password: password,
      displayName: displayName,
    )..validate();
    return registration.username == username &&
        registration.displayName == displayName;
  } on FormatException {
    return false;
  }
}

bool _endpointTransportAllowed(Uri endpoint) {
  if (endpoint.scheme == 'https') return true;
  if (endpoint.scheme != 'http') return false;
  final host = endpoint.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

final class _AcceptanceFailure implements Exception {
  const _AcceptanceFailure(this.stage);

  final String stage;
}

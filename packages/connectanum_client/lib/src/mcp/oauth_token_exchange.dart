import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show containsMcpWhitespaceOrControl;

import 'authorization_discovery.dart';
import 'oauth_authorization.dart';

const _authorizationCodeGrant = 'authorization_code';
const _refreshTokenGrant = 'refresh_token';
const _clientSecretBasic = 'client_secret_basic';
const _clientSecretPost = 'client_secret_post';
const _noClientAuthentication = 'none';
const _defaultTokenResponseBytes = 64 * 1024;
const _defaultTokenTimeout = Duration(seconds: 30);
const _standardTokenResponseParameters = <String>{
  'access_token',
  'token_type',
  'expires_in',
  'refresh_token',
  'scope',
};
const _controlledTokenRequestHeaders = <String>{
  'accept',
  'authorization',
  'connection',
  'content-length',
  'content-type',
  'cookie',
  'host',
  'last-event-id',
  'proxy-authorization',
  'transfer-encoding',
};
const _oauthTokenGrantStateType = 'mcp_oauth_token_grant';
const _oauthTokenGrantStateVersion = 1;
const _forbiddenPersistedGrantParameters = <String>{
  'client_assertion',
  'client_assertion_type',
  'client_secret',
  'registration_access_token',
};

/// Client authentication used at an OAuth token endpoint.
final class McpOAuthClientAuthentication {
  const McpOAuthClientAuthentication._({
    required this.clientId,
    required this.method,
    String? clientSecret,
  }) : _clientSecret = clientSecret;

  factory McpOAuthClientAuthentication.none(String clientId) {
    return McpOAuthClientAuthentication._(
      clientId: clientId,
      method: _noClientAuthentication,
    );
  }

  factory McpOAuthClientAuthentication.clientSecretBasic({
    required String clientId,
    required String clientSecret,
  }) {
    return McpOAuthClientAuthentication._(
      clientId: clientId,
      method: _clientSecretBasic,
      clientSecret: clientSecret,
    );
  }

  factory McpOAuthClientAuthentication.clientSecretPost({
    required String clientId,
    required String clientSecret,
  }) {
    return McpOAuthClientAuthentication._(
      clientId: clientId,
      method: _clientSecretPost,
      clientSecret: clientSecret,
    );
  }

  final String clientId;
  final String method;
  final String? _clientSecret;

  @override
  String toString() => 'McpOAuthClientAuthentication($method)';
}

/// Selects which credential from an OAuth grant to revoke.
enum McpOAuthTokenKind {
  accessToken('access_token'),
  refreshToken('refresh_token');

  const McpOAuthTokenKind(this.hint);

  final String hint;
}

/// An OAuth bearer grant issued for one canonical MCP resource.
final class McpOAuthTokenGrant {
  McpOAuthTokenGrant._({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.issuedAt,
    required this.expiresAt,
    required List<String> scopes,
    required this.resource,
    required this.clientId,
    required this.authorizationServer,
    required Map<String, Object?> additionalParameters,
  }) : scopes = List<String>.unmodifiable(scopes),
       additionalParameters = _copyTokenGrantStateJsonObject(
         additionalParameters,
       );

  /// Revalidates a versioned sensitive OAuth token-grant document.
  ///
  /// Callers should pin every expected trust-context value they already know.
  /// The document contains bearer credentials and belongs only in
  /// caller-selected secure storage.
  factory McpOAuthTokenGrant.fromJson(
    Map<String, Object?> json, {
    Uri? expectedAuthorizationServerIssuer,
    Uri? expectedResource,
    String? expectedClientId,
    DateTime? now,
  }) {
    try {
      if (json['type'] != _oauthTokenGrantStateType) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant has an unsupported document type.',
        );
      }
      if (json['version'] != _oauthTokenGrantStateVersion) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant has an unsupported schema version.',
        );
      }

      final issuedAt = _tokenGrantStateDateTime(json, 'issued_at');
      final current = (now ?? DateTime.now()).toUtc();
      if (issuedAt.isAfter(current)) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant is not yet valid.',
        );
      }
      final expiresIn = _tokenGrantStateExpiresIn(json);
      final DateTime? expiresAt;
      if (expiresIn == null) {
        if (json.containsKey('expires_at')) {
          throw const McpOAuthTokenGrantStateException(
            'Persisted OAuth token grant expiry is inconsistent.',
          );
        }
        expiresAt = null;
      } else {
        if (!json.containsKey('expires_at')) {
          throw const McpOAuthTokenGrantStateException(
            'Persisted OAuth token grant expiry is incomplete.',
          );
        }
        expiresAt = _tokenGrantStateDateTime(json, 'expires_at');
        if (expiresAt != _tokenGrantExpiresAt(issuedAt, expiresIn)) {
          throw const McpOAuthTokenGrantStateException(
            'Persisted OAuth token grant expiry is inconsistent.',
          );
        }
      }

      final authorizationServer = McpAuthorizationServerMetadata.fromJson(
        _tokenGrantStateObject(json, 'authorization_server'),
      );
      if (expectedAuthorizationServerIssuer != null &&
          authorizationServer.issuer.toString() !=
              expectedAuthorizationServerIssuer.toString()) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant belongs to a different authorization '
          'server.',
        );
      }
      final resource = _tokenGrantStateUri(json, 'resource');
      if (expectedResource != null &&
          !_resourcesMatch(resource, expectedResource)) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant belongs to a different MCP resource.',
        );
      }
      final clientId = _tokenGrantStateString(json, 'client_id');
      if (expectedClientId != null && clientId != expectedClientId) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant belongs to a different OAuth client.',
        );
      }
      final scopes = _tokenGrantStateStringList(json, 'scopes');
      final tokens = _tokenGrantStateObject(json, 'tokens');
      if (tokens.containsKey('expires_in') || tokens.containsKey('scope')) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant contains duplicated response fields.',
        );
      }
      if (tokens.keys.any(_forbiddenPersistedGrantParameters.contains)) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant contains unsupported client '
          'credentials.',
        );
      }

      final restored = _parseTokenGrantResponse(
        statusCode: HttpStatus.ok,
        mimeType: 'application/json',
        body: jsonEncode(<String, Object?>{
          ...tokens,
          if (expiresIn != null) 'expires_in': expiresIn.inSeconds,
          if (scopes.isNotEmpty) 'scope': scopes.join(' '),
        }),
        endpoint: authorizationServer.tokenEndpoint,
        resource: resource,
        clientId: clientId,
        authorizationServer: authorizationServer,
        effectiveScopes: scopes,
        issuedAt: issuedAt,
      );
      if (!_sameTokenGrantScopes(restored.scopes, scopes) ||
          restored.expiresAt != expiresAt) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant fields are inconsistent.',
        );
      }
      return restored;
    } on McpOAuthTokenGrantStateException {
      rethrow;
    } on Object {
      throw const McpOAuthTokenGrantStateException(
        'Persisted OAuth token grant is invalid.',
      );
    }
  }

  final String accessToken;
  final String tokenType = 'Bearer';
  final String? refreshToken;
  final Duration? expiresIn;

  /// Local time at which the token response was validated.
  final DateTime issuedAt;

  /// Absolute local expiry derived from the token response lifetime.
  final DateTime? expiresAt;

  /// Effective scopes returned by the server, or the requested scopes when
  /// the response scope is omitted as defined by RFC 6749 section 5.1.
  final List<String> scopes;
  final Uri resource;
  final String clientId;
  final McpAuthorizationServerMetadata authorizationServer;
  final Map<String, Object?> additionalParameters;

  /// Whether [candidate] identifies the same canonical MCP resource.
  bool isForResource(Uri candidate) {
    return _resourcesMatch(resource, candidate);
  }

  /// Whether the access token has reached its advertised absolute expiry.
  bool isAccessTokenExpired({DateTime? now}) {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    final current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(expiry);
  }

  /// Returns a versioned JSON-compatible document containing bearer secrets.
  ///
  /// Store the returned document only in caller-selected secure storage. Do
  /// not log the document or its extension parameters.
  Map<String, Object?> toJson() {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'type': _oauthTokenGrantStateType,
      'version': _oauthTokenGrantStateVersion,
      'issued_at': issuedAt.toUtc().toIso8601String(),
      if (expiresIn != null) 'expires_in': expiresIn!.inSeconds,
      if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      'authorization_server': _copyTokenGrantStateJsonObject(
        authorizationServer.toJson(),
      ),
      'resource': resource.toString(),
      'client_id': clientId,
      'scopes': List<String>.unmodifiable(scopes),
      'tokens': Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in _copyTokenGrantStateJsonObject(
          additionalParameters,
        ).entries)
          if (!_forbiddenPersistedGrantParameters.contains(entry.key))
            entry.key: entry.value,
        'access_token': accessToken,
        'token_type': tokenType,
        if (refreshToken != null) 'refresh_token': refreshToken,
      }),
    });
  }

  @override
  String toString() {
    return 'McpOAuthTokenGrant('
        'Bearer, scopes: ${scopes.length}, '
        'refreshable: ${refreshToken != null})';
  }
}

/// A redacted persisted OAuth token-grant validation failure.
final class McpOAuthTokenGrantStateException implements Exception {
  const McpOAuthTokenGrantStateException(this.message);

  final String message;

  @override
  String toString() => 'McpOAuthTokenGrantStateException: $message';
}

/// A local token-flow failure or typed OAuth token endpoint error.
final class McpOAuthTokenException implements Exception {
  const McpOAuthTokenException(
    this.message, {
    this.endpoint,
    this.statusCode,
    this.oauthError,
    this.errorDescription,
    this.errorUri,
  });

  final String message;
  final Uri? endpoint;
  final int? statusCode;
  final String? oauthError;
  final String? errorDescription;
  final Uri? errorUri;

  @override
  String toString() {
    final buffer = StringBuffer('McpOAuthTokenException: $message');
    if (oauthError != null) {
      buffer.write(' (error: $oauthError)');
    }
    if (statusCode != null) {
      buffer.write(' (status: $statusCode)');
    }
    if (endpoint != null) {
      buffer.write(' (${endpoint!})');
    }
    return buffer.toString();
  }
}

/// Redeems a validated MCP authorization code at its discovered token endpoint.
///
/// [onRequestOpened] observes the request before it is sent so an owning client
/// can bind it to a larger lifecycle.
Future<McpOAuthTokenGrant> exchangeMcpAuthorizationCode(
  McpAuthorizationCode authorizationCode, {
  required McpOAuthClientAuthentication clientAuthentication,
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  Duration timeout = _defaultTokenTimeout,
  int maxResponseBytes = _defaultTokenResponseBytes,
  void Function(HttpClientRequest request)? onRequestOpened,
}) async {
  final requestState = authorizationCode.request;
  final authorizationServer = requestState.authorizationServer;
  final endpoint = authorizationServer.tokenEndpoint;
  _validateExchangeInputs(
    authorizationCode,
    clientAuthentication,
    headers,
    timeout,
    maxResponseBytes,
  );

  final response = await _postOAuthForm(
    endpoint: endpoint,
    form: <String, String>{
      'grant_type': _authorizationCodeGrant,
      'code': authorizationCode.code,
      'redirect_uri': requestState.redirectUri.toString(),
      if (clientAuthentication.method != _clientSecretBasic)
        'client_id': clientAuthentication.clientId,
      'code_verifier': requestState.pkce.verifier,
      'resource': requestState.resource.toString(),
      if (clientAuthentication.method == _clientSecretPost)
        'client_secret': clientAuthentication._clientSecret!,
    },
    clientAuthentication: clientAuthentication,
    httpClient: httpClient,
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
    endpointLabel: 'OAuth token endpoint',
    onRequestOpened: onRequestOpened,
  );
  return _parseTokenGrantResponse(
    statusCode: response.statusCode,
    mimeType: response.mimeType,
    body: _decodeOAuthResponse(response, endpoint, 'OAuth token endpoint'),
    endpoint: endpoint,
    resource: requestState.resource,
    clientId: clientAuthentication.clientId,
    authorizationServer: authorizationServer,
    effectiveScopes: requestState.scopes,
  );
}

/// Refreshes a resource-bound MCP OAuth grant without mutating [grant].
///
/// [onRequestOpened] observes the request before it is sent so an owning client
/// can bind it to a larger lifecycle.
Future<McpOAuthTokenGrant> refreshMcpOAuthToken(
  McpOAuthTokenGrant grant, {
  required McpOAuthClientAuthentication clientAuthentication,
  Iterable<String>? scopes,
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  Duration timeout = _defaultTokenTimeout,
  int maxResponseBytes = _defaultTokenResponseBytes,
  void Function(HttpClientRequest request)? onRequestOpened,
}) async {
  final authorizationServer = grant.authorizationServer;
  final endpoint = authorizationServer.tokenEndpoint;
  final refreshToken = grant.refreshToken;
  if (!_credentialValid(refreshToken)) {
    throw McpOAuthTokenException(
      'OAuth grant does not contain a usable refresh token.',
      endpoint: endpoint,
    );
  }
  final supportedGrants = authorizationServer.grantTypesSupported;
  if (supportedGrants != null &&
      !supportedGrants.contains(_refreshTokenGrant)) {
    throw McpOAuthTokenException(
      'Authorization server does not advertise refresh_token grants.',
      endpoint: endpoint,
    );
  }
  final requestedScopes = _validatedRefreshScopes(
    scopes,
    grant: grant,
    endpoint: endpoint,
  );
  _validateOAuthEndpointInputs(
    expectedClientId: grant.clientId,
    clientAuthentication: clientAuthentication,
    supportedMethods:
        authorizationServer.tokenEndpointAuthMethodsSupported ??
        const <String>[_clientSecretBasic],
    endpoint: endpoint,
    endpointLabel: 'OAuth token endpoint',
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
  );

  final response = await _postOAuthForm(
    endpoint: endpoint,
    form: <String, String>{
      'grant_type': _refreshTokenGrant,
      'refresh_token': refreshToken!,
      if (clientAuthentication.method != _clientSecretBasic)
        'client_id': clientAuthentication.clientId,
      'resource': grant.resource.toString(),
      if (scopes != null) 'scope': requestedScopes.join(' '),
      if (clientAuthentication.method == _clientSecretPost)
        'client_secret': clientAuthentication._clientSecret!,
    },
    clientAuthentication: clientAuthentication,
    httpClient: httpClient,
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
    endpointLabel: 'OAuth token endpoint',
    onRequestOpened: onRequestOpened,
  );
  return _parseTokenGrantResponse(
    statusCode: response.statusCode,
    mimeType: response.mimeType,
    body: _decodeOAuthResponse(response, endpoint, 'OAuth token endpoint'),
    endpoint: endpoint,
    resource: grant.resource,
    clientId: grant.clientId,
    authorizationServer: authorizationServer,
    effectiveScopes: requestedScopes,
    retainedRefreshToken: refreshToken,
    allowedResponseScopes: requestedScopes.toSet(),
  );
}

/// Revokes one credential from [grant] through its discovered RFC 7009 endpoint.
///
/// [onRequestOpened] observes the request before it is sent so an owning client
/// can bind it to a larger lifecycle.
Future<void> revokeMcpOAuthToken(
  McpOAuthTokenGrant grant, {
  required McpOAuthClientAuthentication clientAuthentication,
  McpOAuthTokenKind tokenKind = McpOAuthTokenKind.refreshToken,
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  Duration timeout = _defaultTokenTimeout,
  int maxResponseBytes = _defaultTokenResponseBytes,
  void Function(HttpClientRequest request)? onRequestOpened,
}) async {
  final authorizationServer = grant.authorizationServer;
  final endpoint = authorizationServer.revocationEndpoint;
  if (endpoint == null) {
    throw McpOAuthTokenException(
      'Authorization server does not advertise a revocation endpoint.',
      endpoint: authorizationServer.issuer,
    );
  }
  final token = switch (tokenKind) {
    McpOAuthTokenKind.accessToken => grant.accessToken,
    McpOAuthTokenKind.refreshToken => grant.refreshToken,
  };
  if (!_credentialValid(token)) {
    throw McpOAuthTokenException(
      'OAuth grant does not contain the selected revocation credential.',
      endpoint: endpoint,
    );
  }
  _validateOAuthEndpointInputs(
    expectedClientId: grant.clientId,
    clientAuthentication: clientAuthentication,
    supportedMethods:
        authorizationServer.revocationEndpointAuthMethodsSupported ??
        const <String>[_clientSecretBasic],
    endpoint: endpoint,
    endpointLabel: 'OAuth revocation endpoint',
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
  );

  final response = await _postOAuthForm(
    endpoint: endpoint,
    form: <String, String>{
      'token': token!,
      'token_type_hint': tokenKind.hint,
      if (clientAuthentication.method != _clientSecretBasic)
        'client_id': clientAuthentication.clientId,
      if (clientAuthentication.method == _clientSecretPost)
        'client_secret': clientAuthentication._clientSecret!,
    },
    clientAuthentication: clientAuthentication,
    httpClient: httpClient,
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
    endpointLabel: 'OAuth revocation endpoint',
    onRequestOpened: onRequestOpened,
  );
  if (response.statusCode == HttpStatus.ok) {
    return;
  }
  if (response.mimeType != 'application/json') {
    throw McpOAuthTokenException(
      'OAuth revocation endpoint returned a non-JSON error response.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
  final json = _jsonObject(
    _decodeOAuthResponse(response, endpoint, 'OAuth revocation endpoint'),
    response.statusCode,
    endpoint,
  );
  _throwTokenError(
    json,
    response.statusCode,
    endpoint,
    rejectionMessage: 'OAuth revocation endpoint rejected the request.',
  );
}

Map<String, Object?> _copyTokenGrantStateJsonObject(
  Map<String, Object?> source,
) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    result[entry.key] = _copyTokenGrantStateJsonValue(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}

Object? _copyTokenGrantStateJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map<Object?>(_copyTokenGrantStateJsonValue),
    );
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const McpOAuthTokenGrantStateException(
          'Persisted OAuth token grant contains a non-string object key.',
        );
      }
      result[key] = _copyTokenGrantStateJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  throw const McpOAuthTokenGrantStateException(
    'Persisted OAuth token grant contains a non-JSON value.',
  );
}

Map<String, Object?> _tokenGrantStateObject(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! Map) {
    throw McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant field "$key" must be a JSON object.',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final entryKey = entry.key;
    if (entryKey is! String) {
      throw McpOAuthTokenGrantStateException(
        'Persisted OAuth token grant field "$key" has a non-string key.',
      );
    }
    result[entryKey] = _copyTokenGrantStateJsonValue(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}

String _tokenGrantStateString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant field "$key" must be a non-empty string.',
    );
  }
  return value;
}

Uri _tokenGrantStateUri(Map<String, Object?> json, String key) {
  final value = _tokenGrantStateString(json, key);
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty || uri.hasFragment) {
    throw McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant field "$key" must be an absolute URI '
      'without a fragment.',
    );
  }
  return uri;
}

DateTime _tokenGrantStateDateTime(Map<String, Object?> json, String key) {
  final value = _tokenGrantStateString(json, key);
  final timestamp = DateTime.tryParse(value);
  if (timestamp == null || !timestamp.isUtc || !value.endsWith('Z')) {
    throw McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant field "$key" must be a UTC timestamp.',
    );
  }
  return timestamp;
}

Duration? _tokenGrantStateExpiresIn(Map<String, Object?> json) {
  final value = json['expires_in'];
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0) {
    throw const McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant expires_in must be a non-negative integer.',
    );
  }
  return Duration(seconds: value);
}

DateTime _tokenGrantExpiresAt(DateTime issuedAt, Duration expiresIn) {
  try {
    return issuedAt.add(expiresIn);
  } on Object {
    throw const McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant expiry is out of range.',
    );
  }
}

List<String> _tokenGrantStateStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List ||
      value.any(
        (entry) =>
            entry is! String || entry.isEmpty || !_oauthScopeTokenValid(entry),
      )) {
    throw McpOAuthTokenGrantStateException(
      'Persisted OAuth token grant field "$key" must contain OAuth scope '
      'tokens.',
    );
  }
  return List<String>.unmodifiable(value.cast<String>());
}

bool _sameTokenGrantScopes(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _validateExchangeInputs(
  McpAuthorizationCode authorizationCode,
  McpOAuthClientAuthentication clientAuthentication,
  Map<String, String> headers,
  Duration timeout,
  int maxResponseBytes,
) {
  final request = authorizationCode.request;
  _validateOAuthEndpointInputs(
    expectedClientId: request.clientId,
    clientAuthentication: clientAuthentication,
    supportedMethods:
        request.authorizationServer.tokenEndpointAuthMethodsSupported ??
        const <String>[_clientSecretBasic],
    endpoint: request.authorizationServer.tokenEndpoint,
    endpointLabel: 'OAuth token endpoint',
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
  );
}

void _validateOAuthEndpointInputs({
  required String expectedClientId,
  required McpOAuthClientAuthentication clientAuthentication,
  required List<String> supportedMethods,
  required Uri endpoint,
  required String endpointLabel,
  required Map<String, String> headers,
  required Duration timeout,
  required int maxResponseBytes,
}) {
  if (clientAuthentication.clientId != expectedClientId) {
    throw McpOAuthTokenException(
      'OAuth client ID must match the issued grant.',
      endpoint: endpoint,
    );
  }
  if (!_printableNonEmpty(clientAuthentication.clientId)) {
    throw McpOAuthTokenException(
      'OAuth client ID must be non-empty printable text.',
      endpoint: endpoint,
    );
  }
  if (!supportedMethods.contains(clientAuthentication.method)) {
    throw McpOAuthTokenException(
      'Authorization server does not support $endpointLabel client '
      'authentication method "${clientAuthentication.method}".',
      endpoint: endpoint,
    );
  }
  if (clientAuthentication.method != _noClientAuthentication &&
      !_credentialValid(clientAuthentication._clientSecret)) {
    throw McpOAuthTokenException(
      'OAuth client secret must be non-empty and contain no controls.',
      endpoint: endpoint,
    );
  }
  if (timeout <= Duration.zero) {
    throw McpOAuthTokenException(
      '$endpointLabel timeout must be positive.',
      endpoint: endpoint,
    );
  }
  if (maxResponseBytes <= 0) {
    throw McpOAuthTokenException(
      '$endpointLabel response byte limit must be positive.',
      endpoint: endpoint,
    );
  }
  for (final entry in headers.entries) {
    final name = entry.key.trim().toLowerCase();
    if (name.isEmpty ||
        _controlledTokenRequestHeaders.contains(name) ||
        name.startsWith('mcp-')) {
      throw McpOAuthTokenException(
        'Header "${entry.key}" is controlled by the $endpointLabel request.',
        endpoint: endpoint,
      );
    }
    if (entry.value.codeUnits.any((value) => value < 0x20 || value == 0x7f)) {
      throw McpOAuthTokenException(
        'Header "${entry.key}" contains control characters.',
        endpoint: endpoint,
      );
    }
  }
}

List<String> _validatedRefreshScopes(
  Iterable<String>? scopes, {
  required McpOAuthTokenGrant grant,
  required Uri endpoint,
}) {
  if (scopes == null) {
    return grant.scopes;
  }
  final requested = scopes.toList(growable: false);
  if (requested.isEmpty) {
    throw McpOAuthTokenException(
      'OAuth refresh scopes must not be empty when provided.',
      endpoint: endpoint,
    );
  }
  final allowed = grant.scopes.toSet();
  for (final scope in requested) {
    if (!_oauthScopeTokenValid(scope)) {
      throw McpOAuthTokenException(
        'OAuth refresh scope contains an invalid token.',
        endpoint: endpoint,
      );
    }
    if (!allowed.contains(scope)) {
      throw McpOAuthTokenException(
        'OAuth refresh scopes must not exceed the original grant.',
        endpoint: endpoint,
      );
    }
  }
  return List<String>.unmodifiable(requested.toSet());
}

final class _OAuthEndpointResponse {
  const _OAuthEndpointResponse({
    required this.statusCode,
    required this.mimeType,
    required this.body,
  });

  final int statusCode;
  final String? mimeType;
  final Uint8List body;
}

Future<_OAuthEndpointResponse> _postOAuthForm({
  required Uri endpoint,
  required Map<String, String> form,
  required McpOAuthClientAuthentication clientAuthentication,
  required HttpClient? httpClient,
  required Map<String, String> headers,
  required Duration timeout,
  required int maxResponseBytes,
  required String endpointLabel,
  required void Function(HttpClientRequest request)? onRequestOpened,
}) async {
  final encodedForm = utf8.encode(Uri(queryParameters: form).query);
  final client = httpClient ?? HttpClient();
  final ownsClient = httpClient == null;
  final deadline = DateTime.now().add(timeout);
  HttpClientRequest? request;

  try {
    request = await client
        .postUrl(endpoint)
        .timeout(_remaining(deadline, endpoint, endpointLabel));
    try {
      onRequestOpened?.call(request);
    } catch (error) {
      request.abort(error);
      rethrow;
    }
    request.followRedirects = false;
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (clientAuthentication.method == _clientSecretBasic) {
      final clientId = _formEncodeComponent(clientAuthentication.clientId);
      final clientSecret = _formEncodeComponent(
        clientAuthentication._clientSecret!,
      );
      final credentials = base64.encode(utf8.encode('$clientId:$clientSecret'));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic $credentials',
      );
    }
    request.contentLength = encodedForm.length;
    request.add(encodedForm);

    final response = await request.close().timeout(
      _remaining(deadline, endpoint, endpointLabel),
    );
    final body = await _readOAuthResponseBytes(
      response,
      maxResponseBytes: maxResponseBytes,
      endpoint: endpoint,
      endpointLabel: endpointLabel,
    ).timeout(_remaining(deadline, endpoint, endpointLabel));
    return _OAuthEndpointResponse(
      statusCode: response.statusCode,
      mimeType: response.headers.contentType?.mimeType,
      body: body,
    );
  } on McpOAuthTokenException {
    rethrow;
  } on TimeoutException {
    request?.abort();
    throw McpOAuthTokenException(
      '$endpointLabel request timed out.',
      endpoint: endpoint,
    );
  } on Object {
    request?.abort();
    throw McpOAuthTokenException(
      '$endpointLabel request failed.',
      endpoint: endpoint,
    );
  } finally {
    if (ownsClient) {
      client.close(force: true);
    }
  }
}

Future<Uint8List> _readOAuthResponseBytes(
  HttpClientResponse response, {
  required int maxResponseBytes,
  required Uri endpoint,
  required String endpointLabel,
}) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response) {
    length += chunk.length;
    if (length > maxResponseBytes) {
      throw McpOAuthTokenException(
        '$endpointLabel response exceeds $maxResponseBytes bytes.',
        endpoint: endpoint,
        statusCode: response.statusCode,
      );
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

String _decodeOAuthResponse(
  _OAuthEndpointResponse response,
  Uri endpoint,
  String endpointLabel,
) {
  try {
    return utf8.decode(response.body);
  } on FormatException {
    throw McpOAuthTokenException(
      '$endpointLabel response is not valid UTF-8.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
}

Duration _remaining(
  DateTime deadline,
  Uri endpoint, [
  String endpointLabel = 'OAuth token endpoint',
]) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw McpOAuthTokenException(
      '$endpointLabel request timed out.',
      endpoint: endpoint,
    );
  }
  return remaining;
}

McpOAuthTokenGrant _parseTokenGrantResponse({
  required int statusCode,
  required String? mimeType,
  required String body,
  required Uri endpoint,
  required Uri resource,
  required String clientId,
  required McpAuthorizationServerMetadata authorizationServer,
  required List<String> effectiveScopes,
  String? retainedRefreshToken,
  Set<String>? allowedResponseScopes,
  DateTime? issuedAt,
}) {
  if (mimeType != 'application/json') {
    throw McpOAuthTokenException(
      'OAuth token endpoint must return application/json.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final json = _jsonObject(body, statusCode, endpoint);
  if (statusCode != HttpStatus.ok) {
    _throwTokenError(json, statusCode, endpoint);
  }

  final accessToken = json['access_token'];
  if (accessToken is! String ||
      accessToken.isEmpty ||
      containsMcpWhitespaceOrControl(accessToken)) {
    throw McpOAuthTokenException(
      'OAuth token response access_token must be a non-empty bearer token.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final tokenType = json['token_type'];
  if (tokenType is! String || tokenType.toLowerCase() != 'bearer') {
    throw McpOAuthTokenException(
      'OAuth token response token_type must be Bearer.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final refreshToken = _optionalCredential(
    json['refresh_token'],
    'refresh_token',
    statusCode,
    endpoint,
  );
  final expiresIn = _expiresIn(json['expires_in'], statusCode, endpoint);
  final tokenIssuedAt = (issuedAt ?? DateTime.now()).toUtc();
  late final DateTime? tokenExpiresAt;
  try {
    tokenExpiresAt = expiresIn == null
        ? null
        : _tokenGrantExpiresAt(tokenIssuedAt, expiresIn);
  } on McpOAuthTokenGrantStateException {
    throw McpOAuthTokenException(
      'OAuth token response expiry is out of range.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final responseScopes = _responseScopes(json['scope'], statusCode, endpoint);
  if (allowedResponseScopes != null &&
      responseScopes != null &&
      responseScopes.any((scope) => !allowedResponseScopes.contains(scope))) {
    throw McpOAuthTokenException(
      'OAuth refresh response scopes exceed the requested refresh scopes.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final additionalParameters = <String, Object?>{
    for (final entry in json.entries)
      if (!_standardTokenResponseParameters.contains(entry.key) &&
          !_forbiddenPersistedGrantParameters.contains(entry.key))
        entry.key: entry.value,
  };
  return McpOAuthTokenGrant._(
    accessToken: accessToken,
    refreshToken: refreshToken ?? retainedRefreshToken,
    expiresIn: expiresIn,
    issuedAt: tokenIssuedAt,
    expiresAt: tokenExpiresAt,
    scopes: responseScopes ?? effectiveScopes,
    resource: resource,
    clientId: clientId,
    authorizationServer: authorizationServer,
    additionalParameters: additionalParameters,
  );
}

Map<String, Object?> _jsonObject(String body, int statusCode, Uri endpoint) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw McpOAuthTokenException(
      'OAuth token endpoint response is not valid JSON.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  if (decoded is! Map) {
    throw McpOAuthTokenException(
      'OAuth token endpoint response must be a JSON object.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final result = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw McpOAuthTokenException(
        'OAuth token endpoint response keys must be strings.',
        endpoint: endpoint,
        statusCode: statusCode,
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Never _throwTokenError(
  Map<String, Object?> json,
  int statusCode,
  Uri endpoint, {
  String rejectionMessage =
      'OAuth token endpoint rejected the authorization grant.',
}) {
  final error = json['error'];
  final description = json['error_description'];
  final errorUriValue = json['error_uri'];
  if (error is! String || !_oauthNqsCharValid(error)) {
    throw McpOAuthTokenException(
      'OAuth endpoint returned an invalid error response.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  if (description != null &&
      (description is! String || !_oauthNqsCharValid(description))) {
    throw McpOAuthTokenException(
      'OAuth endpoint returned an invalid error_description.',
      endpoint: endpoint,
      statusCode: statusCode,
      oauthError: error,
    );
  }
  final errorUri = _safeErrorUri(errorUriValue, statusCode, endpoint);
  throw McpOAuthTokenException(
    rejectionMessage,
    endpoint: endpoint,
    statusCode: statusCode,
    oauthError: error,
    errorDescription: description as String?,
    errorUri: errorUri,
  );
}

String? _optionalCredential(
  Object? value,
  String name,
  int statusCode,
  Uri endpoint,
) {
  if (value == null) {
    return null;
  }
  if (value is! String || !_credentialValid(value)) {
    throw McpOAuthTokenException(
      'OAuth token response $name must be a non-empty credential.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  return value;
}

Duration? _expiresIn(Object? value, int statusCode, Uri endpoint) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0) {
    throw McpOAuthTokenException(
      'OAuth token response expires_in must be a non-negative integer.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  return Duration(seconds: value);
}

List<String>? _responseScopes(Object? value, int statusCode, Uri endpoint) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw McpOAuthTokenException(
      'OAuth token response scope must be a non-empty scope string.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final scopes = value.split(' ');
  if (scopes.any((scope) => !_oauthScopeTokenValid(scope))) {
    throw McpOAuthTokenException(
      'OAuth token response scope contains an invalid token.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  return List<String>.unmodifiable(scopes.toSet());
}

Uri? _safeErrorUri(Object? value, int statusCode, Uri endpoint) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw McpOAuthTokenException(
      'OAuth token endpoint returned an invalid error_uri.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  final uri = Uri.tryParse(value);
  final secure = uri?.scheme == 'https';
  final localHttp =
      uri?.scheme == 'http' && uri != null && _isLoopbackHost(uri.host);
  if (uri == null ||
      (!secure && !localHttp) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw McpOAuthTokenException(
      'OAuth token endpoint returned an unsafe error_uri.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  return uri;
}

String _formEncodeComponent(String value) {
  const key = 'value';
  return Uri(
    queryParameters: <String, String>{key: value},
  ).query.substring(key.length + 1);
}

bool _credentialValid(String? value) {
  if (value == null || value.isEmpty) {
    return false;
  }
  return !value.codeUnits.any(
    (codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f,
  );
}

bool _printableNonEmpty(String value) {
  return value.trim().isNotEmpty &&
      !value.codeUnits.any((codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f);
}

bool _oauthScopeTokenValid(String value) {
  if (value.isEmpty) {
    return false;
  }
  return value.codeUnits.every(
    (codeUnit) =>
        codeUnit == 0x21 ||
        (codeUnit >= 0x23 && codeUnit <= 0x5b) ||
        (codeUnit >= 0x5d && codeUnit <= 0x7e),
  );
}

bool _oauthNqsCharValid(String value) {
  if (value.isEmpty) {
    return false;
  }
  return value.codeUnits.every(
    (codeUnit) =>
        (codeUnit >= 0x20 && codeUnit <= 0x21) ||
        (codeUnit >= 0x23 && codeUnit <= 0x5b) ||
        (codeUnit >= 0x5d && codeUnit <= 0x7e),
  );
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

bool _resourcesMatch(Uri expected, Uri candidate) {
  return expected.scheme.toLowerCase() == candidate.scheme.toLowerCase() &&
      expected.host.toLowerCase() == candidate.host.toLowerCase() &&
      expected.port == candidate.port &&
      expected.path == candidate.path &&
      expected.query == candidate.query &&
      candidate.userInfo.isEmpty &&
      !candidate.hasFragment;
}

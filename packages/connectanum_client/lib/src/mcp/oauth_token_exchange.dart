import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show containsMcpWhitespaceOrControl;

import 'authorization_discovery.dart';
import 'oauth_authorization.dart';

const _authorizationCodeGrant = 'authorization_code';
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

/// An OAuth bearer grant issued for one canonical MCP resource.
final class McpOAuthTokenGrant {
  McpOAuthTokenGrant._({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required List<String> scopes,
    required this.resource,
    required this.clientId,
    required this.authorizationServer,
    required Map<String, Object?> additionalParameters,
  }) : scopes = List<String>.unmodifiable(scopes),
       additionalParameters = Map<String, Object?>.unmodifiable(
         additionalParameters,
       );

  final String accessToken;
  final String tokenType = 'Bearer';
  final String? refreshToken;
  final Duration? expiresIn;

  /// Effective scopes returned by the server, or the requested scopes when
  /// `scope` is omitted as defined by RFC 6749 section 5.1.
  final List<String> scopes;
  final Uri resource;
  final String clientId;
  final McpAuthorizationServerMetadata authorizationServer;
  final Map<String, Object?> additionalParameters;

  /// Whether [candidate] identifies the same canonical MCP resource.
  bool isForResource(Uri candidate) {
    return _resourcesMatch(resource, candidate);
  }
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
Future<McpOAuthTokenGrant> exchangeMcpAuthorizationCode(
  McpAuthorizationCode authorizationCode, {
  required McpOAuthClientAuthentication clientAuthentication,
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  Duration timeout = _defaultTokenTimeout,
  int maxResponseBytes = _defaultTokenResponseBytes,
}) async {
  final requestState = authorizationCode.request;
  final authorizationServer = requestState.authorizationServer;
  final tokenEndpoint = authorizationServer.tokenEndpoint;
  _validateExchangeInputs(
    authorizationCode,
    clientAuthentication,
    headers,
    timeout,
    maxResponseBytes,
  );

  final form = <String, String>{
    'grant_type': _authorizationCodeGrant,
    'code': authorizationCode.code,
    'redirect_uri': requestState.redirectUri.toString(),
    if (clientAuthentication.method != _clientSecretBasic)
      'client_id': clientAuthentication.clientId,
    'code_verifier': requestState.pkce.verifier,
    'resource': requestState.resource.toString(),
    if (clientAuthentication.method == _clientSecretPost)
      'client_secret': clientAuthentication._clientSecret!,
  };
  final encodedForm = utf8.encode(Uri(queryParameters: form).query);
  final client = httpClient ?? HttpClient();
  final ownsClient = httpClient == null;
  final deadline = DateTime.now().add(timeout);
  HttpClientRequest? request;

  try {
    request = await client
        .postUrl(tokenEndpoint)
        .timeout(_remaining(deadline, tokenEndpoint));
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
      _remaining(deadline, tokenEndpoint),
    );
    final body = await _readTokenResponse(
      response,
      maxResponseBytes: maxResponseBytes,
      endpoint: tokenEndpoint,
    ).timeout(_remaining(deadline, tokenEndpoint));
    return _parseTokenResponse(
      response,
      body,
      authorizationCode: authorizationCode,
      clientAuthentication: clientAuthentication,
    );
  } on McpOAuthTokenException {
    rethrow;
  } on TimeoutException {
    request?.abort();
    throw McpOAuthTokenException(
      'OAuth token endpoint request timed out.',
      endpoint: tokenEndpoint,
    );
  } on Object {
    request?.abort();
    throw McpOAuthTokenException(
      'OAuth token endpoint request failed.',
      endpoint: tokenEndpoint,
    );
  } finally {
    if (ownsClient) {
      client.close(force: true);
    }
  }
}

void _validateExchangeInputs(
  McpAuthorizationCode authorizationCode,
  McpOAuthClientAuthentication clientAuthentication,
  Map<String, String> headers,
  Duration timeout,
  int maxResponseBytes,
) {
  final request = authorizationCode.request;
  final tokenEndpoint = request.authorizationServer.tokenEndpoint;
  if (clientAuthentication.clientId != request.clientId) {
    throw McpOAuthTokenException(
      'Token client ID must match the authorization request.',
      endpoint: tokenEndpoint,
    );
  }
  if (!_printableNonEmpty(clientAuthentication.clientId)) {
    throw McpOAuthTokenException(
      'OAuth client ID must be non-empty printable text.',
      endpoint: tokenEndpoint,
    );
  }
  final supportedMethods =
      request.authorizationServer.tokenEndpointAuthMethodsSupported ??
      const <String>[_clientSecretBasic];
  if (!supportedMethods.contains(clientAuthentication.method)) {
    throw McpOAuthTokenException(
      'Authorization server does not support token endpoint client '
      'authentication method "${clientAuthentication.method}".',
      endpoint: tokenEndpoint,
    );
  }
  if (clientAuthentication.method != _noClientAuthentication &&
      !_credentialValid(clientAuthentication._clientSecret)) {
    throw McpOAuthTokenException(
      'OAuth client secret must be non-empty and contain no controls.',
      endpoint: tokenEndpoint,
    );
  }
  if (timeout <= Duration.zero) {
    throw McpOAuthTokenException(
      'Token endpoint timeout must be positive.',
      endpoint: tokenEndpoint,
    );
  }
  if (maxResponseBytes <= 0) {
    throw McpOAuthTokenException(
      'Token response byte limit must be positive.',
      endpoint: tokenEndpoint,
    );
  }
  for (final entry in headers.entries) {
    final name = entry.key.trim().toLowerCase();
    if (name.isEmpty ||
        _controlledTokenRequestHeaders.contains(name) ||
        name.startsWith('mcp-')) {
      throw McpOAuthTokenException(
        'Header "${entry.key}" is controlled by the OAuth token exchange.',
        endpoint: tokenEndpoint,
      );
    }
    if (entry.value.codeUnits.any((value) => value < 0x20 || value == 0x7f)) {
      throw McpOAuthTokenException(
        'Header "${entry.key}" contains control characters.',
        endpoint: tokenEndpoint,
      );
    }
  }
}

Duration _remaining(DateTime deadline, Uri endpoint) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw McpOAuthTokenException(
      'OAuth token endpoint request timed out.',
      endpoint: endpoint,
    );
  }
  return remaining;
}

Future<String> _readTokenResponse(
  HttpClientResponse response, {
  required int maxResponseBytes,
  required Uri endpoint,
}) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response) {
    length += chunk.length;
    if (length > maxResponseBytes) {
      throw McpOAuthTokenException(
        'OAuth token endpoint response exceeds $maxResponseBytes bytes.',
        endpoint: endpoint,
        statusCode: response.statusCode,
      );
    }
    bytes.add(chunk);
  }
  try {
    return utf8.decode(bytes.takeBytes());
  } on FormatException {
    throw McpOAuthTokenException(
      'OAuth token endpoint response is not valid UTF-8.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
}

McpOAuthTokenGrant _parseTokenResponse(
  HttpClientResponse response,
  String body, {
  required McpAuthorizationCode authorizationCode,
  required McpOAuthClientAuthentication clientAuthentication,
}) {
  final endpoint = authorizationCode.request.authorizationServer.tokenEndpoint;
  if (response.headers.contentType?.mimeType != 'application/json') {
    throw McpOAuthTokenException(
      'OAuth token endpoint must return application/json.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
  final json = _jsonObject(body, response.statusCode, endpoint);
  if (response.statusCode != HttpStatus.ok) {
    _throwTokenError(json, response.statusCode, endpoint);
  }

  final accessToken = json['access_token'];
  if (accessToken is! String ||
      accessToken.isEmpty ||
      containsMcpWhitespaceOrControl(accessToken)) {
    throw McpOAuthTokenException(
      'OAuth token response access_token must be a non-empty bearer token.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
  final tokenType = json['token_type'];
  if (tokenType is! String || tokenType.toLowerCase() != 'bearer') {
    throw McpOAuthTokenException(
      'OAuth token response token_type must be Bearer.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
  final refreshToken = _optionalCredential(
    json['refresh_token'],
    'refresh_token',
    response.statusCode,
    endpoint,
  );
  final expiresIn = _expiresIn(
    json['expires_in'],
    response.statusCode,
    endpoint,
  );
  final responseScopes = _responseScopes(
    json['scope'],
    response.statusCode,
    endpoint,
  );
  final additionalParameters = <String, Object?>{
    for (final entry in json.entries)
      if (!_standardTokenResponseParameters.contains(entry.key))
        entry.key: entry.value,
  };
  final request = authorizationCode.request;
  return McpOAuthTokenGrant._(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresIn: expiresIn,
    scopes: responseScopes ?? request.scopes,
    resource: request.resource,
    clientId: clientAuthentication.clientId,
    authorizationServer: request.authorizationServer,
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
  Uri endpoint,
) {
  final error = json['error'];
  final description = json['error_description'];
  final errorUriValue = json['error_uri'];
  if (error is! String || !_oauthNqsCharValid(error)) {
    throw McpOAuthTokenException(
      'OAuth token endpoint returned an invalid error response.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  if (description != null &&
      (description is! String || !_oauthNqsCharValid(description))) {
    throw McpOAuthTokenException(
      'OAuth token endpoint returned an invalid error_description.',
      endpoint: endpoint,
      statusCode: statusCode,
      oauthError: error,
    );
  }
  final errorUri = _safeErrorUri(errorUriValue, statusCode, endpoint);
  throw McpOAuthTokenException(
    'OAuth token endpoint rejected the authorization grant.',
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

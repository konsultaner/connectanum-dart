import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'authorization_discovery.dart';

const _pkceMethod = 'S256';
const _secureRandomByteCount = 32;
final _pkceVerifierPattern = RegExp(r'^[A-Za-z0-9._~-]{43,128}$');
const _authorizationRequestParameters = <String>{
  'response_type',
  'client_id',
  'redirect_uri',
  'scope',
  'state',
  'code_challenge',
  'code_challenge_method',
  'resource',
};
const _authorizationCallbackParameters = <String>{
  'code',
  'error',
  'error_description',
  'error_uri',
  'state',
};

/// An RFC 7636 verifier and its SHA-256 code challenge.
final class McpPkcePair {
  const McpPkcePair._({required this.verifier, required this.challenge});

  factory McpPkcePair.generate() {
    return McpPkcePair.fromVerifier(
      _secureRandomBase64Url(_secureRandomByteCount),
    );
  }

  factory McpPkcePair.fromVerifier(String verifier) {
    if (!_pkceVerifierPattern.hasMatch(verifier)) {
      throw const McpAuthorizationFlowException(
        'PKCE verifier must contain 43-128 RFC 7636 unreserved ASCII '
        'characters.',
      );
    }
    final challenge = _base64UrlWithoutPadding(
      sha256.convert(ascii.encode(verifier)).bytes,
    );
    return McpPkcePair._(verifier: verifier, challenge: challenge);
  }

  final String verifier;
  final String challenge;
  String get method => _pkceMethod;
}

/// State retained by an MCP client while the resource owner authorizes access.
final class McpAuthorizationRequest {
  const McpAuthorizationRequest._({
    required this.uri,
    required this.authorizationServer,
    required this.resource,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.state,
    required this.pkce,
  });

  final Uri uri;
  final McpAuthorizationServerMetadata authorizationServer;
  final Uri resource;
  final String clientId;
  final Uri redirectUri;
  final List<String> scopes;
  final String state;
  final McpPkcePair pkce;
}

/// A validated authorization code tied to its original PKCE request.
final class McpAuthorizationCode {
  const McpAuthorizationCode._({
    required this.code,
    required this.callbackUri,
    required this.request,
  });

  final String code;
  final Uri callbackUri;
  final McpAuthorizationRequest request;
}

/// A local validation failure or OAuth error from an authorization callback.
final class McpAuthorizationFlowException implements Exception {
  const McpAuthorizationFlowException(
    this.message, {
    this.uri,
    this.oauthError,
    this.errorDescription,
    this.errorUri,
  });

  final String message;
  final Uri? uri;
  final String? oauthError;
  final String? errorDescription;
  final Uri? errorUri;

  @override
  String toString() {
    final buffer = StringBuffer('McpAuthorizationFlowException: $message');
    if (oauthError != null) {
      buffer.write(' (error: $oauthError)');
    }
    if (uri != null) {
      buffer.write(' (${uri!})');
    }
    return buffer.toString();
  }
}

/// Creates an OAuth authorization-code request for a protected MCP resource.
McpAuthorizationRequest createMcpAuthorizationRequest({
  required McpAuthorizationServerMetadata authorizationServer,
  required Uri resource,
  required String clientId,
  required Uri redirectUri,
  Iterable<String> scopes = const <String>[],
  McpPkcePair? pkce,
}) {
  if (!authorizationServer.codeChallengeMethodsSupported.contains(
    _pkceMethod,
  )) {
    throw const McpAuthorizationFlowException(
      'Authorization server must support the S256 PKCE method.',
    );
  }
  _validateSecureEndpoint(
    authorizationServer.authorizationEndpoint,
    'Authorization endpoint',
  );
  _validateSecureEndpoint(resource, 'MCP resource');
  _validateRedirectUri(redirectUri);
  _validateClientId(clientId);
  _rejectControlledQueryParameters(
    authorizationServer.authorizationEndpoint,
    _authorizationRequestParameters,
    'Authorization endpoint',
  );
  _rejectControlledQueryParameters(
    redirectUri,
    _authorizationCallbackParameters,
    'Redirect URI',
  );

  final selectedScopes = _validatedScopes(scopes);
  final requestPkce = pkce ?? McpPkcePair.generate();
  final state = _secureRandomBase64Url(_secureRandomByteCount);
  final query = <String, Object>{
    for (final entry
        in authorizationServer.authorizationEndpoint.queryParametersAll.entries)
      entry.key: entry.value,
    'response_type': 'code',
    'client_id': clientId,
    'redirect_uri': redirectUri.toString(),
    'resource': resource.toString(),
    if (selectedScopes.isNotEmpty) 'scope': selectedScopes.join(' '),
    'state': state,
    'code_challenge': requestPkce.challenge,
    'code_challenge_method': requestPkce.method,
  };

  return McpAuthorizationRequest._(
    uri: authorizationServer.authorizationEndpoint.replace(
      queryParameters: query,
    ),
    authorizationServer: authorizationServer,
    resource: resource,
    clientId: clientId,
    redirectUri: redirectUri,
    scopes: selectedScopes,
    state: state,
    pkce: requestPkce,
  );
}

/// Validates an OAuth redirect callback for [request].
McpAuthorizationCode parseMcpAuthorizationCallback(
  Uri callbackUri, {
  required McpAuthorizationRequest request,
}) {
  _validateAuthorizationCallbackTarget(callbackUri, request.redirectUri);

  final parameters = callbackUri.queryParametersAll;
  for (final name in _authorizationCallbackParameters) {
    final values = parameters[name];
    if (values != null && values.length != 1) {
      throw McpAuthorizationFlowException(
        'Authorization callback parameter "$name" must occur exactly once.',
        uri: callbackUri,
      );
    }
  }

  final state = _singleParameter(parameters, 'state');
  if (state == null || state != request.state) {
    throw McpAuthorizationFlowException(
      'Authorization callback state does not match the request.',
      uri: callbackUri,
    );
  }

  final code = _singleParameter(parameters, 'code');
  final error = _singleParameter(parameters, 'error');
  if ((code == null) == (error == null)) {
    throw McpAuthorizationFlowException(
      'Authorization callback must contain exactly one code or error.',
      uri: callbackUri,
    );
  }

  if (error != null) {
    if (!_oauthNqsCharValid(error)) {
      throw McpAuthorizationFlowException(
        'Authorization callback error is malformed.',
        uri: callbackUri,
      );
    }
    final description = _singleParameter(parameters, 'error_description');
    if (description != null && !_oauthNqsCharValid(description)) {
      throw McpAuthorizationFlowException(
        'Authorization callback error_description is malformed.',
        uri: callbackUri,
      );
    }
    final errorUri = _optionalErrorUri(
      _singleParameter(parameters, 'error_uri'),
      callbackUri,
    );
    throw McpAuthorizationFlowException(
      description ?? 'Authorization server returned "$error".',
      uri: callbackUri,
      oauthError: error,
      errorDescription: description,
      errorUri: errorUri,
    );
  }

  if (!_oauthVsCharValid(code!)) {
    throw McpAuthorizationFlowException(
      'Authorization callback code is malformed.',
      uri: callbackUri,
    );
  }
  return McpAuthorizationCode._(
    code: code,
    callbackUri: callbackUri,
    request: request,
  );
}

String _secureRandomBase64Url(int byteCount) {
  final random = Random.secure();
  return _base64UrlWithoutPadding(
    List<int>.generate(byteCount, (_) => random.nextInt(256), growable: false),
  );
}

String _base64UrlWithoutPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

void _validateClientId(String clientId) {
  if (clientId.trim().isEmpty || !_oauthVsCharValid(clientId)) {
    throw const McpAuthorizationFlowException(
      'OAuth client ID must be non-empty printable ASCII.',
    );
  }
}

List<String> _validatedScopes(Iterable<String> scopes) {
  final result = <String>[];
  final seen = <String>{};
  for (final scope in scopes) {
    if (!_oauthScopeTokenValid(scope)) {
      throw McpAuthorizationFlowException('OAuth scope "$scope" is malformed.');
    }
    if (seen.add(scope)) {
      result.add(scope);
    }
  }
  return List<String>.unmodifiable(result);
}

bool _oauthScopeTokenValid(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit != 0x21 &&
        (codeUnit < 0x23 || codeUnit > 0x5b) &&
        (codeUnit < 0x5d || codeUnit > 0x7e)) {
      return false;
    }
  }
  return true;
}

bool _oauthVsCharValid(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit > 0x7e) {
      return false;
    }
  }
  return true;
}

bool _oauthNqsCharValid(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if ((codeUnit < 0x20 || codeUnit > 0x21) &&
        (codeUnit < 0x23 || codeUnit > 0x5b) &&
        (codeUnit < 0x5d || codeUnit > 0x7e)) {
      return false;
    }
  }
  return true;
}

void _validateSecureEndpoint(Uri uri, String name) {
  final secure = uri.scheme == 'https';
  final localHttp = uri.scheme == 'http' && _isLoopbackHost(uri.host);
  if ((!secure && !localHttp) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw McpAuthorizationFlowException(
      '$name must be an HTTPS URL without user info or fragment; loopback '
      'HTTP is allowed for local development.',
      uri: uri,
    );
  }
}

void _validateRedirectUri(Uri uri) {
  _validateSecureEndpoint(uri, 'OAuth redirect URI');
}

bool _isLoopbackHost(String host) {
  if (host.toLowerCase() == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback ?? false;
}

void _rejectControlledQueryParameters(
  Uri uri,
  Set<String> controlled,
  String name,
) {
  final conflicts = uri.queryParametersAll.keys
      .where(controlled.contains)
      .toList(growable: false);
  if (conflicts.isNotEmpty) {
    throw McpAuthorizationFlowException(
      '$name must not predefine controlled OAuth parameter '
      '"${conflicts.first}".',
      uri: uri,
    );
  }
}

void _validateAuthorizationCallbackTarget(Uri callback, Uri expected) {
  if (callback.hasFragment ||
      callback.scheme != expected.scheme ||
      callback.host.toLowerCase() != expected.host.toLowerCase() ||
      callback.port != expected.port ||
      callback.userInfo != expected.userInfo ||
      callback.path != expected.path) {
    throw McpAuthorizationFlowException(
      'Authorization callback does not match the configured redirect URI.',
      uri: callback,
    );
  }

  for (final entry in expected.queryParametersAll.entries) {
    final actual = callback.queryParametersAll[entry.key];
    if (actual == null || !_sameStrings(actual, entry.value)) {
      throw McpAuthorizationFlowException(
        'Authorization callback does not preserve redirect parameter '
        '"${entry.key}".',
        uri: callback,
      );
    }
  }
}

bool _sameStrings(List<String> left, List<String> right) {
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

String? _singleParameter(Map<String, List<String>> parameters, String name) {
  final values = parameters[name];
  return values == null || values.isEmpty ? null : values.single;
}

Uri? _optionalErrorUri(String? value, Uri callbackUri) {
  if (value == null) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) {
    throw McpAuthorizationFlowException(
      'Authorization callback error_uri is malformed.',
      uri: callbackUri,
    );
  }
  _validateSecureEndpoint(uri, 'Authorization callback error_uri');
  return uri;
}

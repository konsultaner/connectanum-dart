import 'dart:io';

import 'authorization_discovery.dart';
import 'oauth_authorization.dart';
import 'oauth_token_exchange.dart';

const _noClientAuthentication = 'none';
const _authorizationCodeGrant = 'authorization_code';
const _authorizationCodeResponse = 'code';

final class McpOAuthClientMetadataDocument {
  factory McpOAuthClientMetadataDocument.publicClient({
    required Uri clientId,
    required String clientName,
    required Iterable<Uri> redirectUris,
    Uri? clientUri,
    Uri? logoUri,
    Iterable<String> scopes = const <String>[],
  }) {
    _validateClientId(clientId);
    _validateClientName(clientName);
    final validatedRedirectUris = _validatedRedirectUris(redirectUris);
    if (clientUri != null) {
      _validatePresentationUri(clientUri, 'Client URI');
    }
    if (logoUri != null) {
      _validatePresentationUri(logoUri, 'Logo URI');
    }
    final validatedScopes = _validatedScopes(scopes);

    return McpOAuthClientMetadataDocument._(
      clientId: clientId,
      clientName: clientName,
      redirectUris: validatedRedirectUris,
      clientUri: clientUri,
      logoUri: logoUri,
      scopes: validatedScopes,
    );
  }

  McpOAuthClientMetadataDocument._({
    required this.clientId,
    required this.clientName,
    required List<Uri> redirectUris,
    required this.clientUri,
    required this.logoUri,
    required List<String> scopes,
  }) : redirectUris = List<Uri>.unmodifiable(redirectUris),
       scopes = List<String>.unmodifiable(scopes);

  final Uri clientId;
  final String clientName;
  final List<Uri> redirectUris;
  final Uri? clientUri;
  final Uri? logoUri;
  final List<String> scopes;

  McpOAuthClientAuthentication get clientAuthentication =>
      McpOAuthClientAuthentication.none(clientId.toString());

  Map<String, Object?> toJson() {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'client_id': clientId.toString(),
      'client_name': clientName,
      'redirect_uris': List<String>.unmodifiable(
        redirectUris.map((uri) => uri.toString()),
      ),
      'token_endpoint_auth_method': _noClientAuthentication,
      'grant_types': const <String>[_authorizationCodeGrant],
      'response_types': const <String>[_authorizationCodeResponse],
      if (clientUri != null) 'client_uri': clientUri.toString(),
      if (logoUri != null) 'logo_uri': logoUri.toString(),
      if (scopes.isNotEmpty) 'scope': scopes.join(' '),
    });
  }

  McpAuthorizationRequest createAuthorizationRequest({
    required McpAuthorizationServerMetadata authorizationServer,
    required Uri resource,
    required Uri redirectUri,
    Iterable<String>? scopes,
    McpPkcePair? pkce,
  }) {
    if (authorizationServer.clientIdMetadataDocumentSupported != true) {
      throw const McpOAuthClientMetadataException(
        'Authorization server does not advertise Client ID Metadata '
        'Document support.',
      );
    }
    if (authorizationServer.tokenEndpointAuthMethodsSupported?.contains(
          _noClientAuthentication,
        ) !=
        true) {
      throw const McpOAuthClientMetadataException(
        'Authorization server does not advertise public-client token '
        'endpoint authentication.',
      );
    }
    final redirectValue = redirectUri.toString();
    if (!redirectUris.any((uri) => uri.toString() == redirectValue)) {
      throw const McpOAuthClientMetadataException(
        'Redirect URI is not registered in the Client ID Metadata Document.',
      );
    }

    return createMcpAuthorizationRequest(
      authorizationServer: authorizationServer,
      resource: resource,
      clientId: clientId.toString(),
      redirectUri: redirectUri,
      scopes: scopes ?? this.scopes,
      pkce: pkce,
    );
  }
}

final class McpOAuthClientMetadataException implements Exception {
  const McpOAuthClientMetadataException(this.message);

  final String message;

  @override
  String toString() => 'McpOAuthClientMetadataException: $message';
}

void _validateClientId(Uri clientId) {
  if (clientId.scheme.toLowerCase() != 'https' ||
      !clientId.hasAuthority ||
      clientId.host.isEmpty ||
      clientId.userInfo.isNotEmpty ||
      clientId.hasQuery ||
      clientId.hasFragment ||
      clientId.path.isEmpty ||
      clientId.path == '/' ||
      clientId.pathSegments.any(
        (segment) => segment == '.' || segment == '..',
      )) {
    throw const McpOAuthClientMetadataException(
      'Client ID must be an HTTPS URL with a non-root path and without '
      'userinfo, query, fragment, or dot path segments.',
    );
  }
}

void _validateClientName(String clientName) {
  if (clientName.trim().isEmpty ||
      clientName.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw const McpOAuthClientMetadataException(
      'Client name must be non-empty and must not contain control characters.',
    );
  }
}

List<Uri> _validatedRedirectUris(Iterable<Uri> redirectUris) {
  final validated = <Uri>[];
  final values = <String>{};
  for (final redirectUri in redirectUris) {
    _validateRedirectUri(redirectUri);
    if (!values.add(redirectUri.toString())) {
      throw const McpOAuthClientMetadataException(
        'Redirect URIs must be unique.',
      );
    }
    validated.add(redirectUri);
  }
  if (validated.isEmpty) {
    throw const McpOAuthClientMetadataException(
      'At least one redirect URI is required.',
    );
  }
  return validated;
}

void _validateRedirectUri(Uri redirectUri) {
  final secure = redirectUri.scheme.toLowerCase() == 'https';
  final loopback =
      redirectUri.scheme.toLowerCase() == 'http' &&
      _isLoopbackHost(redirectUri.host);
  if (!redirectUri.hasAuthority ||
      redirectUri.host.isEmpty ||
      redirectUri.userInfo.isNotEmpty ||
      redirectUri.hasFragment ||
      (!secure && !loopback)) {
    throw const McpOAuthClientMetadataException(
      'Redirect URI must use HTTPS or loopback HTTP and must not contain '
      'userinfo or a fragment.',
    );
  }
}

void _validatePresentationUri(Uri uri, String label) {
  if (uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw McpOAuthClientMetadataException(
      '$label must be an HTTPS URL without userinfo or a fragment.',
    );
  }
}

List<String> _validatedScopes(Iterable<String> scopes) {
  final validated = <String>[];
  final seen = <String>{};
  for (final scope in scopes) {
    if (!_scopeTokenValid(scope)) {
      throw const McpOAuthClientMetadataException(
        'OAuth scopes must contain only RFC 6749 scope-token characters.',
      );
    }
    if (seen.add(scope)) {
      validated.add(scope);
    }
  }
  return validated;
}

bool _scopeTokenValid(String value) {
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

bool _isLoopbackHost(String host) {
  if (host.toLowerCase() == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback ?? false;
}

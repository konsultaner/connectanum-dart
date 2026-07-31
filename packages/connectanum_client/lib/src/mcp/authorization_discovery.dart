import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _protectedResourceWellKnownPath = '/.well-known/oauth-protected-resource';
const _oauthAuthorizationServerWellKnownPath =
    '/.well-known/oauth-authorization-server';
const _openIdConfigurationWellKnownPath = '/.well-known/openid-configuration';
const _defaultMaxMetadataBytes = 1024 * 1024;
final _scopeSeparator = RegExp(' +');

/// A parsed Bearer challenge from a `WWW-Authenticate` response header.
final class McpBearerChallenge {
  McpBearerChallenge(Map<String, String> parameters)
    : parameters = Map<String, String>.unmodifiable(<String, String>{
        for (final entry in parameters.entries)
          entry.key.toLowerCase(): entry.value,
      });

  final Map<String, String> parameters;

  String? get realm => parameters['realm'];

  String? get resourceMetadataValue => parameters['resource_metadata'];

  Uri? get resourceMetadata {
    final value = resourceMetadataValue;
    return value == null ? null : Uri.tryParse(value);
  }

  String? get scope => parameters['scope'];

  List<String> get scopes {
    final value = scope?.trim();
    if (value == null || value.isEmpty) {
      return const <String>[];
    }
    return List<String>.unmodifiable(value.split(_scopeSeparator));
  }

  String? get error => parameters['error'];

  String? get errorDescription => parameters['error_description'];
}

/// Parses valid Bearer challenges while ignoring other authentication schemes.
List<McpBearerChallenge> parseMcpBearerChallenges(Iterable<String> values) {
  final challenges = <McpBearerChallenge>[];
  for (final value in values) {
    for (final challenge in _parseAuthenticateHeader(value)) {
      if (challenge.scheme.toLowerCase() == 'bearer' && !challenge.malformed) {
        challenges.add(McpBearerChallenge(challenge.parameters));
      }
    }
  }
  return List<McpBearerChallenge>.unmodifiable(challenges);
}

/// Validated OAuth Protected Resource Metadata for an MCP HTTP endpoint.
final class McpProtectedResourceMetadata {
  McpProtectedResourceMetadata._({
    required this.resource,
    required List<Uri> authorizationServers,
    required List<String>? scopesSupported,
    required this.resourceName,
    required List<String>? bearerMethodsSupported,
    required Map<String, Object?> raw,
  }) : authorizationServers = List<Uri>.unmodifiable(authorizationServers),
       scopesSupported = scopesSupported == null
           ? null
           : List<String>.unmodifiable(scopesSupported),
       bearerMethodsSupported = bearerMethodsSupported == null
           ? null
           : List<String>.unmodifiable(bearerMethodsSupported),
       raw = Map<String, Object?>.unmodifiable(raw);

  final Uri resource;
  final List<Uri> authorizationServers;
  final List<String>? scopesSupported;
  final String? resourceName;
  final List<String>? bearerMethodsSupported;
  final Map<String, Object?> raw;
}

/// The result of Protected Resource Metadata discovery.
final class McpProtectedResourceDiscovery {
  const McpProtectedResourceDiscovery({
    required this.metadataUri,
    required this.metadata,
    required this.challenge,
  });

  final Uri metadataUri;
  final McpProtectedResourceMetadata metadata;
  final McpBearerChallenge? challenge;

  /// Scopes required for the current request, honoring the MCP priority order.
  List<String> get requiredScopes {
    final challengedScope = challenge?.scope;
    if (challengedScope != null) {
      return challenge!.scopes;
    }
    return metadata.scopesSupported ?? const <String>[];
  }
}

/// Validated OAuth authorization-server metadata for an MCP client.
final class McpAuthorizationServerMetadata {
  McpAuthorizationServerMetadata._({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.registrationEndpoint,
    required this.jwksUri,
    required List<String>? scopesSupported,
    required List<String> responseTypesSupported,
    required List<String>? grantTypesSupported,
    required List<String> codeChallengeMethodsSupported,
    required List<String>? tokenEndpointAuthMethodsSupported,
    required this.clientIdMetadataDocumentSupported,
    required Map<String, Object?> raw,
  }) : scopesSupported = scopesSupported == null
           ? null
           : List<String>.unmodifiable(scopesSupported),
       responseTypesSupported = List<String>.unmodifiable(
         responseTypesSupported,
       ),
       grantTypesSupported = grantTypesSupported == null
           ? null
           : List<String>.unmodifiable(grantTypesSupported),
       codeChallengeMethodsSupported = List<String>.unmodifiable(
         codeChallengeMethodsSupported,
       ),
       tokenEndpointAuthMethodsSupported =
           tokenEndpointAuthMethodsSupported == null
           ? null
           : List<String>.unmodifiable(tokenEndpointAuthMethodsSupported),
       raw = Map<String, Object?>.unmodifiable(raw);

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? registrationEndpoint;
  final Uri? jwksUri;
  final List<String>? scopesSupported;
  final List<String> responseTypesSupported;
  final List<String>? grantTypesSupported;
  final List<String> codeChallengeMethodsSupported;
  final List<String>? tokenEndpointAuthMethodsSupported;
  final bool? clientIdMetadataDocumentSupported;
  final Map<String, Object?> raw;
}

/// The successful result of authorization-server metadata discovery.
final class McpAuthorizationServerDiscovery {
  const McpAuthorizationServerDiscovery({
    required this.metadataUri,
    required this.metadata,
  });

  final Uri metadataUri;
  final McpAuthorizationServerMetadata metadata;
}

/// A standards or transport failure during MCP OAuth metadata discovery.
final class McpAuthorizationDiscoveryException implements Exception {
  const McpAuthorizationDiscoveryException(
    this.message, {
    this.uri,
    this.statusCode,
  });

  final String message;
  final Uri? uri;
  final int? statusCode;

  @override
  String toString() {
    final location = uri == null ? '' : ' ($uri)';
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    return 'McpAuthorizationDiscoveryException$status$location: $message';
  }
}

/// Discovers and validates RFC 9728 metadata for an MCP HTTP endpoint.
///
/// Requests intentionally omit MCP session and authorization headers. Explicit
/// [headers] are accepted for metadata-specific routing, but credential and
/// session headers are rejected.
Future<McpProtectedResourceDiscovery> discoverMcpProtectedResourceMetadata(
  Uri endpoint, {
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  bool closeHttpClient = false,
  int maxMetadataBytes = _defaultMaxMetadataBytes,
}) async {
  _validateProtectedResourceUri(endpoint, 'endpoint');
  if (maxMetadataBytes <= 0) {
    throw ArgumentError.value(
      maxMetadataBytes,
      'maxMetadataBytes',
      'must be greater than zero',
    );
  }
  _validateDiscoveryHeaders(headers);

  final client = httpClient ?? HttpClient();
  final ownsClient = httpClient == null || closeHttpClient;
  try {
    final probe = await _getDiscoveryDocument(
      client,
      endpoint,
      headers: headers,
      maxMetadataBytes: maxMetadataBytes,
    );
    final challenges = parseMcpBearerChallenges(
      probe.headers[HttpHeaders.wwwAuthenticateHeader] ?? const <String>[],
    );
    final challenge = _preferredBearerChallenge(challenges);
    _validateChallengeScope(challenge);

    final directMetadata = _directMetadataJson(probe);
    if (directMetadata != null) {
      return McpProtectedResourceDiscovery(
        metadataUri: endpoint,
        metadata: _metadataFromJson(directMetadata, endpoint),
        challenge: challenge,
      );
    }

    final challengedMetadataValue = challenge?.resourceMetadataValue;
    if (challengedMetadataValue != null) {
      final metadataUri = challenge!.resourceMetadata;
      if (metadataUri == null) {
        throw McpAuthorizationDiscoveryException(
          'Bearer resource_metadata is not a valid absolute URL.',
          uri: endpoint,
        );
      }
      _validateMetadataUri(metadataUri);
      final metadata = await _fetchRequiredMetadata(
        client,
        metadataUri,
        endpoint,
        headers: headers,
        maxMetadataBytes: maxMetadataBytes,
      );
      return McpProtectedResourceDiscovery(
        metadataUri: metadataUri,
        metadata: metadata,
        challenge: challenge,
      );
    }

    final attempted = <Uri>[];
    for (final metadataUri in _wellKnownMetadataUris(endpoint)) {
      attempted.add(metadataUri);
      final response = await _getDiscoveryDocument(
        client,
        metadataUri,
        headers: headers,
        maxMetadataBytes: maxMetadataBytes,
      );
      if (response.statusCode == HttpStatus.notFound ||
          response.statusCode == HttpStatus.gone) {
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw McpAuthorizationDiscoveryException(
          'Protected Resource Metadata request failed.',
          uri: metadataUri,
          statusCode: response.statusCode,
        );
      }
      final metadata = _metadataFromResponse(response, metadataUri, endpoint);
      return McpProtectedResourceDiscovery(
        metadataUri: metadataUri,
        metadata: metadata,
        challenge: challenge,
      );
    }

    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata was not found at ${attempted.join(', ')}.',
      uri: endpoint,
    );
  } finally {
    if (ownsClient) {
      client.close(force: true);
    }
  }
}

/// Discovers MCP-compatible OAuth authorization-server metadata for [issuer].
///
/// The RFC 8414 and OpenID Connect endpoints are attempted in MCP priority
/// order. Requests intentionally omit authorization and MCP session state.
Future<McpAuthorizationServerDiscovery> discoverMcpAuthorizationServerMetadata(
  Uri issuer, {
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  bool closeHttpClient = false,
  int maxMetadataBytes = _defaultMaxMetadataBytes,
}) async {
  _validateAuthorizationServerIssuer(issuer, 'issuer');
  if (maxMetadataBytes <= 0) {
    throw ArgumentError.value(
      maxMetadataBytes,
      'maxMetadataBytes',
      'must be greater than zero',
    );
  }
  _validateDiscoveryHeaders(headers);

  final client = httpClient ?? HttpClient();
  final ownsClient = httpClient == null || closeHttpClient;
  final attempted = <Uri>[];
  McpAuthorizationDiscoveryException? lastFailure;
  try {
    for (final metadataUri in _authorizationServerMetadataUris(issuer)) {
      attempted.add(metadataUri);
      try {
        final response = await _getDiscoveryDocument(
          client,
          metadataUri,
          headers: headers,
          maxMetadataBytes: maxMetadataBytes,
          documentLabel: 'Authorization Server Metadata',
        );
        if (response.statusCode != HttpStatus.ok) {
          throw McpAuthorizationDiscoveryException(
            'Authorization Server Metadata request failed.',
            uri: metadataUri,
            statusCode: response.statusCode,
          );
        }
        final metadata = _authorizationServerMetadataFromResponse(
          response,
          metadataUri,
          issuer,
        );
        return McpAuthorizationServerDiscovery(
          metadataUri: metadataUri,
          metadata: metadata,
        );
      } on McpAuthorizationDiscoveryException catch (error) {
        lastFailure = error;
      }
    }

    final detail = lastFailure == null ? '' : ' ${lastFailure.message}';
    throw McpAuthorizationDiscoveryException(
      'Authorization Server Metadata discovery failed after attempting '
      '${attempted.join(', ')}.$detail',
      uri: lastFailure?.uri ?? issuer,
      statusCode: lastFailure?.statusCode,
    );
  } finally {
    if (ownsClient) {
      client.close(force: true);
    }
  }
}

McpBearerChallenge? _preferredBearerChallenge(
  List<McpBearerChallenge> challenges,
) {
  for (final challenge in challenges) {
    if (challenge.resourceMetadataValue != null) {
      return challenge;
    }
  }
  return challenges.firstOrNull;
}

void _validateChallengeScope(McpBearerChallenge? challenge) {
  final rawScope = challenge?.scope;
  if (rawScope == null) {
    return;
  }
  final scopes = challenge!.scopes;
  if (scopes.isEmpty || scopes.any((scope) => !_oauthScopeTokenValid(scope))) {
    throw const McpAuthorizationDiscoveryException(
      'Bearer scope contains an invalid OAuth scope token.',
    );
  }
}

Map<String, Object?>? _directMetadataJson(_DiscoveryResponse response) {
  if (response.statusCode != HttpStatus.ok ||
      !_isJsonContentType(response.headers) ||
      response.body.isEmpty) {
    return null;
  }
  Object? value;
  try {
    value = jsonDecode(response.body);
  } on FormatException {
    return null;
  }
  if (value is Map<String, Object?> && value.containsKey('resource')) {
    return value;
  }
  return null;
}

Future<McpProtectedResourceMetadata> _fetchRequiredMetadata(
  HttpClient client,
  Uri metadataUri,
  Uri expectedResource, {
  required Map<String, String> headers,
  required int maxMetadataBytes,
}) async {
  final response = await _getDiscoveryDocument(
    client,
    metadataUri,
    headers: headers,
    maxMetadataBytes: maxMetadataBytes,
  );
  if (response.statusCode != HttpStatus.ok) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata request failed.',
      uri: metadataUri,
      statusCode: response.statusCode,
    );
  }
  return _metadataFromResponse(response, metadataUri, expectedResource);
}

McpProtectedResourceMetadata _metadataFromResponse(
  _DiscoveryResponse response,
  Uri metadataUri,
  Uri expectedResource,
) {
  if (!_isJsonContentType(response.headers)) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata must use application/json.',
      uri: metadataUri,
      statusCode: response.statusCode,
    );
  }
  return _metadataFromJson(
    _decodeJsonObject(response.body, metadataUri),
    expectedResource,
  );
}

McpProtectedResourceMetadata _metadataFromJson(
  Map<String, Object?> json,
  Uri expectedResource,
) {
  final resourceValue = _requiredString(json, 'resource');
  final resource = Uri.tryParse(resourceValue);
  if (resource == null) {
    throw const McpAuthorizationDiscoveryException(
      'Protected Resource Metadata resource is not a valid URI.',
    );
  }
  _validateProtectedResourceUri(resource, 'resource');
  if (!_sameResourceIdentifier(resource, expectedResource)) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata resource $resource does not match '
      '$expectedResource.',
      uri: resource,
    );
  }

  final authorizationServers =
      _requiredStringList(json, 'authorization_servers')
          .map((value) {
            final uri = Uri.tryParse(value);
            if (uri == null) {
              throw McpAuthorizationDiscoveryException(
                'Protected Resource Metadata authorization server must be an '
                'absolute issuer URL.',
                uri: uri,
              );
            }
            _validateAuthorizationServerIssuer(uri, 'authorization server');
            return uri;
          })
          .toList(growable: false);
  if (authorizationServers.toSet().length != authorizationServers.length) {
    throw const McpAuthorizationDiscoveryException(
      'Protected Resource Metadata authorization servers must be unique.',
    );
  }

  final scopesSupported = _optionalStringList(json, 'scopes_supported');
  if (scopesSupported != null &&
      (scopesSupported.isEmpty ||
          scopesSupported.any((scope) => !_oauthScopeTokenValid(scope)))) {
    throw const McpAuthorizationDiscoveryException(
      'Protected Resource Metadata scopes_supported contains an invalid OAuth '
      'scope token.',
    );
  }
  final bearerMethods = _optionalStringList(
    json,
    'bearer_methods_supported',
    allowEmpty: true,
  );
  final resourceName = _optionalString(json, 'resource_name');

  return McpProtectedResourceMetadata._(
    resource: resource,
    authorizationServers: authorizationServers,
    scopesSupported: scopesSupported,
    resourceName: resourceName,
    bearerMethodsSupported: bearerMethods,
    raw: json,
  );
}

McpAuthorizationServerMetadata _authorizationServerMetadataFromResponse(
  _DiscoveryResponse response,
  Uri metadataUri,
  Uri expectedIssuer,
) {
  if (!_isJsonContentType(response.headers)) {
    throw McpAuthorizationDiscoveryException(
      'Authorization Server Metadata must use application/json.',
      uri: metadataUri,
      statusCode: response.statusCode,
    );
  }
  return _authorizationServerMetadataFromJson(
    _decodeJsonObject(
      response.body,
      metadataUri,
      documentLabel: 'Authorization Server Metadata',
    ),
    expectedIssuer,
  );
}

McpAuthorizationServerMetadata _authorizationServerMetadataFromJson(
  Map<String, Object?> json,
  Uri expectedIssuer,
) {
  const documentLabel = 'Authorization Server Metadata';
  final issuerValue = _requiredString(
    json,
    'issuer',
    documentLabel: documentLabel,
  );
  final issuer = Uri.tryParse(issuerValue);
  if (issuer == null || issuerValue != expectedIssuer.toString()) {
    throw McpAuthorizationDiscoveryException(
      'Authorization Server Metadata issuer must exactly match '
      '$expectedIssuer.',
      uri: issuer,
    );
  }
  _validateAuthorizationServerIssuer(issuer, 'issuer');

  final authorizationEndpoint = _authorizationServerEndpoint(
    json,
    'authorization_endpoint',
    documentLabel: documentLabel,
  )!;
  final tokenEndpoint = _authorizationServerEndpoint(
    json,
    'token_endpoint',
    documentLabel: documentLabel,
  )!;
  final registrationEndpoint = _authorizationServerEndpoint(
    json,
    'registration_endpoint',
    documentLabel: documentLabel,
    optional: true,
  );
  final jwksUri = _authorizationServerEndpoint(
    json,
    'jwks_uri',
    documentLabel: documentLabel,
    optional: true,
  );

  final scopesSupported = _optionalStringList(
    json,
    'scopes_supported',
    documentLabel: documentLabel,
  );
  if (scopesSupported != null &&
      scopesSupported.any((scope) => !_oauthScopeTokenValid(scope))) {
    throw const McpAuthorizationDiscoveryException(
      'Authorization Server Metadata scopes_supported contains an invalid '
      'OAuth scope token.',
    );
  }

  final responseTypesSupported = _requiredStringList(
    json,
    'response_types_supported',
    documentLabel: documentLabel,
  );
  if (!responseTypesSupported.contains('code')) {
    throw const McpAuthorizationDiscoveryException(
      'Authorization Server Metadata response_types_supported must include '
      'code for MCP authorization.',
    );
  }

  final grantTypesSupported = _optionalStringList(
    json,
    'grant_types_supported',
    documentLabel: documentLabel,
  );
  if (grantTypesSupported != null &&
      !grantTypesSupported.contains('authorization_code')) {
    throw const McpAuthorizationDiscoveryException(
      'Authorization Server Metadata grant_types_supported must include '
      'authorization_code for MCP authorization.',
    );
  }

  final codeChallengeMethodsSupported = _requiredStringList(
    json,
    'code_challenge_methods_supported',
    documentLabel: documentLabel,
  );
  // MCP 2025-11-25 requires clients to refuse authorization without S256.
  if (!codeChallengeMethodsSupported.contains('S256')) {
    throw const McpAuthorizationDiscoveryException(
      'Authorization Server Metadata code_challenge_methods_supported must '
      'include S256 for MCP authorization.',
    );
  }

  final tokenEndpointAuthMethodsSupported = _optionalStringList(
    json,
    'token_endpoint_auth_methods_supported',
    documentLabel: documentLabel,
  );
  final clientIdMetadataDocumentSupported = _optionalBool(
    json,
    'client_id_metadata_document_supported',
    documentLabel: documentLabel,
  );

  return McpAuthorizationServerMetadata._(
    issuer: issuer,
    authorizationEndpoint: authorizationEndpoint,
    tokenEndpoint: tokenEndpoint,
    registrationEndpoint: registrationEndpoint,
    jwksUri: jwksUri,
    scopesSupported: scopesSupported,
    responseTypesSupported: responseTypesSupported,
    grantTypesSupported: grantTypesSupported,
    codeChallengeMethodsSupported: codeChallengeMethodsSupported,
    tokenEndpointAuthMethodsSupported: tokenEndpointAuthMethodsSupported,
    clientIdMetadataDocumentSupported: clientIdMetadataDocumentSupported,
    raw: json,
  );
}

Uri? _authorizationServerEndpoint(
  Map<String, Object?> json,
  String name, {
  required String documentLabel,
  bool optional = false,
}) {
  final value = optional
      ? _optionalString(json, name, documentLabel: documentLabel)
      : _requiredString(json, name, documentLabel: documentLabel);
  if (value == null) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel $name must be an absolute URL.',
    );
  }
  _validateAuthorizationServerEndpoint(uri, name);
  return uri;
}

bool? _optionalBool(
  Map<String, Object?> json,
  String name, {
  required String documentLabel,
}) {
  final value = json[name];
  if (value == null || value is bool) {
    return value as bool?;
  }
  throw McpAuthorizationDiscoveryException(
    '$documentLabel $name must be a boolean.',
  );
}

Map<String, Object?> _decodeJsonObject(
  String body,
  Uri uri, {
  String documentLabel = 'Protected Resource Metadata',
}) {
  Object? value;
  try {
    value = jsonDecode(body);
  } on FormatException catch (error) {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel is not valid JSON: ${error.message}',
      uri: uri,
    );
  }
  if (value is! Map<String, Object?>) {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel must be a JSON object.',
      uri: uri,
    );
  }
  return value;
}

String _requiredString(
  Map<String, Object?> json,
  String name, {
  String documentLabel = 'Protected Resource Metadata',
}) {
  final value = json[name];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw McpAuthorizationDiscoveryException(
    '$documentLabel $name must be a non-empty string.',
  );
}

String? _optionalString(
  Map<String, Object?> json,
  String name, {
  String documentLabel = 'Protected Resource Metadata',
}) {
  final value = json[name];
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw McpAuthorizationDiscoveryException(
    '$documentLabel $name must be a non-empty string.',
  );
}

List<String> _requiredStringList(
  Map<String, Object?> json,
  String name, {
  String documentLabel = 'Protected Resource Metadata',
}) {
  final values = _optionalStringList(json, name, documentLabel: documentLabel);
  if (values == null || values.isEmpty) {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel $name must be a non-empty string array.',
    );
  }
  return values;
}

List<String>? _optionalStringList(
  Map<String, Object?> json,
  String name, {
  bool allowEmpty = false,
  String documentLabel = 'Protected Resource Metadata',
}) {
  final value = json[name];
  if (value == null) {
    return null;
  }
  if (value is! List<Object?> ||
      (!allowEmpty && value.isEmpty) ||
      value.any((entry) => entry is! String || entry.isEmpty)) {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel $name must be a '
      '${allowEmpty ? '' : 'non-empty '}string array.',
    );
  }
  final values = value.cast<String>();
  if (values.toSet().length != values.length) {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel $name values must be unique.',
    );
  }
  return List<String>.unmodifiable(values);
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

void _validateProtectedResourceUri(Uri uri, String name) {
  final secure = uri.scheme == 'https';
  final localHttp = uri.scheme == 'http' && _isLoopbackHost(uri.host);
  if ((!secure && !localHttp) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw McpAuthorizationDiscoveryException(
      '$name must be an HTTPS URL without user info or fragment; loopback '
      'HTTP is allowed for local development.',
      uri: uri,
    );
  }
}

void _validateMetadataUri(Uri uri) {
  _validateProtectedResourceUri(uri, 'resource_metadata');
}

bool _isLoopbackHost(String host) {
  if (host.toLowerCase() == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback ?? false;
}

bool _sameResourceIdentifier(Uri actual, Uri expected) {
  return actual.scheme.toLowerCase() == expected.scheme.toLowerCase() &&
      actual.host.toLowerCase() == expected.host.toLowerCase() &&
      actual.hasPort == expected.hasPort &&
      (!actual.hasPort || actual.port == expected.port) &&
      actual.userInfo == expected.userInfo &&
      actual.path == expected.path &&
      actual.query == expected.query &&
      actual.fragment == expected.fragment;
}

void _validateAuthorizationServerIssuer(Uri uri, String name) {
  _validateAuthorizationServerEndpoint(uri, name);
  if (uri.hasQuery) {
    throw McpAuthorizationDiscoveryException(
      '$name must not include a query.',
      uri: uri,
    );
  }
}

void _validateAuthorizationServerEndpoint(Uri uri, String name) {
  final secure = uri.scheme == 'https';
  final localHttp = uri.scheme == 'http' && _isLoopbackHost(uri.host);
  if ((!secure && !localHttp) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw McpAuthorizationDiscoveryException(
      '$name must be an HTTPS URL without user info or fragment; loopback '
      'HTTP is allowed for local development.',
      uri: uri,
    );
  }
}

List<Uri> _authorizationServerMetadataUris(Uri issuer) {
  final issuerPath = issuer.path.isEmpty || issuer.path == '/'
      ? ''
      : issuer.path;
  final oauth = issuer.replace(
    path: '$_oauthAuthorizationServerWellKnownPath$issuerPath',
    query: null,
    fragment: null,
  );
  final openIdInserted = issuer.replace(
    path: '$_openIdConfigurationWellKnownPath$issuerPath',
    query: null,
    fragment: null,
  );
  if (issuerPath.isEmpty) {
    return <Uri>[oauth, openIdInserted];
  }
  final appendBase = issuerPath.endsWith('/')
      ? issuerPath.substring(0, issuerPath.length - 1)
      : issuerPath;
  final openIdAppended = issuer.replace(
    path: '$appendBase$_openIdConfigurationWellKnownPath',
    query: null,
    fragment: null,
  );
  return <Uri>[oauth, openIdInserted, openIdAppended];
}

List<Uri> _wellKnownMetadataUris(Uri resource) {
  final pathSuffix = resource.path.isEmpty || resource.path == '/'
      ? ''
      : resource.path;
  final pathSpecific = resource.replace(
    path: '$_protectedResourceWellKnownPath$pathSuffix',
    fragment: null,
  );
  final root = resource.replace(
    path: _protectedResourceWellKnownPath,
    query: null,
    fragment: null,
  );
  if (pathSpecific == root) {
    return <Uri>[root];
  }
  return <Uri>[pathSpecific, root];
}

void _validateDiscoveryHeaders(Map<String, String> headers) {
  const forbidden = <String>{
    HttpHeaders.authorizationHeader,
    HttpHeaders.proxyAuthorizationHeader,
    HttpHeaders.cookieHeader,
    'mcp-session-id',
    'mcp-protocol-version',
    'last-event-id',
  };
  for (final name in headers.keys) {
    if (forbidden.contains(name.toLowerCase())) {
      throw ArgumentError.value(
        name,
        'headers',
        'credentials and MCP session headers are not allowed during discovery',
      );
    }
  }
}

Future<_DiscoveryResponse> _getDiscoveryDocument(
  HttpClient client,
  Uri uri, {
  required Map<String, String> headers,
  required int maxMetadataBytes,
  String documentLabel = 'Protected Resource Metadata',
}) async {
  final request = await client.getUrl(uri);
  for (final entry in headers.entries) {
    request.headers.set(entry.key, entry.value);
  }
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  final response = await request.close();
  final responseHeaders = <String, List<String>>{};
  response.headers.forEach((name, values) {
    responseHeaders[name.toLowerCase()] = List<String>.unmodifiable(values);
  });
  final body = await _readBoundedBody(
    response,
    uri,
    maxMetadataBytes,
    documentLabel: documentLabel,
  );
  return _DiscoveryResponse(
    uri: uri,
    statusCode: response.statusCode,
    headers: Map<String, List<String>>.unmodifiable(responseHeaders),
    body: body,
  );
}

Future<String> _readBoundedBody(
  HttpClientResponse response,
  Uri uri,
  int maxMetadataBytes, {
  required String documentLabel,
}) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response) {
    length += chunk.length;
    if (length > maxMetadataBytes) {
      throw McpAuthorizationDiscoveryException(
        '$documentLabel exceeds $maxMetadataBytes bytes.',
        uri: uri,
        statusCode: response.statusCode,
      );
    }
    bytes.add(chunk);
  }
  try {
    return utf8.decode(bytes.takeBytes());
  } on FormatException {
    throw McpAuthorizationDiscoveryException(
      '$documentLabel is not valid UTF-8.',
      uri: uri,
      statusCode: response.statusCode,
    );
  }
}

bool _isJsonContentType(Map<String, List<String>> headers) {
  final values = headers[HttpHeaders.contentTypeHeader];
  if (values == null) {
    return false;
  }
  return values.any(
    (value) =>
        value.split(';').first.trim().toLowerCase() ==
        ContentType.json.mimeType,
  );
}

final class _DiscoveryResponse {
  const _DiscoveryResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final Map<String, List<String>> headers;
  final String body;
}

final class _ParsedChallenge {
  const _ParsedChallenge({
    required this.scheme,
    required this.parameters,
    required this.malformed,
  });

  final String scheme;
  final Map<String, String> parameters;
  final bool malformed;
}

List<_ParsedChallenge> _parseAuthenticateHeader(String input) {
  final challenges = <_ParsedChallenge>[];
  var cursor = 0;
  while (cursor < input.length) {
    cursor = _skipWhitespaceAndCommas(input, cursor);
    final schemeStart = cursor;
    cursor = _skipToken(input, cursor);
    if (cursor == schemeStart) {
      break;
    }
    final scheme = input.substring(schemeStart, cursor);
    cursor = _skipWhitespace(input, cursor);
    final parameters = <String, String>{};
    var malformed = false;

    while (cursor < input.length) {
      final parameterStart = cursor;
      final nameEnd = _skipToken(input, cursor);
      if (nameEnd == cursor) {
        malformed = true;
        break;
      }
      var valueStart = _skipWhitespace(input, nameEnd);
      if (valueStart >= input.length || input.codeUnitAt(valueStart) != 0x3d) {
        cursor = parameterStart;
        break;
      }
      valueStart = _skipWhitespace(input, valueStart + 1);
      final parsedValue = _parseAuthParameterValue(input, valueStart);
      if (parsedValue == null) {
        malformed = true;
        cursor = input.length;
        break;
      }
      final name = input.substring(cursor, nameEnd).toLowerCase();
      if (parameters.containsKey(name)) {
        malformed = true;
      } else {
        parameters[name] = parsedValue.value;
      }
      cursor = _skipWhitespace(input, parsedValue.next);
      if (cursor >= input.length || input.codeUnitAt(cursor) != 0x2c) {
        break;
      }

      final next = _skipWhitespace(input, cursor + 1);
      if (!_looksLikeAuthParameter(input, next)) {
        cursor = next;
        break;
      }
      cursor = next;
    }

    challenges.add(
      _ParsedChallenge(
        scheme: scheme,
        parameters: Map<String, String>.unmodifiable(parameters),
        malformed: malformed,
      ),
    );
    if (malformed) {
      break;
    }
  }
  return challenges;
}

bool _looksLikeAuthParameter(String input, int cursor) {
  final nameEnd = _skipToken(input, cursor);
  if (nameEnd == cursor) {
    return false;
  }
  final separator = _skipWhitespace(input, nameEnd);
  return separator < input.length && input.codeUnitAt(separator) == 0x3d;
}

_ParsedParameterValue? _parseAuthParameterValue(String input, int cursor) {
  if (cursor >= input.length) {
    return null;
  }
  if (input.codeUnitAt(cursor) != 0x22) {
    final end = _skipToken(input, cursor);
    if (end == cursor) {
      return null;
    }
    return _ParsedParameterValue(input.substring(cursor, end), end);
  }

  final value = StringBuffer();
  cursor += 1;
  while (cursor < input.length) {
    final codeUnit = input.codeUnitAt(cursor);
    if (codeUnit == 0x22) {
      return _ParsedParameterValue(value.toString(), cursor + 1);
    }
    if (codeUnit == 0x5c) {
      cursor += 1;
      if (cursor >= input.length) {
        return null;
      }
      final escaped = input.codeUnitAt(cursor);
      if (escaped != 0x09 &&
          escaped != 0x20 &&
          (escaped < 0x21 || escaped == 0x7f)) {
        return null;
      }
      value.writeCharCode(escaped);
      cursor += 1;
      continue;
    }
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      return null;
    }
    value.writeCharCode(codeUnit);
    cursor += 1;
  }
  return null;
}

int _skipWhitespaceAndCommas(String input, int cursor) {
  while (cursor < input.length) {
    final codeUnit = input.codeUnitAt(cursor);
    if (codeUnit != 0x20 && codeUnit != 0x09 && codeUnit != 0x2c) {
      break;
    }
    cursor += 1;
  }
  return cursor;
}

int _skipWhitespace(String input, int cursor) {
  while (cursor < input.length) {
    final codeUnit = input.codeUnitAt(cursor);
    if (codeUnit != 0x20 && codeUnit != 0x09) {
      break;
    }
    cursor += 1;
  }
  return cursor;
}

int _skipToken(String input, int cursor) {
  while (cursor < input.length && _isTokenCodeUnit(input.codeUnitAt(cursor))) {
    cursor += 1;
  }
  return cursor;
}

bool _isTokenCodeUnit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      const <int>{
        0x21,
        0x23,
        0x24,
        0x25,
        0x26,
        0x27,
        0x2a,
        0x2b,
        0x2d,
        0x2e,
        0x5e,
        0x5f,
        0x60,
        0x7c,
        0x7e,
      }.contains(codeUnit);
}

final class _ParsedParameterValue {
  const _ParsedParameterValue(this.value, this.next);

  final String value;
  final int next;
}

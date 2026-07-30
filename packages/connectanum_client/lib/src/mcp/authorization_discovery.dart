import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _protectedResourceWellKnownPath = '/.well-known/oauth-protected-resource';
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

  final authorizationServers = _requiredStringList(json, 'authorization_servers')
      .map((value) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment) {
          throw McpAuthorizationDiscoveryException(
            'Protected Resource Metadata authorization server must be an HTTPS '
            'issuer URL without user info, query, or fragment.',
            uri: uri,
          );
        }
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

Map<String, Object?> _decodeJsonObject(String body, Uri uri) {
  Object? value;
  try {
    value = jsonDecode(body);
  } on FormatException catch (error) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata is not valid JSON: ${error.message}',
      uri: uri,
    );
  }
  if (value is! Map<String, Object?>) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata must be a JSON object.',
      uri: uri,
    );
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw McpAuthorizationDiscoveryException(
    'Protected Resource Metadata $name must be a non-empty string.',
  );
}

String? _optionalString(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw McpAuthorizationDiscoveryException(
    'Protected Resource Metadata $name must be a non-empty string.',
  );
}

List<String> _requiredStringList(Map<String, Object?> json, String name) {
  final values = _optionalStringList(json, name);
  if (values == null || values.isEmpty) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata $name must be a non-empty string array.',
    );
  }
  return values;
}

List<String>? _optionalStringList(
  Map<String, Object?> json,
  String name, {
  bool allowEmpty = false,
}) {
  final value = json[name];
  if (value == null) {
    return null;
  }
  if (value is! List<Object?> ||
      (!allowEmpty && value.isEmpty) ||
      value.any((entry) => entry is! String || entry.isEmpty)) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata $name must be a '
      '${allowEmpty ? '' : 'non-empty '}string array.',
    );
  }
  final values = value.cast<String>();
  if (values.toSet().length != values.length) {
    throw McpAuthorizationDiscoveryException(
      'Protected Resource Metadata $name values must be unique.',
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
  final body = await _readBoundedBody(response, uri, maxMetadataBytes);
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
  int maxMetadataBytes,
) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response) {
    length += chunk.length;
    if (length > maxMetadataBytes) {
      throw McpAuthorizationDiscoveryException(
        'Protected Resource Metadata exceeds $maxMetadataBytes bytes.',
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
      'Protected Resource Metadata is not valid UTF-8.',
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

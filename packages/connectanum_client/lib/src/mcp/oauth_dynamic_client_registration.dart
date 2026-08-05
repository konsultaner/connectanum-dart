import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'authorization_discovery.dart';
import 'oauth_authorization.dart';
import 'oauth_token_exchange.dart';

const _authorizationCodeGrant = 'authorization_code';
const _refreshTokenGrant = 'refresh_token';
const _authorizationCodeResponse = 'code';
const _noClientAuthentication = 'none';
const _defaultRegistrationResponseBytes = 64 * 1024;
const _defaultRegistrationTimeout = Duration(seconds: 30);
const _controlledRegistrationHeaders = <String>{
  'accept',
  'authorization',
  'content-length',
  'content-type',
  'cookie',
  'host',
  'last-event-id',
  'transfer-encoding',
};
const _standardRegistrationResponseParameters = <String>{
  'application_type',
  'client_id',
  'client_id_issued_at',
  'client_name',
  'client_secret',
  'client_secret_expires_at',
  'client_uri',
  'grant_types',
  'logo_uri',
  'redirect_uris',
  'registration_access_token',
  'response_types',
  'scope',
  'token_endpoint_auth_method',
};

const _dynamicRegistrationStateType = 'mcp_oauth_dynamic_client_registration';
const _dynamicRegistrationStateVersion = 1;

enum McpOAuthClientApplicationType {
  native('native'),
  web('web');

  const McpOAuthClientApplicationType(this.value);

  final String value;
}

final class McpOAuthDynamicClientRegistrationRequest {
  factory McpOAuthDynamicClientRegistrationRequest.publicClient({
    required String clientName,
    required Iterable<Uri> redirectUris,
    required McpOAuthClientApplicationType applicationType,
    Uri? clientUri,
    Uri? logoUri,
    Iterable<String> scopes = const <String>[],
  }) {
    _validateClientName(clientName);
    final validatedRedirectUris = _validatedRedirectUris(
      redirectUris,
      applicationType,
    );
    if (clientUri != null) {
      _validatePresentationUri(clientUri, 'Client URI');
    }
    if (logoUri != null) {
      _validatePresentationUri(logoUri, 'Logo URI');
    }
    final validatedScopes = _validatedScopes(scopes);

    return McpOAuthDynamicClientRegistrationRequest._(
      clientName: clientName,
      redirectUris: validatedRedirectUris,
      applicationType: applicationType,
      clientUri: clientUri,
      logoUri: logoUri,
      scopes: validatedScopes,
    );
  }

  McpOAuthDynamicClientRegistrationRequest._({
    required this.clientName,
    required List<Uri> redirectUris,
    required this.applicationType,
    required this.clientUri,
    required this.logoUri,
    required List<String> scopes,
  }) : redirectUris = List<Uri>.unmodifiable(redirectUris),
       scopes = List<String>.unmodifiable(scopes);

  final String clientName;
  final List<Uri> redirectUris;
  final McpOAuthClientApplicationType applicationType;
  final Uri? clientUri;
  final Uri? logoUri;
  final List<String> scopes;

  Map<String, Object?> toJson() {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'client_name': clientName,
      'redirect_uris': List<String>.unmodifiable(
        redirectUris.map((uri) => uri.toString()),
      ),
      'token_endpoint_auth_method': _noClientAuthentication,
      'grant_types': const <String>[
        _authorizationCodeGrant,
        _refreshTokenGrant,
      ],
      'response_types': const <String>[_authorizationCodeResponse],
      'application_type': applicationType.value,
      if (clientUri != null) 'client_uri': clientUri.toString(),
      if (logoUri != null) 'logo_uri': logoUri.toString(),
      if (scopes.isNotEmpty) 'scope': scopes.join(' '),
    });
  }
}

final class McpOAuthDynamicClientRegistration {
  McpOAuthDynamicClientRegistration._({
    required this.clientId,
    required this.clientIdIssuedAt,
    required this.clientName,
    required List<Uri> redirectUris,
    required this.applicationType,
    required this.clientUri,
    required this.logoUri,
    required List<String> scopes,
    required List<String> grantTypes,
    required List<String> responseTypes,
    required this.authorizationServer,
    required Map<String, Object?> additionalParameters,
  }) : redirectUris = List<Uri>.unmodifiable(redirectUris),
       scopes = List<String>.unmodifiable(scopes),
       grantTypes = List<String>.unmodifiable(grantTypes),
       responseTypes = List<String>.unmodifiable(responseTypes),
       additionalParameters = Map<String, Object?>.unmodifiable(
         additionalParameters,
       );

  /// Revalidates a versioned public-client registration document.
  ///
  /// When [expectedAuthorizationServerIssuer] is provided, restoration fails
  /// unless it exactly matches the issuer stored with the client identity.
  factory McpOAuthDynamicClientRegistration.fromJson(
    Map<String, Object?> json, {
    Uri? expectedAuthorizationServerIssuer,
  }) {
    try {
      if (json['type'] != _dynamicRegistrationStateType) {
        throw const McpOAuthClientRegistrationStateException(
          'Persisted OAuth client registration has an unsupported document '
          'type.',
        );
      }
      if (json['version'] != _dynamicRegistrationStateVersion) {
        throw const McpOAuthClientRegistrationStateException(
          'Persisted OAuth client registration has an unsupported schema '
          'version.',
        );
      }

      final authorizationServer = McpAuthorizationServerMetadata.fromJson(
        _registrationStateObject(json, 'authorization_server'),
      );
      if (expectedAuthorizationServerIssuer != null &&
          authorizationServer.issuer.toString() !=
              expectedAuthorizationServerIssuer.toString()) {
        throw const McpOAuthClientRegistrationStateException(
          'Persisted OAuth client registration belongs to a different '
          'authorization server.',
        );
      }
      final endpoint = authorizationServer.registrationEndpoint;
      if (endpoint == null) {
        throw const McpOAuthClientRegistrationStateException(
          'Persisted OAuth client registration has no registration endpoint.',
        );
      }

      final registrationJson = _registrationStateObject(json, 'registration');
      if (registrationJson['registration_access_token'] != null) {
        throw const McpOAuthClientRegistrationStateException(
          'Persisted OAuth client registration contains unsupported '
          'management credentials.',
        );
      }
      final applicationType = _registrationStateApplicationType(
        registrationJson,
      );
      final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
        clientName: _requiredPrintableString(
          registrationJson,
          'client_name',
          endpoint: endpoint,
        ),
        redirectUris: _requiredUriList(
          registrationJson,
          'redirect_uris',
          endpoint: endpoint,
          applicationType: applicationType,
        ),
        applicationType: applicationType,
        clientUri: _optionalPresentationUri(
          registrationJson,
          'client_uri',
          endpoint: endpoint,
        ),
        logoUri: _optionalPresentationUri(
          registrationJson,
          'logo_uri',
          endpoint: endpoint,
        ),
        scopes: _responseScopes(registrationJson, endpoint),
      );
      return _registrationFromJson(
        registrationJson,
        endpoint: endpoint,
        authorizationServer: authorizationServer,
        request: request,
      );
    } on McpOAuthClientRegistrationStateException {
      rethrow;
    } on Object {
      throw const McpOAuthClientRegistrationStateException(
        'Persisted OAuth client registration is invalid.',
      );
    }
  }

  final String clientId;
  final int? clientIdIssuedAt;
  final String clientName;
  final List<Uri> redirectUris;
  final McpOAuthClientApplicationType applicationType;
  final Uri? clientUri;
  final Uri? logoUri;
  final List<String> scopes;
  final List<String> grantTypes;
  final List<String> responseTypes;
  final McpAuthorizationServerMetadata authorizationServer;
  final Map<String, Object?> additionalParameters;

  McpOAuthClientAuthentication get clientAuthentication =>
      McpOAuthClientAuthentication.none(clientId);

  McpAuthorizationRequest createAuthorizationRequest({
    required Uri resource,
    required Uri redirectUri,
    Iterable<String>? scopes,
    McpPkcePair? pkce,
  }) {
    final redirectValue = redirectUri.toString();
    if (!redirectUris.any((uri) => uri.toString() == redirectValue)) {
      throw const McpOAuthClientRegistrationException(
        'Redirect URI is not present in the dynamic client registration.',
      );
    }
    final selectedScopes = _validatedScopes(scopes ?? this.scopes);
    if (this.scopes.isNotEmpty &&
        selectedScopes.any((scope) => !this.scopes.contains(scope))) {
      throw const McpOAuthClientRegistrationException(
        'Authorization scopes must not exceed the dynamic client '
        'registration.',
      );
    }
    return createMcpAuthorizationRequest(
      authorizationServer: authorizationServer,
      resource: resource,
      clientId: clientId,
      redirectUri: redirectUri,
      scopes: selectedScopes,
      pkce: pkce,
    );
  }

  /// Returns a versioned JSON-compatible registration document.
  ///
  /// The document keeps the issued identity associated with its validated
  /// authorization-server metadata. Store it only in caller-selected durable
  /// storage and do not log extension parameters.
  Map<String, Object?> toJson() {
    final registrationJson = <String, Object?>{
      ..._copyRegistrationStateJsonObject(additionalParameters),
      'client_id': clientId,
      if (clientIdIssuedAt != null) 'client_id_issued_at': clientIdIssuedAt,
      'client_name': clientName,
      'redirect_uris': List<String>.unmodifiable(
        redirectUris.map((uri) => uri.toString()),
      ),
      'token_endpoint_auth_method': _noClientAuthentication,
      'grant_types': grantTypes,
      'response_types': responseTypes,
      'application_type': applicationType.value,
      if (clientUri != null) 'client_uri': clientUri.toString(),
      if (logoUri != null) 'logo_uri': logoUri.toString(),
      if (scopes.isNotEmpty) 'scope': scopes.join(' '),
    };
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'type': _dynamicRegistrationStateType,
      'version': _dynamicRegistrationStateVersion,
      'authorization_server': _copyRegistrationStateJsonObject(
        authorizationServer.toJson(),
      ),
      'registration': Map<String, Object?>.unmodifiable(registrationJson),
    });
  }

  @override
  String toString() {
    return 'McpOAuthDynamicClientRegistration('
        'public client, redirects: ${redirectUris.length})';
  }
}

/// A redacted persisted dynamic-registration validation failure.
final class McpOAuthClientRegistrationStateException implements Exception {
  const McpOAuthClientRegistrationStateException(this.message);

  final String message;

  @override
  String toString() => 'McpOAuthClientRegistrationStateException: $message';
}

final class McpOAuthClientRegistrationException implements Exception {
  const McpOAuthClientRegistrationException(
    this.message, {
    this.endpoint,
    this.statusCode,
    this.registrationError,
    this.errorDescription,
  });

  final String message;
  final Uri? endpoint;
  final int? statusCode;
  final String? registrationError;
  final String? errorDescription;

  @override
  String toString() {
    final buffer = StringBuffer(
      'McpOAuthClientRegistrationException: $message',
    );
    if (registrationError != null) {
      buffer.write(' (error: $registrationError)');
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

/// Registers a public OAuth client through the advertised RFC 7591 endpoint.
///
/// [onRequestOpened] observes the request before it is sent so an owning client
/// can bind it to a larger lifecycle.
Future<McpOAuthDynamicClientRegistration> registerMcpOAuthClient({
  required McpAuthorizationServerMetadata authorizationServer,
  required McpOAuthDynamicClientRegistrationRequest registration,
  String? initialAccessToken,
  HttpClient? httpClient,
  Map<String, String> headers = const <String, String>{},
  Duration timeout = _defaultRegistrationTimeout,
  int maxResponseBytes = _defaultRegistrationResponseBytes,
  void Function(HttpClientRequest request)? onRequestOpened,
}) async {
  final endpoint = authorizationServer.registrationEndpoint;
  if (endpoint == null) {
    throw McpOAuthClientRegistrationException(
      'Authorization server does not advertise a dynamic client '
      'registration endpoint.',
      endpoint: authorizationServer.issuer,
    );
  }
  _validateRegistrationInputs(
    endpoint: endpoint,
    initialAccessToken: initialAccessToken,
    headers: headers,
    timeout: timeout,
    maxResponseBytes: maxResponseBytes,
  );

  final encodedBody = utf8.encode(jsonEncode(registration.toJson()));
  final client = httpClient ?? HttpClient();
  final ownsClient = httpClient == null;
  final deadline = DateTime.now().add(timeout);
  HttpClientRequest? request;

  try {
    request = await client
        .postUrl(endpoint)
        .timeout(_remaining(deadline, endpoint));
    try {
      onRequestOpened?.call(request);
    } catch (error) {
      request.abort(error);
      rethrow;
    }
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (initialAccessToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $initialAccessToken',
      );
    }
    request.contentLength = encodedBody.length;
    request.add(encodedBody);

    final response = await request.close().timeout(
      _remaining(deadline, endpoint),
    );
    final body = await _readRegistrationResponse(
      response,
      endpoint: endpoint,
      maxResponseBytes: maxResponseBytes,
    ).timeout(_remaining(deadline, endpoint));
    final registrationResponse = _ClientRegistrationResponse(
      statusCode: response.statusCode,
      mimeType: response.headers.contentType?.mimeType,
      body: body,
    );
    return _parseRegistrationResponse(
      registrationResponse,
      endpoint: endpoint,
      authorizationServer: authorizationServer,
      request: registration,
    );
  } on McpOAuthClientRegistrationException {
    rethrow;
  } on TimeoutException {
    request?.abort();
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration request timed out.',
      endpoint: endpoint,
    );
  } on Object {
    request?.abort();
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration request failed.',
      endpoint: endpoint,
    );
  } finally {
    if (ownsClient) {
      client.close(force: true);
    }
  }
}

final class _ClientRegistrationResponse {
  const _ClientRegistrationResponse({
    required this.statusCode,
    required this.mimeType,
    required this.body,
  });

  final int statusCode;
  final String? mimeType;
  final Uint8List body;
}

McpOAuthDynamicClientRegistration _parseRegistrationResponse(
  _ClientRegistrationResponse response, {
  required Uri endpoint,
  required McpAuthorizationServerMetadata authorizationServer,
  required McpOAuthDynamicClientRegistrationRequest request,
}) {
  if (response.mimeType?.toLowerCase() != 'application/json') {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration response must use application/json.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }

  late final String body;
  try {
    body = utf8.decode(response.body);
  } on FormatException {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration response is not valid UTF-8.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }

  late final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration response is not valid JSON.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
  if (decoded is! Map) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration response must be a JSON object.',
      endpoint: endpoint,
      statusCode: response.statusCode,
    );
  }
  final json = decoded.cast<String, Object?>();
  if (response.statusCode != HttpStatus.created) {
    _throwRegistrationError(json, response.statusCode, endpoint);
  }

  return _registrationFromJson(
    json,
    endpoint: endpoint,
    authorizationServer: authorizationServer,
    request: request,
  );
}

McpOAuthDynamicClientRegistration _registrationFromJson(
  Map<String, Object?> json, {
  required Uri endpoint,
  required McpAuthorizationServerMetadata authorizationServer,
  required McpOAuthDynamicClientRegistrationRequest request,
}) {
  final clientId = _requiredPrintableString(
    json,
    'client_id',
    endpoint: endpoint,
  );
  if (json['client_secret'] != null ||
      json['client_secret_expires_at'] != null) {
    throw McpOAuthClientRegistrationException(
      'Authorization server returned confidential-client credentials for a '
      'public registration.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  final tokenEndpointAuthMethod = _requiredPrintableString(
    json,
    'token_endpoint_auth_method',
    endpoint: endpoint,
  );
  if (tokenEndpointAuthMethod != _noClientAuthentication) {
    throw McpOAuthClientRegistrationException(
      'Authorization server did not preserve public token endpoint '
      'authentication.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final redirectUris = _requiredUriList(
    json,
    'redirect_uris',
    endpoint: endpoint,
    applicationType: request.applicationType,
  );
  final requestedRedirects = request.redirectUris
      .map((uri) => uri.toString())
      .toSet();
  final returnedRedirects = redirectUris.map((uri) => uri.toString()).toSet();
  if (requestedRedirects.length != returnedRedirects.length ||
      !requestedRedirects.containsAll(returnedRedirects)) {
    throw McpOAuthClientRegistrationException(
      'Authorization server changed the requested redirect registration.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final clientName = _requiredPrintableString(
    json,
    'client_name',
    endpoint: endpoint,
  );
  if (clientName != request.clientName) {
    throw McpOAuthClientRegistrationException(
      'Authorization server changed the requested client name.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final grantTypes = _requiredStringList(
    json,
    'grant_types',
    endpoint: endpoint,
  );
  if (!grantTypes.contains(_authorizationCodeGrant)) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration must include the authorization_code '
      'grant.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  final responseTypes = _requiredStringList(
    json,
    'response_types',
    endpoint: endpoint,
  );
  if (!responseTypes.contains(_authorizationCodeResponse)) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration must include the code response type.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final applicationTypeValue = json['application_type'];
  if (applicationTypeValue != null &&
      applicationTypeValue != request.applicationType.value) {
    throw McpOAuthClientRegistrationException(
      'Authorization server changed the requested application type.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final clientUri = _optionalPresentationUri(
    json,
    'client_uri',
    endpoint: endpoint,
  );
  final logoUri = _optionalPresentationUri(
    json,
    'logo_uri',
    endpoint: endpoint,
  );
  if (clientUri != request.clientUri || logoUri != request.logoUri) {
    throw McpOAuthClientRegistrationException(
      'Authorization server changed requested client presentation metadata.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final scopes = _responseScopes(json, endpoint);
  if (request.scopes.isNotEmpty &&
      (scopes.length != request.scopes.length ||
          !request.scopes.toSet().containsAll(scopes))) {
    throw McpOAuthClientRegistrationException(
      'Authorization server changed the requested OAuth scopes.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  final clientIdIssuedAtValue = json['client_id_issued_at'];
  if (clientIdIssuedAtValue != null &&
      (clientIdIssuedAtValue is! int || clientIdIssuedAtValue < 0)) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration client_id_issued_at must be a '
      'non-negative integer.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }

  return McpOAuthDynamicClientRegistration._(
    clientId: clientId,
    clientIdIssuedAt: clientIdIssuedAtValue as int?,
    clientName: clientName,
    redirectUris: redirectUris,
    applicationType: request.applicationType,
    clientUri: clientUri,
    logoUri: logoUri,
    scopes: scopes,
    grantTypes: grantTypes,
    responseTypes: responseTypes,
    authorizationServer: authorizationServer,
    additionalParameters: <String, Object?>{
      for (final entry in json.entries)
        if (!_standardRegistrationResponseParameters.contains(entry.key))
          entry.key: entry.value,
    },
  );
}

McpOAuthClientApplicationType _registrationStateApplicationType(
  Map<String, Object?> json,
) {
  final value = json['application_type'];
  for (final candidate in McpOAuthClientApplicationType.values) {
    if (candidate.value == value) {
      return candidate;
    }
  }
  throw const McpOAuthClientRegistrationStateException(
    'Persisted OAuth client registration application type is invalid.',
  );
}

Map<String, Object?> _registrationStateObject(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! Map) {
    throw McpOAuthClientRegistrationStateException(
      'Persisted OAuth client registration field "$key" must be a JSON '
      'object.',
    );
  }
  return _copyRegistrationStateJsonObject(value);
}

Map<String, Object?> _copyRegistrationStateJsonObject(Map source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const McpOAuthClientRegistrationStateException(
        'Persisted OAuth client registration contains a non-string JSON key.',
      );
    }
    result[key] = _copyRegistrationStateJsonValue(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}

Object? _copyRegistrationStateJsonValue(Object? value) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw const McpOAuthClientRegistrationStateException(
        'Persisted OAuth client registration contains a non-finite number.',
      );
    }
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map<Object?>(_copyRegistrationStateJsonValue),
    );
  }
  if (value is Map) {
    return _copyRegistrationStateJsonObject(value);
  }
  throw const McpOAuthClientRegistrationStateException(
    'Persisted OAuth client registration contains a non-JSON value.',
  );
}

void _validateRegistrationInputs({
  required Uri endpoint,
  required String? initialAccessToken,
  required Map<String, String> headers,
  required Duration timeout,
  required int maxResponseBytes,
}) {
  if (initialAccessToken != null && !_credentialValid(initialAccessToken)) {
    throw McpOAuthClientRegistrationException(
      'Initial access token must be non-empty and contain no whitespace or '
      'control characters.',
      endpoint: endpoint,
    );
  }
  if (timeout <= Duration.zero) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration timeout must be positive.',
      endpoint: endpoint,
    );
  }
  if (maxResponseBytes <= 0) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration response byte limit must be positive.',
      endpoint: endpoint,
    );
  }
  for (final entry in headers.entries) {
    final name = entry.key.trim().toLowerCase();
    if (name.isEmpty ||
        entry.key != entry.key.trim() ||
        _controlledRegistrationHeaders.contains(name) ||
        name.startsWith('mcp-')) {
      throw McpOAuthClientRegistrationException(
        'Header "${entry.key}" is controlled by dynamic client '
        'registration.',
        endpoint: endpoint,
      );
    }
    if (entry.value.codeUnits.any((value) => value < 0x20 || value == 0x7f)) {
      throw McpOAuthClientRegistrationException(
        'Header "${entry.key}" contains control characters.',
        endpoint: endpoint,
      );
    }
  }
}

Future<Uint8List> _readRegistrationResponse(
  HttpClientResponse response, {
  required Uri endpoint,
  required int maxResponseBytes,
}) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response) {
    length += chunk.length;
    if (length > maxResponseBytes) {
      throw McpOAuthClientRegistrationException(
        'Dynamic client registration response exceeds $maxResponseBytes '
        'bytes.',
        endpoint: endpoint,
        statusCode: response.statusCode,
      );
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Duration _remaining(DateTime deadline, Uri endpoint) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration request timed out.',
      endpoint: endpoint,
    );
  }
  return remaining;
}

Never _throwRegistrationError(
  Map<String, Object?> json,
  int statusCode,
  Uri endpoint,
) {
  final error = json['error'];
  final description = json['error_description'];
  if (error is! String || !_oauthNqsCharValid(error)) {
    throw McpOAuthClientRegistrationException(
      'Authorization server returned an invalid client registration error.',
      endpoint: endpoint,
      statusCode: statusCode,
    );
  }
  if (description != null &&
      (description is! String || !_oauthNqsCharValid(description))) {
    throw McpOAuthClientRegistrationException(
      'Authorization server returned an invalid registration '
      'error_description.',
      endpoint: endpoint,
      statusCode: statusCode,
      registrationError: error,
    );
  }
  throw McpOAuthClientRegistrationException(
    'Authorization server rejected dynamic client registration.',
    endpoint: endpoint,
    statusCode: statusCode,
    registrationError: error,
    errorDescription: description as String?,
  );
}

String _requiredPrintableString(
  Map<String, Object?> json,
  String name, {
  required Uri endpoint,
}) {
  final value = json[name];
  if (value is! String || !_printableNonEmpty(value)) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration $name must be non-empty printable text.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  return value;
}

List<String> _requiredStringList(
  Map<String, Object?> json,
  String name, {
  required Uri endpoint,
}) {
  final value = json[name];
  if (value is! List || value.isEmpty || value.any((item) => item is! String)) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration $name must be a non-empty string array.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  final values = value.cast<String>();
  if (values.any((item) => !_printableNonEmpty(item)) ||
      values.toSet().length != values.length) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration $name contains invalid or duplicate '
      'values.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  return values;
}

List<Uri> _requiredUriList(
  Map<String, Object?> json,
  String name, {
  required Uri endpoint,
  required McpOAuthClientApplicationType applicationType,
}) {
  final values = _requiredStringList(json, name, endpoint: endpoint);
  final uris = <Uri>[];
  for (final value in values) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      throw McpOAuthClientRegistrationException(
        'Dynamic client registration $name contains an invalid URI.',
        endpoint: endpoint,
        statusCode: HttpStatus.created,
      );
    }
    _validateRedirectUri(uri, applicationType);
    uris.add(uri);
  }
  return uris;
}

Uri? _optionalPresentationUri(
  Map<String, Object?> json,
  String name, {
  required Uri endpoint,
}) {
  final value = json[name];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration $name must be a URL string.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration $name must be a valid URL.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  _validatePresentationUri(uri, name);
  return uri;
}

List<String> _responseScopes(Map<String, Object?> json, Uri endpoint) {
  final value = json['scope'];
  if (value == null) {
    return const <String>[];
  }
  if (value is! String || value.isEmpty) {
    throw McpOAuthClientRegistrationException(
      'Dynamic client registration scope must be a non-empty OAuth scope '
      'string.',
      endpoint: endpoint,
      statusCode: HttpStatus.created,
    );
  }
  return _validatedScopes(value.split(' '));
}

void _validateClientName(String clientName) {
  if (!_printableNonEmpty(clientName)) {
    throw const McpOAuthClientRegistrationException(
      'Client name must be non-empty and must not contain control characters.',
    );
  }
}

List<Uri> _validatedRedirectUris(
  Iterable<Uri> redirectUris,
  McpOAuthClientApplicationType applicationType,
) {
  final validated = <Uri>[];
  final values = <String>{};
  for (final redirectUri in redirectUris) {
    _validateRedirectUri(redirectUri, applicationType);
    if (!values.add(redirectUri.toString())) {
      throw const McpOAuthClientRegistrationException(
        'Redirect URIs must be unique.',
      );
    }
    validated.add(redirectUri);
  }
  if (validated.isEmpty) {
    throw const McpOAuthClientRegistrationException(
      'At least one redirect URI is required.',
    );
  }
  return validated;
}

void _validateRedirectUri(
  Uri redirectUri,
  McpOAuthClientApplicationType applicationType,
) {
  final secure = redirectUri.scheme.toLowerCase() == 'https';
  final loopback =
      redirectUri.scheme.toLowerCase() == 'http' &&
      _isLoopbackHost(redirectUri.host);
  if (!redirectUri.hasAuthority ||
      redirectUri.host.isEmpty ||
      redirectUri.userInfo.isNotEmpty ||
      redirectUri.hasFragment ||
      (!secure && !loopback) ||
      (applicationType == McpOAuthClientApplicationType.web && !secure)) {
    throw const McpOAuthClientRegistrationException(
      'Redirect URI must use HTTPS or native loopback HTTP and must not '
      'contain userinfo or a fragment.',
    );
  }
}

void _validatePresentationUri(Uri uri, String label) {
  if (uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw McpOAuthClientRegistrationException(
      '$label must be an HTTPS URL without userinfo or a fragment.',
    );
  }
}

List<String> _validatedScopes(Iterable<String> scopes) {
  final validated = <String>[];
  final seen = <String>{};
  for (final scope in scopes) {
    if (!_scopeTokenValid(scope)) {
      throw const McpOAuthClientRegistrationException(
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

bool _credentialValid(String value) {
  return value.isNotEmpty &&
      value.codeUnits.every((unit) => unit > 0x20 && unit != 0x7f);
}

bool _printableNonEmpty(String value) {
  return value.trim().isNotEmpty &&
      value.runes.every((rune) => rune >= 0x20 && rune != 0x7f);
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
  if (host.toLowerCase() == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback ?? false;
}

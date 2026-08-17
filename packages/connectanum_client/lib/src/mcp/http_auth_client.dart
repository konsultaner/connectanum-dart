import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';

import 'authorization_discovery.dart';

typedef _HttpAuthRequestOpener = Future<HttpClientRequest> Function();

abstract interface class _PendingHttpAuthOperation {
  void reject(Object error, StackTrace stackTrace);
}

final class _PendingHttpAuthOperationHandle<T>
    implements _PendingHttpAuthOperation {
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  void complete(T value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }

  @override
  void reject(Object error, StackTrace stackTrace) {
    completeError(error, stackTrace);
  }
}

/// Dart IO client for Connectanum router HTTP auth bridge endpoints.
///
/// The router auth bridge exposes WAMP challenge/response authenticators over a
/// JSON HTTP endpoint. This helper keeps that handshake in the public client
/// package so protected router-hosted MCP routes can be used without
/// reimplementing the token flow in each consumer application. Every complete
/// issue, challenge, refresh, or revoke operation shares [requestTimeout], and
/// each response is limited to [maxResponseBytes] before UTF-8/JSON decoding.
final class ConnectanumHttpAuthClient {
  static const Duration defaultRequestTimeout = Duration(seconds: 30);
  static const int defaultMaxResponseBytes = 64 * 1024;

  ConnectanumHttpAuthClient(
    this.endpoint, {
    HttpClient? httpClient,
    this.headers = const <String, String>{},
    Duration requestTimeout = defaultRequestTimeout,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) : requestTimeout = _validatedHttpAuthRequestTimeout(requestTimeout),
       maxResponseBytes = _validatedHttpAuthMaxResponseBytes(maxResponseBytes),
       _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null || closeHttpClient;

  /// Creates an auth bridge client from a router-hosted MCP Bearer challenge.
  ///
  /// The advertised `auth_path` must be an absolute path on the MCP
  /// endpoint's own HTTP(S) origin. Authority, query, and fragment components
  /// are rejected so credentials cannot be redirected or mixed with
  /// challenge-controlled URL data.
  factory ConnectanumHttpAuthClient.fromMcpBearerChallenge(
    Uri mcpEndpoint,
    McpBearerChallenge challenge, {
    HttpClient? httpClient,
    Map<String, String> headers = const <String, String>{},
    Duration requestTimeout = defaultRequestTimeout,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) {
    return ConnectanumHttpAuthClient(
      _resolveConnectanumHttpAuthEndpoint(mcpEndpoint, challenge),
      httpClient: httpClient,
      headers: headers,
      requestTimeout: requestTimeout,
      maxResponseBytes: maxResponseBytes,
      closeHttpClient: closeHttpClient,
    );
  }

  final Uri endpoint;
  final Map<String, String> headers;

  /// One total deadline for a complete operation, including challenge work.
  final Duration requestTimeout;

  /// Maximum raw bytes accepted for each HTTP auth response.
  final int maxResponseBytes;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final Set<HttpClientRequest> _pendingRequests = <HttpClientRequest>{};
  final Set<_PendingHttpAuthOperation> _pendingOperations =
      <_PendingHttpAuthOperation>{};
  bool _closed = false;

  Future<ConnectanumHttpAuthGrant> issueTicketToken({
    required String realm,
    required String authId,
    required String ticket,
    Map<String, String> headers = const <String, String>{},
  }) {
    return authenticate(
      realm: realm,
      authId: authId,
      authentication: TicketAuthentication(ticket),
      authMethod: 'ticket',
      headers: headers,
    );
  }

  Future<ConnectanumHttpAuthGrant> issueWampCraToken({
    required String realm,
    required String authId,
    required String secret,
    Map<String, String> headers = const <String, String>{},
  }) {
    return authenticate(
      realm: realm,
      authId: authId,
      authentication: CraAuthentication(secret),
      authMethod: 'wampcra',
      headers: headers,
    );
  }

  Future<ConnectanumHttpAuthGrant> issueScramToken({
    required String realm,
    required String authId,
    required String secret,
    Map<String, String> headers = const <String, String>{},
  }) {
    return authenticate(
      realm: realm,
      authId: authId,
      authentication: ScramAuthentication(secret),
      authMethod: 'scram',
      headers: headers,
    );
  }

  Future<ConnectanumHttpAuthGrant> authenticate({
    required String realm,
    required String authId,
    required AbstractAuthentication authentication,
    String? authMethod,
    Map<String, Object?> authextra = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
  }) {
    return _runTrackedOperation((openRequest) async {
      final requestRealm = _nonEmptyArgument(realm, 'realm');
      final requestAuthId = _nonEmptyArgument(authId, 'authId');
      final method = _httpAuthMethodName(
        authMethod ?? authentication.getName(),
      );
      final details = Details.forHello()
        ..authid = requestAuthId
        ..authmethods = <String>[method];
      if (authextra.isNotEmpty) {
        details.authextra = Map<String, dynamic>.from(authextra);
      }
      await authentication.hello(requestRealm, details);

      final startBody = <String, Object?>{
        'realm': requestRealm,
        'authmethod': method,
        'authid': requestAuthId,
        if (details.authextra != null && details.authextra!.isNotEmpty)
          'authextra': Map<String, Object?>.from(details.authextra!),
      };
      final challenge = await _postJsonObject(
        startBody,
        expectedStatus: HttpStatus.unauthorized,
        label: 'HTTP auth challenge',
        extraHeaders: headers,
        openRequest: openRequest,
      );
      _validateAuthResponseIdentity(
        challenge,
        label: 'HTTP auth challenge',
        realm: requestRealm,
        authMethod: method,
      );
      final state = _nonEmptyString(challenge['state'], 'state');
      final authenticate = await authentication.challenge(
        _challengeExtraFrom(challenge['challenge']),
      );

      final grant = await _postJsonObject(
        <String, Object?>{
          'state': state,
          if (authenticate.signature != null)
            'signature': authenticate.signature,
          if (authenticate.extra != null)
            'extra': Map<String, Object?>.from(authenticate.extra!),
        },
        expectedStatus: HttpStatus.ok,
        label: 'HTTP auth token request',
        extraHeaders: headers,
        openRequest: openRequest,
      );
      final parsedGrant = ConnectanumHttpAuthGrant.fromJson(grant);
      _validateAuthResponseIdentity(
        grant,
        label: 'HTTP auth grant',
        realm: requestRealm,
        authMethod: method,
        authId: requestAuthId,
      );
      return parsedGrant;
    });
  }

  Future<ConnectanumHttpAuthGrant> refreshToken(
    String refreshToken, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return _runTrackedOperation((openRequest) {
      final token = _nonEmptyToken(refreshToken, 'refreshToken');
      return _requestRefreshToken(
        token,
        headers: headers,
        openRequest: openRequest,
      );
    });
  }

  /// Refreshes [grant] while requiring the replacement authorization lineage
  /// to match it exactly.
  ///
  /// Use [refreshToken] only when the caller intentionally has no prior grant
  /// metadata to bind.
  Future<ConnectanumHttpAuthGrant> refreshGrant(
    ConnectanumHttpAuthGrant grant, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return _runTrackedOperation((openRequest) async {
      final token = grant.refreshToken;
      if (token == null) {
        throw ArgumentError(
          'grant.refreshToken must contain a usable refresh token.',
        );
      }
      final requestRefreshToken = _nonEmptyToken(token, 'grant.refreshToken');
      final realm = _requiredGrantLineageField(grant.realm, 'grant.realm');
      final authMethod = _requiredGrantLineageField(
        grant.authMethod,
        'grant.authMethod',
      );
      final authId = _requiredGrantLineageField(grant.authId, 'grant.authId');
      final authRole = _requiredGrantLineageField(
        grant.authRole,
        'grant.authRole',
      );
      final tokenType = _nonEmptyArgument(grant.tokenType, 'grant.tokenType');
      if (tokenType.toLowerCase() != 'bearer') {
        throw ArgumentError(
          'grant.tokenType must use the Bearer authentication scheme.',
        );
      }
      final authProvider = grant.authProvider;
      if (authProvider != null) {
        _nonEmptyArgument(authProvider, 'grant.authProvider');
      }

      final refreshed = await _requestRefreshToken(
        requestRefreshToken,
        headers: headers,
        openRequest: openRequest,
      );
      _validateRefreshedGrantLineage(
        refreshed,
        realm: realm,
        authMethod: authMethod,
        authId: authId,
        authRole: authRole,
        authProvider: authProvider,
        details: grant.details,
      );
      return refreshed;
    });
  }

  Future<ConnectanumHttpAuthGrant> _requestRefreshToken(
    String token, {
    required Map<String, String> headers,
    required _HttpAuthRequestOpener openRequest,
  }) async {
    final grant = await _postJsonObject(
      <String, Object?>{
        'grant_type': 'refresh_token',
        'refresh_token': token,
      },
      expectedStatus: HttpStatus.ok,
      label: 'HTTP auth refresh request',
      extraHeaders: headers,
      openRequest: openRequest,
    );
    return ConnectanumHttpAuthGrant.fromJson(grant);
  }

  Future<void> revokeToken(
    String token, {
    String? tokenTypeHint,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _runTrackedOperation((openRequest) async {
      final revokeToken = _nonEmptyToken(token, 'token');
      final revokeTokenTypeHint = _optionalTokenTypeHint(tokenTypeHint);
      final request = <String, Object?>{
        'grant_type': 'revoke',
        'token': revokeToken,
      };
      if (revokeTokenTypeHint != null) {
        request['token_type_hint'] = revokeTokenTypeHint;
      }
      await _postJsonObject(
        request,
        expectedStatus: HttpStatus.ok,
        label: 'HTTP auth revoke request',
        extraHeaders: headers,
        openRequest: openRequest,
      );
    });
  }

  void close({bool force = false}) {
    if (_closed) {
      return;
    }
    _closed = true;

    final error = _closedError();
    final stackTrace = StackTrace.current;
    final operations = List<_PendingHttpAuthOperation>.of(_pendingOperations);
    final requests = List<HttpClientRequest>.of(_pendingRequests);
    _pendingOperations.clear();
    _pendingRequests.clear();
    for (final operation in operations) {
      operation.reject(error, stackTrace);
    }
    for (final request in requests) {
      request.abort(error, stackTrace);
    }
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  Future<T> _runTrackedOperation<T>(
    Future<T> Function(_HttpAuthRequestOpener openRequest) operation,
  ) {
    if (_closed) {
      return Future<T>.error(_closedError(), StackTrace.current);
    }

    final pending = _PendingHttpAuthOperationHandle<T>();
    final operationRequests = <HttpClientRequest>{};
    final timeoutError = TimeoutException(
      'Connectanum HTTP auth operation exceeded '
      '${requestTimeout.inMilliseconds} ms.',
      requestTimeout,
    );
    var timedOut = false;
    _pendingOperations.add(pending);

    Future<HttpClientRequest> openRequest() async {
      if (_closed) {
        throw _closedError();
      }
      if (timedOut) {
        throw timeoutError;
      }
      final request = await _httpClient.postUrl(endpoint);
      if (_closed || timedOut) {
        final error = _closed ? _closedError() : timeoutError;
        request.abort(error, StackTrace.current);
        throw error;
      }
      operationRequests.add(request);
      _pendingRequests.add(request);
      return request;
    }

    late final Timer timer;
    void finishPending() {
      timer.cancel();
      _pendingOperations.remove(pending);
      operationRequests.clear();
    }

    timer = Timer(requestTimeout, () {
      timedOut = true;
      final stackTrace = StackTrace.current;
      for (final request in operationRequests) {
        if (_pendingRequests.remove(request)) {
          request.abort(timeoutError, stackTrace);
        }
      }
      pending.reject(timeoutError, stackTrace);
    });

    unawaited(
      pending.future.then<void>(
        (_) => finishPending(),
        onError: (Object _, StackTrace _) => finishPending(),
      ),
    );

    unawaited(
      Future<T>.sync(() => operation(openRequest))
          .then<void>(
            pending.complete,
            onError: (Object error, StackTrace stackTrace) {
              pending.completeError(error, stackTrace);
            },
          )
          .whenComplete(() {
            for (final request in operationRequests) {
              _pendingRequests.remove(request);
            }
          }),
    );
    return pending.future;
  }

  StateError _closedError() {
    return StateError('ConnectanumHttpAuthClient is closed.');
  }

  Future<Map<String, Object?>> _postJsonObject(
    Map<String, Object?> payload, {
    required int expectedStatus,
    required String label,
    required _HttpAuthRequestOpener openRequest,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final request = await openRequest();
    try {
      request.followRedirects = false;
      void applyConsumerHeaders(Map<String, String> source) {
        for (final header in source.entries) {
          if (_isControlledHttpAuthRequestHeader(header.key)) {
            continue;
          }
          request.headers.set(header.key, header.value);
        }
      }

      applyConsumerHeaders(headers);
      applyConsumerHeaders(extraHeaders);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final body = await _readResponseBody(response);
      Object? decoded;
      if (body.isNotEmpty) {
        try {
          decoded = jsonDecode(body);
        } on FormatException {
          if (response.statusCode == expectedStatus) {
            rethrow;
          }
        }
      }
      if (response.statusCode != expectedStatus) {
        throw ConnectanumHttpAuthException(
          statusCode: response.statusCode,
          reasonPhrase: response.reasonPhrase,
          body: body,
          error: decoded,
        );
      }
      return _jsonObject(decoded, label);
    } finally {
      _pendingRequests.remove(request);
    }
  }

  Future<String> _readResponseBody(HttpClientResponse response) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > maxResponseBytes) {
        throw ConnectanumHttpAuthProtocolException(
          'Connectanum HTTP auth response exceeds '
          '$maxResponseBytes bytes.',
        );
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  static String _httpAuthMethodName(String authMethod) {
    final method = _nonEmptyToken(authMethod, 'authMethod');
    return method == 'wamp-scram' ? 'scram' : method;
  }

  static String _nonEmptyArgument(String value, String name) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }
    if (!containsMcpWhitespaceOrControl(value)) {
      return value;
    }
    throw ArgumentError.value(
      value,
      name,
      '$name must not contain whitespace or control characters.',
    );
  }

  static void _validateAuthResponseIdentity(
    Map<String, Object?> response, {
    required String label,
    required String realm,
    required String authMethod,
    String? authId,
  }) {
    final responseRealm = _nonEmptyString(response['realm'], 'realm');
    if (responseRealm != realm) {
      throw ConnectanumHttpAuthProtocolException(
        '$label realm does not match the authentication request.',
      );
    }

    final responseAuthMethod = _nonEmptyString(
      response['authmethod'],
      'authmethod',
    );
    if (responseAuthMethod != authMethod) {
      throw ConnectanumHttpAuthProtocolException(
        '$label authmethod does not match the authentication request.',
      );
    }

    if (authId == null) {
      return;
    }
    final responseAuthId = _nonEmptyString(response['authid'], 'authid');
    if (responseAuthId != authId) {
      throw ConnectanumHttpAuthProtocolException(
        '$label authid does not match the authentication request.',
      );
    }
  }

  static String _requiredGrantLineageField(String? value, String name) {
    if (value == null) {
      throw ArgumentError('$name must be present on a grant-aware refresh.');
    }
    return _nonEmptyArgument(value, name);
  }

  static void _validateRefreshedGrantLineage(
    ConnectanumHttpAuthGrant grant, {
    required String realm,
    required String authMethod,
    required String authId,
    required String authRole,
    required String? authProvider,
    required Map<String, Object?> details,
  }) {
    if (grant.tokenType.toLowerCase() != 'bearer') {
      _throwRefreshLineageMismatch('token_type');
    }
    if (_requiredRefreshedGrantField(grant.realm, 'realm') != realm) {
      _throwRefreshLineageMismatch('realm');
    }
    if (_requiredRefreshedGrantField(grant.authMethod, 'authmethod') !=
        authMethod) {
      _throwRefreshLineageMismatch('authmethod');
    }
    if (_requiredRefreshedGrantField(grant.authId, 'authid') != authId) {
      _throwRefreshLineageMismatch('authid');
    }
    if (_requiredRefreshedGrantField(grant.authRole, 'authrole') != authRole) {
      _throwRefreshLineageMismatch('authrole');
    }
    if (grant.authProvider != authProvider) {
      _throwRefreshLineageMismatch('authprovider');
    }
    if (!_jsonValuesEqual(grant.details, details)) {
      _throwRefreshLineageMismatch('details');
    }
  }

  static String _requiredRefreshedGrantField(String? value, String name) {
    if (value == null) {
      throw FormatException(
        'HTTP auth refresh response is missing "$name".',
      );
    }
    return value;
  }

  static Never _throwRefreshLineageMismatch(String field) {
    throw ConnectanumHttpAuthProtocolException(
      'HTTP auth refreshed grant $field does not match the prior grant.',
    );
  }

  static bool _jsonValuesEqual(Object? left, Object? right) {
    if (identical(left, right)) {
      return true;
    }
    if (left is num && right is num) {
      return left == right;
    }
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index += 1) {
        if (!_jsonValuesEqual(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_jsonValuesEqual(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  static Extra _challengeExtraFrom(Object? value) {
    if (value == null) {
      return Extra();
    }
    final map = _jsonDynamicObject(value, 'HTTP auth challenge');
    for (final key in [
      'challenge',
      'salt',
      'channel_binding',
      'kdf',
      'nonce',
    ]) {
      _validateOptionalChallengeString(map, key);
    }
    for (final key in ['keylen', 'iterations', 'memory']) {
      _validateOptionalChallengeInteger(map, key);
    }
    return Extra.fromMap(map);
  }

  static void _validateOptionalChallengeString(
    Map<String, dynamic> map,
    String key,
  ) {
    final value = map[key];
    if (value != null && value is! String) {
      throw FormatException(
        'HTTP auth challenge "challenge.$key" must be a string.',
      );
    }
  }

  static void _validateOptionalChallengeInteger(
    Map<String, dynamic> map,
    String key,
  ) {
    final value = map[key];
    if (value != null && value is! int) {
      throw FormatException(
        'HTTP auth challenge "challenge.$key" must be an integer.',
      );
    }
    if (value is int && value <= 0) {
      throw FormatException(
        'HTTP auth challenge "challenge.$key" must be a positive integer.',
      );
    }
  }

  static Map<String, Object?> _jsonObject(Object? value, String label) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    throw FormatException('$label response must be a JSON object.');
  }

  static Map<String, dynamic> _jsonDynamicObject(Object? value, String label) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw FormatException('$label must be a JSON object.');
  }

  static String _nonEmptyString(Object? value, String key) {
    if (value is! String || value.isEmpty) {
      throw FormatException('HTTP auth response is missing "$key".');
    }
    if (!containsMcpWhitespaceOrControl(value)) {
      return value;
    }
    throw FormatException(
      'HTTP auth response "$key" must not contain whitespace or control characters.',
    );
  }

  static String _nonEmptyToken(String token, String name) {
    final value = token.trim();
    if (value.isNotEmpty && !containsMcpWhitespaceOrControl(value)) {
      return value;
    }
    throw ArgumentError.value(
      token,
      name,
      value.isEmpty
          ? '$name must not be empty.'
          : '$name must not contain whitespace or control characters.',
    );
  }

  static String? _optionalTokenTypeHint(String? tokenTypeHint) {
    if (tokenTypeHint == null) {
      return null;
    }
    return _nonEmptyToken(tokenTypeHint, 'tokenTypeHint');
  }
}

Uri _resolveConnectanumHttpAuthEndpoint(
  Uri mcpEndpoint,
  McpBearerChallenge challenge,
) {
  final scheme = mcpEndpoint.scheme.toLowerCase();
  if (!mcpEndpoint.isAbsolute ||
      (scheme != 'http' && scheme != 'https') ||
      mcpEndpoint.host.isEmpty ||
      mcpEndpoint.userInfo.isNotEmpty ||
      mcpEndpoint.hasFragment) {
    throw const ConnectanumHttpAuthProtocolException(
      'MCP endpoint must be an absolute credential-free HTTP(S) URI',
    );
  }

  final authPath = challenge.authPath;
  final authReference = authPath == null ? null : Uri.tryParse(authPath);
  if (authPath == null ||
      authPath.isEmpty ||
      authPath != authPath.trim() ||
      authReference == null ||
      authReference.isAbsolute ||
      authReference.hasAuthority ||
      !authReference.path.startsWith('/') ||
      authReference.hasQuery ||
      authReference.hasFragment) {
    throw const ConnectanumHttpAuthProtocolException(
      'Bearer challenge auth_path must be a same-origin absolute path',
    );
  }

  final endpoint = mcpEndpoint.resolveUri(authReference);
  if (endpoint.scheme.toLowerCase() != scheme ||
      endpoint.host.toLowerCase() != mcpEndpoint.host.toLowerCase() ||
      endpoint.port != mcpEndpoint.port) {
    throw const ConnectanumHttpAuthProtocolException(
      'Bearer challenge auth_path must preserve the MCP endpoint origin',
    );
  }
  return endpoint;
}

bool _isControlledHttpAuthRequestHeader(String name) {
  final normalized = name.toLowerCase();
  return normalized == HttpHeaders.acceptHeader ||
      normalized == HttpHeaders.contentTypeHeader ||
      normalized == HttpHeaders.contentLengthHeader;
}

final class ConnectanumHttpAuthGrant {
  const ConnectanumHttpAuthGrant({
    required this.accessToken,
    required this.tokenType,
    this.refreshToken,
    this.realm,
    this.authId,
    this.authRole,
    this.authMethod,
    this.authProvider,
    this.accessTokenExpiresIn,
    this.refreshTokenExpiresIn,
    this.details = const <String, Object?>{},
  });

  factory ConnectanumHttpAuthGrant.fromJson(Map<String, Object?> json) {
    final tokenType = _optionalToken(json, 'token_type');
    return ConnectanumHttpAuthGrant(
      accessToken: _requiredToken(json['access_token'], 'access_token'),
      tokenType: tokenType == null || tokenType.isEmpty ? 'Bearer' : tokenType,
      refreshToken: _optionalToken(json, 'refresh_token'),
      realm: _optionalString(json, 'realm'),
      authId: _optionalString(json, 'authid'),
      authRole: _optionalString(json, 'authrole'),
      authMethod: _optionalString(json, 'authmethod'),
      authProvider: _optionalString(json, 'authprovider'),
      accessTokenExpiresIn: _durationFromSeconds(json, 'expires_in'),
      refreshTokenExpiresIn: _durationFromSeconds(
        json,
        'refresh_token_expires_in',
      ),
      details: _detailsFromJson(json),
    );
  }

  final String accessToken;
  final String tokenType;
  final String? refreshToken;
  final String? realm;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final Duration? accessTokenExpiresIn;
  final Duration? refreshTokenExpiresIn;
  final Map<String, Object?> details;

  static String _requiredToken(Object? value, String key) {
    if (value == null) {
      throw FormatException('HTTP auth response is missing "$key".');
    }
    if (value is! String) {
      throw FormatException('HTTP auth response "$key" must be a string.');
    }
    final token = value.trim();
    if (token.isEmpty) {
      throw FormatException('HTTP auth response is missing "$key".');
    }
    if (containsMcpWhitespaceOrControl(token)) {
      throw FormatException(
        'HTTP auth response "$key" must not contain whitespace or control '
        'characters.',
      );
    }
    return token;
  }

  static String? _optionalToken(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    final value = json[key];
    if (value is! String) {
      throw FormatException('HTTP auth response "$key" must be a string.');
    }
    final token = value.trim();
    if (token.isEmpty) {
      return null;
    }
    if (containsMcpWhitespaceOrControl(token)) {
      throw FormatException(
        'HTTP auth response "$key" must not contain whitespace or control '
        'characters.',
      );
    }
    return token;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    final value = json[key];
    if (value is! String) {
      throw FormatException('HTTP auth response "$key" must be a string.');
    }
    if (value.isEmpty) {
      throw FormatException('HTTP auth response "$key" must not be empty.');
    }
    if (containsMcpWhitespaceOrControl(value)) {
      throw FormatException(
        'HTTP auth response "$key" must not contain whitespace or control '
        'characters.',
      );
    }
    return value;
  }

  static Map<String, Object?> _detailsFromJson(Map<String, Object?> json) {
    if (!json.containsKey('details') || json['details'] == null) {
      return const <String, Object?>{};
    }
    final value = json['details'];
    if (value is! Map) {
      throw const FormatException(
        'HTTP auth response "details" must be a JSON object.',
      );
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException(
          'HTTP auth response "details" must contain only string keys.',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  static Duration? _durationFromSeconds(
    Map<String, Object?> json,
    String name,
  ) {
    final value = json[name];
    if (value == null) {
      return null;
    }
    if (value is num &&
        value.isFinite &&
        !value.isNegative &&
        value.truncateToDouble() == value) {
      return Duration(seconds: value.toInt());
    }
    throw FormatException(
      '"$name" must be a non-negative integer number of seconds.',
    );
  }
}

final class ConnectanumHttpAuthProtocolException implements Exception {
  const ConnectanumHttpAuthProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ConnectanumHttpAuthProtocolException: $message';
}

final class ConnectanumHttpAuthException implements Exception {
  const ConnectanumHttpAuthException({
    required this.statusCode,
    required this.reasonPhrase,
    required this.body,
    this.error,
  });

  final int statusCode;
  final String reasonPhrase;
  final String body;
  final Object? error;

  @override
  String toString() {
    final suffix = body.isEmpty ? '' : ': $body';
    return 'ConnectanumHttpAuthException($statusCode $reasonPhrase$suffix)';
  }
}

Duration _validatedHttpAuthRequestTimeout(Duration value) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(
      value,
      'requestTimeout',
      'requestTimeout must be positive',
    );
  }
  return value;
}

int _validatedHttpAuthMaxResponseBytes(int value) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      'maxResponseBytes',
      'maxResponseBytes must be positive',
    );
  }
  return value;
}

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_core/connectanum_core.dart';

/// Dart IO client for Connectanum router HTTP auth bridge endpoints.
///
/// The router auth bridge exposes WAMP challenge/response authenticators over a
/// JSON HTTP endpoint. This helper keeps that handshake in the public client
/// package so protected router-hosted MCP routes can be used without
/// reimplementing the token flow in each consumer application.
final class ConnectanumHttpAuthClient {
  ConnectanumHttpAuthClient(
    this.endpoint, {
    HttpClient? httpClient,
    this.headers = const <String, String>{},
    bool closeHttpClient = false,
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null || closeHttpClient;

  final Uri endpoint;
  final Map<String, String> headers;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;

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
  }) async {
    final requestRealm = _nonEmptyArgument(realm, 'realm');
    final requestAuthId = _nonEmptyArgument(authId, 'authId');
    final method = _httpAuthMethodName(authMethod ?? authentication.getName());
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
    );
    final state = _nonEmptyString(challenge['state'], 'state');
    final authenticate = await authentication.challenge(
      _challengeExtraFrom(challenge['challenge']),
    );

    final grant = await _postJsonObject(
      <String, Object?>{
        'state': state,
        if (authenticate.signature != null) 'signature': authenticate.signature,
        if (authenticate.extra != null)
          'extra': Map<String, Object?>.from(authenticate.extra!),
      },
      expectedStatus: HttpStatus.ok,
      label: 'HTTP auth token request',
      extraHeaders: headers,
    );
    return ConnectanumHttpAuthGrant.fromJson(grant);
  }

  Future<ConnectanumHttpAuthGrant> refreshToken(
    String refreshToken, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final token = _nonEmptyToken(refreshToken, 'refreshToken');
    final grant = await _postJsonObject(
      <String, Object?>{'grant_type': 'refresh_token', 'refresh_token': token},
      expectedStatus: HttpStatus.ok,
      label: 'HTTP auth refresh request',
      extraHeaders: headers,
    );
    return ConnectanumHttpAuthGrant.fromJson(grant);
  }

  Future<void> revokeToken(
    String token, {
    String? tokenTypeHint,
    Map<String, String> headers = const <String, String>{},
  }) async {
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
    );
  }

  void close({bool force = false}) {
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  Future<Map<String, Object?>> _postJsonObject(
    Map<String, Object?> payload, {
    required int expectedStatus,
    required String label,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final request = await _httpClient.postUrl(endpoint);
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
    final body = await utf8.decodeStream(response);
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

  static Extra _challengeExtraFrom(Object? value) {
    if (value == null) {
      return Extra();
    }
    return Extra.fromMap(_jsonDynamicObject(value, 'HTTP auth challenge'));
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
    if (value is String) {
      return value;
    }
    throw FormatException('HTTP auth response "$key" must be a string.');
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

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
    final method = _httpAuthMethodName(authMethod ?? authentication.getName());
    final details = Details.forHello()
      ..authid = authId
      ..authmethods = <String>[method];
    if (authextra.isNotEmpty) {
      details.authextra = Map<String, dynamic>.from(authextra);
    }
    await authentication.hello(realm, details);

    final startBody = <String, Object?>{
      'realm': realm,
      'authmethod': method,
      'authid': authId,
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
    await _postJsonObject(
      <String, Object?>{
        'grant_type': 'revoke',
        'token': revokeToken,
        if (tokenTypeHint != null && tokenTypeHint.isNotEmpty)
          'token_type_hint': tokenTypeHint,
      },
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
    final trimmed = authMethod.trim();
    return trimmed == 'wamp-scram' ? 'scram' : trimmed;
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
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('HTTP auth response is missing "$key".');
  }

  static String _nonEmptyToken(String token, String name) {
    final value = token.trim();
    if (value.isNotEmpty) {
      return value;
    }
    throw ArgumentError.value(token, name, '$name must not be empty.');
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
    return ConnectanumHttpAuthGrant(
      accessToken: ConnectanumHttpAuthClient._nonEmptyString(
        json['access_token'],
        'access_token',
      ),
      tokenType: switch (json['token_type']) {
        final String value when value.isNotEmpty => value,
        _ => 'Bearer',
      },
      refreshToken: switch (json['refresh_token']) {
        final String value when value.isNotEmpty => value,
        _ => null,
      },
      realm: json['realm'] as String?,
      authId: json['authid'] as String?,
      authRole: json['authrole'] as String?,
      authMethod: json['authmethod'] as String?,
      authProvider: json['authprovider'] as String?,
      accessTokenExpiresIn: _durationFromSeconds(json['expires_in']),
      refreshTokenExpiresIn: _durationFromSeconds(
        json['refresh_token_expires_in'],
      ),
      details: switch (json['details']) {
        final Map value => Map<String, Object?>.from(value),
        _ => const <String, Object?>{},
      },
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

  static Duration? _durationFromSeconds(Object? value) {
    if (value is int) {
      return Duration(seconds: value);
    }
    if (value is num) {
      return Duration(seconds: value.toInt());
    }
    return null;
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

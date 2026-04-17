import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart' show CraAuthentication;

import '../config/authenticator.dart';

/// Request context passed to HTTP bearer auth providers.
class HttpAuthBearerRequest {
  const HttpAuthBearerRequest({
    required this.token,
    required this.realmUri,
    required this.method,
    required this.path,
    required this.headers,
    required this.transport,
    this.sessionProfileName,
  });

  final String token;
  final String realmUri;
  final String method;
  final String path;
  final Map<String, String> headers;
  final TransportMetadata transport;
  final String? sessionProfileName;
}

/// Result of a bearer-token authentication attempt.
class HttpAuthResult {
  const HttpAuthResult._({
    required this.success,
    this.authenticated,
    this.failure,
  });

  factory HttpAuthResult.success(HttpAuthSuccess authenticated) =>
      HttpAuthResult._(success: true, authenticated: authenticated);

  factory HttpAuthResult.failure(HttpAuthFailure failure) =>
      HttpAuthResult._(success: false, failure: failure);

  final bool success;
  final HttpAuthSuccess? authenticated;
  final HttpAuthFailure? failure;
}

/// Successful bearer-token authentication result.
class HttpAuthSuccess {
  const HttpAuthSuccess({
    required this.authId,
    this.authRole,
    required this.authMethod,
    required this.authProvider,
    this.details = const <String, Object?>{},
    this.roles = const <String, Object?>{},
    this.expiresAt,
  });

  final String authId;
  final String? authRole;
  final String authMethod;
  final String authProvider;
  final Map<String, Object?> details;
  final Map<String, Object?> roles;
  final DateTime? expiresAt;
}

/// Failed bearer-token authentication result.
class HttpAuthFailure {
  const HttpAuthFailure({required this.reason, this.message});

  final String reason;
  final String? message;
}

/// Runtime provider interface for bearer-backed HTTP auth.
abstract class HttpAuthProvider {
  const HttpAuthProvider();

  Future<HttpAuthResult> authenticate(HttpAuthBearerRequest request);
}

/// Factory interface for configured HTTP auth providers.
abstract class HttpAuthProviderFactory {
  const HttpAuthProviderFactory();

  String get type;

  Future<HttpAuthProvider> create(Map<String, Object?> options);
}

/// Registry for pluggable HTTP bearer auth provider factories.
class HttpAuthProviderRegistry {
  HttpAuthProviderRegistry._();

  static final Map<String, HttpAuthProviderFactory> _factories = {};

  static void registerFactory(HttpAuthProviderFactory factory) {
    _factories[factory.type] = factory;
  }

  static void registerFactories(Iterable<HttpAuthProviderFactory> factories) {
    for (final factory in factories) {
      registerFactory(factory);
    }
  }

  static void unregisterFactory(String type) {
    _factories.remove(type);
  }

  static HttpAuthProviderFactory? factoryFor(String type) => _factories[type];

  static Map<String, HttpAuthProviderFactory> get factories =>
      Map.unmodifiable(_factories);

  static void clear() => _factories.clear();
}

bool _defaultHttpAuthProvidersRegistered = false;

/// Registers the built-in bearer auth providers.
void registerDefaultHttpAuthProviders() {
  if (_defaultHttpAuthProvidersRegistered &&
      HttpAuthProviderRegistry.factoryFor(
            const JwtHttpAuthProviderFactory().type,
          ) !=
          null) {
    return;
  }
  HttpAuthProviderRegistry.registerFactories(const <HttpAuthProviderFactory>[
    JwtHttpAuthProviderFactory(),
    OidcHttpAuthProviderFactory(),
    OAuthIntrospectionHttpAuthProviderFactory(),
  ]);
  _defaultHttpAuthProvidersRegistered = true;
}

class JwtHttpAuthProviderFactory extends HttpAuthProviderFactory {
  const JwtHttpAuthProviderFactory();

  @override
  String get type => 'jwt';

  @override
  Future<HttpAuthProvider> create(Map<String, Object?> options) async {
    return _JwtHttpAuthProvider(options, method: type);
  }
}

class OidcHttpAuthProviderFactory extends HttpAuthProviderFactory {
  const OidcHttpAuthProviderFactory();

  @override
  String get type => 'oidc';

  @override
  Future<HttpAuthProvider> create(Map<String, Object?> options) async {
    return _JwtHttpAuthProvider(options, method: type);
  }
}

class _JwtHttpAuthProvider extends HttpAuthProvider {
  _JwtHttpAuthProvider(this._options, {required this.method});

  final Map<String, Object?> _options;
  final String method;

  @override
  Future<HttpAuthResult> authenticate(HttpAuthBearerRequest request) async {
    final providerName =
        _stringOption(_options['name']) ??
        _stringOption(_options['provider_name']) ??
        method;
    final algorithm = _stringOption(_options['algorithm']) ?? 'HS256';
    if (algorithm != 'HS256') {
      return HttpAuthResult.failure(
        HttpAuthFailure(
          reason: 'unsupported_alg',
          message: 'Only HS256 JWT validation is currently supported',
        ),
      );
    }
    final secret = _stringOption(
      _options['hmac_secret'] ??
          _options['secret'] ??
          _options['shared_secret'],
    );
    if (secret == null || secret.isEmpty) {
      throw StateError(
        'HTTP auth provider "$providerName" requires hmac_secret for $method tokens.',
      );
    }

    final segments = request.token.split('.');
    if (segments.length != 3) {
      return HttpAuthResult.failure(
        const HttpAuthFailure(
          reason: 'invalid_token',
          message: 'JWT must contain exactly 3 segments',
        ),
      );
    }

    Map<String, Object?> header;
    Map<String, Object?> claims;
    try {
      header = _decodeJwtJson(segments[0]);
      claims = _decodeJwtJson(segments[1]);
    } on FormatException catch (error) {
      return HttpAuthResult.failure(
        HttpAuthFailure(reason: 'invalid_token', message: error.message),
      );
    }

    final headerAlg = _stringOption(header['alg']);
    if (headerAlg != algorithm) {
      return HttpAuthResult.failure(
        HttpAuthFailure(
          reason: 'invalid_token',
          message: 'Unexpected JWT algorithm ${headerAlg ?? 'unknown'}',
        ),
      );
    }

    final signingInput = utf8.encode('${segments[0]}.${segments[1]}');
    final expectedSignature = CraAuthentication.encodeByteHmac(
      Uint8List.fromList(utf8.encode(secret)),
      32,
      signingInput,
    );
    final actualSignature = _decodeBase64UrlBytes(segments[2]);
    if (!_constantTimeEquals(expectedSignature, actualSignature)) {
      return HttpAuthResult.failure(
        const HttpAuthFailure(
          reason: 'invalid_token',
          message: 'JWT signature validation failed',
        ),
      );
    }

    final now = DateTime.now().toUtc();
    final leewaySeconds = _intOption(_options['leeway_seconds']) ?? 0;
    final leeway = Duration(seconds: leewaySeconds < 0 ? 0 : leewaySeconds);
    final expiresAt = _dateTimeFromEpochSeconds(claims['exp']);
    if (expiresAt != null && now.isAfter(expiresAt.add(leeway))) {
      return HttpAuthResult.failure(
        const HttpAuthFailure(reason: 'expired_token', message: 'JWT expired'),
      );
    }
    final notBefore = _dateTimeFromEpochSeconds(claims['nbf']);
    if (notBefore != null && now.isBefore(notBefore.subtract(leeway))) {
      return HttpAuthResult.failure(
        const HttpAuthFailure(
          reason: 'inactive_token',
          message: 'JWT is not active yet',
        ),
      );
    }

    final expectedIssuer = _stringOption(_options['issuer']);
    if (expectedIssuer != null && expectedIssuer.isNotEmpty) {
      final actualIssuer = _stringOption(claims['iss']);
      if (actualIssuer != expectedIssuer) {
        return HttpAuthResult.failure(
          const HttpAuthFailure(
            reason: 'invalid_token',
            message: 'JWT issuer did not match provider configuration',
          ),
        );
      }
    }

    final expectedAudiences = _stringListOption(_options['audience']);
    if (expectedAudiences.isNotEmpty &&
        !_audienceMatches(claims['aud'], expectedAudiences)) {
      return HttpAuthResult.failure(
        const HttpAuthFailure(
          reason: 'invalid_token',
          message: 'JWT audience did not match provider configuration',
        ),
      );
    }

    final mapped = _mapClaimsToAuthSuccess(
      claims: claims,
      method: method,
      providerName: providerName,
      options: _options,
      expiresAt: expiresAt,
    );
    if (mapped == null) {
      return HttpAuthResult.failure(
        const HttpAuthFailure(
          reason: 'invalid_token',
          message: 'JWT did not contain a usable subject/auth id',
        ),
      );
    }
    return HttpAuthResult.success(mapped);
  }
}

class OAuthIntrospectionHttpAuthProviderFactory
    extends HttpAuthProviderFactory {
  const OAuthIntrospectionHttpAuthProviderFactory();

  @override
  String get type => 'oauth';

  @override
  Future<HttpAuthProvider> create(Map<String, Object?> options) async {
    return _OAuthIntrospectionHttpAuthProvider(options);
  }
}

class _OAuthIntrospectionHttpAuthProvider extends HttpAuthProvider {
  _OAuthIntrospectionHttpAuthProvider(this._options);

  final Map<String, Object?> _options;

  @override
  Future<HttpAuthResult> authenticate(HttpAuthBearerRequest request) async {
    final providerName =
        _stringOption(_options['name']) ??
        _stringOption(_options['provider_name']) ??
        'oauth';
    final urlValue = _stringOption(
      _options['introspection_url'] ?? _options['url'],
    );
    if (urlValue == null || urlValue.isEmpty) {
      throw StateError(
        'HTTP auth provider "$providerName" requires introspection_url.',
      );
    }
    final uri = Uri.parse(urlValue);
    final timeoutMs = _intOption(_options['timeout_ms']) ?? 5000;
    final client = HttpClient();
    if (_boolOption(_options['allow_insecure_tls']) == true) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    try {
      final httpRequest = await client
          .postUrl(uri)
          .timeout(Duration(milliseconds: timeoutMs));
      httpRequest.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      httpRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final clientId = _stringOption(_options['client_id']);
      final clientSecret = _stringOption(_options['client_secret']);
      final introspectionBearer = _stringOption(_options['bearer_token']);
      if (clientId != null && clientSecret != null) {
        final credentials = base64Encode(
          utf8.encode('$clientId:$clientSecret'),
        );
        httpRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $credentials',
        );
      } else if (introspectionBearer != null &&
          introspectionBearer.isNotEmpty) {
        httpRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $introspectionBearer',
        );
      }
      final body = <String, String>{
        'token': request.token,
        'token_type_hint':
            _stringOption(_options['token_type_hint']) ?? 'access_token',
      };
      final resource = _stringOption(_options['resource']);
      if (resource != null && resource.isNotEmpty) {
        body['resource'] = resource;
      }
      final audience = _stringOption(_options['audience']);
      if (audience != null && audience.isNotEmpty) {
        body['audience'] = audience;
      }
      httpRequest.write(Uri(queryParameters: body).query);
      final response = await httpRequest.close().timeout(
        Duration(milliseconds: timeoutMs),
      );
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        return HttpAuthResult.failure(
          HttpAuthFailure(
            reason: 'introspection_failed',
            message:
                'Introspection endpoint returned HTTP ${response.statusCode}',
          ),
        );
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        return HttpAuthResult.failure(
          const HttpAuthFailure(
            reason: 'invalid_token_response',
            message: 'Introspection endpoint did not return a JSON object',
          ),
        );
      }
      final claims = Map<String, Object?>.from(decoded.cast<String, Object?>());
      final active = claims['active'];
      if (active != true) {
        return HttpAuthResult.failure(
          const HttpAuthFailure(
            reason: 'invalid_token',
            message: 'OAuth introspection reported an inactive token',
          ),
        );
      }
      final expiresAt = _dateTimeFromEpochSeconds(claims['exp']);
      final now = DateTime.now().toUtc();
      if (expiresAt != null && now.isAfter(expiresAt)) {
        return HttpAuthResult.failure(
          const HttpAuthFailure(
            reason: 'expired_token',
            message: 'OAuth token expired',
          ),
        );
      }
      final expectedIssuer = _stringOption(_options['issuer']);
      if (expectedIssuer != null && expectedIssuer.isNotEmpty) {
        final actualIssuer = _stringOption(claims['iss']);
        if (actualIssuer != expectedIssuer) {
          return HttpAuthResult.failure(
            const HttpAuthFailure(
              reason: 'invalid_token',
              message:
                  'OAuth token issuer did not match provider configuration',
            ),
          );
        }
      }
      final expectedAudiences = _stringListOption(_options['audience']);
      if (expectedAudiences.isNotEmpty &&
          !_audienceMatches(claims['aud'], expectedAudiences)) {
        return HttpAuthResult.failure(
          const HttpAuthFailure(
            reason: 'invalid_token',
            message:
                'OAuth token audience did not match provider configuration',
          ),
        );
      }
      final mapped = _mapClaimsToAuthSuccess(
        claims: claims,
        method: 'oauth',
        providerName: providerName,
        options: _options,
        expiresAt: expiresAt,
      );
      if (mapped == null) {
        return HttpAuthResult.failure(
          const HttpAuthFailure(
            reason: 'invalid_token',
            message: 'OAuth token did not contain a usable subject/auth id',
          ),
        );
      }
      return HttpAuthResult.success(mapped);
    } on TimeoutException {
      return HttpAuthResult.failure(
        const HttpAuthFailure(
          reason: 'auth_timeout',
          message: 'OAuth introspection timed out',
        ),
      );
    } on SocketException catch (error) {
      return HttpAuthResult.failure(
        HttpAuthFailure(reason: 'auth_unavailable', message: error.message),
      );
    } finally {
      client.close(force: true);
    }
  }
}

HttpAuthSuccess? _mapClaimsToAuthSuccess({
  required Map<String, Object?> claims,
  required String method,
  required String providerName,
  required Map<String, Object?> options,
  DateTime? expiresAt,
}) {
  final authIdClaim =
      _stringOption(options['auth_id_claim']) ??
      _stringOption(options['subject_claim']) ??
      'sub';
  final authRoleClaim =
      _stringOption(options['auth_role_claim']) ??
      _stringOption(options['role_claim']) ??
      'role';
  final rolesClaim =
      _stringOption(options['roles_claim']) ??
      _stringOption(options['role_list_claim']);

  final authId =
      _stringOption(claims[authIdClaim]) ??
      _stringOption(claims['sub']) ??
      _stringOption(claims['username']) ??
      _stringOption(claims['client_id']);
  if (authId == null || authId.isEmpty) {
    return null;
  }

  var authRole = _stringOption(claims[authRoleClaim]);
  if (authRole == null || authRole.isEmpty) {
    authRole = _mapScopeToRole(claims['scope'], options['scope_role_map']);
  }
  authRole ??= _stringOption(options['default_auth_role']);

  final roles = <String, Object?>{};
  if (rolesClaim != null && rolesClaim.isNotEmpty) {
    final roleNames = _stringListOption(claims[rolesClaim]);
    for (final role in roleNames) {
      roles[role] = const <String, Object?>{};
    }
  }
  if (authRole != null && authRole.isNotEmpty && !roles.containsKey(authRole)) {
    roles[authRole] = const <String, Object?>{};
  }

  final details = <String, Object?>{
    'authprovider': providerName,
    'authextra': Map<String, Object?>.from(claims),
  };
  return HttpAuthSuccess(
    authId: authId,
    authRole: authRole,
    authMethod: method,
    authProvider: providerName,
    details: details,
    roles: roles,
    expiresAt: expiresAt,
  );
}

Map<String, Object?> _decodeJwtJson(String segment) {
  final decoded = jsonDecode(utf8.decode(_decodeBase64UrlBytes(segment)));
  if (decoded is! Map) {
    throw const FormatException('JWT segment did not contain a JSON object');
  }
  return Map<String, Object?>.from(decoded.cast<String, Object?>());
}

List<int> _decodeBase64UrlBytes(String value) {
  final normalized = base64Url.normalize(value);
  return base64Url.decode(normalized);
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}

DateTime? _dateTimeFromEpochSeconds(Object? value) {
  final seconds = _intOption(value);
  if (seconds == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

bool _audienceMatches(Object? value, List<String> expectedAudiences) {
  if (value == null) {
    return false;
  }
  final actual = _stringListOption(value);
  if (actual.isEmpty) {
    final single = _stringOption(value);
    if (single == null || single.isEmpty) {
      return false;
    }
    return expectedAudiences.contains(single);
  }
  for (final item in actual) {
    if (expectedAudiences.contains(item)) {
      return true;
    }
  }
  return false;
}

String? _mapScopeToRole(Object? scopeValue, Object? scopeRoleMapValue) {
  if (scopeRoleMapValue is! Map) {
    return null;
  }
  final scopes = <String>[];
  if (scopeValue is Iterable) {
    scopes.addAll(_stringListOption(scopeValue));
  } else {
    final scopeString = _stringOption(scopeValue);
    if (scopeString != null && scopeString.isNotEmpty) {
      scopes.addAll(
        scopeString.split(RegExp(r'\s+')).where((scope) => scope.isNotEmpty),
      );
    }
  }
  final scopeRoleMap = Map<String, Object?>.from(
    scopeRoleMapValue.cast<Object?, Object?>().map(
      (key, value) => MapEntry(key.toString(), value),
    ),
  );
  for (final scope in scopes) {
    final mapped = _stringOption(scopeRoleMap[scope]);
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
  }
  return null;
}

String? _stringOption(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return value.toString();
}

int? _intOption(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString().trim());
}

bool? _boolOption(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  final raw = value.toString().trim().toLowerCase();
  if (raw == 'true') {
    return true;
  }
  if (raw == 'false') {
    return false;
  }
  return null;
}

List<String> _stringListOption(Object? value) {
  if (value == null) {
    return <String>[];
  }
  if (value is Iterable) {
    return value
        .map((entry) => _stringOption(entry))
        .whereType<String>()
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }
  final single = _stringOption(value);
  if (single == null || single.isEmpty) {
    return <String>[];
  }
  return <String>[single];
}

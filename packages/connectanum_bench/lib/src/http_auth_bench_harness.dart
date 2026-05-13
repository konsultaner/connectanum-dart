import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';

class HttpAuthBenchHarness {
  HttpAuthBenchHarness._({
    required Logger logger,
    required List<HttpServer> servers,
  }) : _logger = logger,
       _servers = servers;

  static const String defaultOAuthAccessToken = 'bench-oauth-token';
  static const String defaultAuthId = 'oauth-user';
  static const String defaultAuthRole = 'member';

  final Logger _logger;
  final List<HttpServer> _servers;

  static bool supports(RouterSettings settings) =>
      _HttpAuthBenchConfig.tryParse(settings) != null;

  static Future<HttpAuthBenchHarness?> maybeStart({
    required RouterSettings settings,
    Logger? logger,
  }) async {
    final config = _HttpAuthBenchConfig.tryParse(settings);
    if (config == null) {
      return null;
    }
    final targetLogger = logger ?? Logger('HttpAuthBenchHarness');
    final servers = <HttpServer>[];
    for (final serverConfig in config.servers) {
      targetLogger.info(
        'Starting HTTP auth bench harness on ${serverConfig.host}:${serverConfig.port}',
      );
      final bindHost =
          InternetAddress.tryParse(serverConfig.host) ?? serverConfig.host;
      final server = await HttpServer.bind(bindHost, serverConfig.port);
      server.listen((request) => serverConfig.handle(request, targetLogger));
      servers.add(server);
    }
    return HttpAuthBenchHarness._(logger: targetLogger, servers: servers);
  }

  Future<void> close() async {
    _logger.info('Stopping HTTP auth bench harness');
    for (final server in _servers) {
      await server.close(force: true);
    }
  }
}

class _HttpAuthBenchConfig {
  const _HttpAuthBenchConfig({required this.servers});

  final List<_IntrospectionServerConfig> servers;

  static _HttpAuthBenchConfig? tryParse(RouterSettings settings) {
    final grouped = <_ServerKey, Map<String, _ProviderBinding>>{};
    for (final entry in settings.httpAuthProviders.entries) {
      if (entry.value.type != 'oauth') {
        continue;
      }
      final binding = _ProviderBinding.tryParse(entry.key, entry.value);
      if (binding == null) {
        continue;
      }
      grouped.putIfAbsent(
        binding.serverKey,
        () => <String, _ProviderBinding>{},
      )[binding.path] = binding;
    }
    if (grouped.isEmpty) {
      return null;
    }
    return _HttpAuthBenchConfig(
      servers: List<_IntrospectionServerConfig>.unmodifiable(
        grouped.entries
            .map(
              (entry) => _IntrospectionServerConfig(
                host: entry.key.host,
                port: entry.key.port,
                bindings: Map<String, _ProviderBinding>.unmodifiable(
                  entry.value,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _IntrospectionServerConfig {
  const _IntrospectionServerConfig({
    required this.host,
    required this.port,
    required this.bindings,
  });

  final String host;
  final int port;
  final Map<String, _ProviderBinding> bindings;

  Future<void> handle(HttpRequest request, Logger logger) async {
    final binding = bindings[request.uri.path];
    if (binding == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await binding.handle(request, logger);
  }
}

class _ProviderBinding {
  _ProviderBinding({
    required this.serverKey,
    required this.name,
    required this.path,
    required this.expectedAuthorization,
    required this.claims,
  });

  final _ServerKey serverKey;
  final String name;
  final String path;
  final String? expectedAuthorization;
  final Map<String, Object?> claims;

  static _ProviderBinding? tryParse(
    String name,
    HttpAuthProviderDefinition definition,
  ) {
    final options = definition.options;
    final rawUrl = _stringOption(
      options['introspection_url'] ?? options['url'],
    );
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.port <= 0) {
      return null;
    }
    final authIdClaim = _stringOption(options['auth_id_claim']) ?? 'sub';
    final authRoleClaim = _stringOption(options['auth_role_claim']) ?? 'role';
    final authId =
        _stringOption(options['default_auth_id']) ??
        HttpAuthBenchHarness.defaultAuthId;
    final authRole =
        _stringOption(options['default_auth_role']) ??
        HttpAuthBenchHarness.defaultAuthRole;
    final claims = <String, Object?>{
      'active': true,
      authIdClaim: authId,
      authRoleClaim: authRole,
      'exp':
          DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch ~/
          1000,
    };
    final issuer = _stringOption(options['issuer']);
    if (issuer != null && issuer.isNotEmpty) {
      claims['iss'] = issuer;
    }
    final audience = _audienceOption(options['audience']);
    if (audience != null) {
      claims['aud'] = audience;
    }
    return _ProviderBinding(
      serverKey: _ServerKey(uri.host, uri.port),
      name: name,
      path: uri.path.isEmpty ? '/' : uri.path,
      expectedAuthorization: _expectedAuthorization(options),
      claims: Map<String, Object?>.unmodifiable(claims),
    );
  }

  Future<void> handle(HttpRequest request, Logger logger) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (expectedAuthorization != null &&
        authorization != expectedAuthorization) {
      logger.warning('Rejecting introspection request for $name: bad auth');
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(const <String, Object?>{'active': false}),
      );
      await request.response.close();
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final form = Uri.splitQueryString(body, encoding: utf8);
    final token = form['token'];
    final active = token == HttpAuthBenchHarness.defaultOAuthAccessToken;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(active ? claims : const <String, Object?>{'active': false}),
    );
    await request.response.close();
  }
}

class _ServerKey {
  const _ServerKey(this.host, this.port);

  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is _ServerKey && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

String? _expectedAuthorization(Map<String, Object?> options) {
  final clientId = _stringOption(options['client_id']);
  final clientSecret = _stringOption(options['client_secret']);
  if (clientId != null &&
      clientId.isNotEmpty &&
      clientSecret != null &&
      clientSecret.isNotEmpty) {
    final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));
    return 'Basic $credentials';
  }
  final bearer = _stringOption(options['bearer_token']);
  if (bearer != null && bearer.isNotEmpty) {
    return 'Bearer $bearer';
  }
  return null;
}

Object? _audienceOption(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is Iterable) {
    return List<String>.unmodifiable(
      value.map((entry) => entry.toString()).where((entry) => entry.isNotEmpty),
    );
  }
  return null;
}

String? _stringOption(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

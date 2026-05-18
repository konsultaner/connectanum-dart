import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_client/socket.dart' as client_socket;
import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor_serializer;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack_serializer;

import '../config/authenticator.dart';
import '../config/router_settings.dart';
import '../models/validators.dart';
import 'remote_authenticator.dart';

class RemoteWampDelegateConfig {
  RemoteWampDelegateConfig._({
    required this.realm,
    required this.transport,
    required this.helloProcedure,
    required this.authenticateProcedure,
    required this.abortProcedure,
    required this.callTimeout,
    required this.connectTimeout,
    required _RemoteStringSource? authTokenSource,
    required this.authId,
    required this.authRole,
    required this.authExtra,
    required _RemoteServiceAuthenticationConfig? serviceAuthentication,
  }) : _authTokenSource = authTokenSource,
       _serviceAuthentication = serviceAuthentication;

  final String realm;
  final RemoteWampTransportConfig transport;
  final String helloProcedure;
  final String authenticateProcedure;
  final String abortProcedure;
  final Duration callTimeout;
  final Duration connectTimeout;
  final _RemoteStringSource? _authTokenSource;
  final String? authId;
  final String? authRole;
  final Map<String, dynamic>? authExtra;
  final _RemoteServiceAuthenticationConfig? _serviceAuthentication;

  String cacheKey() => jsonEncode(<String, Object?>{
    'realm': realm,
    'transport': transport.cacheKeyMap(),
    'helloProcedure': helloProcedure,
    'authenticateProcedure': authenticateProcedure,
    'abortProcedure': abortProcedure,
    'callTimeoutMs': callTimeout.inMilliseconds,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'authToken': _authTokenSource?.cacheKeyMap(),
    'authId': authId,
    'authRole': authRole,
    'authExtra': authExtra,
    'serviceAuthentication': _serviceAuthentication?.cacheKeyMap(),
  });

  Future<String?> resolveAuthToken() async => await _authTokenSource?.resolve();

  Future<List<AbstractAuthentication>> buildAuthenticationMethods() async {
    return (await _serviceAuthentication?.build()) ??
        const <AbstractAuthentication>[];
  }

  Future<String> connectionFingerprint() async {
    return jsonEncode(<String, Object?>{
      'transport': await transport.fingerprintMap(),
      'serviceAuthentication': await _serviceAuthentication?.fingerprintMap(),
      'authId': authId,
      'authRole': authRole,
      'authExtra': authExtra,
    });
  }

  static RemoteWampDelegateConfig parse(
    Map<String, Object?> options,
    RealmSettings realm,
  ) {
    final rpc = options['rpc'];
    if (rpc is! Map) {
      throw ArgumentError.value(
        rpc,
        'rpc',
        'Expected a map describing the remote WAMP transport.',
      );
    }
    final rpcMap = Map<String, Object?>.from(rpc.cast<Object?, Object?>());
    final realmName = (rpcMap['realm'] as String?)?.trim().isNotEmpty == true
        ? (rpcMap['realm'] as String).trim()
        : 'connectanum.authenticate';
    final helloProcedure =
        (rpcMap['hello_procedure'] as String?)?.trim().isNotEmpty == true
        ? (rpcMap['hello_procedure'] as String).trim()
        : 'authenticate.hello';
    final authenticateProcedure =
        (rpcMap['authenticate_procedure'] as String?)?.trim().isNotEmpty == true
        ? (rpcMap['authenticate_procedure'] as String).trim()
        : 'authenticate.authenticate';
    final abortProcedure =
        (rpcMap['abort_procedure'] as String?)?.trim().isNotEmpty == true
        ? (rpcMap['abort_procedure'] as String).trim()
        : 'authenticate.abort';
    final callTimeout = Duration(
      milliseconds: _parsePositiveInt(rpcMap['call_timeout_ms'], 5000),
    );
    final connectTimeout = Duration(
      milliseconds: _parsePositiveInt(rpcMap['connect_timeout_ms'], 5000),
    );
    final authExtra = _parseStringDynamicMap(rpcMap['service_auth_extra']);
    final authId = _trimmedOrNull(rpcMap['service_auth_id'] as String?);
    final authRole = _trimmedOrNull(rpcMap['service_auth_role'] as String?);
    final authTokenSource = _RemoteStringSource.parseWithFallback(
      primary: rpcMap,
      fallback: options,
      field: 'auth_token',
    );
    final serviceAuthentication = _RemoteServiceAuthenticationConfig.parse(
      rpcMap,
      realm: realm,
    );
    return RemoteWampDelegateConfig._(
      realm: realmName,
      transport: RemoteWampTransportConfig.parse(rpcMap),
      helloProcedure: helloProcedure,
      authenticateProcedure: authenticateProcedure,
      abortProcedure: abortProcedure,
      callTimeout: callTimeout,
      connectTimeout: connectTimeout,
      authTokenSource: authTokenSource,
      authId: authId,
      authRole: authRole,
      authExtra: authExtra,
      serviceAuthentication: serviceAuthentication,
    );
  }

  static int _parsePositiveInt(Object? value, int defaultValue) {
    if (value == null) {
      return defaultValue;
    }
    if (value is num) {
      final result = value.toInt();
      return result > 0 ? result : defaultValue;
    }
    throw ArgumentError.value(value, 'int option', 'Expected a number');
  }

  static Map<String, dynamic>? _parseStringDynamicMap(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw ArgumentError.value(value, 'map option', 'Expected a map');
    }
    return Map<String, dynamic>.from(value.cast<Object?, Object?>());
  }

  static String? _trimmedOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class RemoteWampTransportConfig {
  RemoteWampTransportConfig._({
    required this.type,
    required this.serializer,
    required this.tls,
    this.host,
    this.port,
    this.ssl = false,
    this.url,
    this.libraryPath,
    this.headers = const <String, dynamic>{},
  });

  final String type;
  final String serializer;
  final RemoteWampTransportTlsConfig tls;
  final String? host;
  final int? port;
  final bool ssl;
  final String? url;
  final String? libraryPath;
  final Map<String, dynamic> headers;

  factory RemoteWampTransportConfig.parse(Map<String, Object?> rpcMap) {
    final transport = rpcMap['transport'];
    if (transport is! Map) {
      throw ArgumentError.value(
        transport,
        'rpc.transport',
        'Expected a map describing the remote auth transport.',
      );
    }
    final map = Map<String, Object?>.from(transport.cast<Object?, Object?>());
    final type = (map['type'] as String?)?.trim();
    if (type == null || type.isEmpty) {
      throw ArgumentError('rpc.transport.type is required');
    }
    final serializer = (map['serializer'] as String?)?.trim().isNotEmpty == true
        ? (map['serializer'] as String).trim()
        : 'json';
    final tls = RemoteWampTransportTlsConfig.parse(map);
    switch (type) {
      case 'rawsocket':
        final host = (map['host'] as String?)?.trim();
        final portValue = map['port'];
        if (host == null || host.isEmpty || portValue is! num) {
          throw ArgumentError(
            'rpc.transport.rawsocket requires host and numeric port.',
          );
        }
        if (map['ssl'] != true && !tls.allowInsecureTransport) {
          throw ArgumentError(
            'rpc.transport.rawsocket.ssl must be true unless '
            'rpc.transport.tls.allow_insecure_transport is true.',
          );
        }
        return RemoteWampTransportConfig._(
          type: type,
          serializer: serializer,
          tls: tls,
          host: host,
          port: portValue.toInt(),
          ssl: map['ssl'] == true,
          libraryPath: RemoteWampDelegateConfig._trimmedOrNull(
            map['library_path'] as String?,
          ),
        );
      case 'websocket':
        final url = (map['url'] as String?)?.trim();
        if (url == null || url.isEmpty) {
          throw ArgumentError('rpc.transport.websocket requires url.');
        }
        final uri = Uri.parse(url);
        if (uri.scheme != 'wss' && !tls.allowInsecureTransport) {
          throw ArgumentError(
            'rpc.transport.websocket.url must use wss:// unless '
            'rpc.transport.tls.allow_insecure_transport is true.',
          );
        }
        final headers = map['headers'];
        return RemoteWampTransportConfig._(
          type: type,
          serializer: serializer,
          tls: tls,
          url: url,
          libraryPath: RemoteWampDelegateConfig._trimmedOrNull(
            map['library_path'] as String?,
          ),
          headers: headers is Map
              ? Map<String, dynamic>.from(headers.cast<Object?, Object?>())
              : const <String, dynamic>{},
        );
      case 'internal':
        return RemoteWampTransportConfig._(
          type: type,
          serializer: serializer,
          tls: tls,
        );
      default:
        throw ArgumentError('Unsupported rpc.transport.type "$type".');
    }
  }

  Future<Map<String, Object?>> fingerprintMap() async => <String, Object?>{
    'type': type,
    'serializer': serializer,
    'host': host,
    'port': port,
    'ssl': ssl,
    'url': url,
    'libraryPath': libraryPath,
    'headers': headers,
    'tls': await tls.fingerprintMap(),
  };

  Map<String, Object?> cacheKeyMap() => <String, Object?>{
    'type': type,
    'serializer': serializer,
    'host': host,
    'port': port,
    'ssl': ssl,
    'url': url,
    'libraryPath': libraryPath,
    'headers': headers,
    'tls': tls.cacheKeyMap(),
  };
}

class RemoteWampTransportTlsConfig {
  RemoteWampTransportTlsConfig._({
    required this.allowInsecureTransport,
    required this.allowInsecureCertificates,
    required _RemoteStringSource? caCertificates,
    required _RemoteStringSource? clientCertificate,
    required _RemoteStringSource? clientPrivateKey,
    required _RemoteStringSource? clientPrivateKeyPassword,
  }) : _caCertificates = caCertificates,
       _clientCertificate = clientCertificate,
       _clientPrivateKey = clientPrivateKey,
       _clientPrivateKeyPassword = clientPrivateKeyPassword;

  final bool allowInsecureTransport;
  final bool allowInsecureCertificates;
  final _RemoteStringSource? _caCertificates;
  final _RemoteStringSource? _clientCertificate;
  final _RemoteStringSource? _clientPrivateKey;
  final _RemoteStringSource? _clientPrivateKeyPassword;

  factory RemoteWampTransportTlsConfig.parse(
    Map<String, Object?> transportMap,
  ) {
    final tlsValue = transportMap['tls'];
    if (tlsValue != null && tlsValue is! Map) {
      throw ArgumentError.value(
        tlsValue,
        'rpc.transport.tls',
        'Expected a map describing TLS settings.',
      );
    }
    final tlsMap = tlsValue is Map
        ? Map<String, Object?>.from(tlsValue.cast<Object?, Object?>())
        : const <String, Object?>{};
    final config = RemoteWampTransportTlsConfig._(
      allowInsecureTransport:
          transportMap['allow_insecure_transport'] == true ||
          tlsMap['allow_insecure_transport'] == true,
      allowInsecureCertificates:
          transportMap['allow_insecure_certificates'] == true ||
          tlsMap['allow_insecure_certificates'] == true,
      caCertificates: _RemoteStringSource.parse(tlsMap, 'ca_certificates'),
      clientCertificate: _RemoteStringSource.parse(
        tlsMap,
        'client_certificate',
      ),
      clientPrivateKey: _RemoteStringSource.parse(tlsMap, 'client_private_key'),
      clientPrivateKeyPassword: _RemoteStringSource.parse(
        tlsMap,
        'client_private_key_password',
      ),
    );
    final hasCertificate = config._clientCertificate != null;
    final hasPrivateKey = config._clientPrivateKey != null;
    if (hasCertificate != hasPrivateKey) {
      throw ArgumentError(
        'rpc.transport.tls.client_certificate and '
        'rpc.transport.tls.client_private_key must be configured together.',
      );
    }
    return config;
  }

  Map<String, Object?> cacheKeyMap() => <String, Object?>{
    'allowInsecureTransport': allowInsecureTransport,
    'allowInsecureCertificates': allowInsecureCertificates,
    'caCertificates': _caCertificates?.cacheKeyMap(),
    'clientCertificate': _clientCertificate?.cacheKeyMap(),
    'clientPrivateKey': _clientPrivateKey?.cacheKeyMap(),
    'clientPrivateKeyPassword': _clientPrivateKeyPassword?.cacheKeyMap(),
  };

  Future<Map<String, Object?>> fingerprintMap() async => <String, Object?>{
    'allowInsecureTransport': allowInsecureTransport,
    'allowInsecureCertificates': allowInsecureCertificates,
    'caCertificates': await _caCertificates?.fingerprint(),
    'clientCertificate': await _clientCertificate?.fingerprint(),
    'clientPrivateKey': await _clientPrivateKey?.fingerprint(),
    'clientPrivateKeyPassword': await _clientPrivateKeyPassword?.fingerprint(),
  };

  Future<SecurityContext?> buildSecurityContext() async {
    final resolvedCaCertificates = await _caCertificates?.resolve();
    final resolvedClientCertificate = await _clientCertificate?.resolve();
    final resolvedClientPrivateKey = await _clientPrivateKey?.resolve();
    final resolvedClientPrivateKeyPassword = await _clientPrivateKeyPassword
        ?.resolve();
    if (resolvedCaCertificates == null &&
        resolvedClientCertificate == null &&
        resolvedClientPrivateKey == null) {
      return null;
    }
    final context = SecurityContext(
      withTrustedRoots: resolvedCaCertificates == null,
    );
    if (resolvedCaCertificates != null) {
      context.setTrustedCertificatesBytes(
        utf8.encode(
          normalizePem(
            resolvedCaCertificates,
            'rpc.transport.tls.ca_certificates',
          ),
        ),
      );
    }
    if (resolvedClientCertificate != null && resolvedClientPrivateKey != null) {
      context.useCertificateChainBytes(
        utf8.encode(
          normalizePem(
            resolvedClientCertificate,
            'rpc.transport.tls.client_certificate',
          ),
        ),
      );
      context.usePrivateKeyBytes(
        utf8.encode(
          normalizePem(
            resolvedClientPrivateKey,
            'rpc.transport.tls.client_private_key',
          ),
        ),
        password: resolvedClientPrivateKeyPassword,
      );
    }
    return context;
  }
}

class _RemoteServiceAuthenticationConfig {
  const _RemoteServiceAuthenticationConfig._({
    required this.method,
    this.secret,
    this.privateKey,
    this.privateKeyFormat = 'base64',
    this.privateKeyPassword,
  });

  final String method;
  final _RemoteStringSource? secret;
  final _RemoteStringSource? privateKey;
  final String privateKeyFormat;
  final _RemoteStringSource? privateKeyPassword;

  static _RemoteServiceAuthenticationConfig? parse(
    Map<String, Object?> rpcMap, {
    required RealmSettings realm,
  }) {
    final method = RemoteWampDelegateConfig._trimmedOrNull(
      rpcMap['service_auth_method'] as String?,
    );
    if (method == null || method == 'anonymous') {
      return null;
    }
    switch (method) {
      case 'ticket':
      case 'wampcra':
      case 'wamp-scram':
        final secret = _RemoteStringSource.parse(rpcMap, 'service_auth_secret');
        if (secret == null) {
          throw ArgumentError('Missing required rpc.service_auth_secret');
        }
        return _RemoteServiceAuthenticationConfig._(
          method: method,
          secret: secret,
        );
      case 'cryptosign':
        final privateKey = _RemoteStringSource.parse(
          rpcMap,
          'service_private_key',
        );
        if (privateKey == null) {
          throw ArgumentError('Missing required rpc.service_private_key');
        }
        return _RemoteServiceAuthenticationConfig._(
          method: method,
          privateKey: privateKey,
          privateKeyFormat:
              RemoteWampDelegateConfig._trimmedOrNull(
                rpcMap['service_private_key_format'] as String?,
              ) ??
              'base64',
          privateKeyPassword: _RemoteStringSource.parse(
            rpcMap,
            'service_private_key_password',
          ),
        );
      default:
        throw ArgumentError(
          'Unsupported rpc.service_auth_method "$method" for realm ${realm.name}.',
        );
    }
  }

  Map<String, Object?> cacheKeyMap() => <String, Object?>{
    'method': method,
    'secret': secret?.cacheKeyMap(),
    'privateKey': privateKey?.cacheKeyMap(),
    'privateKeyFormat': privateKeyFormat,
    'privateKeyPassword': privateKeyPassword?.cacheKeyMap(),
  };

  Future<Map<String, Object?>> fingerprintMap() async => <String, Object?>{
    'method': method,
    'secret': await secret?.fingerprint(),
    'privateKey': await privateKey?.fingerprint(),
    'privateKeyFormat': privateKeyFormat,
    'privateKeyPassword': await privateKeyPassword?.fingerprint(),
  };

  Future<List<AbstractAuthentication>> build() async {
    switch (method) {
      case 'ticket':
        return <AbstractAuthentication>[
          TicketAuthentication(await secret!.resolveRequired()),
        ];
      case 'wampcra':
        return <AbstractAuthentication>[
          CraAuthentication(await secret!.resolveRequired()),
        ];
      case 'wamp-scram':
        return <AbstractAuthentication>[
          ScramAuthentication(await secret!.resolveRequired()),
        ];
      case 'cryptosign':
        final key = await privateKey!.resolveRequired();
        final password = await privateKeyPassword?.resolve();
        return <AbstractAuthentication>[
          switch (privateKeyFormat) {
            'base64' => CryptosignAuthentication.fromBase64(key),
            'hex' => CryptosignAuthentication.fromHex(key),
            'openssh' => CryptosignAuthentication.fromOpenSshPrivateKey(
              key,
              password: password,
            ),
            'putty' => CryptosignAuthentication.fromPuttyPrivateKey(
              key,
              password: password,
            ),
            'pkcs8' => CryptosignAuthentication.fromPkcs8PrivateKey(key),
            _ => throw ArgumentError(
              'Unsupported rpc.service_private_key_format: $privateKeyFormat',
            ),
          },
        ];
      default:
        throw StateError('Unsupported authentication method $method');
    }
  }
}

class _RemoteStringSource {
  const _RemoteStringSource._({
    this.inlineValue,
    this.filePath,
    required this.field,
  });

  final String? inlineValue;
  final String? filePath;
  final String field;

  static _RemoteStringSource? parse(Map<String, Object?> values, String field) {
    final hasInline = values.containsKey(field);
    final fileField = '${field}_file';
    final hasFile = values.containsKey(fileField);
    if (!hasInline && !hasFile) {
      return null;
    }
    final inlineValue = _readStringOption(values[field], field);
    final filePath = _readStringOption(values[fileField], fileField);
    if (inlineValue != null && filePath != null) {
      throw ArgumentError(
        'Only one of $field or $fileField may be configured.',
      );
    }
    if (inlineValue == null && filePath == null) {
      return null;
    }
    return _RemoteStringSource._(
      inlineValue: inlineValue,
      filePath: filePath,
      field: field,
    );
  }

  static _RemoteStringSource? parseWithFallback({
    required Map<String, Object?> primary,
    required Map<String, Object?> fallback,
    required String field,
  }) {
    final source = parse(primary, field);
    return source ?? parse(fallback, field);
  }

  Map<String, Object?> cacheKeyMap() => <String, Object?>{
    'field': field,
    if (inlineValue != null) 'inlineHash': _stableFingerprint(inlineValue!),
    if (filePath != null) 'filePath': filePath,
  };

  Future<String?> fingerprint() async {
    final value = await resolve();
    return value == null ? null : _stableFingerprint(value);
  }

  Future<String?> resolve() async {
    if (inlineValue != null) {
      return inlineValue;
    }
    final path = filePath;
    if (path == null) {
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Missing configured file for $field: $path');
    }
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  Future<String> resolveRequired() async {
    final value = await resolve();
    if (value == null) {
      throw StateError('Missing required value for $field');
    }
    return value;
  }

  static String? _readStringOption(Object? value, String field) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ArgumentError.value(value, field, 'Expected a string value.');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

typedef RemoteWampProcedureCall =
    Future<RemoteWampProcedureCallResult> Function(
      String procedure, {
      Map<String, Object?>? argumentsKeywords,
    });

class RemoteWampProcedureCallResult {
  const RemoteWampProcedureCallResult({this.arguments, this.argumentsKeywords});

  final List<dynamic>? arguments;
  final Map<String, dynamic>? argumentsKeywords;
}

/// Remote-auth delegate backed by WAMP procedure calls supplied by the caller.
///
/// This keeps the remote auth WAMP contract reusable for embedded router flows:
/// a [RouterSession] can provide the procedure caller without opening a TCP
/// rawsocket/websocket connection back into the same process.
class RemoteWampProcedureDelegate implements RemoteAuthenticatorDelegate {
  RemoteWampProcedureDelegate({
    required RemoteWampProcedureCall call,
    this.helloProcedure = 'authenticate.hello',
    this.authenticateProcedure = 'authenticate.authenticate',
    this.abortProcedure = 'authenticate.abort',
    this.callTimeout = const Duration(seconds: 5),
    FutureOr<String?> Function()? resolveAuthToken,
  }) : _call = call,
       _resolveAuthToken = resolveAuthToken;

  final RemoteWampProcedureCall _call;
  final FutureOr<String?> Function()? _resolveAuthToken;
  final String helloProcedure;
  final String authenticateProcedure;
  final String abortProcedure;
  final Duration callTimeout;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    try {
      final result = await _call(
        helloProcedure,
        argumentsKeywords: _RemoteWampPayloadCodec.buildHelloRequestPayload(
          request,
          authToken: await _authTokenFor(request.options),
        ),
      ).timeout(callTimeout);
      return _RemoteWampPayloadCodec.decodeHelloResponse(
        result.argumentsKeywords,
        result.arguments,
      );
    } on wamp_core.Error catch (error) {
      return RemoteHelloResponse.failure(
        _RemoteWampPayloadCodec.failureFromCallError(error),
      );
    } on TimeoutException {
      throw RemoteDelegateUnavailableException(
        'Remote authenticator hello call timed out',
      );
    } on StateError catch (error) {
      throw RemoteDelegateUnavailableException(error.toString());
    }
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    try {
      final result = await _call(
        authenticateProcedure,
        argumentsKeywords:
            _RemoteWampPayloadCodec.buildAuthenticateRequestPayload(
              request,
              authToken: await _authTokenFor(request.options),
            ),
      ).timeout(callTimeout);
      return _RemoteWampPayloadCodec.decodeAuthenticateResponse(
        result.argumentsKeywords,
        result.arguments,
      );
    } on wamp_core.Error catch (error) {
      return RemoteAuthenticateResponse.failure(
        _RemoteWampPayloadCodec.failureFromCallError(error),
      );
    } on TimeoutException {
      throw RemoteDelegateUnavailableException(
        'Remote authenticator authenticate call timed out',
      );
    } on StateError catch (error) {
      throw RemoteDelegateUnavailableException(error.toString());
    }
  }

  @override
  Future<void> onAbort(RemoteAbortRequest request) async {
    try {
      await _call(
        abortProcedure,
        argumentsKeywords: _RemoteWampPayloadCodec.buildAbortRequestPayload(
          request,
          authToken: await _authTokenFor(request.options),
        ),
      ).timeout(callTimeout);
    } catch (_) {
      // Abort notifications are best-effort and must not break router cleanup.
    }
  }

  Future<String?> _authTokenFor(Map<String, Object?> options) async {
    final explicit = await _resolveAuthToken?.call();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final optionValue = options['auth_token'];
    if (optionValue is String && optionValue.trim().isNotEmpty) {
      return optionValue.trim();
    }
    return null;
  }
}

class WampRemoteAuthenticatorDelegate implements RemoteAuthenticatorDelegate {
  WampRemoteAuthenticatorDelegate(this._config);

  final RemoteWampDelegateConfig _config;
  client_pkg.Client? _client;
  client_pkg.Session? _session;
  Future<client_pkg.Session>? _connecting;
  String? _connectionFingerprint;

  Future<void> warmUpSession() async {
    try {
      await _ensureSession();
    } catch (_) {
      // Fail closed on real auth attempts, but keep startup warmup best-effort.
    }
  }

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    try {
      final session = await _ensureSession();
      final payload = await _buildHelloRequestPayload(request);
      final result = await session
          .callSinglePayload(_config.helloProcedure, argumentsKeywords: payload)
          .timeout(_config.callTimeout);
      return _decodeHelloResponse(result.argumentsKeywords, result.arguments);
    } on wamp_core.Error catch (error) {
      return RemoteHelloResponse.failure(_failureFromCallError(error));
    } on TimeoutException {
      _invalidateSession();
      throw RemoteDelegateUnavailableException(
        'Remote authenticator hello call timed out',
      );
    } on client_pkg.Abort catch (error) {
      _invalidateSession();
      throw RemoteDelegateUnavailableException(error.toString());
    } on StateError catch (error) {
      _invalidateSession();
      throw RemoteDelegateUnavailableException(error.toString());
    }
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    try {
      final session = await _ensureSession();
      final payload = await _buildAuthenticateRequestPayload(request);
      final result = await session
          .callSinglePayload(
            _config.authenticateProcedure,
            argumentsKeywords: payload,
          )
          .timeout(_config.callTimeout);
      return _decodeAuthenticateResponse(
        result.argumentsKeywords,
        result.arguments,
      );
    } on wamp_core.Error catch (error) {
      return RemoteAuthenticateResponse.failure(_failureFromCallError(error));
    } on TimeoutException {
      _invalidateSession();
      throw RemoteDelegateUnavailableException(
        'Remote authenticator authenticate call timed out',
      );
    } on client_pkg.Abort catch (error) {
      _invalidateSession();
      throw RemoteDelegateUnavailableException(error.toString());
    } on StateError catch (error) {
      _invalidateSession();
      throw RemoteDelegateUnavailableException(error.toString());
    }
  }

  @override
  Future<void> onAbort(RemoteAbortRequest request) async {
    try {
      final session = await _ensureSession();
      final payload = await _buildAbortRequestPayload(request);
      await session
          .callSinglePayload(_config.abortProcedure, argumentsKeywords: payload)
          .timeout(_config.callTimeout);
    } catch (_) {
      _invalidateSession();
    }
  }

  Future<client_pkg.Session> _ensureSession() async {
    final existing = _session;
    if (existing != null) {
      final currentFingerprint = await _config.connectionFingerprint();
      if (_connectionFingerprint == currentFingerprint) {
        return existing;
      }
      _invalidateSession();
    }
    final connecting = _connecting;
    if (connecting != null) {
      return connecting;
    }
    final future = _connect();
    _connecting = future;
    return future.whenComplete(() {
      if (identical(_connecting, future)) {
        _connecting = null;
      }
    });
  }

  Future<client_pkg.Session> _connect() async {
    final connectionFingerprint = await _config.connectionFingerprint();
    final authenticationMethods = await _config.buildAuthenticationMethods();
    final client = client_pkg.Client(
      realm: _config.realm,
      transport: await _buildTransport(_config.transport),
      authId: _config.authId,
      authRole: _config.authRole,
      authExtra: _config.authExtra,
      authenticationMethods: authenticationMethods,
    );
    try {
      final session = await client
          .connect(options: client_pkg.ClientConnectOptions(reconnectCount: 0))
          .first
          .timeout(_config.connectTimeout);
      _client = client;
      _session = session;
      _connectionFingerprint = connectionFingerprint;
      unawaited(
        Future.any<dynamic>([
          session.onDisconnect,
          session.onConnectionLost,
        ]).whenComplete(_invalidateSession),
      );
      return session;
    } catch (_) {
      await client.disconnect();
      rethrow;
    }
  }

  void _invalidateSession() {
    final client = _client;
    _client = null;
    _session = null;
    _connecting = null;
    _connectionFingerprint = null;
    if (client != null) {
      unawaited(client.disconnect());
    }
  }

  Future<Map<String, Object?>> _buildHelloRequestPayload(
    RemoteHelloRequest request,
  ) async {
    return _RemoteWampPayloadCodec.buildHelloRequestPayload(
      request,
      authToken: await _config.resolveAuthToken(),
    );
  }

  Future<Map<String, Object?>> _buildAuthenticateRequestPayload(
    RemoteAuthenticateRequest request,
  ) async {
    return _RemoteWampPayloadCodec.buildAuthenticateRequestPayload(
      request,
      authToken: await _config.resolveAuthToken(),
    );
  }

  Future<Map<String, Object?>> _buildAbortRequestPayload(
    RemoteAbortRequest request,
  ) async {
    return _RemoteWampPayloadCodec.buildAbortRequestPayload(
      request,
      authToken: await _config.resolveAuthToken(),
    );
  }

  RemoteHelloResponse _decodeHelloResponse(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    return _RemoteWampPayloadCodec.decodeHelloResponse(
      argumentsKeywords,
      arguments,
    );
  }

  RemoteAuthenticateResponse _decodeAuthenticateResponse(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    return _RemoteWampPayloadCodec.decodeAuthenticateResponse(
      argumentsKeywords,
      arguments,
    );
  }

  AuthFailure _failureFromCallError(wamp_core.Error error) {
    return _RemoteWampPayloadCodec.failureFromCallError(error);
  }
}

class _RemoteWampPayloadCodec {
  static Map<String, Object?> buildHelloRequestPayload(
    RemoteHelloRequest request, {
    String? authToken,
  }) {
    return <String, Object?>{
      'transactionId': request.transactionId,
      'hello': <String, Object?>{
        'realm': request.realmSettings.name,
        'sessionId': request.context.sessionId,
        'details': minimalHelloDetails(request.context.helloDetails),
        'transport': <String, Object?>{
          'connectionId': request.context.transport.connectionId,
          if (request.context.transport.peerAddress != null)
            'peerAddress': request.context.transport.peerAddress,
          'isEncrypted': request.context.transport.isEncrypted,
          if (request.context.transport.protocol != null)
            'protocol': request.context.transport.protocol,
          if (request.context.transport.websocketProtocol != null)
            'websocketProtocol': request.context.transport.websocketProtocol,
          if (request.context.transport.websocketSerializer != null)
            'websocketSerializer':
                request.context.transport.websocketSerializer,
        },
      },
      'auth_token': ?authToken,
    };
  }

  static Map<String, Object?> buildAuthenticateRequestPayload(
    RemoteAuthenticateRequest request, {
    String? authToken,
  }) {
    return <String, Object?>{
      'transactionId': request.transactionId,
      'authenticate': <String, Object?>{
        'signature': request.authenticate.signature,
        if (request.authenticate.extra.isNotEmpty)
          'extra': Map<String, Object?>.from(request.authenticate.extra),
      },
      'auth_token': ?authToken,
    };
  }

  static Map<String, Object?> buildAbortRequestPayload(
    RemoteAbortRequest request, {
    String? authToken,
  }) {
    return <String, Object?>{
      'transactionId': request.transactionId,
      'reason': ?request.reason,
      'auth_token': ?authToken,
    };
  }

  static Map<String, Object?> minimalHelloDetails(
    Map<String, Object?> helloDetails,
  ) {
    final minimal = <String, Object?>{};
    final authId = helloDetails['authid'];
    if (authId is String && authId.isNotEmpty) {
      minimal['authid'] = authId;
    }
    final authMethods = helloDetails['authmethods'];
    if (authMethods is Iterable) {
      minimal['authmethods'] = authMethods
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    final authExtra = helloDetails['authextra'];
    if (authExtra is Map && authExtra.isNotEmpty) {
      minimal['authextra'] = Map<String, Object?>.from(
        authExtra.cast<Object?, Object?>(),
      );
    }
    return minimal;
  }

  static RemoteHelloResponse decodeHelloResponse(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    final map = resultMap(argumentsKeywords, arguments);
    final status = map['status'];
    if (status == 'challenge') {
      return RemoteHelloResponse.challenge(
        RemoteChallenge(
          authId: asRequiredString(map, 'authId'),
          challenge: asStringObjectMap(map, 'challenge'),
          extra:
              asOptionalStringObjectMap(map, 'extra') ??
              const <String, Object?>{},
        ),
      );
    }
    if (status == 'success') {
      return RemoteHelloResponse.success(
        AuthSuccess(
          authId: asRequiredString(map, 'authId'),
          authRole: asRequiredString(map, 'authRole'),
          details:
              asOptionalStringObjectMap(map, 'details') ??
              const <String, Object?>{},
        ),
      );
    }
    if (status == 'failure') {
      return RemoteHelloResponse.failure(failureFromResultMap(map));
    }
    if (map.containsKey('challenge')) {
      return RemoteHelloResponse.challenge(
        RemoteChallenge(
          authId:
              asOptionalString(map, 'authId') ??
              asRequiredString(map, 'auth_id'),
          challenge: asStringObjectMap(map, 'challenge'),
          extra:
              asOptionalStringObjectMap(map, 'extra') ??
              const <String, Object?>{},
        ),
      );
    }
    if (map.containsKey('authRole') || map.containsKey('auth_role')) {
      return RemoteHelloResponse.success(
        AuthSuccess(
          authId:
              asOptionalString(map, 'authId') ??
              asRequiredString(map, 'auth_id'),
          authRole:
              asOptionalString(map, 'authRole') ??
              asRequiredString(map, 'auth_role'),
          details:
              asOptionalStringObjectMap(map, 'details') ??
              const <String, Object?>{},
        ),
      );
    }
    return RemoteHelloResponse.failure(
      const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Malformed remote hello response',
      ),
    );
  }

  static RemoteAuthenticateResponse decodeAuthenticateResponse(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    final map = resultMap(argumentsKeywords, arguments);
    final status = map['status'];
    if (status == 'success') {
      return RemoteAuthenticateResponse.success(
        AuthSuccess(
          authId: asRequiredString(map, 'authId'),
          authRole: asRequiredString(map, 'authRole'),
          details:
              asOptionalStringObjectMap(map, 'details') ??
              const <String, Object?>{},
        ),
      );
    }
    if (status == 'failure') {
      return RemoteAuthenticateResponse.failure(failureFromResultMap(map));
    }
    if (map.containsKey('authRole') || map.containsKey('auth_role')) {
      return RemoteAuthenticateResponse.success(
        AuthSuccess(
          authId:
              asOptionalString(map, 'authId') ??
              asRequiredString(map, 'auth_id'),
          authRole:
              asOptionalString(map, 'authRole') ??
              asRequiredString(map, 'auth_role'),
          details:
              asOptionalStringObjectMap(map, 'details') ??
              const <String, Object?>{},
        ),
      );
    }
    return RemoteAuthenticateResponse.failure(
      const AuthFailure(
        reason: wamp_core.Error.notAuthorized,
        message: 'Malformed remote authenticate response',
      ),
    );
  }

  static Map<String, Object?> resultMap(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
      return Map<String, Object?>.from(argumentsKeywords);
    }
    if (arguments != null &&
        arguments.isNotEmpty &&
        arguments.first is Map<Object?, Object?>) {
      return Map<String, Object?>.from(
        (arguments.first as Map<Object?, Object?>),
      );
    }
    return const <String, Object?>{};
  }

  static AuthFailure failureFromResultMap(Map<String, Object?> map) {
    return AuthFailure(
      reason: asOptionalString(map, 'reason') ?? wamp_core.Error.notAuthorized,
      message: asOptionalString(map, 'message'),
      details:
          asOptionalStringObjectMap(map, 'details') ??
          const <String, Object?>{},
      arguments: map['arguments'] is List
          ? List<dynamic>.from(map['arguments'] as List)
          : null,
      argumentsKeywords: asOptionalStringObjectMap(map, 'argumentsKeywords'),
    );
  }

  static AuthFailure failureFromCallError(wamp_core.Error error) {
    final message =
        error.argumentsKeywords?['message'] as String? ??
        (error.arguments?.isNotEmpty == true
            ? error.arguments!.first as String?
            : null);
    final detailsRaw = error.argumentsKeywords?['details'];
    return AuthFailure(
      reason: error.error ?? wamp_core.Error.notAuthorized,
      message: message,
      details: detailsRaw is Map
          ? Map<String, Object?>.from(detailsRaw.cast<Object?, Object?>())
          : const <String, Object?>{},
      arguments: error.arguments,
      argumentsKeywords: error.argumentsKeywords,
    );
  }

  static String asRequiredString(Map<String, Object?> map, String key) {
    final value = asOptionalString(map, key);
    if (value == null) {
      throw StateError('Missing required key "$key" in remote auth result.');
    }
    return value;
  }

  static String? asOptionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static Map<String, Object?> asStringObjectMap(
    Map<String, Object?> map,
    String key,
  ) {
    final value = asOptionalStringObjectMap(map, key);
    if (value == null) {
      throw StateError('Missing required map "$key" in remote auth result.');
    }
    return value;
  }

  static Map<String, Object?>? asOptionalStringObjectMap(
    Map<String, Object?> map,
    String key,
  ) {
    final value = map[key];
    if (value is Map) {
      return Map<String, Object?>.from(value.cast<Object?, Object?>());
    }
    return null;
  }
}

class RemoteWampDelegateRegistry {
  static final Map<String, RemoteAuthenticatorDelegate> _delegates =
      <String, RemoteAuthenticatorDelegate>{};

  static RemoteAuthenticatorDelegate forConfig(
    RemoteWampDelegateConfig config,
  ) {
    if (config.transport.type == 'internal') {
      final delegate = _delegates[config.cacheKey()];
      if (delegate == null) {
        throw StateError(
          'Internal remote WAMP delegate is not registered for this worker.',
        );
      }
      return delegate;
    }
    return _delegates.putIfAbsent(
      config.cacheKey(),
      () => WampRemoteAuthenticatorDelegate(config),
    );
  }

  static void registerInternal(
    RemoteWampDelegateConfig config,
    RemoteAuthenticatorDelegate delegate,
  ) {
    if (config.transport.type != 'internal') {
      throw ArgumentError.value(
        config.transport.type,
        'config.transport.type',
        'Expected internal transport.',
      );
    }
    _delegates[config.cacheKey()] = delegate;
  }

  static Future<void> warmUpForSettings(RouterSettings settings) async {
    final futures = collectRemoteWampDelegateConfigsForSettings(settings)
        .where((config) => config.transport.type != 'internal')
        .map(
          (config) => (forConfig(config) as WampRemoteAuthenticatorDelegate)
              .warmUpSession(),
        );
    await Future.wait(futures, eagerError: false);
  }

  static void clear() {
    for (final delegate in _delegates.values) {
      if (delegate is WampRemoteAuthenticatorDelegate) {
        delegate._invalidateSession();
      }
    }
    _delegates.clear();
  }
}

Iterable<RemoteWampDelegateConfig> collectRemoteWampDelegateConfigsForSettings(
  RouterSettings settings,
) sync* {
  final seen = <String>{};
  for (final realm in settings.realms) {
    for (final method in realm.auth.methods) {
      if (method == 'anonymous') {
        continue;
      }
      final mergedOptions = _mergedRemoteAuthenticatorOptionsForMethod(
        settings: settings,
        realm: realm,
        method: method,
      );
      if (mergedOptions == null) {
        continue;
      }
      final config = RemoteAuthenticatorConfig.parse(mergedOptions, realm);
      final rpcDelegate = config.rpcDelegate;
      if (rpcDelegate == null) {
        continue;
      }
      final cacheKey = rpcDelegate.cacheKey();
      if (seen.add(cacheKey)) {
        yield rpcDelegate;
      }
    }
  }
}

Map<String, Object?>? _mergedRemoteAuthenticatorOptionsForMethod({
  required RouterSettings settings,
  required RealmSettings realm,
  required String method,
}) {
  final realmOptions = realm.auth.optionsFor(method);
  String? authenticatorKey;
  final options = <String, Object?>{};
  if (realmOptions != null) {
    authenticatorKey =
        realmOptions['authenticator'] as String? ??
        realmOptions['use'] as String?;
    options.addAll(realmOptions);
    options.remove('authenticator');
    options.remove('use');
  }

  final definitionKey = authenticatorKey ?? method;
  final definition = settings.authenticators[definitionKey];
  final factoryKey = definition?.type ?? definitionKey;
  if (factoryKey != 'remote') {
    return null;
  }

  if (definition != null) {
    options.addAll(definition.options);
  }
  options['authenticator'] ??= definitionKey;
  return options;
}

Future<client_pkg.AbstractTransport> _buildTransport(
  RemoteWampTransportConfig config,
) async {
  final tlsSecurityContext = await config.tls.buildSecurityContext();
  switch (config.type) {
    case 'rawsocket':
      switch (config.serializer) {
        case 'json':
          return client_socket.SocketTransport(
            config.host!,
            config.port!,
            json_serializer.Serializer(),
            _rawSocketSerializerJson,
            ssl: config.ssl,
            allowInsecureCertificates: config.tls.allowInsecureCertificates,
            tlsSecurityContext: tlsSecurityContext,
          );
        case 'msgpack':
          return client_socket.SocketTransport(
            config.host!,
            config.port!,
            msgpack_serializer.Serializer(),
            _rawSocketSerializerMsgpack,
            ssl: config.ssl,
            allowInsecureCertificates: config.tls.allowInsecureCertificates,
            tlsSecurityContext: tlsSecurityContext,
          );
        case 'cbor':
          return client_socket.SocketTransport(
            config.host!,
            config.port!,
            cbor_serializer.Serializer(),
            _rawSocketSerializerCbor,
            ssl: config.ssl,
            allowInsecureCertificates: config.tls.allowInsecureCertificates,
            tlsSecurityContext: tlsSecurityContext,
          );
        default:
          throw ArgumentError(
            'Unsupported remote rawsocket serializer ${config.serializer}.',
          );
      }
    case 'websocket':
      switch (config.serializer) {
        case 'json':
          return client_pkg.WebSocketTransport.withJsonSerializer(
            config.url!,
            config.headers,
            config.tls.allowInsecureCertificates,
            tlsSecurityContext,
          );
        case 'msgpack':
          return client_pkg.WebSocketTransport.withMsgpackSerializer(
            config.url!,
            config.headers,
            config.tls.allowInsecureCertificates,
            tlsSecurityContext,
          );
        case 'cbor':
          return client_pkg.WebSocketTransport.withCborSerializer(
            config.url!,
            config.headers,
            config.tls.allowInsecureCertificates,
            tlsSecurityContext,
          );
        default:
          throw ArgumentError(
            'Unsupported remote websocket serializer ${config.serializer}.',
          );
      }
    default:
      throw ArgumentError('Unsupported remote transport type ${config.type}.');
  }
}

const int _rawSocketSerializerJson = 1;
const int _rawSocketSerializerMsgpack = 2;
const int _rawSocketSerializerCbor = 3;

String _stableFingerprint(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

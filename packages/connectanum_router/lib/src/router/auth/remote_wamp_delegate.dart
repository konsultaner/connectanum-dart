import 'dart:async';
import 'dart:convert';

import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_client/socket.dart' as client_socket;
import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor_serializer;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack_serializer;

import '../config/authenticator.dart';
import '../config/router_settings.dart';
import 'remote_authenticator.dart';

class RemoteWampDelegateConfig {
  RemoteWampDelegateConfig({
    required this.realm,
    required this.transport,
    required this.helloProcedure,
    required this.authenticateProcedure,
    required this.abortProcedure,
    required this.callTimeout,
    required this.connectTimeout,
    required this.authToken,
    required this.authId,
    required this.authRole,
    required this.authExtra,
    required this.authenticationMethods,
  });

  final String realm;
  final RemoteWampTransportConfig transport;
  final String helloProcedure;
  final String authenticateProcedure;
  final String abortProcedure;
  final Duration callTimeout;
  final Duration connectTimeout;
  final String? authToken;
  final String? authId;
  final String? authRole;
  final Map<String, dynamic>? authExtra;
  final List<AbstractAuthentication> authenticationMethods;

  String cacheKey() => jsonEncode(<String, Object?>{
    'realm': realm,
    'transport': transport.cacheKeyMap(),
    'helloProcedure': helloProcedure,
    'authenticateProcedure': authenticateProcedure,
    'abortProcedure': abortProcedure,
    'callTimeoutMs': callTimeout.inMilliseconds,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'authToken': authToken,
    'authId': authId,
    'authRole': authRole,
    'authExtra': authExtra,
    'authenticationMethods': authenticationMethods
        .map(_authenticationCacheKey)
        .toList(growable: false),
  });

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
    final authToken =
        _trimmedOrNull(rpcMap['auth_token'] as String?) ??
        _trimmedOrNull(options['auth_token'] as String?);
    final authenticationMethods = _parseAuthenticationMethods(
      rpcMap,
      realm: realm,
    );
    return RemoteWampDelegateConfig(
      realm: realmName,
      transport: RemoteWampTransportConfig.parse(rpcMap),
      helloProcedure: helloProcedure,
      authenticateProcedure: authenticateProcedure,
      abortProcedure: abortProcedure,
      callTimeout: callTimeout,
      connectTimeout: connectTimeout,
      authToken: authToken,
      authId: authId,
      authRole: authRole,
      authExtra: authExtra,
      authenticationMethods: authenticationMethods,
    );
  }

  static List<AbstractAuthentication> _parseAuthenticationMethods(
    Map<String, Object?> rpcMap, {
    required RealmSettings realm,
  }) {
    final method = _trimmedOrNull(rpcMap['service_auth_method'] as String?);
    if (method == null || method == 'anonymous') {
      return const <AbstractAuthentication>[];
    }
    switch (method) {
      case 'ticket':
        final secret = _requireString(
          rpcMap['service_auth_secret'],
          'rpc.service_auth_secret',
        );
        return <AbstractAuthentication>[TicketAuthentication(secret)];
      case 'wampcra':
        final secret = _requireString(
          rpcMap['service_auth_secret'],
          'rpc.service_auth_secret',
        );
        return <AbstractAuthentication>[CraAuthentication(secret)];
      case 'wamp-scram':
        final secret = _requireString(
          rpcMap['service_auth_secret'],
          'rpc.service_auth_secret',
        );
        return <AbstractAuthentication>[ScramAuthentication(secret)];
      case 'cryptosign':
        final key = _requireString(
          rpcMap['service_private_key'],
          'rpc.service_private_key',
        );
        final format =
            _trimmedOrNull(rpcMap['service_private_key_format'] as String?) ??
            'base64';
        final password = _trimmedOrNull(
          rpcMap['service_private_key_password'] as String?,
        );
        return <AbstractAuthentication>[
          switch (format) {
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
              'Unsupported rpc.service_private_key_format: $format',
            ),
          },
        ];
      default:
        throw ArgumentError(
          'Unsupported rpc.service_auth_method "$method" for realm ${realm.name}.',
        );
    }
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

  static String _requireString(Object? value, String field) {
    final string = _trimmedOrNull(value as String?);
    if (string == null) {
      throw ArgumentError('Missing required $field');
    }
    return string;
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
    this.host,
    this.port,
    this.ssl = false,
    this.url,
    this.libraryPath,
    this.allowInsecureCertificates = false,
    this.headers = const <String, dynamic>{},
  });

  final String type;
  final String serializer;
  final String? host;
  final int? port;
  final bool ssl;
  final String? url;
  final String? libraryPath;
  final bool allowInsecureCertificates;
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
    switch (type) {
      case 'rawsocket':
        final host = (map['host'] as String?)?.trim();
        final portValue = map['port'];
        if (host == null || host.isEmpty || portValue is! num) {
          throw ArgumentError(
            'rpc.transport.rawsocket requires host and numeric port.',
          );
        }
        return RemoteWampTransportConfig._(
          type: type,
          serializer: serializer,
          host: host,
          port: portValue.toInt(),
          ssl: map['ssl'] == true,
          libraryPath: RemoteWampDelegateConfig._trimmedOrNull(
            map['library_path'] as String?,
          ),
          allowInsecureCertificates: map['allow_insecure_certificates'] == true,
        );
      case 'websocket':
        final url = (map['url'] as String?)?.trim();
        if (url == null || url.isEmpty) {
          throw ArgumentError('rpc.transport.websocket requires url.');
        }
        final headers = map['headers'];
        return RemoteWampTransportConfig._(
          type: type,
          serializer: serializer,
          url: url,
          libraryPath: RemoteWampDelegateConfig._trimmedOrNull(
            map['library_path'] as String?,
          ),
          allowInsecureCertificates: map['allow_insecure_certificates'] == true,
          headers: headers is Map
              ? Map<String, dynamic>.from(headers.cast<Object?, Object?>())
              : const <String, dynamic>{},
        );
      default:
        throw ArgumentError('Unsupported rpc.transport.type "$type".');
    }
  }

  Map<String, Object?> cacheKeyMap() => <String, Object?>{
    'type': type,
    'serializer': serializer,
    'host': host,
    'port': port,
    'ssl': ssl,
    'url': url,
    'libraryPath': libraryPath,
    'allowInsecureCertificates': allowInsecureCertificates,
    'headers': headers,
  };
}

class WampRemoteAuthenticatorDelegate implements RemoteAuthenticatorDelegate {
  WampRemoteAuthenticatorDelegate(this._config);

  final RemoteWampDelegateConfig _config;
  client_pkg.Client? _client;
  client_pkg.Session? _session;
  Future<client_pkg.Session>? _connecting;

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    try {
      final session = await _ensureSession();
      final result = await session
          .callSinglePayload(
            _config.helloProcedure,
            argumentsKeywords: _buildHelloRequestPayload(request),
          )
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
      final result = await session
          .callSinglePayload(
            _config.authenticateProcedure,
            argumentsKeywords: _buildAuthenticateRequestPayload(request),
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
      await session
          .callSinglePayload(
            _config.abortProcedure,
            argumentsKeywords: _buildAbortRequestPayload(request),
          )
          .timeout(_config.callTimeout);
    } catch (_) {
      _invalidateSession();
    }
  }

  Future<client_pkg.Session> _ensureSession() {
    final existing = _session;
    if (existing != null) {
      return Future<client_pkg.Session>.value(existing);
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
    final client = client_pkg.Client(
      realm: _config.realm,
      transport: _buildTransport(_config.transport),
      authId: _config.authId,
      authRole: _config.authRole,
      authExtra: _config.authExtra,
      authenticationMethods: _config.authenticationMethods,
    );
    try {
      final session = await client
          .connect(options: client_pkg.ClientConnectOptions(reconnectCount: 0))
          .first
          .timeout(_config.connectTimeout);
      _client = client;
      _session = session;
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
    if (client != null) {
      unawaited(client.disconnect());
    }
  }

  Map<String, Object?> _buildHelloRequestPayload(RemoteHelloRequest request) {
    return <String, Object?>{
      'transactionId': request.transactionId,
      'hello': <String, Object?>{
        'realm': request.realmSettings.name,
        'sessionId': request.context.sessionId,
        'details': _minimalHelloDetails(request.context.helloDetails),
        'transport': <String, Object?>{
          'connectionId': request.context.transport.connectionId,
          if (request.context.transport.peerAddress != null)
            'peerAddress': request.context.transport.peerAddress,
          'isEncrypted': request.context.transport.isEncrypted,
        },
      },
      if (_config.authToken != null) 'auth_token': _config.authToken,
    };
  }

  Map<String, Object?> _buildAuthenticateRequestPayload(
    RemoteAuthenticateRequest request,
  ) {
    final payload = <String, Object?>{
      'transactionId': request.transactionId,
      'authenticate': <String, Object?>{
        'signature': request.authenticate.signature,
        if (request.authenticate.extra.isNotEmpty)
          'extra': Map<String, Object?>.from(request.authenticate.extra),
      },
    };
    if (_config.authToken != null) {
      payload['auth_token'] = _config.authToken;
    }
    return payload;
  }

  Map<String, Object?> _buildAbortRequestPayload(RemoteAbortRequest request) {
    return <String, Object?>{
      'transactionId': request.transactionId,
      if (request.reason != null) 'reason': request.reason,
      if (_config.authToken != null) 'auth_token': _config.authToken,
    };
  }

  Map<String, Object?> _minimalHelloDetails(Map<String, Object?> helloDetails) {
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

  RemoteHelloResponse _decodeHelloResponse(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    final map = _resultMap(argumentsKeywords, arguments);
    final status = map['status'];
    if (status == 'challenge') {
      return RemoteHelloResponse.challenge(
        RemoteChallenge(
          authId: _asRequiredString(map, 'authId'),
          challenge: _asStringObjectMap(map, 'challenge'),
          extra:
              _asOptionalStringObjectMap(map, 'extra') ??
              const <String, Object?>{},
        ),
      );
    }
    if (status == 'success') {
      return RemoteHelloResponse.success(
        AuthSuccess(
          authId: _asRequiredString(map, 'authId'),
          authRole: _asRequiredString(map, 'authRole'),
          details:
              _asOptionalStringObjectMap(map, 'details') ??
              const <String, Object?>{},
        ),
      );
    }
    if (status == 'failure') {
      return RemoteHelloResponse.failure(_failureFromResultMap(map));
    }
    if (map.containsKey('challenge')) {
      return RemoteHelloResponse.challenge(
        RemoteChallenge(
          authId:
              _asOptionalString(map, 'authId') ??
              _asRequiredString(map, 'auth_id'),
          challenge: _asStringObjectMap(map, 'challenge'),
          extra:
              _asOptionalStringObjectMap(map, 'extra') ??
              const <String, Object?>{},
        ),
      );
    }
    if (map.containsKey('authRole') || map.containsKey('auth_role')) {
      return RemoteHelloResponse.success(
        AuthSuccess(
          authId:
              _asOptionalString(map, 'authId') ??
              _asRequiredString(map, 'auth_id'),
          authRole:
              _asOptionalString(map, 'authRole') ??
              _asRequiredString(map, 'auth_role'),
          details:
              _asOptionalStringObjectMap(map, 'details') ??
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

  RemoteAuthenticateResponse _decodeAuthenticateResponse(
    Map<String, dynamic>? argumentsKeywords,
    List<dynamic>? arguments,
  ) {
    final map = _resultMap(argumentsKeywords, arguments);
    final status = map['status'];
    if (status == 'success') {
      return RemoteAuthenticateResponse.success(
        AuthSuccess(
          authId: _asRequiredString(map, 'authId'),
          authRole: _asRequiredString(map, 'authRole'),
          details:
              _asOptionalStringObjectMap(map, 'details') ??
              const <String, Object?>{},
        ),
      );
    }
    if (status == 'failure') {
      return RemoteAuthenticateResponse.failure(_failureFromResultMap(map));
    }
    if (map.containsKey('authRole') || map.containsKey('auth_role')) {
      return RemoteAuthenticateResponse.success(
        AuthSuccess(
          authId:
              _asOptionalString(map, 'authId') ??
              _asRequiredString(map, 'auth_id'),
          authRole:
              _asOptionalString(map, 'authRole') ??
              _asRequiredString(map, 'auth_role'),
          details:
              _asOptionalStringObjectMap(map, 'details') ??
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

  Map<String, Object?> _resultMap(
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

  AuthFailure _failureFromResultMap(Map<String, Object?> map) {
    return AuthFailure(
      reason: _asOptionalString(map, 'reason') ?? wamp_core.Error.notAuthorized,
      message: _asOptionalString(map, 'message'),
      details:
          _asOptionalStringObjectMap(map, 'details') ??
          const <String, Object?>{},
      arguments: map['arguments'] is List
          ? List<dynamic>.from(map['arguments'] as List)
          : null,
      argumentsKeywords: _asOptionalStringObjectMap(map, 'argumentsKeywords'),
    );
  }

  AuthFailure _failureFromCallError(wamp_core.Error error) {
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

  String _asRequiredString(Map<String, Object?> map, String key) {
    final value = _asOptionalString(map, key);
    if (value == null) {
      throw StateError('Missing required key "$key" in remote auth result.');
    }
    return value;
  }

  String? _asOptionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  Map<String, Object?> _asStringObjectMap(
    Map<String, Object?> map,
    String key,
  ) {
    final value = _asOptionalStringObjectMap(map, key);
    if (value == null) {
      throw StateError('Missing required map "$key" in remote auth result.');
    }
    return value;
  }

  Map<String, Object?>? _asOptionalStringObjectMap(
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
  static final Map<String, WampRemoteAuthenticatorDelegate> _delegates =
      <String, WampRemoteAuthenticatorDelegate>{};

  static WampRemoteAuthenticatorDelegate forConfig(
    RemoteWampDelegateConfig config,
  ) {
    return _delegates.putIfAbsent(
      config.cacheKey(),
      () => WampRemoteAuthenticatorDelegate(config),
    );
  }

  static void clear() {
    for (final delegate in _delegates.values) {
      delegate._invalidateSession();
    }
    _delegates.clear();
  }
}

client_pkg.AbstractTransport _buildTransport(RemoteWampTransportConfig config) {
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
            allowInsecureCertificates: config.allowInsecureCertificates,
          );
        case 'msgpack':
          return client_socket.SocketTransport(
            config.host!,
            config.port!,
            msgpack_serializer.Serializer(),
            _rawSocketSerializerMsgpack,
            ssl: config.ssl,
            allowInsecureCertificates: config.allowInsecureCertificates,
          );
        case 'cbor':
          return client_socket.SocketTransport(
            config.host!,
            config.port!,
            cbor_serializer.Serializer(),
            _rawSocketSerializerCbor,
            ssl: config.ssl,
            allowInsecureCertificates: config.allowInsecureCertificates,
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
          );
        case 'msgpack':
          return client_pkg.WebSocketTransport.withMsgpackSerializer(
            config.url!,
            config.headers,
          );
        case 'cbor':
          return client_pkg.WebSocketTransport.withCborSerializer(
            config.url!,
            config.headers,
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

String _authenticationCacheKey(AbstractAuthentication authentication) {
  return switch (authentication) {
    TicketAuthentication() => 'ticket',
    CraAuthentication() => 'wampcra',
    ScramAuthentication() => 'wamp-scram',
    CryptosignAuthentication() => 'cryptosign',
    _ => authentication.getName(),
  };
}

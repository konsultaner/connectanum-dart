import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';

import 'auth_server.dart';

class AuthServerRouterBinding {
  AuthServerRouterBinding._({
    required this.router,
    required this.session,
    required this.procedures,
    NativeTransportRuntime? ownedRuntime,
    bool ownsRouter = false,
  }) : _ownedRuntime = ownedRuntime,
       _ownsRouter = ownsRouter;

  final RouterBinding router;
  final RouterSession session;
  final AuthServerProcedureBinding procedures;

  final NativeTransportRuntime? _ownedRuntime;
  final bool _ownsRouter;
  bool _closed = false;

  static Future<AuthServerRouterBinding> start({
    required AuthServer server,
    required RouterConfig config,
    required RouterSettings settings,
    String? nativeLibPath,
    String realmUri = 'connectanum.authenticate',
    String authId = 'auth-service',
    String authRole = 'internal',
    String helloProcedure = 'authenticate.hello',
    String authenticateProcedure = 'authenticate.authenticate',
    String abortProcedure = 'authenticate.abort',
    Duration workerPollInterval = const Duration(milliseconds: 1),
    Map<String, RouterHttpRouteHandler> httpRouteHandlers = const {},
    void Function(Object event)? onEvent,
  }) async {
    final runtime = NativeTransportRuntime(libraryPath: nativeLibPath);
    RouterBinding? router;
    try {
      runtime.start();
      router = Router(config, settings: settings).start(
        runtime,
        workerPollInterval: workerPollInterval,
        httpRouteHandlers: httpRouteHandlers,
        onEvent: onEvent,
      );
      return await _bind(
        server: server,
        router: router,
        realmUri: realmUri,
        authId: authId,
        authRole: authRole,
        helloProcedure: helloProcedure,
        authenticateProcedure: authenticateProcedure,
        abortProcedure: abortProcedure,
        ownedRuntime: runtime,
        ownsRouter: true,
      );
    } catch (_) {
      try {
        await router?.dispose();
      } catch (_) {}
      try {
        runtime.shutdown();
      } catch (_) {}
      runtime.dispose();
      rethrow;
    }
  }

  static Future<AuthServerRouterBinding> bind({
    required AuthServer server,
    required RouterBinding router,
    String realmUri = 'connectanum.authenticate',
    String authId = 'auth-service',
    String authRole = 'internal',
    String helloProcedure = 'authenticate.hello',
    String authenticateProcedure = 'authenticate.authenticate',
    String abortProcedure = 'authenticate.abort',
  }) {
    return _bind(
      server: server,
      router: router,
      realmUri: realmUri,
      authId: authId,
      authRole: authRole,
      helloProcedure: helloProcedure,
      authenticateProcedure: authenticateProcedure,
      abortProcedure: abortProcedure,
    );
  }

  static Future<AuthServerRouterBinding> _bind({
    required AuthServer server,
    required RouterBinding router,
    required String realmUri,
    required String authId,
    required String authRole,
    required String helloProcedure,
    required String authenticateProcedure,
    required String abortProcedure,
    NativeTransportRuntime? ownedRuntime,
    bool ownsRouter = false,
  }) async {
    final session = await router.createInternalSession(
      realmUri: realmUri,
      authId: authId,
      authRole: authRole,
    );
    AuthServerProcedureBinding? procedures;
    try {
      procedures = await AuthServerProcedureBinding.bind(
        server: server,
        session: session,
        helloProcedure: helloProcedure,
        authenticateProcedure: authenticateProcedure,
        abortProcedure: abortProcedure,
      );
      return AuthServerRouterBinding._(
        router: router,
        session: session,
        procedures: procedures,
        ownedRuntime: ownedRuntime,
        ownsRouter: ownsRouter,
      );
    } catch (_) {
      try {
        await procedures?.close();
      } catch (_) {}
      try {
        await session.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    Object? firstError;

    Future<void> record(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        firstError ??= error;
      }
    }

    await record(procedures.close);
    await record(session.close);
    if (_ownsRouter) {
      await record(router.dispose);
    }
    final runtime = _ownedRuntime;
    if (runtime != null) {
      await record(runtime.shutdown);
      await record(runtime.dispose);
    }

    if (firstError != null) {
      throw firstError!;
    }
  }
}

class AuthServerProcedureBinding {
  AuthServerProcedureBinding._({
    required AuthServer server,
    required RouterSession session,
    required this.helloProcedure,
    required this.authenticateProcedure,
    required this.abortProcedure,
  }) : _server = server,
       _session = session;

  final AuthServer _server;
  final RouterSession _session;
  final String helloProcedure;
  final String authenticateProcedure;
  final String abortProcedure;

  final Map<String, _PendingRemoteRequest> _pending =
      <String, _PendingRemoteRequest>{};

  Registered? _helloRegistration;
  Registered? _authenticateRegistration;
  Registered? _abortRegistration;

  static Future<AuthServerProcedureBinding> bind({
    required AuthServer server,
    required RouterSession session,
    String helloProcedure = 'authenticate.hello',
    String authenticateProcedure = 'authenticate.authenticate',
    String abortProcedure = 'authenticate.abort',
  }) async {
    final binding = AuthServerProcedureBinding._(
      server: server,
      session: session,
      helloProcedure: helloProcedure,
      authenticateProcedure: authenticateProcedure,
      abortProcedure: abortProcedure,
    );
    await binding._register();
    return binding;
  }

  Future<void> close() async {
    _pending.clear();
    if (_abortRegistration != null) {
      await _session.unregister(_abortRegistration!.registrationId);
      _abortRegistration = null;
    }
    if (_authenticateRegistration != null) {
      await _session.unregister(_authenticateRegistration!.registrationId);
      _authenticateRegistration = null;
    }
    if (_helloRegistration != null) {
      await _session.unregister(_helloRegistration!.registrationId);
      _helloRegistration = null;
    }
  }

  Future<void> _register() async {
    _helloRegistration = await _session.register(helloProcedure);
    _helloRegistration!.onLazyInvokePayload(_handleHello);

    _authenticateRegistration = await _session.register(authenticateProcedure);
    _authenticateRegistration!.onLazyInvokePayload(_handleAuthenticate);

    _abortRegistration = await _session.register(abortProcedure);
    _abortRegistration!.onLazyInvokePayload(_handleAbort);
  }

  Future<void> _handleHello(LazyInvocationPayload invocation) async {
    try {
      final payload = _payloadMap(invocation);
      final transactionId = _requiredString(payload, 'transactionId');
      final hello = _requiredMap(payload, 'hello');
      final realmName = _requiredString(hello, 'realm');
      final realmSettings = _server.settings.realms.firstWhere(
        (realm) => realm.name == realmName,
        orElse: () => throw _InvocationSchemaException(
          'Unknown remote auth realm "$realmName".',
        ),
      );
      final request = RemoteHelloRequest(
        realmSettings: realmSettings,
        context: _helloContext(realmSettings, hello),
        options: _optionsPayload(
          payload,
          reservedKeys: const {'transactionId', 'hello'},
        ),
        transactionId: transactionId,
      );
      final response = await _server.onHello(request);
      if (response.status == RemoteHelloStatus.challenge) {
        _pending[transactionId] = _PendingRemoteRequest(
          realmSettings: request.realmSettings,
          context: request.context,
          authId:
              request.context.helloDetails['authid'] as String? ?? 'unknown',
        );
      } else {
        _pending.remove(transactionId);
      }
      invocation.respondWith(
        argumentsKeywords: _helloResponsePayload(response),
      );
    } on _InvocationSchemaException catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.invalidArgument,
        arguments: <Object?>[error.message],
      );
    } catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.notAuthorized,
        arguments: <Object?>[error.toString()],
      );
    }
  }

  Future<void> _handleAuthenticate(LazyInvocationPayload invocation) async {
    try {
      final payload = _payloadMap(invocation);
      final transactionId = _requiredString(payload, 'transactionId');
      final pending = _pending.remove(transactionId);
      if (pending == null) {
        invocation.respondWith(
          argumentsKeywords: _authenticateResponsePayload(
            const RemoteAuthenticateResponse.failure(
              AuthFailure(
                reason: wamp_core.Error.protocolViolation,
                message: 'AUTHENTICATE received without pending challenge',
              ),
            ),
          ),
        );
        return;
      }
      final authenticate = _requiredMap(payload, 'authenticate');
      final request = RemoteAuthenticateRequest(
        realmSettings: pending.realmSettings,
        context: pending.context,
        authId: pending.authId,
        authenticate: AuthenticateMessage(
          signature: _requiredString(authenticate, 'signature'),
          extra:
              _optionalMap(authenticate, 'extra') ?? const <String, Object?>{},
        ),
        options: _optionsPayload(
          payload,
          reservedKeys: const {'transactionId', 'authenticate'},
        ),
        transactionId: transactionId,
      );
      final response = await _server.onAuthenticate(request);
      invocation.respondWith(
        argumentsKeywords: _authenticateResponsePayload(response),
      );
    } on _InvocationSchemaException catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.invalidArgument,
        arguments: <Object?>[error.message],
      );
    } catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.notAuthorized,
        arguments: <Object?>[error.toString()],
      );
    }
  }

  Future<void> _handleAbort(LazyInvocationPayload invocation) async {
    try {
      final payload = _payloadMap(invocation);
      final transactionId = _requiredString(payload, 'transactionId');
      final pending = _pending.remove(transactionId);
      if (pending != null) {
        await _server.onAbort(
          RemoteAbortRequest(
            realmSettings: pending.realmSettings,
            context: pending.context,
            authId: pending.authId,
            options: _optionsPayload(
              payload,
              reservedKeys: const {'transactionId', 'reason'},
            ),
            transactionId: transactionId,
            reason: _optionalString(payload, 'reason'),
          ),
        );
      }
      invocation.respondWith(
        argumentsKeywords: const <String, Object?>{'status': 'ok'},
      );
    } on _InvocationSchemaException catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.invalidArgument,
        arguments: <Object?>[error.message],
      );
    } catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.notAuthorized,
        arguments: <Object?>[error.toString()],
      );
    }
  }

  AuthenticatorContext _helloContext(
    RealmSettings realmSettings,
    Map<String, Object?> hello,
  ) {
    final details = _optionalMap(hello, 'details') ?? const <String, Object?>{};
    final transport =
        _optionalMap(hello, 'transport') ?? const <String, Object?>{};
    return AuthenticatorContext(
      realm: realmSettings,
      sessionId: _requiredInt(hello, 'sessionId'),
      transport: TransportMetadata(
        connectionId: _requiredInt(transport, 'connectionId'),
        peerAddress: _optionalString(transport, 'peerAddress'),
        isEncrypted: transport['isEncrypted'] == true,
      ),
      helloDetails: details,
    );
  }

  Map<String, Object?> _helloResponsePayload(RemoteHelloResponse response) {
    return switch (response.status) {
      RemoteHelloStatus.success => <String, Object?>{
        'status': 'success',
        'authId': response.success!.authId,
        'authRole': response.success!.authRole,
        if (response.success!.details.isNotEmpty)
          'details': response.success!.details,
      },
      RemoteHelloStatus.failure => _failurePayload(response.failure!),
      RemoteHelloStatus.challenge => <String, Object?>{
        'status': 'challenge',
        'authId': response.challenge!.authId,
        'challenge': response.challenge!.challenge,
        if (response.challenge!.extra.isNotEmpty)
          'extra': response.challenge!.extra,
      },
    };
  }

  Map<String, Object?> _authenticateResponsePayload(
    RemoteAuthenticateResponse response,
  ) {
    return switch (response.status) {
      RemoteAuthenticateStatus.success => <String, Object?>{
        'status': 'success',
        'authId': response.success!.authId,
        'authRole': response.success!.authRole,
        if (response.success!.details.isNotEmpty)
          'details': response.success!.details,
      },
      RemoteAuthenticateStatus.failure => _failurePayload(response.failure!),
    };
  }

  Map<String, Object?> _failurePayload(AuthFailure failure) {
    return <String, Object?>{
      'status': 'failure',
      'reason': failure.reason,
      if (failure.message != null) 'message': failure.message,
      if (failure.details.isNotEmpty) 'details': failure.details,
      if (failure.arguments != null) 'arguments': failure.arguments!,
      if (failure.argumentsKeywords != null)
        'argumentsKeywords': failure.argumentsKeywords!,
    };
  }

  Map<String, Object?> _payloadMap(LazyInvocationPayload invocation) {
    final kwargs = invocation.argumentsKeywords;
    if (kwargs != null && kwargs.isNotEmpty) {
      return Map<String, Object?>.from(kwargs);
    }
    final args = invocation.arguments;
    if (args != null && args.isNotEmpty && args.first is Map) {
      return Map<String, Object?>.from(
        (args.first as Map<Object?, Object?>).cast<Object?, Object?>(),
      );
    }
    throw const _InvocationSchemaException(
      'Remote auth RPC requires keyword arguments.',
    );
  }

  Map<String, Object?> _optionsPayload(
    Map<String, Object?> payload, {
    required Set<String> reservedKeys,
  }) {
    final result = <String, Object?>{};
    for (final entry in payload.entries) {
      if (reservedKeys.contains(entry.key)) {
        continue;
      }
      result[entry.key] = _normalizeValue(entry.value, context: entry.key);
    }
    return result;
  }

  Map<String, Object?> _requiredMap(Map<String, Object?> map, String key) {
    final value = _optionalMap(map, key);
    if (value == null) {
      throw _InvocationSchemaException('Missing required map "$key".');
    }
    return value;
  }

  Map<String, Object?>? _optionalMap(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! Map) {
      return null;
    }
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw _InvocationSchemaException(
          'Map "$key" contains a non-string key.',
        );
      }
      normalized[entry.key as String] = _normalizeValue(
        entry.value,
        context: '$key.${entry.key}',
      );
    }
    return normalized;
  }

  String _requiredString(Map<String, Object?> map, String key) {
    final value = _optionalString(map, key);
    if (value == null) {
      throw _InvocationSchemaException('Missing required string "$key".');
    }
    return value;
  }

  String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw _InvocationSchemaException('Missing required int "$key".');
  }

  Object? _normalizeValue(Object? value, {required String context}) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is List) {
      return List<Object?>.unmodifiable(
        value.map((entry) => _normalizeValue(entry, context: context)),
      );
    }
    if (value is Map) {
      final normalized = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String || (entry.key as String).isEmpty) {
          throw _InvocationSchemaException(
            '$context contains a non-string map key.',
          );
        }
        normalized[entry.key as String] = _normalizeValue(
          entry.value,
          context: '$context.${entry.key}',
        );
      }
      return Map<String, Object?>.unmodifiable(normalized);
    }
    throw _InvocationSchemaException(
      '$context contains unsupported value type ${value.runtimeType}.',
    );
  }
}

class _PendingRemoteRequest {
  const _PendingRemoteRequest({
    required this.realmSettings,
    required this.context,
    required this.authId,
  });

  final RealmSettings realmSettings;
  final AuthenticatorContext context;
  final String authId;
}

class _InvocationSchemaException implements Exception {
  const _InvocationSchemaException(this.message);

  final String message;
}

part of '../router_instance.dart';

Future<void> _handleHello(
  SendPort bossPort,
  SendPort? statePort,
  RouterSettings settings,
  WorkerConnectionState state,
  Hello hello,
  int connectionId,
  RealmContextCache? realmContexts,
  int workerId,
) async {
  if (state.phase != HandshakePhase.awaitingHello) {
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.protocolViolation,
      message: 'HELLO received in unexpected state',
    );
    state.phase = HandshakePhase.aborted;
    return;
  }

  final realmUri = hello.realm;
  if (realmUri == null || realmUri.isEmpty) {
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.errorInvalidUri,
      message: 'Missing realm in HELLO',
    );
    state.phase = HandshakePhase.aborted;
    return;
  }

  RealmSettings? realmSettings;
  for (final realm in settings.realms) {
    if (realm.name == realmUri) {
      realmSettings = realm;
      break;
    }
  }
  if (realmSettings == null) {
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.noSuchRealm,
      message: 'Realm $realmUri is not configured',
    );
    state.phase = HandshakePhase.aborted;
    return;
  }

  state.realmSettings = realmSettings;
  state.realmUri = realmUri;

  final selection = resolveAuthenticatorSelection(
    settings: settings,
    listenerSettings: state.listenerSettings,
    realmSettings: realmSettings,
    hello: hello,
  );
  final pendingAuthId = hello.details.authid;
  state.pendingAuthId = pendingAuthId;
  if (pendingAuthId != null &&
      AuthSecurityTracker.isLocked(
        realmUri,
        pendingAuthId,
        realmSettings.limits,
      )) {
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.notAuthorized,
      message: 'Too many failed authentication attempts',
    );
    AuthAuditLogger.failure(
      realmUri: realmUri,
      method: 'unknown',
      authId: pendingAuthId,
      message: 'locked out',
    );
    state.pendingAuthId = null;
    state.phase = HandshakePhase.aborted;
    return;
  }
  if (selection == null) {
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.notAuthorized,
      message: 'No acceptable authentication method',
    );
    if (pendingAuthId != null) {
      AuthSecurityTracker.recordFailure(
        realmUri,
        pendingAuthId,
        realmSettings.limits,
      );
      AuthAuditLogger.failure(
        realmUri: realmUri,
        method: 'unknown',
        authId: pendingAuthId,
        message: 'no acceptable method',
      );
    }
    state.phase = HandshakePhase.aborted;
    return;
  }

  statePort?.send(
    RealmEnsureCommand(realmUri: realmUri, options: const <String, Object?>{}),
  );
  realmContexts?.invalidate(realmUri);

  state.authMethod = selection.method;

  if (selection.isAnonymous) {
    await _openAnonymousSession(
      bossPort: bossPort,
      statePort: statePort,
      state: state,
      hello: hello,
      connectionId: connectionId,
      workerId: workerId,
    );
    return;
  }

  try {
    final sessionId = await allocateSessionId(statePort);
    state.sessionId = sessionId;

    final authenticator = await selection.factory!.create(
      realmSettings,
      selection.options,
    );
    state.authenticator = authenticator;

    final context = AuthenticatorContext(
      realm: realmSettings,
      sessionId: sessionId,
      transport: buildTransportMetadata(
        listener: state.listener,
        connectionId: connectionId,
      ),
      helloDetails: helloDetailsToMap(hello.details),
    );
    state.authContext = context;

    final result = await authenticator.onHello(context);
    state.challengeIssuedAt = DateTime.now();
    await _applyAuthResult(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      realmSettings: realmSettings,
      state: state,
      method: selection.method,
      result: result,
      connectionId: connectionId,
      workerId: workerId,
    );
  } catch (error) {
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.notAuthorized,
      message: 'Authentication failed: $error',
    );
    state.phase = HandshakePhase.aborted;
    state.authenticator = null;
    state.authContext = null;
  }
}

Future<void> _handleAuthenticate(
  SendPort bossPort,
  SendPort? statePort,
  RealmContextCache? realmContexts,
  WorkerConnectionState state,
  authenticate_msg.Authenticate authenticate,
  int connectionId,
  int workerId,
) async {
  if (state.phase != HandshakePhase.awaitingAuthenticate ||
      state.authenticator == null ||
      state.authContext == null ||
      state.realmSettings == null ||
      state.authMethod == null) {
    await _abortPendingAuthentication(state, reason: 'unexpected_authenticate');
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.protocolViolation,
      message: 'AUTHENTICATE unexpected',
    );
    state.phase = HandshakePhase.aborted;
    state.authenticator = null;
    state.authContext = null;
    return;
  }

  final signature = authenticate.signature;
  if (signature == null || signature.isEmpty) {
    await _abortPendingAuthentication(state, reason: 'missing_signature');
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.protocolViolation,
      message: 'Missing signature in AUTHENTICATE',
    );
    state.phase = HandshakePhase.aborted;
    state.authenticator = null;
    state.authContext = null;
    return;
  }

  final message = AuthenticateMessage(
    signature: signature,
    extra: authenticate.extra ?? const {},
  );

  final limits = state.realmSettings?.limits;
  if (limits != null &&
      limits.authTimeoutMs > 0 &&
      state.challengeIssuedAt != null) {
    final deadline = state.challengeIssuedAt!.add(
      Duration(milliseconds: limits.authTimeoutMs),
    );
    if (DateTime.now().isAfter(deadline)) {
      await _abortPendingAuthentication(state, reason: 'challenge_timeout');
      await sendAbort(
        bossPort,
        state,
        connectionId,
        wamp_core.Error.authenticationFailed,
        message: 'Authentication timed out',
      );
      final authId = state.pendingAuthId;
      final realmUri = state.realmUri;
      if (realmUri != null && authId != null) {
        AuthSecurityTracker.recordFailure(realmUri, authId, limits);
        AuthAuditLogger.failure(
          realmUri: realmUri,
          method: state.authMethod ?? 'unknown',
          authId: authId,
          message: 'challenge timeout',
        );
      }
      state.phase = HandshakePhase.aborted;
      state.authenticator = null;
      state.authContext = null;
      state.pendingAuthId = null;
      state.challengeIssuedAt = null;
      return;
    }
  }

  try {
    final result = await state.authenticator!.onAuthenticate(
      state.authContext!,
      message,
    );
    await _applyAuthResult(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      realmSettings: state.realmSettings!,
      state: state,
      method: state.authMethod!,
      result: result,
      connectionId: connectionId,
      workerId: workerId,
    );
  } catch (error) {
    await _abortPendingAuthentication(state, reason: 'authenticate_exception');
    await sendAbort(
      bossPort,
      state,
      connectionId,
      wamp_core.Error.notAuthorized,
      message: 'Authentication failed: $error',
    );
    state.phase = HandshakePhase.aborted;
    state.authenticator = null;
    state.authContext = null;
  }
}

Future<void> _abortPendingAuthentication(
  WorkerConnectionState state, {
  String? reason,
}) async {
  if (state.phase != HandshakePhase.awaitingAuthenticate) {
    return;
  }
  final authenticator = state.authenticator;
  final authContext = state.authContext;
  if (authenticator == null || authContext == null) {
    return;
  }
  try {
    await authenticator.onAbort(authContext, reason: reason);
  } catch (_) {
    // Best-effort cleanup only.
  }
}

Future<void> _openAnonymousSession({
  required SendPort bossPort,
  required SendPort? statePort,
  required WorkerConnectionState state,
  required Hello hello,
  required int connectionId,
  required int workerId,
}) async {
  final serializer = state.serializer ?? NativeMessageSerializer.json;
  final realmUri = state.realmUri!;
  final authId = hello.details.authid ?? 'anonymous';
  final welcomeDetails = Details.forWelcome(
    realm: realmUri,
    authId: authId,
    authMethod: 'anonymous',
    authProvider: 'static',
    authRole: 'anonymous',
  );
  state.welcomeDetails = welcomeDetails;
  state.authMethod = 'anonymous';
  state.authenticator = null;
  state.authContext = null;
  state.pendingChallengeExtra = null;

  final sessionId = await allocateSessionId(statePort);
  state.sessionId = sessionId;

  await sendMessage(
    bossPort,
    connectionId,
    serializer,
    Welcome(sessionId, welcomeDetails),
  );

  state.phase = HandshakePhase.open;

  if (statePort != null) {
    final session = SessionRecord(
      id: sessionId,
      authId: authId,
      authRole: welcomeDetails.authrole,
      roles: extractRolesMap(welcomeDetails),
      workerId: workerId,
      connectionId: connectionId,
      lastActivity: DateTime.now(),
      listener: state.listener,
      protocol:
          state.protocol ??
          state.listener.settings?.primaryProtocol ??
          ListenerProtocol.rawsocket,
    );
    statePort.send(
      SessionOpenCommand(realmUri: state.realmUri!, session: session),
    );
  }
  try {
    bossPort.send({
      'type': _workerEventSessionOpened,
      'connectionId': connectionId,
      'sessionId': sessionId,
      'realmUri': realmUri,
    });
  } catch (_) {}

  AuthAuditLogger.success(
    realmUri: state.realmUri ?? 'unknown',
    method: 'anonymous',
    authId: authId,
  );
  state.pendingAuthId = null;
  state.challengeIssuedAt = null;
}

Future<void> _applyAuthResult({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required RealmSettings realmSettings,
  required WorkerConnectionState state,
  required String method,
  required AuthResult result,
  required int connectionId,
  required int workerId,
}) async {
  if (result.isChallenge && result.challenge != null) {
    state.pendingChallengeExtra = result.challenge!.extra;
    state.phase = HandshakePhase.awaitingAuthenticate;
    state.challengeIssuedAt = DateTime.now();
    await sendChallenge(
      bossPort,
      state,
      connectionId,
      method,
      result.challenge!,
    );
    return;
  }

  if (result.isSuccess && result.success != null) {
    await completeAuthenticatedSession(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      success: result.success!,
      method: method,
      connectionId: connectionId,
      workerId: workerId,
    );
    state.pendingAuthId = null;
    state.challengeIssuedAt = null;
    return;
  }

  if (result.isFailure && result.failure != null) {
    await handleAuthFailure(bossPort, state, connectionId, result.failure!);
  }
}

Future<void> sendChallenge(
  SendPort bossPort,
  WorkerConnectionState state,
  int connectionId,
  String method,
  AuthChallenge challenge,
) async {
  final serializer = state.serializer ?? NativeMessageSerializer.json;
  final extra = mapAuthChallengeToExtra(challenge.challenge);
  await sendMessage(
    bossPort,
    connectionId,
    serializer,
    Challenge(method, extra),
  );
}

Extra mapAuthChallengeToExtra(Map<String, Object?> values) {
  return Extra(
    challenge: values['challenge'] as String?,
    salt: values['salt'] as String?,
    keyLen: asInt(values['keylen']),
    channelBinding:
        values['channel_binding'] as String? ??
        values['channelBinding'] as String?,
    iterations: asInt(values['iterations']),
    memory: asInt(values['memory']),
    kdf: values['kdf'] as String?,
    nonce: values['nonce'] as String?,
  );
}

Future<void> completeAuthenticatedSession({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required AuthSuccess success,
  required String method,
  required int connectionId,
  required int workerId,
}) async {
  final serializer = state.serializer ?? NativeMessageSerializer.json;
  final sessionId = state.sessionId ?? await allocateSessionId(statePort);
  state.sessionId = sessionId;

  final rawAuthExtra = success.details['authextra'];
  Map<String, dynamic>? authExtra;
  if (rawAuthExtra is Map) {
    authExtra = Map<String, dynamic>.from(rawAuthExtra);
  }
  if (state.pendingChallengeExtra != null) {
    final pendingExtra = state.pendingChallengeExtra!['authextra'];
    if (pendingExtra is Map) {
      authExtra ??= <String, dynamic>{};
      authExtra.addAll(Map<String, dynamic>.from(pendingExtra));
    }
  }
  final authProvider =
      (success.details['authprovider'] ?? success.details['provider'])
          as String? ??
      'static';

  final welcomeDetails = Details.forWelcome(
    realm: state.realmUri,
    authId: success.authId,
    authMethod: method,
    authProvider: authProvider,
    authRole: success.authRole,
    authExtra: authExtra,
  );
  welcomeDetails.authrole = success.authRole;
  welcomeDetails.authmethod = method;
  welcomeDetails.authprovider = authProvider;
  state.welcomeDetails = welcomeDetails;
  state.phase = HandshakePhase.open;
  state.authenticator = null;
  state.authContext = null;
  state.pendingChallengeExtra = null;

  await sendMessage(
    bossPort,
    connectionId,
    serializer,
    Welcome(sessionId, welcomeDetails),
  );

  if (statePort != null) {
    final session = SessionRecord(
      id: sessionId,
      authId: success.authId,
      authRole: success.authRole,
      roles: extractRolesMap(welcomeDetails),
      workerId: workerId,
      connectionId: connectionId,
      lastActivity: DateTime.now(),
      listener: state.listener,
      protocol:
          state.protocol ??
          state.listener.settings?.primaryProtocol ??
          ListenerProtocol.rawsocket,
    );
    statePort.send(
      SessionOpenCommand(realmUri: state.realmUri!, session: session),
    );
  }
  try {
    bossPort.send({
      'type': _workerEventSessionOpened,
      'connectionId': connectionId,
      'sessionId': sessionId,
      'realmUri': state.realmUri,
    });
  } catch (_) {}

  if (realmContexts != null && state.realmUri != null) {
    realmContexts.invalidate(state.realmUri!);
  }

  final realmUri = state.realmUri;
  if (realmUri != null) {
    AuthSecurityTracker.recordSuccess(realmUri, success.authId);
    AuthAuditLogger.success(
      realmUri: realmUri,
      method: method,
      authId: success.authId,
    );
  }
  state.pendingAuthId = null;
  state.challengeIssuedAt = null;
}

Future<void> handleAuthFailure(
  SendPort bossPort,
  WorkerConnectionState state,
  int connectionId,
  AuthFailure failure,
) async {
  await _abortPendingAuthentication(state, reason: failure.reason);
  await sendAbort(
    bossPort,
    state,
    connectionId,
    failure.reason,
    message: failure.message,
    details: failure.details.isEmpty ? null : failure.details,
    arguments: failure.arguments,
    argumentsKeywords: failure.argumentsKeywords,
  );
  final realmUri = state.realmUri;
  final authId = state.pendingAuthId;
  final limits = state.realmSettings?.limits;
  if (realmUri != null && authId != null && limits != null) {
    AuthSecurityTracker.recordFailure(realmUri, authId, limits);
  }
  if (realmUri != null) {
    AuthAuditLogger.failure(
      realmUri: realmUri,
      method: state.authMethod ?? 'unknown',
      authId: authId,
      message: failure.message,
    );
  }
  state.phase = HandshakePhase.aborted;
  state.authenticator = null;
  state.authContext = null;
  state.pendingChallengeExtra = null;
  state.pendingAuthId = null;
  state.challengeIssuedAt = null;
}

int? asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

Map<String, Object?> extractRolesMap(Details details) {
  final welcome = Welcome(0, details);
  final encoded = _jsonSerializer.serializeToString(welcome);
  final decoded = jsonDecode(encoded) as List<dynamic>;
  final detailsMap = decoded[2] as Map<String, dynamic>;
  final roles = detailsMap['roles'];
  if (roles is Map<String, dynamic>) {
    return Map<String, Object?>.from(roles);
  }
  return <String, Object?>{};
}

@visibleForTesting
dynamic createWorkerStateForTest({
  required RouterListener listener,
  required ListenerSettings listenerSettings,
}) => WorkerConnectionState(
  listener: listener,
  listenerSettings: listenerSettings,
);

@visibleForTesting
Future<void> handleHelloForTest(
  SendPort bossPort,
  SendPort? statePort,
  RouterSettings settings,
  dynamic state,
  Hello hello,
  int connectionId,
  RealmContextCache? realmContexts,
  int workerId,
) => _handleHello(
  bossPort,
  statePort,
  settings,
  state as WorkerConnectionState,
  hello,
  connectionId,
  realmContexts,
  workerId,
);

@visibleForTesting
Future<void> handleAuthenticateForTest(
  SendPort bossPort,
  SendPort? statePort,
  RealmContextCache? realmContexts,
  dynamic state,
  authenticate_msg.Authenticate authenticate,
  int connectionId,
  int workerId,
) => _handleAuthenticate(
  bossPort,
  statePort,
  realmContexts,
  state as WorkerConnectionState,
  authenticate,
  connectionId,
  workerId,
);

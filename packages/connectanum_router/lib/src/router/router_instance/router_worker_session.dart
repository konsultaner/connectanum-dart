part of '../router_instance.dart';

const String _wampErrorNoSuchInvocation = 'wamp.error.no_such_invocation';

Future<void> _handleSessionMessage({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required AbstractMessage message,
  required int connectionId,
}) async {
  if (message is goodbye_msg.Goodbye) {
    await _handleGoodbye(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
    );
    return;
  }

  if (state.phase != HandshakePhase.open || state.sessionId == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: _messageTypeCode(message),
      requestId: _extractRequestId(message),
      reason: wamp_core.Error.noSuchSession,
      detailsMessage: 'Session is not open',
    );
    return;
  }

  if (message is subscribe_msg.Subscribe) {
    await _handleSubscribe(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is unsubscribe_msg.Unsubscribe) {
    await _handleUnsubscribe(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is register_msg.Register) {
    await _handleRegister(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is unregister_msg.Unregister) {
    await _handleUnregister(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is publish_msg.Publish) {
    await _handlePublish(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is call_msg.Call) {
    await _handleCall(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is cancel_msg.Cancel) {
    await _handleCancel(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is yield_msg.Yield) {
    await _handleYield(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  if (message is error_msg.Error &&
      message.requestTypeId == MessageTypes.codeInvocation) {
    await _handleInvocationError(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
    );
    return;
  }

  // For unsupported messages, respond with a generic error to unblock callers.
  await _sendSessionError(
    bossPort: bossPort,
    state: state,
    connectionId: connectionId,
    requestType: _messageTypeCode(message),
    requestId: _extractRequestId(message),
    reason: 'wamp.error.not_supported',
    detailsMessage: 'Message type ${message.runtimeType} not supported yet',
  );
}

Future<void> _handleGoodbye({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
}) async {
  if (state.phase == HandshakePhase.open) {
    final serializer = state.serializer ?? NativeMessageSerializer.json;
    await sendMessage(
      bossPort,
      connectionId,
      serializer,
      goodbye_msg.Goodbye(null, 'wamp.close.goodbye_and_out'),
    );
  }
  await _closeSession(
    statePort: statePort,
    realmContexts: realmContexts,
    state: state,
  );
}

Future<void> _handleSubscribe({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required subscribe_msg.Subscribe message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeSubscribe,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final subscriptionId = await context.addSubscription(
      sessionId: state.sessionId!,
      topic: message.topic,
      matchPolicy: _matchPolicyFromSubscribe(message.options),
      details: _subscriptionDetailsFromOptions(message.options),
    );
    await sendMessage(
      bossPort,
      connectionId,
      state.serializer ?? NativeMessageSerializer.json,
      subscribed_msg.Subscribed(message.requestId, subscriptionId),
    );
  } on ArgumentError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeSubscribe,
      requestId: message.requestId,
      reason: wamp_core.Error.invalidArgument,
      detailsMessage: error.message,
    );
  } on StateError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeSubscribe,
      requestId: message.requestId,
      reason: wamp_core.Error.noSuchSession,
      detailsMessage: error.message,
    );
  } catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeSubscribe,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handleUnsubscribe({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required unsubscribe_msg.Unsubscribe message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeUnsubscribe,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final snapshot = await context.ensureSnapshot(forceRefresh: true);
    final sessionId = state.sessionId!;
    SubscriptionSnapshot? subscription;
    for (final candidate in snapshot.subscriptions) {
      if (candidate.id == message.subscriptionId) {
        subscription = candidate;
        break;
      }
    }
    final ownsSubscription =
        subscription?.subscribers.any(
          (subscriber) => subscriber.sessionId == sessionId,
        ) ??
        false;
    if (!ownsSubscription) {
      throw StateError(
        'Subscription ${message.subscriptionId} not found for session '
        '$sessionId',
      );
    }
    await context.removeSubscription(
      sessionId: sessionId,
      subscriptionId: message.subscriptionId,
    );
    await sendMessage(
      bossPort,
      connectionId,
      state.serializer ?? NativeMessageSerializer.json,
      unsubscribed_msg.Unsubscribed(message.requestId, null),
    );
  } on StateError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeUnsubscribe,
      requestId: message.requestId,
      reason: wamp_core.Error.noSuchSubscription,
      detailsMessage: error.message,
    );
  } catch (error, _) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeUnsubscribe,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handleRegister({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required register_msg.Register message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeRegister,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final registrationId = await context.registerProcedure(
      sessionId: state.sessionId!,
      procedure: message.procedure,
      details: _registrationDetailsFromOptions(message.options),
    );
    await sendMessage(
      bossPort,
      connectionId,
      state.serializer ?? NativeMessageSerializer.json,
      registered_msg.Registered(message.requestId, registrationId),
    );
  } on ArgumentError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeRegister,
      requestId: message.requestId,
      reason: wamp_core.Error.invalidArgument,
      detailsMessage: error.message,
    );
  } on StateError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeRegister,
      requestId: message.requestId,
      reason: wamp_core.Error.noSuchSession,
      detailsMessage: error.message,
    );
  } catch (error, _) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeRegister,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handleUnregister({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required unregister_msg.Unregister message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeUnregister,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final snapshot = await context.ensureSnapshot(forceRefresh: true);
    final sessionId = state.sessionId!;
    var registration;
    for (final candidate in snapshot.registrations) {
      if (candidate.registrationId == message.registrationId) {
        registration = candidate;
        break;
      }
    }
    final ownsRegistration =
        registration?.callees.any((callee) => callee.sessionId == sessionId) ??
        false;
    if (!ownsRegistration) {
      throw StateError(
        'Registration ${message.registrationId} not found for session '
        '$sessionId',
      );
    }
    await context.unregisterProcedure(
      sessionId: sessionId,
      registrationId: message.registrationId,
    );
    await sendMessage(
      bossPort,
      connectionId,
      state.serializer ?? NativeMessageSerializer.json,
      unregistered_msg.Unregistered(message.requestId),
    );
  } on StateError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeUnregister,
      requestId: message.requestId,
      reason: wamp_core.Error.noSuchRegistration,
      detailsMessage: error.message,
    );
  } catch (error, _) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeUnregister,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handlePublish({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required publish_msg.Publish message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codePublish,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final routing = await context.matchSubscriptions(
      publisherSessionId: state.sessionId!,
      topic: message.topic,
      options: _publishOptionsToMap(message.options),
    );
    final discloseMe = message.options?.discloseMe == true;
    for (final match in routing.matches) {
      final eventDetails = event_msg.EventDetails(
        publisher: discloseMe ? state.sessionId : null,
        topic: _eventTopicForMatch(match.details, message.topic),
      );
      final event = event_msg.Event(
        match.subscriptionId,
        routing.publicationId,
        eventDetails,
        arguments: message.arguments,
        argumentsKeywords: message.argumentsKeywords,
      );
      _forwardToConnection(
        bossPort: bossPort,
        connectionId: match.connectionId,
        message: event,
      );
    }
    if (message.options?.acknowledge == true) {
      await sendMessage(
        bossPort,
        connectionId,
        state.serializer ?? NativeMessageSerializer.json,
        published_msg.Published(message.requestId, routing.publicationId),
      );
    }
  } on ArgumentError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codePublish,
      requestId: message.requestId,
      reason: wamp_core.Error.invalidArgument,
      detailsMessage: error.message,
    );
  } on StateError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codePublish,
      requestId: message.requestId,
      reason: wamp_core.Error.noSuchSession,
      detailsMessage: error.message,
    );
  } catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codePublish,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: '${error.runtimeType}: $error',
    );
  }
}

Future<void> _handleCall({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required call_msg.Call message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCall,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final dispatch = await context.dispatchInvocation(
      callerSessionId: state.sessionId!,
      requestId: message.requestId,
      procedure: message.procedure,
      options: _callOptionsToMap(message.options),
    );
    final discloseCaller = message.options?.discloseMe == true;
    final invocationDetails = invocation_msg.InvocationDetails(
      discloseCaller ? state.sessionId : null,
      message.procedure,
      message.options?.receiveProgress,
    );
    final invocation = invocation_msg.Invocation(
      dispatch.invocationId,
      dispatch.registrationId,
      invocationDetails,
      arguments: message.arguments,
      argumentsKeywords: message.argumentsKeywords,
    );
    _forwardToConnection(
      bossPort: bossPort,
      connectionId: dispatch.calleeConnectionId,
      message: invocation,
    );
  } on ArgumentError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCall,
      requestId: message.requestId,
      reason: wamp_core.Error.invalidArgument,
      detailsMessage: error.message,
    );
  } on StateError catch (error) {
    final reason = _reasonForInvocationDispatchError(error.message);
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCall,
      requestId: message.requestId,
      reason: reason,
      detailsMessage: error.message,
    );
  } catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCall,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handleCancel({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required cancel_msg.Cancel message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCancel,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final invocation = await context.findInvocationByCaller(
      callerSessionId: state.sessionId!,
      requestId: message.requestId,
    );
    if (invocation == null) {
      await _sendSessionError(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        requestType: MessageTypes.codeCancel,
        requestId: message.requestId,
        reason: _wampErrorNoSuchInvocation,
        detailsMessage: 'No active invocation for request ${message.requestId}',
      );
      return;
    }

    interrupt_msg.InterruptOptions? interruptOptions;
    final mode = message.options?.mode;
    if (mode != null) {
      interruptOptions = interrupt_msg.InterruptOptions()..mode = mode;
    }

    final calleeConnectionId = await _findConnectionIdForSession(
      context: context,
      sessionId: invocation.calleeSessionId,
      forceRefresh: true,
    );
    if (calleeConnectionId != null) {
      final interrupt = interrupt_msg.Interrupt(
        invocation.invocationId,
        options: interruptOptions,
      );
      _forwardToConnection(
        bossPort: bossPort,
        connectionId: calleeConnectionId,
        message: interrupt,
      );
    }

    await context.completeInvocation(invocation.invocationId);

    await sendMessage(
      bossPort,
      connectionId,
      state.serializer ?? NativeMessageSerializer.json,
      error_msg.Error(
        MessageTypes.codeCall,
        message.requestId,
        const {},
        error_msg.Error.errorInvocationCanceled,
      ),
    );
  } catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCancel,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handleYield({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required yield_msg.Yield message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: message.invocationRequestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  final invocationId = message.invocationRequestId;
  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final invocation = await context.getInvocation(invocationId);
    if (invocation == null) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: _wampErrorNoSuchInvocation,
      );
      return;
    }
    if (invocation.calleeSessionId != state.sessionId) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: wamp_core.Error.notAuthorized,
      );
      await context.completeInvocation(invocationId);
      return;
    }

    final isProgress = message.options?.progress ?? false;
    if (isProgress && !invocation.allowProgress) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: wamp_core.Error.invalidArgument,
        detailsMessage: 'Invocation $invocationId does not allow progress',
      );
      await context.completeInvocation(invocationId);
      return;
    }

    if (!isProgress) {
      await context.completeInvocation(invocationId);
    }

    final callerConnectionId = await _findConnectionIdForSession(
      context: context,
      sessionId: invocation.callerSessionId,
      forceRefresh: true,
    );
    if (callerConnectionId == null) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: wamp_core.Error.noSuchSession,
        detailsMessage:
            'Caller session ${invocation.callerSessionId} not available',
      );
      await context.completeInvocation(invocationId);
      return;
    }

    final result = result_msg.Result(
      invocation.callerRequestId,
      result_msg.ResultDetails(progress: isProgress),
      arguments: message.arguments,
      argumentsKeywords: message.argumentsKeywords,
    );
    _forwardToConnection(
      bossPort: bossPort,
      connectionId: callerConnectionId,
      message: result,
    );
  } catch (error) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: invocationId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

Future<void> _handleInvocationError({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required error_msg.Error message,
}) async {
  if (statePort == null || realmContexts == null || state.realmUri == null) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Router state store unavailable',
    );
    return;
  }

  final invocationId = message.requestId;
  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final invocation = await context.getInvocation(invocationId);
    if (invocation == null) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: _wampErrorNoSuchInvocation,
      );
      return;
    }
    if (invocation.calleeSessionId != state.sessionId) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: wamp_core.Error.notAuthorized,
      );
      await context.completeInvocation(invocationId);
      return;
    }

    await context.completeInvocation(invocationId);
    final callerConnectionId = await _findConnectionIdForSession(
      context: context,
      sessionId: invocation.callerSessionId,
      forceRefresh: true,
    );
    if (callerConnectionId == null) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: wamp_core.Error.noSuchSession,
        detailsMessage:
            'Caller session ${invocation.callerSessionId} not available',
      );
      return;
    }

    final forwardedError = error_msg.Error(
      MessageTypes.codeCall,
      invocation.callerRequestId,
      Map<String, dynamic>.from(message.details),
      message.error,
      arguments: message.arguments,
      argumentsKeywords: message.argumentsKeywords,
    );
    _forwardToConnection(
      bossPort: bossPort,
      connectionId: callerConnectionId,
      message: forwardedError,
    );
  } catch (error) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: invocationId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
  }
}

TopicMatchPolicy _matchPolicyFromSubscribe(
  subscribe_msg.SubscribeOptions? options,
) {
  final match = options?.match;
  if (match == 'prefix') {
    return TopicMatchPolicy.prefix;
  }
  if (match == 'wildcard') {
    return TopicMatchPolicy.wildcard;
  }
  return TopicMatchPolicy.exact;
}

Map<String, Object?> _subscriptionDetailsFromOptions(
  subscribe_msg.SubscribeOptions? options,
) {
  if (options == null) {
    return const {};
  }
  final details = <String, Object?>{};
  if (options.match != null) {
    details['match'] = options.match;
  }
  if (options.metaTopic != null) {
    details['meta_topic'] = options.metaTopic;
  }
  if (options.getRetained != null) {
    details['get_retained'] = options.getRetained;
  }
  return details;
}

Map<String, Object?> _registrationDetailsFromOptions(
  register_msg.RegisterOptions? options,
) {
  if (options == null) {
    return const {};
  }
  final details = <String, Object?>{};
  if (options.discloseCaller != null) {
    details['disclose_caller'] = options.discloseCaller;
  }
  if (options.match != null) {
    details['match'] = options.match;
  }
  if (options.invoke != null) {
    details['invoke'] = options.invoke;
  }
  return details;
}

Map<String, Object?> _publishOptionsToMap(publish_msg.PublishOptions? options) {
  if (options == null) {
    return const {};
  }
  final map = <String, Object?>{};
  if (options.acknowledge != null) {
    map['acknowledge'] = options.acknowledge;
  }
  if (options.exclude != null) {
    map['exclude'] = List<int>.from(options.exclude!);
  }
  if (options.eligible != null) {
    map['eligible'] = List<int>.from(options.eligible!);
  }
  if (options.excludeMe != null) {
    map['exclude_me'] = options.excludeMe;
  }
  if (options.discloseMe != null) {
    map['disclose_me'] = options.discloseMe;
  }
  return map;
}

Map<String, Object?> _callOptionsToMap(call_msg.CallOptions? options) {
  if (options == null) {
    return const {};
  }
  final map = <String, Object?>{};
  if (options.receiveProgress != null) {
    map['receive_progress'] = options.receiveProgress;
  }
  if (options.timeout != null) {
    map['timeout'] = options.timeout;
  }
  if (options.discloseMe != null) {
    map['disclose_me'] = options.discloseMe;
  }
  return map;
}

String? _eventTopicForMatch(
  Map<String, Object?> subscriberDetails,
  String topic,
) {
  final match = subscriberDetails['match'];
  if (match == subscribe_msg.SubscribeOptions.matchPrefix ||
      match == subscribe_msg.SubscribeOptions.matchWildcard) {
    return topic;
  }
  return null;
}

void _forwardToConnection({
  required SendPort bossPort,
  required int connectionId,
  required AbstractMessage message,
}) {
  bossPort.send({
    'type': 'worker_forward_message',
    'connectionId': connectionId,
    'message': message,
  });
}

Future<int?> _findConnectionIdForSession({
  required RealmContext context,
  required int sessionId,
  bool forceRefresh = false,
}) async {
  final snapshot = await context.ensureSnapshot(forceRefresh: forceRefresh);
  for (final session in snapshot.sessions) {
    if (session.id == sessionId) {
      return session.connectionId;
    }
  }
  return null;
}

Future<void> _sendInvocationErrorToCallee({
  required SendPort bossPort,
  required WorkerConnectionState state,
  required int connectionId,
  required int invocationId,
  required String reason,
  String? detailsMessage,
}) async {
  final details = <String, dynamic>{};
  if (detailsMessage != null && detailsMessage.isNotEmpty) {
    details['message'] = detailsMessage;
  }
  await sendMessage(
    bossPort,
    connectionId,
    state.serializer ?? NativeMessageSerializer.json,
    error_msg.Error(MessageTypes.codeInvocation, invocationId, details, reason),
  );
}

String _reasonForInvocationDispatchError(String? message) {
  if (message == null) {
    return wamp_core.Error.unknown;
  }
  if (message.contains('No registration') ||
      message.contains('No available callee')) {
    return wamp_core.Error.noSuchProcedure;
  }
  if (message.contains('Caller session')) {
    return wamp_core.Error.noSuchSession;
  }
  return wamp_core.Error.unknown;
}

Future<void> _sendSessionError({
  required SendPort bossPort,
  required WorkerConnectionState state,
  required int connectionId,
  required int? requestType,
  required int? requestId,
  required String reason,
  String? detailsMessage,
}) async {
  if (requestType == null || requestId == null) {
    return;
  }
  final details = <String, dynamic>{};
  if (detailsMessage != null && detailsMessage.isNotEmpty) {
    details['message'] = detailsMessage;
  }
  await sendMessage(
    bossPort,
    connectionId,
    state.serializer ?? NativeMessageSerializer.json,
    error_msg.Error(requestType, requestId, details, reason),
  );
}

Future<void> _closeSession({
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
}) async {
  if (state.phase != HandshakePhase.open) {
    return;
  }

  final sessionId = state.sessionId;
  final realmUri = state.realmUri;

  if (statePort != null && sessionId != null && realmUri != null) {
    statePort.send(
      SessionCloseCommand(realmUri: realmUri, sessionId: sessionId),
    );
  }
  if (realmUri != null) {
    realmContexts?.invalidate(realmUri);
  }

  state.phase = HandshakePhase.aborted;
  state.sessionId = null;
  state.realmUri = null;
  state.realmSettings = null;
  state.welcomeDetails = null;
  state.authenticator = null;
  state.authContext = null;
  state.authMethod = null;
  state.pendingChallengeExtra = null;
}

int? _messageTypeCode(AbstractMessage message) => switch (message) {
  Hello() => MessageTypes.codeHello,
  authenticate_msg.Authenticate() => MessageTypes.codeAuthenticate,
  abort_msg.Abort() => MessageTypes.codeAbort,
  goodbye_msg.Goodbye() => MessageTypes.codeGoodbye,
  subscribe_msg.Subscribe() => MessageTypes.codeSubscribe,
  unsubscribe_msg.Unsubscribe() => MessageTypes.codeUnsubscribe,
  register_msg.Register() => MessageTypes.codeRegister,
  unregister_msg.Unregister() => MessageTypes.codeUnregister,
  publish_msg.Publish() => MessageTypes.codePublish,
  call_msg.Call() => MessageTypes.codeCall,
  cancel_msg.Cancel() => MessageTypes.codeCancel,
  yield_msg.Yield() => MessageTypes.codeYield,
  _ => null,
};

int? _extractRequestId(AbstractMessage message) => switch (message) {
  subscribe_msg.Subscribe() => message.requestId,
  unsubscribe_msg.Unsubscribe() => message.requestId,
  register_msg.Register() => message.requestId,
  unregister_msg.Unregister() => message.requestId,
  publish_msg.Publish() => message.requestId,
  call_msg.Call() => message.requestId,
  cancel_msg.Cancel() => message.requestId,
  yield_msg.Yield() => message.invocationRequestId,
  _ => null,
};

@visibleForTesting
Future<void> handleSessionMessageForTest({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required AbstractMessage message,
  required int connectionId,
}) => _handleSessionMessage(
  bossPort: bossPort,
  statePort: statePort,
  realmContexts: realmContexts,
  state: state,
  message: message,
  connectionId: connectionId,
);

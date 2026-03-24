part of '../router_instance.dart';

const String _wampErrorNoSuchInvocation = 'wamp.error.no_such_invocation';
const bool _forwardNativePublishEventsConst = bool.fromEnvironment(
  'CONNECTANUM_FORWARD_NATIVE_PUBLISH',
  defaultValue: false,
);

bool _parseForwardNativePublishFlag(String? raw) {
  if (raw == null) {
    return false;
  }
  final normalized = raw.trim().toLowerCase();
  return normalized == 'true' ||
      normalized == '1' ||
      normalized == 'yes' ||
      normalized == 'on';
}

final bool forwardNativePublishEvents =
    _forwardNativePublishEventsConst ||
    _parseForwardNativePublishFlag(
      Platform.environment['CONNECTANUM_FORWARD_NATIVE_PUBLISH'],
    );

void _safeSend(SendPort port, Object? message) {
  try {
    port.send(message);
  } catch (_) {
    // Telemetry should not prevent session handling.
  }
}

Future<void> _handleSessionMessage({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required AbstractMessage message,
  required int connectionId,
  NativeIncomingMessage? incomingMessage,
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
      incomingMessage: incomingMessage,
    );
    return;
  }

  if (message is call_msg.Call) {
    _safeSend(bossPort, {
      'type': _workerEventCallReceived,
      'connectionId': connectionId,
      'callRequestId': message.requestId,
      'procedure': message.procedure,
    });
    await _handleCall(
      bossPort: bossPort,
      statePort: statePort,
      realmContexts: realmContexts,
      state: state,
      connectionId: connectionId,
      message: message,
      incomingMessage: incomingMessage,
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
      incomingMessage: incomingMessage,
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
      incomingMessage: incomingMessage,
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
  String reason = 'wamp.close.goodbye_and_out',
}) async {
  if (state.phase == HandshakePhase.open) {
    final serializer = state.serializer ?? NativeMessageSerializer.json;
    // TODO(protocol-negotiation): forward the negotiated protocol once the
    // native runtime reports real negotiation outcomes.
    await sendMessage(
      bossPort,
      connectionId,
      serializer,
      goodbye_msg.Goodbye(null, reason),
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
    final matchPolicy = _matchPolicyFromSubscribe(message.options);
    _validateTopicUri(message.topic, matchPolicy);
    final subscriptionId = await context.addSubscription(
      sessionId: state.sessionId!,
      topic: message.topic,
      matchPolicy: matchPolicy,
      details: _subscriptionDetailsFromOptions(message.options),
    );
    await sendMessage(
      bossPort,
      connectionId,
      state.serializer ?? NativeMessageSerializer.json,
      subscribed_msg.Subscribed(message.requestId, subscriptionId),
    );
  } on ArgumentError catch (error) {
    final errorMessage = error.toString();
    final reason = errorMessage.contains('invalid_uri')
        ? wamp_core.Error.errorInvalidUri
        : wamp_core.Error.invalidArgument;
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeSubscribe,
      requestId: message.requestId,
      reason: reason,
      detailsMessage: errorMessage,
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
    final matchPolicy = _matchPolicyFromRegisterOptions(message.options);
    _validateProcedureUri(message.procedure, matchPolicy);
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
    final errorMessage = error.toString();
    final isInvalidUri = errorMessage.contains('invalid_uri');
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeRegister,
      requestId: message.requestId,
      reason: isInvalidUri
          ? wamp_core.Error.errorInvalidUri
          : wamp_core.Error.invalidArgument,
      detailsMessage: errorMessage,
    );
  } on StateError catch (error) {
    final reason = _reasonForRegisterStateError(error.message);
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeRegister,
      requestId: message.requestId,
      reason: reason,
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
    RegistrationRecord? registrationRecord;
    for (final candidate in snapshot.registrations) {
      for (final callee in candidate.callees) {
        if (callee.registrationId == message.registrationId) {
          registrationRecord = callee;
          break;
        }
      }
      if (registrationRecord != null) {
        break;
      }
    }
    final ownsRegistration = registrationRecord?.sessionId == sessionId;
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
  NativeIncomingMessage? incomingMessage,
}) async {
  // Zero-copy forwarding of publish payloads is disabled by default to avoid
  // the bench/pubsub hang observed under higher concurrency. Opt in via the
  // CONNECTANUM_FORWARD_NATIVE_PUBLISH flag (compile-time define or env var)
  // once the native path is proven stable end-to-end.
  Map<String, Object?>? normalizedArgumentsKeywords;
  final Object? rawArgumentsKeywords = message.argumentsKeywords;
  if (rawArgumentsKeywords != null) {
    if (rawArgumentsKeywords is Map<String, Object?>) {
      normalizedArgumentsKeywords = Map<String, Object?>.from(
        rawArgumentsKeywords,
      );
    } else {
      // Protect downstream serializers from bad shapes (e.g. lists sneaking
      // into kwargs) by dropping invalid kwargs and surfacing a worker event
      // for observability.
      bossPort.send({
        'type': _workerEventPublishRouted,
        'connectionId': connectionId,
        'requestId': message.requestId,
        'publicationId': null,
        'matchCount': 0,
        'topic': message.topic,
        'stage': 'invalid_kwargs',
        'kwargs_type': rawArgumentsKeywords.runtimeType.toString(),
      });
    }
  }
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

  var nativeForwardingFailed = false;
  try {
    final context = realmContexts.contextFor(state.realmUri!);
    final routing = await context.matchSubscriptions(
      publisherSessionId: state.sessionId!,
      topic: message.topic,
      options: _publishOptionsToMap(message.options),
    );
    _safeSend(bossPort, {
      'type': _workerEventPublishRouted,
      'connectionId': connectionId,
      'requestId': message.requestId,
      'publicationId': routing.publicationId,
      'matchCount': routing.matches.length,
      'topic': message.topic,
      'stage': 'routed',
    });
    final discloseMe = message.options?.discloseMe == true;
    final matches = routing.matches;
    final internalMatches = <SubscriptionMatch>[];
    final externalMatches = <SubscriptionMatch>[];
    for (final match in matches) {
      if (match.internalSendPort != null) {
        internalMatches.add(match);
      } else {
        externalMatches.add(match);
      }
    }
    var usedZeroCopy = false;
    final nativeMessage = incomingMessage;
    if (forwardNativePublishEvents &&
        nativeMessage?.hasNativeHandle == true &&
        externalMatches.isNotEmpty) {
      final messageHandle = nativeMessage!;
      final pending = <Map<String, Object?>>[];
      var failed = false;
      for (final match in externalMatches) {
        final retainedHandle = messageHandle.retainHandle();
        if (retainedHandle <= 0) {
          failed = true;
          break;
        }
        final command = <String, Object?>{
          'type': 'worker_forward_native_event',
          'connectionId': match.connectionId,
          'handle': retainedHandle,
          'subscriptionId': match.subscriptionId,
          'publicationId': routing.publicationId,
        };
        final publisherSessionId = discloseMe ? state.sessionId : null;
        if (publisherSessionId != null) {
          command['publisherSessionId'] = publisherSessionId;
        }
        final topic = _eventTopicForMatch(match.details, message.topic);
        if (topic != null) {
          command['topic'] = topic;
        }
        pending.add(command);
      }
      if (failed) {
        for (final command in pending) {
          messageHandle.releaseRetainedHandle(command['handle'] as int);
        }
      } else {
        var sentCount = 0;
        try {
          for (final command in pending) {
            bossPort.send(command);
            sentCount += 1;
          }
          usedZeroCopy = true;
        } catch (error) {
          nativeForwardingFailed = true;
          for (var i = sentCount; i < pending.length; i += 1) {
            final command = pending[i];
            messageHandle.releaseRetainedHandle(command['handle'] as int);
          }
          rethrow;
        }
      }
    }

    for (final match in internalMatches) {
      final topic = _eventTopicForMatch(match.details, message.topic);
      match.internalSendPort!.send({
        'type': 'event',
        'subscriptionId': match.subscriptionId,
        'publicationId': routing.publicationId,
        'topic': topic,
        'arguments': message.arguments,
        'argumentsKeywords': normalizedArgumentsKeywords,
        'publisherSessionId': discloseMe ? state.sessionId : null,
        'details': Map<String, Object?>.from(match.details),
      });
    }

    if (!usedZeroCopy) {
      for (final match in externalMatches) {
        final eventDetails = event_msg.EventDetails(
          publisher: discloseMe ? state.sessionId : null,
          topic: _eventTopicForMatch(match.details, message.topic),
        );
        final event = event_msg.Event(
          match.subscriptionId,
          routing.publicationId,
          eventDetails,
          arguments: message.arguments,
          argumentsKeywords: normalizedArgumentsKeywords,
        );
        _forwardToConnection(
          bossPort: bossPort,
          connectionId: match.connectionId,
          message: event,
        );
      }
    }
    if (message.options?.acknowledge == true) {
      try {
        _safeSend(bossPort, {
          'type': _workerEventPublishRouted,
          'connectionId': connectionId,
          'requestId': message.requestId,
          'publicationId': routing.publicationId,
          'matchCount': matches.length,
          'topic': message.topic,
          'stage': 'ack_sending',
        });
        // Fire-and-forget ACK to avoid blocking the publish path; surface any
        // error back to the bossPort for observability.
        unawaited(
          sendMessage(
                bossPort,
                connectionId,
                state.serializer ?? NativeMessageSerializer.json,
                published_msg.Published(
                  message.requestId,
                  routing.publicationId,
                ),
              )
              .then((_) {
                bossPort.send({
                  'type': _workerEventPublishRouted,
                  'connectionId': connectionId,
                  'requestId': message.requestId,
                  'publicationId': routing.publicationId,
                  'matchCount': matches.length,
                  'topic': message.topic,
                  'stage': 'acked',
                });
              })
              .onError((error, stackTrace) {
                _safeSend(bossPort, {
                  'type': _workerEventPublishRouted,
                  'connectionId': connectionId,
                  'requestId': message.requestId,
                  'publicationId': routing.publicationId,
                  'matchCount': matches.length,
                  'topic': message.topic,
                  'stage': 'ack_error_async',
                  'error': error.toString(),
                  'stackTrace': stackTrace.toString(),
                });
              })
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  _safeSend(bossPort, {
                    'type': _workerEventPublishRouted,
                    'connectionId': connectionId,
                    'requestId': message.requestId,
                    'publicationId': routing.publicationId,
                    'matchCount': matches.length,
                    'topic': message.topic,
                    'stage': 'ack_error_timeout',
                  });
                },
              ),
        );
      } catch (error, stackTrace) {
        _safeSend(bossPort, {
          'type': _workerEventPublishRouted,
          'connectionId': connectionId,
          'requestId': message.requestId,
          'publicationId': routing.publicationId,
          'matchCount': matches.length,
          'topic': message.topic,
          'stage': 'ack_error',
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
        rethrow;
      }
    }
  } on ArgumentError catch (error) {
    _safeSend(bossPort, {
      'type': _workerEventPublishRouted,
      'connectionId': connectionId,
      'requestId': message.requestId,
      'publicationId': null,
      'matchCount': 0,
      'topic': message.topic,
      'stage': 'error',
      'error': error.message,
    });
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
    _safeSend(bossPort, {
      'type': _workerEventPublishRouted,
      'connectionId': connectionId,
      'requestId': message.requestId,
      'publicationId': null,
      'matchCount': 0,
      'topic': message.topic,
      'stage': 'error',
      'error': error.message,
    });
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codePublish,
      requestId: message.requestId,
      reason: wamp_core.Error.noSuchSession,
      detailsMessage: error.message,
    );
    if (nativeForwardingFailed) {
      rethrow;
    }
  } catch (error) {
    _safeSend(bossPort, {
      'type': _workerEventPublishRouted,
      'connectionId': connectionId,
      'requestId': message.requestId,
      'publicationId': null,
      'matchCount': 0,
      'topic': message.topic,
      'stage': 'error',
      'error': error.toString(),
    });
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codePublish,
      requestId: message.requestId,
      reason: wamp_core.Error.unknown,
      detailsMessage: '${error.runtimeType}: $error',
    );
    if (nativeForwardingFailed) {
      rethrow;
    }
  }
}

Future<void> _handleCall({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required call_msg.Call message,
  NativeIncomingMessage? incomingMessage,
}) async {
  _safeSend(bossPort, {
    'type': 'worker_call_dispatch_start',
    'connectionId': connectionId,
    'requestId': message.requestId,
    'procedure': message.procedure,
    'realm': state.realmUri,
  });
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

  var nativeForwardingFailed = false;
  try {
    final context = realmContexts.contextFor(state.realmUri!);
    InvocationDispatchResult dispatch;
    try {
      dispatch = await context.dispatchInvocation(
        callerSessionId: state.sessionId!,
        requestId: message.requestId,
        procedure: message.procedure,
        options: _callOptionsToMap(message.options),
      );
    } catch (error, stackTrace) {
      _safeSend(bossPort, {
        'type': _workerEventCallDispatched,
        'connectionId': connectionId,
        'requestId': message.requestId,
        'procedure': message.procedure,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      rethrow;
    }
    _safeSend(bossPort, {
      'type': _workerEventCallDispatched,
      'connectionId': connectionId,
      'requestId': message.requestId,
      'procedure': message.procedure,
      'calleeConnectionId': dispatch.calleeConnectionId,
      'registrationId': dispatch.registrationId,
      'invocationId': dispatch.invocationId,
    });
    final discloseCaller = message.options?.discloseMe == true;
    final nativeMessage = incomingMessage;
    var usedZeroCopy = false;
    if (dispatch.calleeInternalSendPort != null) {
      await _handleInternalInvocation(
        bossPort: bossPort,
        statePort: statePort,
        realmContexts: realmContexts,
        callerState: state,
        message: message,
        dispatch: dispatch,
        connectionId: connectionId,
      );
      return;
    }
    if (nativeMessage?.hasNativeHandle == true) {
      final messageHandle = nativeMessage!;
      final retainedHandle = messageHandle.retainHandle();
      if (retainedHandle > 0) {
        final command = <String, Object?>{
          'type': 'worker_forward_native_invocation',
          'connectionId': dispatch.calleeConnectionId,
          'handle': retainedHandle,
          'invocationId': dispatch.invocationId,
          'registrationId': dispatch.registrationId,
          'procedure': message.procedure,
        };
        if (discloseCaller) {
          command['callerSessionId'] = state.sessionId;
        }
        final receiveProgress = message.options?.receiveProgress;
        if (receiveProgress != null) {
          command['receiveProgress'] = receiveProgress;
        }
        try {
          bossPort.send(command);
          usedZeroCopy = true;
        } catch (error) {
          nativeForwardingFailed = true;
          messageHandle.releaseRetainedHandle(retainedHandle);
          rethrow;
        }
      }
    }

    if (!usedZeroCopy) {
      final invocationDetails = invocation_msg.InvocationDetails(
        discloseCaller ? state.sessionId : null,
        message.procedure,
        message.options?.receiveProgress,
      );
      final customOptions = message.options?.custom;
      if (customOptions != null && customOptions.isNotEmpty) {
        invocationDetails.custom.addAll(
          customOptions.map((key, value) => MapEntry(key, value)),
        );
      }
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
    }
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
    if (nativeForwardingFailed) {
      rethrow;
    }
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
    if (nativeForwardingFailed) {
      rethrow;
    }
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
    if (nativeForwardingFailed) {
      rethrow;
    }
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

    final mode = _normalizeCancelMode(message.options?.mode);
    if (mode == null) {
      await _sendSessionError(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        requestType: MessageTypes.codeCancel,
        requestId: message.requestId,
        reason: wamp_core.Error.invalidArgument,
        detailsMessage: 'Unsupported cancel mode: ${message.options?.mode}',
      );
      return;
    }

    if (mode == cancel_msg.CancelOptions.modeSkip) {
      await context.completeInvocation(invocation.invocationId);
      await _sendCancelAck(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        requestId: message.requestId,
      );
      return;
    }

    final waitForAck = mode == cancel_msg.CancelOptions.modeKill;
    if (!await context.cancelInvocation(
      invocationId: invocation.invocationId,
      mode: mode,
      waitForAck: waitForAck,
    )) {
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

    final shouldInterrupt =
        mode == cancel_msg.CancelOptions.modeKill ||
        mode == cancel_msg.CancelOptions.modeKillNoWait;
    if (shouldInterrupt) {
      final internalPort = invocation.calleeInternalSendPort;
      if (internalPort != null) {
        internalPort.send({
          'type': 'interrupt',
          'invocationId': invocation.invocationId,
          'mode': mode,
        });
      } else {
        final calleeConnectionId =
            invocation.calleeConnectionId ??
            await _findConnectionIdForSession(
              context: context,
              sessionId: invocation.calleeSessionId,
              forceRefresh: true,
            );
        if (calleeConnectionId != null) {
          final interruptOptions = interrupt_msg.InterruptOptions()
            ..mode = mode;
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
      }
    }

    if (!waitForAck) {
      await _sendCancelAck(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        requestId: message.requestId,
      );
    }
  } on StateError catch (error) {
    await _sendSessionError(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      requestType: MessageTypes.codeCancel,
      requestId: message.requestId,
      reason: _wampErrorNoSuchInvocation,
      detailsMessage: error.message,
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
  bossPort.send({
    'type': _workerEventCallDispatchComplete,
    'connectionId': connectionId,
    'requestId': message.requestId,
  });
}

String? _normalizeCancelMode(String? rawMode) {
  if (rawMode == null) {
    return cancel_msg.CancelOptions.modeSkip;
  }
  switch (rawMode) {
    case 'skip':
      return cancel_msg.CancelOptions.modeSkip;
    case 'kill':
      return cancel_msg.CancelOptions.modeKill;
    case 'killnowait':
      return cancel_msg.CancelOptions.modeKillNoWait;
    default:
      return null;
  }
}

Future<void> _handleInternalInvocation({
  required SendPort bossPort,
  required SendPort statePort,
  required RealmContextCache realmContexts,
  required WorkerConnectionState callerState,
  required call_msg.Call message,
  required InvocationDispatchResult dispatch,
  required int connectionId,
}) async {
  final realmUri = callerState.realmUri;
  final callerSessionId = callerState.sessionId;
  if (realmUri == null || callerSessionId == null) {
    await _sendSessionError(
      bossPort: bossPort,
      state: callerState,
      connectionId: connectionId,
      requestType: MessageTypes.codeCall,
      requestId: message.requestId,
      reason: 'wamp.error.not_supported',
      detailsMessage: 'Session is not open',
    );
    return;
  }
  final replyPort = ReceivePort();
  try {
    dispatch.calleeInternalSendPort!.send({
      'type': 'invocation',
      'invocationId': dispatch.invocationId,
      'registrationId': dispatch.registrationId,
      'procedure': message.procedure,
      'arguments': message.arguments,
      'argumentsKeywords': message.argumentsKeywords,
      'options': _callOptionsToMap(message.options),
      'realmUri': realmUri,
      'callerSessionId': callerSessionId,
      'callerRequestId': message.requestId,
      'replyPort': replyPort.sendPort,
    });
    final response = await replyPort.first;
    if (response is Map<String, Object?> && response['type'] == 'result') {
      await _sendInternalInvocationResult(
        bossPort: bossPort,
        realmContexts: realmContexts,
        realmUri: realmUri,
        invocationId: dispatch.invocationId,
        calleeSessionId: dispatch.calleeSessionId,
        arguments: response['arguments'] as List<dynamic>?,
        argumentsKeywords:
            response['argumentsKeywords'] as Map<String, Object?>?,
        progress: response['progress'] as bool? ?? false,
      );
    } else if (response is Map<String, Object?> &&
        response['type'] == 'error') {
      await _sendInternalInvocationError(
        bossPort: bossPort,
        realmContexts: realmContexts,
        realmUri: realmUri,
        invocationId: dispatch.invocationId,
        calleeSessionId: dispatch.calleeSessionId,
        errorUri: (response['error'] as String?) ?? 'wamp.error.runtime_error',
        arguments: response['arguments'] as List<dynamic>?,
        argumentsKeywords:
            response['argumentsKeywords'] as Map<String, Object?>?,
        details: response['details'] as Map<String, Object?>?,
      );
    } else {
      await _sendInternalInvocationError(
        bossPort: bossPort,
        realmContexts: realmContexts,
        realmUri: realmUri,
        invocationId: dispatch.invocationId,
        calleeSessionId: dispatch.calleeSessionId,
        errorUri: 'wamp.error.runtime_error',
        arguments: <String>[
          'Internal session returned invalid response for '
              '${message.procedure}',
        ],
      );
    }
  } finally {
    replyPort.close();
  }
}

Future<void> _sendCancelAck({
  required SendPort bossPort,
  required WorkerConnectionState state,
  required int connectionId,
  required int requestId,
}) async {
  await sendMessage(
    bossPort,
    connectionId,
    state.serializer ?? NativeMessageSerializer.json,
    error_msg.Error(
      MessageTypes.codeCall,
      requestId,
      const {},
      error_msg.Error.errorInvocationCanceled,
    ),
  );
}

Future<void> _sendInternalInvocationResult({
  required SendPort bossPort,
  required RealmContextCache realmContexts,
  required String realmUri,
  required int invocationId,
  required int calleeSessionId,
  List<dynamic>? arguments,
  Map<String, Object?>? argumentsKeywords,
  bool progress = false,
}) async {
  try {
    final context = realmContexts.contextFor(realmUri);
    final invocation = await context.getInvocation(invocationId);
    if (invocation == null) {
      return;
    }
    if (invocation.calleeSessionId != calleeSessionId) {
      await context.completeInvocation(invocationId);
      return;
    }
    final callerPort = invocation.callerInternalSendPort;
    if (invocation.cancelRequested) {
      await context.completeInvocation(invocationId);
      if (callerPort != null) {
        callerPort.send({
          'type': 'call_error',
          'requestId': invocation.callerRequestId,
          'error': error_msg.Error.errorInvocationCanceled,
          'arguments': const ['Invocation cancelled'],
        });
      } else {
        await _sendInternalInvocationError(
          bossPort: bossPort,
          realmContexts: realmContexts,
          realmUri: realmUri,
          invocationId: invocationId,
          calleeSessionId: calleeSessionId,
          errorUri: error_msg.Error.errorInvocationCanceled,
          arguments: const ['Invocation cancelled'],
        );
      }
      return;
    }
    if (progress && !invocation.allowProgress) {
      await context.completeInvocation(invocationId);
      if (callerPort != null) {
        callerPort.send({
          'type': 'call_error',
          'requestId': invocation.callerRequestId,
          'error': wamp_core.Error.invalidArgument,
          'arguments': const ['Invocation does not allow progress'],
        });
      } else {
        await _sendInternalInvocationError(
          bossPort: bossPort,
          realmContexts: realmContexts,
          realmUri: realmUri,
          invocationId: invocationId,
          calleeSessionId: calleeSessionId,
          errorUri: wamp_core.Error.invalidArgument,
          arguments: const ['Invocation does not allow progress'],
        );
      }
      return;
    }
    if (!progress) {
      await context.completeInvocation(invocationId);
    }
    if (callerPort != null) {
      callerPort.send({
        'type': progress ? 'call_progress' : 'call_result',
        'requestId': invocation.callerRequestId,
        'arguments': arguments,
        'argumentsKeywords': argumentsKeywords,
        'progress': progress,
      });
      return;
    }
    final callerConnectionId = await _findConnectionIdForSession(
      context: context,
      sessionId: invocation.callerSessionId,
      forceRefresh: true,
    );
    if (callerConnectionId == null) {
      return;
    }
    final result = result_msg.Result(
      invocation.callerRequestId,
      result_msg.ResultDetails(progress: progress),
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
    );
    _forwardToConnection(
      bossPort: bossPort,
      connectionId: callerConnectionId,
      message: result,
    );
  } catch (error) {
    await _sendInternalInvocationError(
      bossPort: bossPort,
      realmContexts: realmContexts,
      realmUri: realmUri,
      invocationId: invocationId,
      calleeSessionId: calleeSessionId,
      errorUri: wamp_core.Error.unknown,
      arguments: [error.toString()],
    );
  }
}

Future<void> _sendInternalInvocationError({
  required SendPort bossPort,
  required RealmContextCache realmContexts,
  required String realmUri,
  required int invocationId,
  required int calleeSessionId,
  required String errorUri,
  List<dynamic>? arguments,
  Map<String, Object?>? argumentsKeywords,
  Map<String, Object?>? details,
}) async {
  try {
    final context = realmContexts.contextFor(realmUri);
    final invocation = await context.getInvocation(invocationId);
    if (invocation == null) {
      return;
    }
    if (invocation.calleeSessionId != calleeSessionId) {
      await context.completeInvocation(invocationId);
      return;
    }
    await context.completeInvocation(invocationId);
    final callerPort = invocation.callerInternalSendPort;
    if (callerPort != null) {
      callerPort.send({
        'type': 'call_error',
        'requestId': invocation.callerRequestId,
        'error': errorUri,
        'arguments': arguments,
        'argumentsKeywords': argumentsKeywords,
        'details': details,
      });
      return;
    }
    final callerConnectionId = await _findConnectionIdForSession(
      context: context,
      sessionId: invocation.callerSessionId,
      forceRefresh: true,
    );
    if (callerConnectionId == null) {
      return;
    }
    final error = error_msg.Error(
      MessageTypes.codeCall,
      invocation.callerRequestId,
      details ?? const {},
      errorUri,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
    );
    _forwardToConnection(
      bossPort: bossPort,
      connectionId: callerConnectionId,
      message: error,
    );
  } catch (error) {
    // Swallow errors – nothing else we can do at this point.
  }
}

Future<void> _handleYield({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required yield_msg.Yield message,
  NativeIncomingMessage? incomingMessage,
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
  var nativeForwardingFailed = false;
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

    if (invocation.cancelRequested) {
      await _sendInvocationErrorToCallee(
        bossPort: bossPort,
        state: state,
        connectionId: connectionId,
        invocationId: invocationId,
        reason: error_msg.Error.errorInvocationCanceled,
        detailsMessage: 'Invocation $invocationId was cancelled',
      );
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

    var usedZeroCopy = false;
    if (incomingMessage?.hasNativeHandle == true) {
      final retainedHandle = incomingMessage!.retainHandle();
      if (retainedHandle > 0) {
        final command = {
          'type': 'worker_forward_native_result',
          'connectionId': callerConnectionId,
          'handle': retainedHandle,
          'requestId': invocation.callerRequestId,
          'progress': isProgress,
        };
        try {
          bossPort.send(command);
          usedZeroCopy = true;
        } catch (error) {
          nativeForwardingFailed = true;
          incomingMessage.releaseRetainedHandle(retainedHandle);
          rethrow;
        }
      }
    }

    if (!usedZeroCopy) {
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
    }
  } on StateError catch (error) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: invocationId,
      reason: _wampErrorNoSuchInvocation,
      detailsMessage: error.message,
    );
    if (nativeForwardingFailed) {
      rethrow;
    }
  } catch (error) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: invocationId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
    if (nativeForwardingFailed) {
      rethrow;
    }
  }
}

Future<void> _handleInvocationError({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  required error_msg.Error message,
  NativeIncomingMessage? incomingMessage,
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
  var nativeForwardingFailed = false;
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

    var usedZeroCopy = false;
    if (incomingMessage?.hasNativeHandle == true) {
      final retainedHandle = incomingMessage!.retainHandle();
      if (retainedHandle > 0) {
        final command = {
          'type': 'worker_forward_native_error',
          'connectionId': callerConnectionId,
          'handle': retainedHandle,
          'requestType': MessageTypes.codeCall,
          'requestId': invocation.callerRequestId,
        };
        try {
          bossPort.send(command);
          usedZeroCopy = true;
        } catch (error) {
          nativeForwardingFailed = true;
          incomingMessage.releaseRetainedHandle(retainedHandle);
          rethrow;
        }
      }
    }

    if (!usedZeroCopy) {
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
    }
  } on StateError catch (error) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: invocationId,
      reason: _wampErrorNoSuchInvocation,
      detailsMessage: error.message,
    );
    if (nativeForwardingFailed) {
      rethrow;
    }
  } catch (error) {
    await _sendInvocationErrorToCallee(
      bossPort: bossPort,
      state: state,
      connectionId: connectionId,
      invocationId: invocationId,
      reason: wamp_core.Error.unknown,
      detailsMessage: error.toString(),
    );
    if (nativeForwardingFailed) {
      rethrow;
    }
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

ProcedureMatchPolicy _matchPolicyFromRegisterOptions(
  register_msg.RegisterOptions? options,
) {
  final match = options?.match;
  if (match == register_msg.RegisterOptions.matchPrefix) {
    return ProcedureMatchPolicy.prefix;
  }
  if (match == register_msg.RegisterOptions.matchWildcard) {
    return ProcedureMatchPolicy.wildcard;
  }
  return ProcedureMatchPolicy.exact;
}

void _validateTopicUri(String topic, TopicMatchPolicy policy) {
  if (policy == TopicMatchPolicy.prefix && topic.endsWith('.')) {
    final trimmed = topic.substring(0, topic.length - 1);
    if (trimmed.isEmpty || trimmed.endsWith('.')) {
      throw ArgumentError('invalid_uri: $topic');
    }
    if (!uri_pattern.UriPattern.match(trimmed)) {
      throw ArgumentError('invalid_uri: $topic');
    }
    return;
  }

  final isValid = switch (policy) {
    TopicMatchPolicy.exact => uri_pattern.UriPattern.match(topic),
    TopicMatchPolicy.prefix => uri_pattern.UriPattern.match(topic),
    TopicMatchPolicy.wildcard => uri_pattern.UriPattern.matchWildcard(topic),
  };
  if (policy == TopicMatchPolicy.wildcard && topic.contains('*')) {
    throw ArgumentError('invalid_uri: $topic');
  }
  if (!isValid) {
    throw ArgumentError('invalid_uri: $topic');
  }
}

void _validateProcedureUri(String procedure, ProcedureMatchPolicy matchPolicy) {
  if (matchPolicy == ProcedureMatchPolicy.prefix && procedure.endsWith('.')) {
    final trimmed = procedure.substring(0, procedure.length - 1);
    if (trimmed.isEmpty || trimmed.endsWith('.')) {
      throw ArgumentError('invalid_uri: $procedure');
    }
    if (!uri_pattern.UriPattern.match(trimmed)) {
      throw ArgumentError('invalid_uri: $procedure');
    }
    return;
  }

  final isValid = switch (matchPolicy) {
    ProcedureMatchPolicy.exact => uri_pattern.UriPattern.match(procedure),
    ProcedureMatchPolicy.prefix => uri_pattern.UriPattern.match(procedure),
    ProcedureMatchPolicy.wildcard => uri_pattern.UriPattern.matchWildcard(
      procedure,
    ),
  };
  if (matchPolicy == ProcedureMatchPolicy.wildcard && procedure.contains('*')) {
    throw ArgumentError('invalid_uri: $procedure');
  }
  if (!isValid) {
    throw ArgumentError('invalid_uri: $procedure');
  }
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
  if (options.excludeAuthRole != null) {
    map['exclude_authroles'] = List<String>.from(options.excludeAuthRole!);
  }
  if (options.eligibleAuthRole != null) {
    map['eligible_authroles'] = List<String>.from(options.eligibleAuthRole!);
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

String _reasonForRegisterStateError(String? message) {
  if (message == null) {
    return wamp_core.Error.unknown;
  }
  if (message.contains('already registered')) {
    return wamp_core.Error.procedureAlreadyExists;
  }
  if (message.contains('Session')) {
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
  NativeIncomingMessage? incomingMessage,
}) => _handleSessionMessage(
  bossPort: bossPort,
  statePort: statePort,
  realmContexts: realmContexts,
  state: state,
  message: message,
  connectionId: connectionId,
  incomingMessage: incomingMessage,
);

@visibleForTesting
Future<void> initiateServerGoodbyeForTest({
  required SendPort bossPort,
  required SendPort? statePort,
  required RealmContextCache? realmContexts,
  required WorkerConnectionState state,
  required int connectionId,
  String reason = 'wamp.close.system_shutdown',
}) => _handleGoodbye(
  bossPort: bossPort,
  statePort: statePort,
  realmContexts: realmContexts,
  state: state,
  connectionId: connectionId,
  reason: reason,
);

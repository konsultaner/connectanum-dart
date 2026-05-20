part of '../router_instance.dart';

const String _jsonBinaryPrefix = '\\u0000';

class RouterSession {
  RouterSession._({
    required this.binding,
    required this.sessionId,
    required this.realmUri,
    required this.authId,
    required this.authRole,
    required this.authMethod,
    required this.authProvider,
    required this.authorizationIsInternal,
    this.cacheKey,
    required Map<String, Object?> roles,
    required SendPort commandPort,
    required RawReceivePort controlPort,
    required ReceivePort responsePort,
    required Isolate isolate,
  }) : roles = Map.unmodifiable(roles),
       _commandPort = commandPort,
       _controlPort = controlPort,
       _responsePort = responsePort,
       _isolate = isolate {
    _controlPort.handler = Zone.current.bindUnaryCallbackGuarded(
      _handleControlMessage,
    );
    _responsePort.listen(_handleResponseMessage);
  }

  final RouterBinding binding;
  final int sessionId;
  final String realmUri;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final bool authorizationIsInternal;
  final String? cacheKey;
  final Map<String, Object?> roles;

  final SendPort _commandPort;
  final RawReceivePort _controlPort;
  final ReceivePort _responsePort;
  final Isolate _isolate;

  bool _closed = false;
  int _nextCommandId = 1;
  int _nextRegisterRequestId = 1;
  int _nextSubscribeRequestId = 1;
  int _nextPublishRequestId = 1;
  int _nextCallRequestId = 1;

  final Map<int, Completer<dynamic>> _pendingCommands = {};
  final Map<int, registered_msg.Registered> _registrations = {};
  final Map<int, subscribed_msg.Subscribed> _subscriptions = {};
  final Map<int, StreamController<result_msg.Result>> _callControllers = {};

  Future<void> close() async {
    if (_closed) {
      return;
    }
    final closeFuture = _sendCommand(_internalCmdClose, const {});
    _closed = true;
    await closeFuture;
    _controlPort.close();
    _responsePort.close();
    _pendingCommands.clear();
    for (final registered in _registrations.values.toList()) {
      await registered.closeInvocationStream();
    }
    _registrations.clear();
    for (final subscribed in _subscriptions.values.toList()) {
      await subscribed.closeEventStream();
    }
    _subscriptions.clear();
    for (final controller in _callControllers.values.toList()) {
      await controller.close();
    }
    _callControllers.clear();
    binding._removeInternalSession(this);
    _isolate.kill(priority: Isolate.immediate);
  }

  Future<dynamic> _sendCommand(String command, Map<String, Object?> payload) {
    if (_closed) {
      throw StateError('Internal session closed');
    }
    final requestId = _nextCommandId++;
    final completer = Completer<dynamic>();
    _pendingCommands[requestId] = completer;
    _commandPort.send({
      'type': 'command',
      'command': command,
      'requestId': requestId,
      'payload': _transferIsolateValue(payload),
      'replyPort': _responsePort.sendPort,
    });
    return completer.future;
  }

  void _handleResponseMessage(dynamic message) {
    if (message is! Map) {
      return;
    }
    final requestId = message['requestId'] as int?;
    if (requestId == null) {
      return;
    }
    final completer = _pendingCommands.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final type = message['type'];
    if (type == _internalMsgCommandResult) {
      completer.complete(message['result']);
    } else if (type == _internalMsgCommandError) {
      completer.completeError(StateError('${message['error']}'));
    } else {
      completer.completeError(
        StateError('Unexpected response for request $requestId: $message'),
      );
    }
  }

  void _handleControlMessage(dynamic message) {
    if (_closed || message is! Map) {
      return;
    }
    final type = message['type'];
    if (type == _internalMsgSessionClosed) {
      _closed = true;
      binding._removeInternalSession(this);
    } else if (type == _internalMsgForwardEvent) {
      final connectionId = message['connectionId'] as int?;
      final subscriptionId = message['subscriptionId'] as int?;
      final publicationId = message['publicationId'] as int?;
      if (connectionId == null ||
          subscriptionId == null ||
          publicationId == null) {
        return;
      }
      final detailMap =
          (_materializeTransferredValue(message['details']) as Map?)
              ?.cast<String, Object?>() ??
          const <String, Object?>{};
      final details = event_msg.EventDetails(
        publisher: message['publisherSessionId'] as int?,
        topic: message['topic'] as String?,
        trustlevel: detailMap['trustlevel'] as int?,
        pptScheme: message['pptScheme'] as String?,
        pptSerializer: message['pptSerializer'] as String?,
        pptCipher: message['pptCipher'] as String?,
        pptKeyid: message['pptKeyId'] as String?,
      );
      final custom = Map<String, dynamic>.from(detailMap)
        ..remove('publisher')
        ..remove('trustlevel')
        ..remove('topic')
        ..remove('ppt_scheme')
        ..remove('ppt_serializer')
        ..remove('ppt_cipher')
        ..remove('ppt_keyid');
      if (custom.isNotEmpty) {
        details.custom.addAll(custom);
      }
      final transferredPayload = _materializeTransferredValue(
        message[_internalMsgLazyPayload],
      );
      final event = event_msg.Event(subscriptionId, publicationId, details);
      _applyTransferredLazyPayload(
        event,
        transferredPayload,
        fallbackArguments:
            (_materializeTransferredValue(message['arguments']) as List?)
                ?.cast<dynamic>()
                .toList(growable: false),
        fallbackArgumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        pptScheme: details.pptScheme,
        pptSerializer: details.pptSerializer,
        pptCipher: details.pptCipher,
        pptKeyId: details.pptKeyId,
      );
      binding.forwardMessageToConnection(connectionId, event);
    } else if (type == _internalMsgForwardInvocation) {
      final connectionId = message['connectionId'] as int?;
      final forward = message['message'];
      if (connectionId == null || forward is! AbstractMessage) {
        return;
      }
      binding.forwardMessageToConnection(connectionId, forward);
    } else if (type == _internalMsgSubscriptionEvent) {
      final subscriptionId = message['subscriptionId'] as int?;
      final publicationId = message['publicationId'] as int?;
      if (subscriptionId == null || publicationId == null) {
        return;
      }
      final subscribed = _subscriptions[subscriptionId];
      if (subscribed == null) {
        return;
      }
      final detailMap =
          (_materializeTransferredValue(message['details']) as Map?)
              ?.cast<String, Object?>() ??
          const <String, Object?>{};
      final custom = Map<String, dynamic>.from(detailMap)
        ..remove('publisher')
        ..remove('trustlevel')
        ..remove('topic')
        ..remove('ppt_scheme')
        ..remove('ppt_serializer')
        ..remove('ppt_cipher')
        ..remove('ppt_keyid');
      final details = event_msg.EventDetails(
        publisher: message['publisherSessionId'] as int?,
        topic: message['topic'] as String?,
        trustlevel: detailMap['trustlevel'] as int?,
        pptScheme: message['pptScheme'] as String?,
        pptSerializer: message['pptSerializer'] as String?,
        pptCipher: message['pptCipher'] as String?,
        pptKeyid: message['pptKeyId'] as String?,
      );
      if (custom.isNotEmpty) {
        details.custom.addAll(custom);
      }
      final transferredPayload = _materializeTransferredValue(
        message[_internalMsgLazyPayload],
      );
      if (!subscribed.hasMaterializedEventConsumers) {
        subscribed.addLazyEventPayload(
          event_msg.LazyEventPayload(
            subscriptionId: subscriptionId,
            publicationId: publicationId,
            publisher: message['publisherSessionId'] as int?,
            topic: message['topic'] as String?,
            pptScheme: message['pptScheme'] as String?,
            pptSerializer: message['pptSerializer'] as String?,
            pptCipher: message['pptCipher'] as String?,
            pptKeyId: message['pptKeyId'] as String?,
            customDetails: custom.isEmpty ? null : custom,
            payload:
                _lazyPayloadFromTransferredWithPpt(
                  transferredPayload,
                  pptScheme: message['pptScheme'] as String?,
                  pptSerializer: message['pptSerializer'] as String?,
                  pptCipher: message['pptCipher'] as String?,
                  pptKeyId: message['pptKeyId'] as String?,
                ) ??
                LazyMessagePayload.materialized(
                  arguments:
                      (_materializeTransferredValue(message['arguments'])
                              as List?)
                          ?.cast<dynamic>()
                          .toList(growable: false),
                  argumentsKeywords:
                      (_materializeTransferredValue(
                                message['argumentsKeywords'],
                              )
                              as Map?)
                          ?.cast<String, dynamic>(),
                ),
          ),
        );
        return;
      }
      final event = event_msg.Event(subscriptionId, publicationId, details);
      _applyTransferredLazyPayload(
        event,
        transferredPayload,
        fallbackArguments:
            (_materializeTransferredValue(message['arguments']) as List?)
                ?.cast<dynamic>()
                .toList(growable: false),
        fallbackArgumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        pptScheme: details.pptScheme,
        pptSerializer: details.pptSerializer,
        pptCipher: details.pptCipher,
        pptKeyId: details.pptKeyId,
      );
      subscribed.addEvent(event);
    } else if (type == _internalMsgInvocationRequest) {
      final registrationId = message['registrationId'] as int?;
      final invocationId = message['invocationId'] as int?;
      final replyPort = message['replyPort'] as SendPort?;
      if (registrationId == null || invocationId == null || replyPort == null) {
        return;
      }
      final registered = _registrations[registrationId];
      if (registered == null) {
        replyPort.send({
          'type': 'error',
          'error': wamp_core.Error.noSuchProcedure,
        });
        return;
      }
      final options =
          (_materializeTransferredValue(message['options']) as Map?)
              ?.cast<String, Object?>() ??
          const {};
      final details = invocation_msg.InvocationDetails(
        message['callerSessionId'] as int?,
        message['procedure'] as String?,
        options['receive_progress'] == true,
        message['pptScheme'] as String? ?? options['ppt_scheme'] as String?,
        message['pptSerializer'] as String? ??
            options['ppt_serializer'] as String?,
        message['pptCipher'] as String? ?? options['ppt_cipher'] as String?,
        message['pptKeyId'] as String? ?? options['ppt_keyid'] as String?,
      );
      final custom = _filteredInvocationOptionDetails(options);
      final callerAuthId = message['callerAuthId'] as String?;
      if (callerAuthId != null) {
        custom['caller_authid'] = callerAuthId;
      }
      final callerAuthRole = message['callerAuthRole'] as String?;
      if (callerAuthRole != null) {
        custom['caller_authrole'] = callerAuthRole;
      }
      if (custom.isNotEmpty) {
        details.custom.addAll(custom);
      }
      final transferredPayload = _materializeTransferredValue(
        message[_internalMsgLazyPayload],
      );
      final invocation = invocation_msg.Invocation(
        invocationId,
        registrationId,
        details,
      );
      _applyTransferredLazyPayload(
        invocation,
        transferredPayload,
        fallbackArguments:
            (_materializeTransferredValue(message['arguments']) as List?)
                ?.cast<dynamic>()
                .toList(growable: false),
        fallbackArgumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        pptScheme: details.pptScheme,
        pptSerializer: details.pptSerializer,
        pptCipher: details.pptCipher,
        pptKeyId: details.pptKeyId,
      );
      invocation.onResponse((response) {
        if (response is yield_msg.Yield) {
          final details = <String, Object?>{};
          if (response.options?.progress != null) {
            details['progress'] = response.options!.progress;
          }
          if (response.options?.pptScheme != null) {
            details['ppt_scheme'] = response.options!.pptScheme;
          }
          if (response.options?.pptSerializer != null) {
            details['ppt_serializer'] = response.options!.pptSerializer;
          }
          if (response.options?.pptCipher != null) {
            details['ppt_cipher'] = response.options!.pptCipher;
          }
          if (response.options?.pptKeyId != null) {
            details['ppt_keyid'] = response.options!.pptKeyId;
          }
          if (response.options?.custom.isNotEmpty == true) {
            details.addAll(response.options!.custom);
          }
          replyPort.send({
            'type': 'result',
            _internalMsgLazyPayload: _transferAbstractMessagePayload(response),
            'progress': response.options?.progress ?? false,
            'pptScheme': response.options?.pptScheme,
            'pptSerializer': response.options?.pptSerializer,
            'pptCipher': response.options?.pptCipher,
            'pptKeyId': response.options?.pptKeyId,
            'details': details.isEmpty ? null : _transferIsolateValue(details),
          });
        } else if (response is error_msg.Error) {
          replyPort.send({
            'type': 'error',
            'error': response.error,
            _internalMsgLazyPayload: _transferAbstractMessagePayload(response),
            'details': _transferIsolateValue(response.details),
          });
        }
      });
      if (!registered.hasMaterializedInvocationConsumers) {
        registered.addLazyInvocationPayload(
          invocation.toLazyInvocationPayload(anchor: invocation),
        );
      } else {
        registered.addInvocation(invocation);
      }
    } else if (type == _internalMsgForwardInterrupt) {
      final connectionId = message['connectionId'] as int?;
      final invocationId = message['invocationId'] as int?;
      if (connectionId == null || invocationId == null) {
        return;
      }
      final mode = message['mode'] as String?;
      interrupt_msg.InterruptOptions? options;
      if (mode != null) {
        options = interrupt_msg.InterruptOptions()..mode = mode;
      }
      final interrupt = interrupt_msg.Interrupt(invocationId, options: options);
      binding.forwardMessageToConnection(connectionId, interrupt);
    } else if (type == _internalMsgCallResult) {
      final requestId = message['requestId'] as int?;
      if (requestId == null) {
        return;
      }
      _emitCallResult(
        requestId,
        transferredPayload: _materializeTransferredValue(
          message[_internalMsgLazyPayload],
        ),
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        progress: message['progress'] == true,
        pptScheme: message['pptScheme'] as String?,
        pptSerializer: message['pptSerializer'] as String?,
        pptCipher: message['pptCipher'] as String?,
        pptKeyId: message['pptKeyId'] as String?,
        details: (_materializeTransferredValue(message['details']) as Map?)
            ?.cast<String, Object?>(),
      );
    } else if (type == _internalMsgCallError) {
      final requestId = message['requestId'] as int?;
      if (requestId == null) {
        return;
      }
      _emitCallError(
        requestId,
        errorUri: message['error'] as String? ?? wamp_core.Error.unknown,
        transferredPayload: _materializeTransferredValue(
          message[_internalMsgLazyPayload],
        ),
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, Object?>(),
        details: (_materializeTransferredValue(message['details']) as Map?)
            ?.cast<String, Object?>(),
      );
    } else if (type == _internalMsgCallProgress) {
      final requestId = message['requestId'] as int?;
      if (requestId == null) {
        return;
      }
      _emitCallResult(
        requestId,
        transferredPayload: _materializeTransferredValue(
          message[_internalMsgLazyPayload],
        ),
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        progress: true,
        pptScheme: message['pptScheme'] as String?,
        pptSerializer: message['pptSerializer'] as String?,
        pptCipher: message['pptCipher'] as String?,
        pptKeyId: message['pptKeyId'] as String?,
        details: (_materializeTransferredValue(message['details']) as Map?)
            ?.cast<String, Object?>(),
      );
    } else if (type == HttpInvocationControlMessages.openResponseStream) {
      final messageReceivedAtUs = DateTime.now().microsecondsSinceEpoch;
      final requestId = message['requestId'] as int?;
      final status = message['status'] as int?;
      final headers = (message['headers'] as Map?)?.cast<String, String>();
      final sentAtUs = message['sentAtUs'] as int?;
      final replyPort = message['replyPort'] as SendPort?;
      final replyRequestId = message['replyRequestId'] as int?;
      if (requestId == null ||
          status == null ||
          headers == null ||
          replyPort == null) {
        return;
      }
      final pending = binding._pendingHttpCalls[requestId];
      if (pending == null) {
        replyPort.send({
          ...?(replyRequestId == null
              ? null
              : <String, Object?>{'replyRequestId': replyRequestId}),
          'error': 'pending_http_request_not_found',
        });
        return;
      }
      int? requestQueueDelayUs;
      if (sentAtUs != null &&
          sentAtUs >= 0 &&
          messageReceivedAtUs >= sentAtUs) {
        requestQueueDelayUs = messageReceivedAtUs - sentAtUs;
      }
      final openStopwatch = Stopwatch()..start();
      final descriptor = binding._openDirectResponseStream(
        pending,
        status: status,
        headers: headers,
      );
      if (descriptor == null) {
        replyPort.send({
          ...?(replyRequestId == null
              ? null
              : <String, Object?>{'replyRequestId': replyRequestId}),
          'error': 'unsupported',
        });
        return;
      }
      final response = <String, Object?>{
        ...?(replyRequestId == null
            ? null
            : <String, Object?>{'replyRequestId': replyRequestId}),
        'handle': descriptor.handle,
        'descriptorOpenUs': openStopwatch.elapsedMicroseconds,
        ...?(requestQueueDelayUs == null
            ? null
            : <String, Object?>{'requestQueueDelayUs': requestQueueDelayUs}),
        ...?(descriptor.libraryPath == null
            ? null
            : <String, Object?>{'libraryPath': descriptor.libraryPath}),
        'replySentAtUs': DateTime.now().microsecondsSinceEpoch,
      };
      replyPort.send(response);
    }
  }

  void _emitCallResult(
    int requestId, {
    Object? transferredPayload,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    bool progress = false,
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
    Map<String, Object?>? details,
  }) {
    final controller = _callControllers[requestId];
    if (controller == null || controller.isClosed) {
      return;
    }
    final result = result_msg.Result(
      requestId,
      result_msg.ResultDetails(
        progress: progress,
        pptScheme: pptScheme,
        pptSerializer: pptSerializer,
        pptCipher: pptCipher,
        pptKeyId: pptKeyId,
      ),
    );
    if (details != null && details.isNotEmpty) {
      result.details.custom.addAll(details);
      result.details.custom.remove('progress');
      result.details.custom.remove('ppt_scheme');
      result.details.custom.remove('ppt_serializer');
      result.details.custom.remove('ppt_cipher');
      result.details.custom.remove('ppt_keyid');
    }
    _applyTransferredLazyPayload(
      result,
      transferredPayload,
      fallbackArguments: arguments,
      fallbackArgumentsKeywords: argumentsKeywords,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
    );
    controller.add(result);
    if (!progress) {
      controller.close();
      _callControllers.remove(requestId);
    }
  }

  void _emitCallError(
    int requestId, {
    required String errorUri,
    Object? transferredPayload,
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    Map<String, Object?>? details,
  }) {
    final controller = _callControllers.remove(requestId);
    if (controller == null || controller.isClosed) {
      return;
    }
    final error = error_msg.Error(
      MessageTypes.codeCall,
      requestId,
      details ?? const {},
      errorUri,
    );
    _applyTransferredLazyPayload(
      error,
      transferredPayload,
      fallbackArguments: arguments,
      fallbackArgumentsKeywords: argumentsKeywords?.cast<String, dynamic>(),
    );
    controller.addError(error);
    controller.close();
  }

  Future<registered_msg.Registered> register(
    String procedure, {
    register_msg.RegisterOptions? options,
  }) async {
    final requestId = _nextRegisterRequestId++;
    final registrationId =
        await _sendCommand(_internalCmdRegister, <String, Object?>{
              'procedure': procedure,
              'options': _registerOptionsToMap(options),
            })
            as int;
    final registered = registered_msg.Registered(requestId, registrationId)
      ..procedure = procedure;
    _registrations[registrationId] = registered;
    return registered;
  }

  Future<void> unregister(int registrationId) async {
    await _sendCommand(_internalCmdUnregister, <String, Object?>{
      'registrationId': registrationId,
    });
    final registered = _registrations.remove(registrationId);
    await registered?.closeInvocationStream();
  }

  Future<subscribed_msg.Subscribed> subscribe(
    String topic, {
    subscribe_msg.SubscribeOptions? options,
  }) async {
    final requestId = _nextSubscribeRequestId++;
    final subscriptionId =
        await _sendCommand(_internalCmdSubscribe, <String, Object?>{
              'topic': topic,
              'options': _subscribeOptionsToMap(options),
            })
            as int;
    final subscribed = subscribed_msg.Subscribed(requestId, subscriptionId);
    _subscriptions[subscriptionId] = subscribed;
    return subscribed;
  }

  Future<void> unsubscribe(int subscriptionId) async {
    await _sendCommand(_internalCmdUnsubscribe, <String, Object?>{
      'subscriptionId': subscriptionId,
    });
    final subscribed = _subscriptions.remove(subscriptionId);
    await subscribed?.closeEventStream();
  }

  Future<published_msg.Published?> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    publish_msg.PublishOptions? options,
  }) async {
    return publishLazyPayload(
      topic,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: options,
    );
  }

  Future<published_msg.Published?> publishLazyPayload(
    String topic, {
    required LazyMessagePayload payload,
    publish_msg.PublishOptions? options,
  }) async {
    final requestId = _nextPublishRequestId++;
    final commandPayload = <String, Object?>{
      'topic': topic,
      'lazyPayload': _transferLazyMessagePayload(payload),
      'options': _publishOptionsToMap(options),
    };
    final publicationId =
        await _sendCommand(_internalCmdPublish, commandPayload) as int;
    if (options?.acknowledge == true) {
      return published_msg.Published(requestId, publicationId);
    }
    return null;
  }

  Stream<result_msg.Result> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    call_msg.CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    return callLazyPayload(
      procedure,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: options,
      cancelCompleter: cancelCompleter,
    );
  }

  Stream<result_msg.Result> callLazyPayload(
    String procedure, {
    required LazyMessagePayload payload,
    call_msg.CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    final requestId = _nextCallRequestId++;
    final controller = StreamController<result_msg.Result>(
      onCancel: () {
        _callControllers.remove(requestId);
      },
    );
    _callControllers[requestId] = controller;
    final commandPayload = <String, Object?>{
      'requestId': requestId,
      'procedure': procedure,
      'lazyPayload': _transferLazyMessagePayload(payload),
      'options': _callOptionsToMap(options),
    };
    _sendCommand(_internalCmdCall, commandPayload).catchError((error, stack) {
      if (!controller.isClosed) {
        controller.addError(
          error,
          stack is StackTrace ? stack : StackTrace.current,
        );
        controller.close();
      }
    });
    if (cancelCompleter != null) {
      cancelCompleter.future.then((mode) {
        _sendCommand(_internalCmdCancel, <String, Object?>{
          'requestId': requestId,
          'mode': mode,
        });
      });
    }
    return controller.stream;
  }

  Map<String, Object?> _registerOptionsToMap(
    register_msg.RegisterOptions? options,
  ) {
    if (options == null) {
      return const {};
    }
    final map = <String, Object?>{};
    if (options.discloseCaller != null) {
      map['disclose_caller'] = options.discloseCaller;
    }
    if (options.match != null) {
      map['match'] = options.match;
    }
    if (options.invoke != null) {
      map['invoke'] = options.invoke;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    return map;
  }

  Map<String, Object?> _subscribeOptionsToMap(
    subscribe_msg.SubscribeOptions? options,
  ) {
    if (options == null) {
      return const {};
    }
    final map = <String, Object?>{};
    if (options.match != null) {
      map['match'] = options.match;
    }
    if (options.metaTopic != null) {
      map['meta_topic'] = options.metaTopic;
    }
    if (options.getRetained != null) {
      map['get_retained'] = options.getRetained;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    return map;
  }

  Map<String, Object?> _publishOptionsToMap(
    publish_msg.PublishOptions? options,
  ) {
    if (options == null) {
      return const {};
    }
    final map = <String, Object?>{};
    if (options.acknowledge != null) {
      map['acknowledge'] = options.acknowledge;
    }
    if (options.exclude != null) {
      map['exclude'] = options.exclude;
    }
    if (options.excludeAuthId != null) {
      map['exclude_authid'] = options.excludeAuthId;
    }
    if (options.excludeAuthRole != null) {
      map['exclude_authrole'] = options.excludeAuthRole;
    }
    if (options.eligible != null) {
      map['eligible'] = options.eligible;
    }
    if (options.eligibleAuthId != null) {
      map['eligible_authid'] = options.eligibleAuthId;
    }
    if (options.eligibleAuthRole != null) {
      map['eligible_authrole'] = options.eligibleAuthRole;
    }
    if (options.excludeMe != null) {
      map['exclude_me'] = options.excludeMe;
    }
    if (options.discloseMe != null) {
      map['disclose_me'] = options.discloseMe;
    }
    if (options.retain != null) {
      map['retain'] = options.retain;
    }
    if (options.pptScheme != null) {
      map['ppt_scheme'] = options.pptScheme;
    }
    if (options.pptSerializer != null) {
      map['ppt_serializer'] = options.pptSerializer;
    }
    if (options.pptCipher != null) {
      map['ppt_cipher'] = options.pptCipher;
    }
    if (options.pptKeyId != null) {
      map['ppt_keyid'] = options.pptKeyId;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
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
    if (options.pptScheme != null) {
      map['ppt_scheme'] = options.pptScheme;
    }
    if (options.pptSerializer != null) {
      map['ppt_serializer'] = options.pptSerializer;
    }
    if (options.pptCipher != null) {
      map['ppt_cipher'] = options.pptCipher;
    }
    if (options.pptKeyId != null) {
      map['ppt_keyid'] = options.pptKeyId;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    return map;
  }
}

const String _internalCmdRegister = 'register';
const String _internalCmdUnregister = 'unregister';
const String _internalCmdSubscribe = 'subscribe';
const String _internalCmdUnsubscribe = 'unsubscribe';
const String _internalCmdPublish = 'publish';
const String _internalCmdCall = 'call';
const String _internalCmdCancel = 'cancel';
const String _internalCmdClose = 'close';

const String _internalMsgCommandResult = 'command_result';
const String _internalMsgCommandError = 'command_error';
const String _internalMsgForwardEvent = 'forward_event';
const String _internalMsgSubscriptionEvent = 'subscription_event';
const String _internalMsgInvocationRequest = 'invocation_request';
const String _internalMsgCallResult = 'call_result';
const String _internalMsgCallError = 'call_error';
const String _internalMsgCallProgress = 'call_progress';
const String _internalMsgForwardInterrupt = 'forward_interrupt';
const String _internalMsgLazyPayload = 'lazyPayload';

const String _transferredLazyPayloadMarkerKey = r'$connectanumLazyPayload';
const String _transferredLazyPayloadEncodingKey = 'encoding';
const String _transferredLazyPayloadTransparentBinaryKey =
    'transparentBinaryPayload';
const String _transferredLazyPayloadArgumentsBytesKey = 'argumentsBytes';
const String _transferredLazyPayloadArgumentsKeywordsBytesKey =
    'argumentsKeywordsBytes';
const String _transferredLazyPayloadPackedPayloadBytesKey =
    'packedPayloadBytes';
const String _transferredLazyPayloadArgumentsKey = 'arguments';
const String _transferredLazyPayloadArgumentsKeywordsKey = 'argumentsKeywords';
const String _transferredLazyPayloadPptDecodedKey = 'pptDecoded';

Object? _transferLazyMessagePayload(LazyMessagePayload? payload) {
  if (payload == null) {
    return null;
  }
  return _buildTransferredLazyPayload(
    encoding: payload.encoding,
    pptDecoded: payload.pptDecoded,
    transparentBinaryPayload: payload.transparentBinaryPayload,
    argumentsBytes: payload.argumentsBytes,
    argumentsKeywordsBytes: payload.argumentsKeywordsBytes,
    packedPayloadBytes: payload.packedPayloadBytes,
    arguments:
        payload.argumentsBytes == null && payload.packedPayloadBytes == null
        ? payload.arguments
        : null,
    argumentsKeywords:
        payload.argumentsKeywordsBytes == null &&
            payload.packedPayloadBytes == null
        ? payload.argumentsKeywords
        : null,
  );
}

Object? _transferAbstractMessagePayload(
  AbstractMessageWithPayload message, {
  List<dynamic>? argumentsOverride,
  bool overrideArguments = false,
  Map<String, dynamic>? argumentsKeywordsOverride,
  bool overrideArgumentsKeywords = false,
}) {
  final canReuseEncodedArguments =
      !overrideArguments &&
      message.debugEncodedArgumentsBytes != null &&
      message.lazyPayloadEncoding != null;
  final canReuseEncodedArgumentsKeywords =
      !overrideArgumentsKeywords &&
      message.debugEncodedArgumentsKeywordsBytes != null &&
      message.lazyPayloadEncoding != null;
  return _buildTransferredLazyPayload(
    encoding: message.lazyPayloadEncoding,
    pptDecoded: message.hasDecodedPptPayload,
    transparentBinaryPayload: message.transparentBinaryPayload,
    argumentsBytes: canReuseEncodedArguments
        ? message.debugEncodedArgumentsBytes
        : null,
    argumentsKeywordsBytes: canReuseEncodedArgumentsKeywords
        ? message.debugEncodedArgumentsKeywordsBytes
        : null,
    arguments: canReuseEncodedArguments
        ? null
        : (overrideArguments ? argumentsOverride : message.arguments),
    argumentsKeywords: canReuseEncodedArgumentsKeywords
        ? null
        : (overrideArgumentsKeywords
              ? argumentsKeywordsOverride
              : message.argumentsKeywords),
  );
}

Object? _buildTransferredLazyPayload({
  LazyPayloadEncoding? encoding,
  bool pptDecoded = false,
  Uint8List? transparentBinaryPayload,
  Uint8List? argumentsBytes,
  Uint8List? argumentsKeywordsBytes,
  Uint8List? packedPayloadBytes,
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
}) {
  if (transparentBinaryPayload == null &&
      argumentsBytes == null &&
      argumentsKeywordsBytes == null &&
      packedPayloadBytes == null &&
      arguments == null &&
      argumentsKeywords == null) {
    return null;
  }
  return <String, Object?>{
    _transferredLazyPayloadMarkerKey: true,
    _transferredLazyPayloadEncodingKey: ?encoding?.name,
    if (pptDecoded) _transferredLazyPayloadPptDecodedKey: true,
    _transferredLazyPayloadTransparentBinaryKey: ?transparentBinaryPayload,
    _transferredLazyPayloadPackedPayloadBytesKey: ?packedPayloadBytes,
    if (argumentsBytes != null)
      _transferredLazyPayloadArgumentsBytesKey: argumentsBytes
    else if (arguments != null)
      _transferredLazyPayloadArgumentsKey: _transferIsolateValue(arguments),
    if (argumentsKeywordsBytes != null)
      _transferredLazyPayloadArgumentsKeywordsBytesKey: argumentsKeywordsBytes
    else if (argumentsKeywords != null)
      _transferredLazyPayloadArgumentsKeywordsKey: _transferIsolateValue(
        argumentsKeywords,
      ),
  };
}

bool _isTransferredLazyPayload(Object? value) {
  return value is Map && value[_transferredLazyPayloadMarkerKey] == true;
}

LazyMessagePayload? _lazyPayloadFromTransferredWithPpt(
  Object? value, {
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
}) {
  if (!_isTransferredLazyPayload(value)) {
    return null;
  }
  final raw = (value as Map).cast<Object?, Object?>();
  final encoding = _lazyPayloadEncodingFromName(
    raw[_transferredLazyPayloadEncodingKey] as String?,
  );
  final transparentBinaryPayload = _coerceTransferredBytes(
    raw[_transferredLazyPayloadTransparentBinaryKey],
  );
  final pptDecoded = raw[_transferredLazyPayloadPptDecodedKey] == true;
  final argumentsBytes = _coerceTransferredBytes(
    raw[_transferredLazyPayloadArgumentsBytesKey],
  );
  final argumentsKeywordsBytes = _coerceTransferredBytes(
    raw[_transferredLazyPayloadArgumentsKeywordsBytesKey],
  );
  final packedPayloadBytes = _coerceTransferredBytes(
    raw[_transferredLazyPayloadPackedPayloadBytesKey],
  );
  final arguments = (raw[_transferredLazyPayloadArgumentsKey] as List?)
      ?.cast<dynamic>()
      .toList(growable: false);
  final argumentsKeywords =
      (raw[_transferredLazyPayloadArgumentsKeywordsKey] as Map?)
          ?.cast<String, dynamic>();
  final retainedPackedPayloadBytes =
      packedPayloadBytes ??
      _extractTransferredWrappedPayloadBytes(
        arguments,
        argumentsKeywords,
        pptScheme: pptScheme,
        pptSerializer: pptSerializer,
      );
  if (argumentsBytes != null || argumentsKeywordsBytes != null) {
    return LazyMessagePayload.encoded(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      argumentsDecoder: argumentsBytes == null || encoding == null
          ? null
          : _payloadListDecoderForEncoding(encoding),
      argumentsKeywordsDecoder:
          argumentsKeywordsBytes == null || encoding == null
          ? null
          : _payloadMapDecoderForEncoding(encoding),
      arguments: argumentsBytes == null ? arguments : null,
      argumentsKeywords: argumentsKeywordsBytes == null
          ? argumentsKeywords
          : null,
    );
  }
  if (retainedPackedPayloadBytes != null) {
    return LazyMessagePayload.packed(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding:
          encoding ?? _lazyPayloadEncodingFromPptSerializer(pptSerializer),
      packedPayloadBytes: retainedPackedPayloadBytes,
      packedPayloadDecoder: (bytes) {
        final decoded = decodeLazyPayloadView(
          LazyMessagePayload.materialized(arguments: <dynamic>[bytes]),
          pptScheme: pptScheme,
          pptSerializer:
              pptSerializer ?? _pptSerializerNameForEncoding(encoding),
          pptCipher: pptCipher,
          pptKeyId: pptKeyId,
        );
        return (
          arguments: decoded.arguments,
          argumentsKeywords: decoded.argumentsKeywords,
        );
      },
      pptDecoded: pptDecoded,
    );
  }
  return LazyMessagePayload.materialized(
    transparentBinaryPayload: transparentBinaryPayload,
    encoding: encoding,
    arguments: arguments,
    argumentsKeywords: argumentsKeywords,
    pptDecoded: pptDecoded,
  );
}

Uint8List? _coerceTransferredBytes(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  if (value is List) {
    return Uint8List.fromList(value.cast<int>());
  }
  throw StateError('Expected transferred byte payload but got $value');
}

void _applyTransferredLazyPayload(
  AbstractMessageWithPayload message,
  Object? transferredPayload, {
  List<dynamic>? fallbackArguments,
  Map<String, dynamic>? fallbackArgumentsKeywords,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
}) {
  final payload = _lazyPayloadFromTransferredWithPpt(
    transferredPayload,
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
  );
  if (payload == null) {
    message.arguments = fallbackArguments;
    message.argumentsKeywords = fallbackArgumentsKeywords;
    return;
  }
  message.restoreLazyPayload(payload);
}

LazyPayloadEncoding? _lazyPayloadEncodingFromName(String? value) {
  return switch (value) {
    'json' => LazyPayloadEncoding.json,
    'messagePack' => LazyPayloadEncoding.messagePack,
    'cbor' => LazyPayloadEncoding.cbor,
    _ => null,
  };
}

PayloadListDecoder _payloadListDecoderForEncoding(
  LazyPayloadEncoding encoding,
) {
  return (bytes) => _decodePayloadArgumentList(encoding, bytes);
}

PayloadMapDecoder _payloadMapDecoderForEncoding(LazyPayloadEncoding encoding) {
  return (bytes) => _decodePayloadKeywordMap(encoding, bytes);
}

List<dynamic> _decodePayloadArgumentList(
  LazyPayloadEncoding encoding,
  Uint8List bytes,
) {
  final decoded = _decodePayloadFragment(encoding, bytes);
  if (decoded == null) {
    return <dynamic>[];
  }
  if (decoded is List) {
    return List<dynamic>.from(decoded);
  }
  throw ArgumentError('Expected lazy payload arguments list but got $decoded');
}

Map<String, dynamic> _decodePayloadKeywordMap(
  LazyPayloadEncoding encoding,
  Uint8List bytes,
) {
  final decoded = _decodePayloadFragment(encoding, bytes);
  if (decoded == null) {
    return <String, dynamic>{};
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError(
    'Expected lazy payload keyword arguments map but got $decoded',
  );
}

Object? _decodePayloadFragment(LazyPayloadEncoding encoding, Uint8List bytes) {
  return switch (encoding) {
    LazyPayloadEncoding.json => _decodeJsonPayloadFragment(bytes),
    LazyPayloadEncoding.messagePack => msgpack_dart.deserialize(bytes),
    LazyPayloadEncoding.cbor => _decodeCborPayloadFragment(bytes),
  };
}

String? _pptSerializerNameForEncoding(LazyPayloadEncoding? encoding) {
  return switch (encoding) {
    LazyPayloadEncoding.json => 'json',
    LazyPayloadEncoding.messagePack => 'msgpack',
    LazyPayloadEncoding.cbor => 'cbor',
    null => null,
  };
}

LazyPayloadEncoding? _lazyPayloadEncodingFromPptSerializer(String? serializer) {
  return switch (serializer) {
    'json' => LazyPayloadEncoding.json,
    'msgpack' => LazyPayloadEncoding.messagePack,
    'cbor' => LazyPayloadEncoding.cbor,
    _ => null,
  };
}

Uint8List? _extractTransferredWrappedPayloadBytes(
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords, {
  String? pptScheme,
  String? pptSerializer,
}) {
  if (pptScheme == null) {
    return null;
  }
  if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
    return null;
  }
  if (arguments == null || arguments.length != 1) {
    return null;
  }
  final first = arguments.first;
  if (first is Uint8List) {
    return first;
  }
  if (first is List<int>) {
    return Uint8List.fromList(first);
  }
  if (first is List) {
    return Uint8List.fromList(first.cast<int>());
  }
  if (pptSerializer == null ||
      (pptSerializer != 'json' &&
          pptSerializer != 'msgpack' &&
          pptSerializer != 'cbor')) {
    return null;
  }
  return null;
}

Object? _decodeCborPayloadFragment(Uint8List bytes) {
  return _cborValueToDart(cbor.decode(bytes.toList()));
}

Object? _decodeJsonPayloadFragment(Uint8List bytes) {
  return _normalizeJsonBinaryPayload(json.decode(utf8.decode(bytes)));
}

Object? _normalizeJsonBinaryPayload(Object? value) {
  if (value is String && value.startsWith(_jsonBinaryPrefix)) {
    return Uint8List.fromList(
      base64.decode(value.substring(_jsonBinaryPrefix.length)),
    );
  }
  if (value is List) {
    return value
        .map<Object?>((element) => _normalizeJsonBinaryPayload(element))
        .toList(growable: false);
  }
  if (value is Map) {
    final entries = <MapEntry<Object?, Object?>>[];
    for (final entry in value.entries) {
      entries.add(
        MapEntry<Object?, Object?>(
          entry.key,
          _normalizeJsonBinaryPayload(entry.value),
        ),
      );
    }
    final allStringKeys = entries.every((entry) => entry.key is String);
    if (allStringKeys) {
      return Map<String, Object?>.fromEntries(
        entries.map((entry) => MapEntry(entry.key as String, entry.value)),
      );
    }
    return Map<Object?, Object?>.fromEntries(entries);
  }
  return value;
}

Object? _cborValueToDart(Object? value) {
  if (value is CborBytes) {
    return Uint8List.fromList(value.bytes);
  }
  if (value is CborList) {
    return value.map(_cborValueToDart).toList(growable: false);
  }
  if (value is CborMap) {
    final entries = <MapEntry<Object?, Object?>>[];
    value.forEach((key, nestedValue) {
      entries.add(
        MapEntry<Object?, Object?>(
          _cborValueToDart(key),
          _cborValueToDart(nestedValue),
        ),
      );
    });
    final allStringKeys = entries.every((entry) => entry.key is String);
    if (allStringKeys) {
      return Map<String, Object?>.fromEntries(
        entries.map((entry) => MapEntry(entry.key as String, entry.value)),
      );
    }
    return Map<Object?, Object?>.fromEntries(entries);
  }
  if (value is CborValue) {
    return value.toObject();
  }
  return value;
}

Object? _transferIsolateValue(Object? value) {
  if (value is Uint8List) {
    return TransferableTypedData.fromList([value]);
  }
  if (value is List) {
    return value
        .map<Object?>((element) => _transferIsolateValue(element))
        .toList(growable: false);
  }
  if (value is Map) {
    final entries = <MapEntry<Object?, Object?>>[];
    for (final entry in value.entries) {
      entries.add(
        MapEntry<Object?, Object?>(
          entry.key,
          _transferIsolateValue(entry.value),
        ),
      );
    }
    final allStringKeys = entries.every((entry) => entry.key is String);
    if (allStringKeys) {
      return Map<String, Object?>.fromEntries(
        entries.map((entry) => MapEntry(entry.key as String, entry.value)),
      );
    }
    return Map<Object?, Object?>.fromEntries(entries);
  }
  return value;
}

Object? _materializeTransferredValue(Object? value) {
  if (value is TransferableTypedData) {
    return value.materialize().asUint8List();
  }
  if (value is Uint8List) {
    return value;
  }
  if (value is List) {
    return value
        .map<Object?>((element) => _materializeTransferredValue(element))
        .toList(growable: false);
  }
  if (value is Map) {
    final entries = <MapEntry<Object?, Object?>>[];
    for (final entry in value.entries) {
      entries.add(
        MapEntry<Object?, Object?>(
          entry.key,
          _materializeTransferredValue(entry.value),
        ),
      );
    }
    final allStringKeys = entries.every((entry) => entry.key is String);
    if (allStringKeys) {
      return Map<String, Object?>.fromEntries(
        entries.map((entry) => MapEntry(entry.key as String, entry.value)),
      );
    }
    return Map<Object?, Object?>.fromEntries(entries);
  }
  return value;
}

const String _internalMsgForwardInvocation = 'forward_invocation';
const String _internalMsgSessionClosed = 'session_closed';

class _InternalSessionBootstrap {
  const _InternalSessionBootstrap({
    required this.sessionId,
    required this.realmUri,
    required this.authId,
    required this.authRole,
    required this.authMethod,
    required this.authProvider,
    required this.authorizationIsInternal,
    required this.roles,
    required this.realmSettings,
    required this.statePort,
    required this.controlPort,
    required this.handshakePort,
  });

  final int sessionId;
  final String realmUri;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final bool authorizationIsInternal;
  final Map<String, Object?> roles;
  final RealmSettings? realmSettings;
  final SendPort statePort;
  final SendPort controlPort;
  final SendPort handshakePort;
}

Future<void> _routerInternalSessionIsolate(
  _InternalSessionBootstrap bootstrap,
) async {
  final commandPort = ReceivePort();
  final invocationPort = ReceivePort();
  final isolate = _InternalSessionIsolate(
    bootstrap: bootstrap,
    commandPort: commandPort,
    invocationPort: invocationPort,
  );

  bootstrap.handshakePort.send({
    'commandPort': commandPort.sendPort,
    'invocationPort': invocationPort.sendPort,
  });

  commandPort.listen(isolate.handleCommand);
  invocationPort.listen(isolate.handleInvocationMessage);
}

class _InternalSessionIsolate {
  _InternalSessionIsolate({
    required _InternalSessionBootstrap bootstrap,
    required this.commandPort,
    required this.invocationPort,
  }) : _bootstrap = bootstrap,
       _realmContexts = RealmContextCache(statePort: bootstrap.statePort);

  final _InternalSessionBootstrap _bootstrap;
  final ReceivePort commandPort;
  final ReceivePort invocationPort;
  final RealmContextCache _realmContexts;
  final Map<int, _InternalInvocationContext> _pendingInvocations = {};

  Future<void> handleCommand(dynamic message) async {
    if (message is! Map) {
      return;
    }
    final decodedMessage = (_materializeTransferredValue(message) as Map)
        .cast<Object?, Object?>();
    final replyPort = decodedMessage['replyPort'] as SendPort?;
    final command = decodedMessage['command'] as String?;
    final requestId = decodedMessage['requestId'] as int?;
    final payload = (decodedMessage['payload'] as Map?)
        ?.cast<String, Object?>();
    if (replyPort == null ||
        command == null ||
        requestId == null ||
        payload == null) {
      return;
    }
    try {
      switch (command) {
        case _internalCmdRegister:
          final registrationId = await _register(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': registrationId,
          });
          break;
        case _internalCmdUnregister:
          await _unregister(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': null,
          });
          break;
        case _internalCmdSubscribe:
          final subscriptionId = await _subscribe(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': subscriptionId,
          });
          break;
        case _internalCmdUnsubscribe:
          await _unsubscribe(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': null,
          });
          break;
        case _internalCmdPublish:
          final publicationId = await _publish(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': publicationId,
          });
          break;
        case _internalCmdCall:
          await _call(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': null,
          });
          break;
        case _internalCmdCancel:
          await _cancel(payload);
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': null,
          });
          break;
        case _internalCmdClose:
          await _close();
          replyPort.send({
            'type': _internalMsgCommandResult,
            'requestId': requestId,
            'result': null,
          });
          break;
        default:
          replyPort.send({
            'type': _internalMsgCommandError,
            'requestId': requestId,
            'error': 'Unsupported command $command',
          });
      }
    } catch (error, stackTrace) {
      replyPort.send({
        'type': _internalMsgCommandError,
        'requestId': requestId,
        'error': '$error\n$stackTrace',
      });
    }
  }

  Future<void> _authorizeActionOrThrow({
    required AuthorizationAction action,
    required String uri,
    Map<String, Object?> options = const <String, Object?>{},
    PermissionMatchPolicy? targetMatchPolicy,
  }) async {
    final realmSettings = _bootstrap.realmSettings;
    if (realmSettings == null) {
      throw StateError('Session authorization context unavailable');
    }
    final decision = await _authorizeRealmAction(
      realmSettings: realmSettings,
      realmUri: _bootstrap.realmUri,
      action: action,
      uri: uri,
      sessionId: _bootstrap.sessionId,
      connectionId: null,
      authId: _bootstrap.authId,
      authRole: _bootstrap.authRole,
      authMethod: _bootstrap.authMethod,
      authProvider: _bootstrap.authProvider,
      protocol: null,
      isInternal: _bootstrap.authorizationIsInternal,
      options: options,
      targetMatchPolicy: targetMatchPolicy,
    );
    if (decision.allowed) {
      return;
    }
    throw StateError(
      decision.message ?? 'Not authorized to ${action.operationName} $uri',
    );
  }

  Future<int> _register(Map<String, Object?> payload) async {
    final procedure =
        payload['procedure'] as String? ??
        (throw ArgumentError('procedure is required'));
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    final details = Map<String, Object?>.from(
      (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final matchPolicy = _parseProcedureMatchPolicy(details['match'] as String?);
    _validateProcedureUri(procedure, matchPolicy);
    await _authorizeActionOrThrow(
      action: AuthorizationAction.register,
      uri: procedure,
      options: details,
      targetMatchPolicy: _permissionMatchPolicyFromProcedure(matchPolicy),
    );
    return context.registerProcedure(
      sessionId: _bootstrap.sessionId,
      procedure: procedure,
      details: details,
    );
  }

  Future<void> _unregister(Map<String, Object?> payload) async {
    final registrationId =
        payload['registrationId'] as int? ??
        (throw ArgumentError('registrationId is required'));
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    final snapshot = await context.ensureSnapshot(forceRefresh: true);
    RegistrationRecord? registrationRecord;
    for (final candidate in snapshot.registrations) {
      for (final callee in candidate.callees) {
        if (callee.registrationId == registrationId) {
          registrationRecord = callee;
          break;
        }
      }
      if (registrationRecord != null) {
        break;
      }
    }
    final ownsRegistration =
        registrationRecord?.sessionId == _bootstrap.sessionId;
    if (!ownsRegistration) {
      throw StateError(
        'Registration $registrationId not found for session '
        '${_bootstrap.sessionId}',
      );
    }
    await _authorizeActionOrThrow(
      action: AuthorizationAction.unregister,
      uri: registrationRecord!.procedure,
      targetMatchPolicy: _permissionMatchPolicyFromProcedure(
        registrationRecord.matchPolicy,
      ),
    );
    await context.unregisterProcedure(
      sessionId: _bootstrap.sessionId,
      registrationId: registrationId,
    );
  }

  Future<int> _subscribe(Map<String, Object?> payload) async {
    final topic =
        payload['topic'] as String? ??
        (throw ArgumentError('topic is required'));
    final details = Map<String, Object?>.from(
      (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final matchPolicy = _parseTopicMatchPolicy(
      details.remove('match') as String?,
    );
    _validateTopicUri(topic, matchPolicy);
    await _authorizeActionOrThrow(
      action: AuthorizationAction.subscribe,
      uri: topic,
      options: details,
      targetMatchPolicy: _permissionMatchPolicyFromTopic(matchPolicy),
    );
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    return context.addSubscription(
      sessionId: _bootstrap.sessionId,
      topic: topic,
      matchPolicy: matchPolicy,
      details: details,
    );
  }

  Future<void> _unsubscribe(Map<String, Object?> payload) async {
    final subscriptionId =
        payload['subscriptionId'] as int? ??
        (throw ArgumentError('subscriptionId is required'));
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    final snapshot = await context.ensureSnapshot(forceRefresh: true);
    SubscriptionSnapshot? subscription;
    for (final candidate in snapshot.subscriptions) {
      if (candidate.id == subscriptionId) {
        subscription = candidate;
        break;
      }
    }
    final ownsSubscription =
        subscription?.subscribers.any(
          (subscriber) => subscriber.sessionId == _bootstrap.sessionId,
        ) ??
        false;
    if (!ownsSubscription) {
      throw StateError(
        'Subscription $subscriptionId not found for session '
        '${_bootstrap.sessionId}',
      );
    }
    await _authorizeActionOrThrow(
      action: AuthorizationAction.unsubscribe,
      uri: subscription!.topic,
      targetMatchPolicy: _permissionMatchPolicyFromTopic(
        subscription.matchPolicy,
      ),
    );
    await context.removeSubscription(
      sessionId: _bootstrap.sessionId,
      subscriptionId: subscriptionId,
    );
  }

  Future<int> _publish(Map<String, Object?> payload) async {
    final topic =
        payload['topic'] as String? ??
        (throw ArgumentError('topic is required'));
    final options = Map<String, Object?>.from(
      (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final transferredPayload =
        payload[_internalMsgLazyPayload] ??
        _buildTransferredLazyPayload(
          arguments: (payload['arguments'] as List?)?.cast<dynamic>(),
          argumentsKeywords: (payload['argumentsKeywords'] as Map?)
              ?.cast<String, dynamic>(),
        );
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    await _authorizeActionOrThrow(
      action: AuthorizationAction.publish,
      uri: topic,
      options: options,
    );
    final eventPptScheme = options['ppt_scheme'] as String?;
    final eventPptSerializer = options['ppt_serializer'] as String?;
    final eventPptCipher = options['ppt_cipher'] as String?;
    final eventPptKeyId = options['ppt_keyid'] as String?;
    final customEventDetails = Map<String, Object?>.from(options)
      ..remove('acknowledge')
      ..remove('exclude_me')
      ..remove('disclose_me')
      ..remove('retain')
      ..remove('exclude')
      ..remove('exclude_authid')
      ..remove('exclude_authrole')
      ..remove('eligible')
      ..remove('eligible_authid')
      ..remove('eligible_authrole')
      ..remove('ppt_scheme')
      ..remove('ppt_serializer')
      ..remove('ppt_cipher')
      ..remove('ppt_keyid');
    final routing = await context.matchSubscriptions(
      publisherSessionId: _bootstrap.sessionId,
      topic: topic,
      options: options,
    );
    for (final match in routing.matches) {
      final eventDetails = Map<String, Object?>.from(match.details);
      if (customEventDetails.isNotEmpty) {
        eventDetails.addAll(customEventDetails);
      }
      if (eventPptScheme != null) {
        eventDetails['ppt_scheme'] = eventPptScheme;
      }
      if (eventPptSerializer != null) {
        eventDetails['ppt_serializer'] = eventPptSerializer;
      }
      if (eventPptCipher != null) {
        eventDetails['ppt_cipher'] = eventPptCipher;
      }
      if (eventPptKeyId != null) {
        eventDetails['ppt_keyid'] = eventPptKeyId;
      }
      if (match.internalSendPort != null) {
        match.internalSendPort!.send({
          'type': 'event',
          'subscriptionId': match.subscriptionId,
          'publicationId': routing.publicationId,
          'topic': payload['topic'],
          _internalMsgLazyPayload: transferredPayload,
          'arguments': payload['arguments'],
          'argumentsKeywords': payload['argumentsKeywords'],
          'publisherSessionId': _bootstrap.sessionId,
          'details': eventDetails,
        });
      } else {
        _bootstrap.controlPort.send({
          'type': _internalMsgForwardEvent,
          'connectionId': match.connectionId,
          'subscriptionId': match.subscriptionId,
          'publicationId': routing.publicationId,
          'topic': payload['topic'],
          _internalMsgLazyPayload: transferredPayload,
          'arguments': payload['arguments'],
          'argumentsKeywords': payload['argumentsKeywords'],
          'publisherSessionId': _bootstrap.sessionId,
          'details': eventDetails,
          'pptScheme': eventPptScheme,
          'pptSerializer': eventPptSerializer,
          'pptCipher': eventPptCipher,
          'pptKeyId': eventPptKeyId,
        });
      }
    }
    return routing.publicationId;
  }

  Future<void> _close() async {
    _bootstrap.controlPort.send({'type': _internalMsgSessionClosed});
  }

  Future<void> _call(Map<String, Object?> payload) async {
    final requestId =
        payload['requestId'] as int? ??
        (throw ArgumentError('requestId is required'));
    final procedure =
        payload['procedure'] as String? ??
        (throw ArgumentError('procedure is required'));
    final transferredPayload =
        payload[_internalMsgLazyPayload] ??
        _buildTransferredLazyPayload(
          arguments: (payload['arguments'] as List?)?.cast<dynamic>(),
          argumentsKeywords: (payload['argumentsKeywords'] as Map?)
              ?.cast<String, dynamic>(),
        );
    final arguments = (payload['arguments'] as List<dynamic>?)?.toList(
      growable: false,
    );
    final argumentsKeywords = (payload['argumentsKeywords'] as Map?)
        ?.cast<String, dynamic>();
    final options = Map<String, Object?>.from(
      (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    await _authorizeActionOrThrow(
      action: AuthorizationAction.call,
      uri: procedure,
      options: options,
    );
    final dispatch = await context.dispatchInvocation(
      callerSessionId: _bootstrap.sessionId,
      requestId: requestId,
      procedure: procedure,
      options: options,
    );

    if (dispatch.calleeInternalSendPort != null) {
      final replyPort = ReceivePort();
      dispatch.calleeInternalSendPort!.send({
        'type': 'invocation',
        'invocationId': dispatch.invocationId,
        'registrationId': dispatch.registrationId,
        'procedure': procedure,
        _internalMsgLazyPayload: transferredPayload,
        'arguments': arguments,
        'argumentsKeywords': argumentsKeywords,
        'options': options,
        'realmUri': _bootstrap.realmUri,
        'callerSessionId': dispatch.disclosedCallerSessionId,
        'callerAuthId': dispatch.disclosedCallerAuthId,
        'callerAuthRole': dispatch.disclosedCallerAuthRole,
        'callerRequestId': requestId,
        'replyPort': replyPort.sendPort,
      });
      try {
        await for (final response in replyPort) {
          if (response is! Map<String, Object?>) {
            await context.completeInvocation(dispatch.invocationId);
            _bootstrap.controlPort.send({
              'type': _internalMsgCallError,
              'requestId': requestId,
              'error': wamp_core.Error.runtimeError,
              _internalMsgLazyPayload: _buildTransferredLazyPayload(
                arguments: const ['Invalid response from callee'],
              ),
              'arguments': const ['Invalid response from callee'],
            });
            break;
          }
          final type = response['type'];
          if (type == 'result') {
            final progress = response['progress'] as bool? ?? false;
            if (!progress) {
              await context.completeInvocation(dispatch.invocationId);
            }
            _bootstrap.controlPort.send({
              'type': _internalMsgCallResult,
              'requestId': requestId,
              _internalMsgLazyPayload: response[_internalMsgLazyPayload],
              'arguments': response['arguments'],
              'argumentsKeywords': response['argumentsKeywords'],
              'progress': progress,
              'pptScheme': response['pptScheme'],
              'pptSerializer': response['pptSerializer'],
              'pptCipher': response['pptCipher'],
              'pptKeyId': response['pptKeyId'],
              'details': response['details'],
            });
            if (!progress) {
              break;
            }
          } else if (type == _internalMsgCallError) {
            _bootstrap.controlPort.send({
              'type': _internalMsgCallError,
              'requestId': requestId,
              'error': response['error'],
              _internalMsgLazyPayload: response[_internalMsgLazyPayload],
              'arguments': response['arguments'],
              'argumentsKeywords': response['argumentsKeywords'],
              'details': response['details'],
            });
            break;
          } else if (type == 'error') {
            await context.completeInvocation(dispatch.invocationId);
            _bootstrap.controlPort.send({
              'type': _internalMsgCallError,
              'requestId': requestId,
              'error': response['error'],
              _internalMsgLazyPayload: response[_internalMsgLazyPayload],
              'arguments': response['arguments'],
              'argumentsKeywords': response['argumentsKeywords'],
              'details': response['details'],
            });
            break;
          } else {
            await context.completeInvocation(dispatch.invocationId);
            _bootstrap.controlPort.send({
              'type': _internalMsgCallError,
              'requestId': requestId,
              'error': wamp_core.Error.runtimeError,
              _internalMsgLazyPayload: _buildTransferredLazyPayload(
                arguments: const ['Invalid response from callee'],
              ),
              'arguments': const ['Invalid response from callee'],
            });
            break;
          }
        }
      } finally {
        replyPort.close();
      }
      return;
    }

    final invocationDetails = _invocationDetailsForInternalCall(
      dispatch: dispatch,
      procedure: procedure,
      options: options,
    );
    final invocation = invocation_msg.Invocation(
      dispatch.invocationId,
      dispatch.registrationId,
      invocationDetails,
    );
    _applyTransferredLazyPayload(
      invocation,
      transferredPayload,
      fallbackArguments: arguments,
      fallbackArgumentsKeywords: argumentsKeywords,
      pptScheme: invocationDetails.pptScheme,
      pptSerializer: invocationDetails.pptSerializer,
      pptCipher: invocationDetails.pptCipher,
      pptKeyId: invocationDetails.pptKeyId,
    );
    _bootstrap.controlPort.send({
      'type': _internalMsgForwardInvocation,
      'connectionId': dispatch.calleeConnectionId,
      'message': invocation,
    });
  }

  Future<void> _cancel(Map<String, Object?> payload) async {
    final requestId =
        payload['requestId'] as int? ??
        (throw ArgumentError('requestId is required'));
    final mode = payload['mode'] as String?;
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    final invocation = await context.findInvocationByCaller(
      callerSessionId: _bootstrap.sessionId,
      requestId: requestId,
    );
    if (invocation == null) {
      _bootstrap.controlPort.send({
        'type': _internalMsgCallError,
        'requestId': requestId,
        'error': wamp_core.Error.noSuchInvocation,
        'arguments': const ['Invocation not found'],
      });
      return;
    }
    await _authorizeActionOrThrow(
      action: AuthorizationAction.cancel,
      uri: invocation.procedure,
    );
    final cancelMode = mode ?? cancel_msg.CancelOptions.modeSkip;
    final waitForAck = cancelMode == cancel_msg.CancelOptions.modeKill;
    final shouldInterrupt =
        cancelMode == cancel_msg.CancelOptions.modeKill ||
        cancelMode == cancel_msg.CancelOptions.modeKillNoWait;

    if (cancelMode == cancel_msg.CancelOptions.modeSkip) {
      await context.completeInvocation(invocation.invocationId);
      _bootstrap.controlPort.send({
        'type': _internalMsgCallError,
        'requestId': requestId,
        'error': error_msg.Error.errorInvocationCanceled,
        'arguments': const ['Invocation cancelled'],
        'details': {'mode': cancelMode},
      });
      return;
    }

    final cancelled = await context.cancelInvocation(
      invocationId: invocation.invocationId,
      mode: cancelMode,
      waitForAck: waitForAck,
    );
    if (!cancelled) {
      _bootstrap.controlPort.send({
        'type': _internalMsgCallError,
        'requestId': requestId,
        'error': wamp_core.Error.noSuchInvocation,
        'arguments': const ['Invocation not found'],
      });
      return;
    }

    if (shouldInterrupt) {
      final calleePort = invocation.calleeInternalSendPort;
      if (calleePort != null) {
        calleePort.send({
          'type': 'interrupt',
          'invocationId': invocation.invocationId,
          'mode': cancelMode,
        });
      } else if (invocation.calleeConnectionId != null) {
        _bootstrap.controlPort.send({
          'type': _internalMsgForwardInterrupt,
          'connectionId': invocation.calleeConnectionId,
          'invocationId': invocation.invocationId,
          'mode': cancelMode,
        });
      }
    }

    if (!waitForAck) {
      _bootstrap.controlPort.send({
        'type': _internalMsgCallError,
        'requestId': requestId,
        'error': error_msg.Error.errorInvocationCanceled,
        'arguments': const ['Invocation cancelled'],
        'details': {'mode': cancelMode},
      });
    }
  }

  Future<void> handleInvocationMessage(dynamic message) async {
    if (message is! Map) {
      return;
    }
    final decodedMessage = (_materializeTransferredValue(message) as Map)
        .cast<Object?, Object?>();
    final type = decodedMessage['type'];
    switch (type) {
      case 'event':
        _bootstrap.controlPort.send({
          'type': _internalMsgSubscriptionEvent,
          'subscriptionId': decodedMessage['subscriptionId'],
          'publicationId': decodedMessage['publicationId'],
          'topic': decodedMessage['topic'],
          _internalMsgLazyPayload: decodedMessage[_internalMsgLazyPayload],
          'arguments': decodedMessage['arguments'],
          'argumentsKeywords': decodedMessage['argumentsKeywords'],
          'publisherSessionId': decodedMessage['publisherSessionId'],
          'pptScheme': (decodedMessage['details'] as Map?)?['ppt_scheme'],
          'pptSerializer':
              (decodedMessage['details'] as Map?)?['ppt_serializer'],
          'pptCipher': (decodedMessage['details'] as Map?)?['ppt_cipher'],
          'pptKeyId': (decodedMessage['details'] as Map?)?['ppt_keyid'],
        });
        break;
      case 'invocation':
        final replyPort = decodedMessage['replyPort'] as SendPort?;
        if (replyPort == null) {
          return;
        }
        final invocationId = decodedMessage['invocationId'] as int?;
        if (invocationId == null) {
          return;
        }
        final callerRequestId = decodedMessage['callerRequestId'] as int?;
        if (callerRequestId == null) {
          return;
        }
        final responsePort = ReceivePort();
        final realmUri =
            (decodedMessage['realmUri'] as String?) ?? _bootstrap.realmUri;
        _pendingInvocations[invocationId] = _InternalInvocationContext(
          replyPort: replyPort,
          realmUri: realmUri,
          responsePort: responsePort,
          callerRequestId: callerRequestId,
        );
        _bootstrap.controlPort.send({
          'type': _internalMsgInvocationRequest,
          'invocationId': invocationId,
          'registrationId': decodedMessage['registrationId'],
          'procedure': decodedMessage['procedure'],
          _internalMsgLazyPayload: decodedMessage[_internalMsgLazyPayload],
          'arguments': decodedMessage['arguments'],
          'argumentsKeywords': decodedMessage['argumentsKeywords'],
          'options': decodedMessage['options'],
          'pptScheme': (decodedMessage['options'] as Map?)?['ppt_scheme'],
          'pptSerializer':
              (decodedMessage['options'] as Map?)?['ppt_serializer'],
          'pptCipher': (decodedMessage['options'] as Map?)?['ppt_cipher'],
          'pptKeyId': (decodedMessage['options'] as Map?)?['ppt_keyid'],
          'callerSessionId': decodedMessage['callerSessionId'],
          'callerAuthId': decodedMessage['callerAuthId'],
          'callerAuthRole': decodedMessage['callerAuthRole'],
          'callerRequestId': decodedMessage['callerRequestId'],
          'replyPort': responsePort.sendPort,
        });
        try {
          await for (final response in responsePort) {
            if (response is! Map) {
              replyPort.send({
                'type': 'error',
                'error': wamp_core.Error.unknown,
                _internalMsgLazyPayload: _buildTransferredLazyPayload(
                  arguments: const ['Invalid response from internal session'],
                ),
                'arguments': ['Invalid response from internal session'],
              });
              break;
            }
            replyPort.send(response);
            final type = response['type'];
            if (type == 'error') {
              break;
            }
            if (type == 'result') {
              final progress = response['progress'] as bool? ?? false;
              if (!progress) {
                break;
              }
            }
          }
        } finally {
          _pendingInvocations.remove(invocationId);
          responsePort.close();
        }
        break;
      case 'interrupt':
        final invocationId = decodedMessage['invocationId'] as int?;
        if (invocationId == null) {
          return;
        }
        final context = _pendingInvocations.remove(invocationId);
        if (context == null) {
          return;
        }
        context.responsePort.close();
        final details = <String, Object?>{};
        final mode = message['mode'] as String?;
        if (mode != null) {
          details['mode'] = mode;
        }
        try {
          final realmContext = _realmContexts.contextFor(context.realmUri);
          await realmContext.completeInvocation(invocationId);
        } catch (_) {
          // Ignore completion errors; scoped error reporting handled elsewhere.
        }
        context.replyPort.send({
          'type': _internalMsgCallError,
          'requestId': context.callerRequestId,
          'error': error_msg.Error.errorInvocationCanceled,
          _internalMsgLazyPayload: _buildTransferredLazyPayload(
            arguments: const ['Invocation cancelled'],
          ),
          'arguments': const ['Invocation cancelled'],
          if (details.isNotEmpty) 'details': details,
        });
        break;
      case _internalMsgCallResult:
      case _internalMsgCallError:
      case _internalMsgCallProgress:
        _bootstrap.controlPort.send(message);
        break;
    }
  }

  TopicMatchPolicy _parseTopicMatchPolicy(String? raw) {
    return switch (raw) {
      'prefix' => TopicMatchPolicy.prefix,
      'wildcard' => TopicMatchPolicy.wildcard,
      _ => TopicMatchPolicy.exact,
    };
  }

  ProcedureMatchPolicy _parseProcedureMatchPolicy(String? raw) {
    if (raw == register_msg.RegisterOptions.matchPrefix) {
      return ProcedureMatchPolicy.prefix;
    }
    if (raw == register_msg.RegisterOptions.matchWildcard) {
      return ProcedureMatchPolicy.wildcard;
    }
    return ProcedureMatchPolicy.exact;
  }
}

class _InternalInvocationContext {
  _InternalInvocationContext({
    required this.replyPort,
    required this.realmUri,
    required this.responsePort,
    required this.callerRequestId,
  });

  final SendPort replyPort;
  final String realmUri;
  final ReceivePort responsePort;
  final int callerRequestId;
}

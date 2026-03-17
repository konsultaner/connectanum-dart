part of '../router_instance.dart';

class RouterSession {
  RouterSession._({
    required this.binding,
    required this.sessionId,
    required this.realmUri,
    required this.authId,
    required this.authRole,
    required Map<String, Object?> roles,
    required SendPort commandPort,
    required ReceivePort controlPort,
    required StreamSubscription<dynamic>? controlSubscription,
    required ReceivePort responsePort,
    required Isolate isolate,
  }) : roles = Map.unmodifiable(roles),
       _commandPort = commandPort,
       _controlPort = controlPort,
       _controlSubscription = controlSubscription,
       _responsePort = responsePort,
       _isolate = isolate {
    _responsePort.listen(_handleResponseMessage);
  }

  final RouterBinding binding;
  final int sessionId;
  final String realmUri;
  final String? authId;
  final String? authRole;
  final Map<String, Object?> roles;

  final SendPort _commandPort;
  final ReceivePort _controlPort;
  StreamSubscription<dynamic>? _controlSubscription;
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
  final Map<int, StreamController<invocation_msg.Invocation>>
  _invocationControllers = {};
  final Map<int, subscribed_msg.Subscribed> _subscriptions = {};
  final Map<int, StreamController<event_msg.Event>> _eventControllers = {};
  final Map<int, StreamController<result_msg.Result>> _callControllers = {};

  Future<void> close() async {
    if (_closed) {
      return;
    }
    final closeFuture = _sendCommand(_internalCmdClose, const {});
    _closed = true;
    await closeFuture;
    await _controlSubscription?.cancel();
    _controlPort.close();
    _responsePort.close();
    _pendingCommands.clear();
    for (final controller in _invocationControllers.values.toList()) {
      await controller.close();
    }
    _invocationControllers.clear();
    for (final controller in _eventControllers.values.toList()) {
      await controller.close();
    }
    _eventControllers.clear();
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
      final details = event_msg.EventDetails(
        publisher: message['publisherSessionId'] as int?,
        topic: message['topic'] as String?,
      );
      final event = event_msg.Event(
        subscriptionId,
        publicationId,
        details,
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, Object?>(),
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
      final controller = _eventControllers[subscriptionId];
      if (controller == null || controller.isClosed) {
        return;
      }
      final details = event_msg.EventDetails(
        publisher: message['publisherSessionId'] as int?,
        topic: message['topic'] as String?,
      );
      final event = event_msg.Event(
        subscriptionId,
        publicationId,
        details,
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, Object?>(),
      );
      controller.add(event);
    } else if (type == _internalMsgInvocationRequest) {
      final registrationId = message['registrationId'] as int?;
      final invocationId = message['invocationId'] as int?;
      final replyPort = message['replyPort'] as SendPort?;
      if (registrationId == null || invocationId == null || replyPort == null) {
        return;
      }
      final controller = _invocationControllers[registrationId];
      if (controller == null || controller.isClosed) {
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
      );
      if (options.isNotEmpty) {
        // Remove fields already consumed to avoid duplication.
        final custom = Map<String, dynamic>.from(options)
          ..remove('receive_progress');
        if (custom.isNotEmpty) {
          details.custom.addAll(custom);
        }
      }
      final invocation = invocation_msg.Invocation(
        invocationId,
        registrationId,
        details,
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
      );
      invocation.onResponse((response) {
        if (response is yield_msg.Yield) {
          replyPort.send({
            'type': 'result',
            'arguments': _transferIsolateValue(response.arguments),
            'argumentsKeywords': _transferIsolateValue(
              response.argumentsKeywords,
            ),
            'progress': response.options?.progress ?? false,
          });
        } else if (response is error_msg.Error) {
          replyPort.send({
            'type': 'error',
            'error': response.error,
            'arguments': _transferIsolateValue(response.arguments),
            'argumentsKeywords': _transferIsolateValue(
              response.argumentsKeywords,
            ),
            'details': _transferIsolateValue(response.details),
          });
        }
      });
      controller.add(invocation);
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
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        progress: message['progress'] == true,
      );
    } else if (type == _internalMsgCallError) {
      final requestId = message['requestId'] as int?;
      if (requestId == null) {
        return;
      }
      _emitCallError(
        requestId,
        errorUri: message['error'] as String? ?? wamp_core.Error.unknown,
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
        arguments: (_materializeTransferredValue(message['arguments']) as List?)
            ?.cast<dynamic>()
            .toList(growable: false),
        argumentsKeywords:
            (_materializeTransferredValue(message['argumentsKeywords']) as Map?)
                ?.cast<String, dynamic>(),
        progress: true,
      );
    } else if (type == HttpInvocationControlMessages.openResponseStream) {
      final requestId = message['requestId'] as int?;
      final status = message['status'] as int?;
      final headers = (message['headers'] as Map?)?.cast<String, String>();
      final replyPort = message['replyPort'] as SendPort?;
      if (requestId == null ||
          status == null ||
          headers == null ||
          replyPort == null) {
        return;
      }
      final pending = binding._pendingHttpCalls[requestId];
      if (pending == null) {
        replyPort.send(const {'error': 'pending_http_request_not_found'});
        return;
      }
      final descriptor = binding._openDirectResponseStream(
        pending,
        status: status,
        headers: headers,
      );
      if (descriptor == null) {
        replyPort.send(const {'error': 'unsupported'});
        return;
      }
      replyPort.send({
        'handle': descriptor.handle,
        if (descriptor.libraryPath != null)
          'libraryPath': descriptor.libraryPath,
      });
    }
  }

  void _attachControlListener() {
    _controlSubscription?.cancel();
    _controlSubscription = _controlPort.listen(_handleControlMessage);
  }

  void _emitCallResult(
    int requestId, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    bool progress = false,
  }) {
    final controller = _callControllers[requestId];
    if (controller == null || controller.isClosed) {
      return;
    }
    final result = result_msg.Result(
      requestId,
      result_msg.ResultDetails(progress: progress),
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
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
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
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
    final controller = StreamController<invocation_msg.Invocation>.broadcast();
    _registrations[registrationId] = registered;
    _invocationControllers[registrationId] = controller;
    registered.invocationStream = controller.stream;
    return registered;
  }

  Future<void> unregister(int registrationId) async {
    await _sendCommand(_internalCmdUnregister, <String, Object?>{
      'registrationId': registrationId,
    });
    _registrations.remove(registrationId);
    await _invocationControllers.remove(registrationId)?.close();
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
    final controller = StreamController<event_msg.Event>.broadcast();
    subscribed.eventStream = controller.stream;
    _subscriptions[subscriptionId] = subscribed;
    _eventControllers[subscriptionId] = controller;
    return subscribed;
  }

  Future<void> unsubscribe(int subscriptionId) async {
    await _sendCommand(_internalCmdUnsubscribe, <String, Object?>{
      'subscriptionId': subscriptionId,
    });
    _subscriptions.remove(subscriptionId);
    await _eventControllers.remove(subscriptionId)?.close();
  }

  Future<published_msg.Published?> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    publish_msg.PublishOptions? options,
  }) async {
    final requestId = _nextPublishRequestId++;
    final payload = <String, Object?>{
      'topic': topic,
      'arguments': arguments,
      'argumentsKeywords': argumentsKeywords,
      'options': _publishOptionsToMap(options),
    };
    final publicationId =
        await _sendCommand(_internalCmdPublish, payload) as int;
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
    final requestId = _nextCallRequestId++;
    final controller = StreamController<result_msg.Result>(
      onCancel: () {
        _callControllers.remove(requestId);
      },
    );
    _callControllers[requestId] = controller;
    final payload = <String, Object?>{
      'requestId': requestId,
      'procedure': procedure,
      'arguments': arguments,
      'argumentsKeywords': argumentsKeywords,
      'options': _callOptionsToMap(options),
    };
    _sendCommand(_internalCmdCall, payload).catchError((error, stack) {
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
    required this.roles,
    required this.statePort,
    required this.controlPort,
    required this.handshakePort,
  });

  final int sessionId;
  final String realmUri;
  final String? authId;
  final String? authRole;
  final Map<String, Object?> roles;
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

  Future<int> _register(Map<String, Object?> payload) async {
    final procedure =
        payload['procedure'] as String? ??
        (throw ArgumentError('procedure is required'));
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    final details = Map<String, Object?>.from(
      (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
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
    await context.removeSubscription(
      sessionId: _bootstrap.sessionId,
      subscriptionId: subscriptionId,
    );
  }

  Future<int> _publish(Map<String, Object?> payload) async {
    final topic =
        payload['topic'] as String? ??
        (throw ArgumentError('topic is required'));
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
    final routing = await context.matchSubscriptions(
      publisherSessionId: _bootstrap.sessionId,
      topic: topic,
      options: Map<String, Object?>.from(
        (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
    );
    for (final match in routing.matches) {
      if (match.internalSendPort != null) {
        match.internalSendPort!.send({
          'type': 'event',
          'subscriptionId': match.subscriptionId,
          'publicationId': routing.publicationId,
          'topic': payload['topic'],
          'arguments': payload['arguments'],
          'argumentsKeywords': payload['argumentsKeywords'],
          'publisherSessionId': _bootstrap.sessionId,
          'details': match.details,
        });
      } else {
        _bootstrap.controlPort.send({
          'type': _internalMsgForwardEvent,
          'connectionId': match.connectionId,
          'subscriptionId': match.subscriptionId,
          'publicationId': routing.publicationId,
          'topic': payload['topic'],
          'arguments': payload['arguments'],
          'argumentsKeywords': payload['argumentsKeywords'],
          'publisherSessionId': _bootstrap.sessionId,
          'details': match.details,
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
    final arguments = (payload['arguments'] as List<dynamic>?)?.toList(
      growable: false,
    );
    final argumentsKeywords = (payload['argumentsKeywords'] as Map?)
        ?.cast<String, dynamic>();
    final options = Map<String, Object?>.from(
      (payload['options'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final context = _realmContexts.contextFor(_bootstrap.realmUri);
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
        'arguments': arguments,
        'argumentsKeywords': argumentsKeywords,
        'options': options,
        'realmUri': _bootstrap.realmUri,
        'callerSessionId': _bootstrap.sessionId,
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
              'arguments': response['arguments'],
              'argumentsKeywords': response['argumentsKeywords'],
              'progress': progress,
            });
            if (!progress) {
              break;
            }
          } else if (type == _internalMsgCallError) {
            _bootstrap.controlPort.send({
              'type': _internalMsgCallError,
              'requestId': requestId,
              'error': response['error'],
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

    final discloseCaller = options['disclose_me'] == true;
    final receiveProgress = options['receive_progress'] == true;
    final invocationDetails = invocation_msg.InvocationDetails(
      discloseCaller ? _bootstrap.sessionId : null,
      procedure,
      receiveProgress,
    );
    final invocation = invocation_msg.Invocation(
      dispatch.invocationId,
      dispatch.registrationId,
      invocationDetails,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
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
          'arguments': decodedMessage['arguments'],
          'argumentsKeywords': decodedMessage['argumentsKeywords'],
          'publisherSessionId': decodedMessage['publisherSessionId'],
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
          'arguments': decodedMessage['arguments'],
          'argumentsKeywords': decodedMessage['argumentsKeywords'],
          'options': decodedMessage['options'],
          'callerSessionId': decodedMessage['callerSessionId'],
          'callerRequestId': decodedMessage['callerRequestId'],
          'replyPort': responsePort.sendPort,
        });
        try {
          await for (final response in responsePort) {
            if (response is! Map) {
              replyPort.send({
                'type': 'error',
                'error': wamp_core.Error.unknown,
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

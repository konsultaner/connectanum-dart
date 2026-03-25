import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';

import '../transport/abstract_transport.dart';

class Session {
  static final Logger _logger = Logger('Connectanum.Session');

  /// The sessions [id]
  int? id;

  /// The sessions [realm]
  String? realm;

  /// The [authId] that has been authenticated with
  String? authId;

  /// The [authRole] given by the server
  String? authRole;

  /// The [authMethod] used to authenticate the session
  String? authMethod;

  /// the [authProvider] used to authenticate the session
  String? authProvider;

  /// the [authExtra] returned by the server
  Map<String, dynamic>? authExtra;

  final AbstractTransport _transport;

  /// the next id used to generate request id for a call
  int nextCallId = 1;

  /// the next id used to generate request id for a publish event
  int nextPublishId = 1;

  /// the next id used to generate request id for a subscription
  int nextSubscribeId = 1;

  /// the next id used to generate request id for an unsubscribe event
  int nextUnsubscribeId = 1;

  /// the next id used to generate request id for a registration
  int nextRegisterId = 1;

  /// the next id used to generate request id for an unregister even
  int nextUnregisterId = 1;

  /// A map that stores all the active registrations
  final Map<int, Registered> registrations = {};

  /// A map that stores all the active subscriptions
  final Map<int, Subscribed> subscriptions = {};

  late StreamSubscription<AbstractMessage?> _transportStreamSubscription;
  final Map<int, _PendingCall> _pendingCalls = {};
  final Map<int, Completer<Published>> _pendingPublishes = {};
  final Map<int, Completer<Subscribed>> _pendingSubscribes = {};
  final Map<int, _PendingUnsubscribe> _pendingUnsubscribes = {};
  final Map<int, _PendingRegister> _pendingRegisters = {};
  final Map<int, _PendingUnregister> _pendingUnregisters = {};
  bool _incomingClosed = false;

  Session(this.realm, this._transport)
    : assert(realm == null || UriPattern.match(realm), _transport.isOpen);

  /// Starting the session will also start the authentication process.
  static Future<Session> start(
    String? realm,
    AbstractTransport transport, {
    String? authId,
    String? authRole,
    Map<String, dynamic>? authExtra,
    List<AbstractAuthentication>? authMethods,
    Duration? reconnect,
  }) async {
    final session = Session(realm, transport);

    final hello = Hello(realm, Details.forHello());
    if (authId != null) {
      hello.details.authid = authId;
    }
    if (authRole != null) {
      hello.details.authrole = authRole;
    }
    if (authExtra != null) {
      hello.details.authextra = authExtra;
    }

    if (authMethods != null && authMethods.isNotEmpty) {
      await authMethods[0].hello(realm, hello.details);
      hello.details.authmethods = authMethods
          .map<String>((authMethod) => authMethod.getName())
          .toList();
    }

    final welcomeCompleter = Completer<Session>();
    session._transportStreamSubscription = transport.receive()!.listen(
      (message) {
        if (message is Challenge) {
          final foundAuthMethod = authMethods
              ?.where(
                (authenticationMethod) =>
                    authenticationMethod.getName() == message.authMethod,
              )
              .first;
          if (foundAuthMethod != null) {
            try {
              foundAuthMethod
                  .challenge(message.extra)
                  .then(
                    (authenticate) => session.authenticate(authenticate),
                    onError: (error) {
                      if (!welcomeCompleter.isCompleted) {
                        welcomeCompleter.completeError(
                          Abort(
                            Error.authorizationFailed,
                            message: error.toString(),
                          ),
                        );
                      }
                      session._transport.send(
                        Abort(
                          Error.authorizationFailed,
                          message: error.toString(),
                        ),
                      );
                      session._transport.close();
                    },
                  );
            } catch (exception) {
              try {
                transport.close();
              } catch (_) {
                /* transport may already be closed */
              }
              welcomeCompleter.completeError(
                Abort(Error.authorizationFailed, message: exception.toString()),
              );
            }
            return;
          }
          final goodbye = Goodbye(
            GoodbyeMessage('Authmethod $foundAuthMethod not supported'),
            Goodbye.reasonGoodbyeAndOut,
          );
          session._transport.send(goodbye);
          welcomeCompleter.completeError(goodbye);
          return;
        }

        if (message is Welcome) {
          session.id = message.sessionId;
          if ((session.realm ?? message.details.realm) == null) {
            welcomeCompleter.completeError(
              Abort(
                Error.authorizationFailed,
                message:
                    'No realm specified! Neither by the client nor by the router',
              ),
            );
            return;
          }
          if (message.details.realm == null) {
            if (_logger.level <= Level.INFO) {
              _logger.info('Warning! No realm returned by the router');
            }
          } else {
            session.realm = message.details.realm;
          }
          session.authId = message.details.authid;
          session.authRole = message.details.authrole;
          session.authMethod = message.details.authmethod;
          session.authProvider = message.details.authprovider;
          session.authExtra = message.details.authextra;
          session._transportStreamSubscription.onData(
            session._handleTransportMessage,
          );
          session._transportStreamSubscription.onDone(() {
            unawaited(session._handleTransportClosed());
          });
          welcomeCompleter.complete(session);
          return;
        }

        if (message is Abort) {
          try {
            transport.close();
          } catch (_) {
            /* transport may already be closed */
          }
          welcomeCompleter.completeError(message);
          return;
        }

        if (message is Goodbye) {
          try {
            transport.close();
          } catch (_) {
            /* transport may already be closed */
          }
        }
      },
      cancelOnError: true,
      onError: (error, stackTrace) {
        _logger.warning(error);
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.completeError(error, stackTrace);
        }
        unawaited(session._handleTransportClosed(error, stackTrace));
        transport.close(error: error);
      },
      onDone: () {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.completeError(
            StateError('Transport closed before session welcome'),
          );
        }
        unawaited(session._handleTransportClosed());
        transport.close();
      },
    );
    if (!transport.isReady) {
      await transport.onReady;
    }
    transport.send(hello);
    return welcomeCompleter.future;
  }

  Future<dynamic> get onDisconnect => _transport.onDisconnect!.future;
  Future<dynamic> get onConnectionLost => _transport.onConnectionLost!.future;

  /// If there is a transport object that is opened and the incoming stream has not
  /// been closed, this will return true.
  bool isConnected() {
    return _transport.isReady && !_incomingClosed;
  }

  /// This sends the [authenticate] message to the transport outgoing stream.
  void authenticate(Authenticate authenticate) {
    _transport.send(authenticate);
  }

  /// This calls a [procedure] with the given [arguments] and/or [argumentsKeywords]
  /// with the given [options]. The WAMP router will either respond with one or
  /// more results or the caller may cancel the call by calling [cancelCompleter.complete()].
  Stream<Result> call(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    final call = _buildCall(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      options: options,
    );
    final controller = StreamController<Result>(
      sync: true,
      onCancel: () async {
        final pending = _pendingCalls.remove(call.requestId);
        if (pending != null) {
          await pending.close();
        }
      },
    );
    _pendingCalls[call.requestId] = _PendingCallStream(controller);
    _transport.send(call);
    _attachCallCancellation(call.requestId, cancelCompleter);
    return controller.stream;
  }

  /// This calls a [procedure] and waits for the final non-progressive [Result].
  /// Progressive interim results are ignored; use [call] when the caller needs the stream.
  Future<Result> callSingle(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    final call = _buildCall(
      procedure,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      options: options,
    );
    final completer = Completer<Result>();
    _pendingCalls[call.requestId] = _PendingCallFuture(completer);
    _transport.send(call);
    _attachCallCancellation(call.requestId, cancelCompleter);
    return completer.future;
  }

  /// This subscribes the session to a [topic]. The subscriber may pass [options]
  /// while subscribing. The resulting events are passed to the [Subscribed.eventStream].
  /// The subscriber should therefore subscribe to that stream to receive the events.
  Future<Subscribed> subscribe(String topic, {SubscribeOptions? options}) {
    final subscribe = Subscribe(nextSubscribeId++, topic, options: options);
    final completer = Completer<Subscribed>();
    _pendingSubscribes[subscribe.requestId] = completer;
    _transport.send(subscribe);
    return completer.future;
  }

  /// This subscribes the session to a [topic] and routes events directly to
  /// [onEvent] without requiring the caller to touch [Subscribed.eventStream].
  Future<Subscribed> subscribeHandler(
    String topic,
    void Function(Event event) onEvent, {
    SubscribeOptions? options,
  }) async {
    final subscribed = await subscribe(topic, options: options);
    subscribed.onEvent(onEvent);
    return subscribed;
  }

  /// This unsubscribes the session from a subscription. Use the [Subscribed.subscriptionId]
  /// to unsubscribe.
  Future<void> unsubscribe(int subscriptionId) {
    final unsubscribe = Unsubscribe(nextUnsubscribeId++, subscriptionId);
    final completer = Completer<void>();
    _pendingUnsubscribes[unsubscribe.requestId] = _PendingUnsubscribe(
      subscriptionId: subscriptionId,
      completer: completer,
    );
    _transport.send(unsubscribe);
    return completer.future;
  }

  /// This publishes an event to a [topic] with the given [arguments] and [argumentsKeywords].
  Future<Published?> publish(
    String topic, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PublishOptions? options,
  }) {
    var pubArguments = arguments;
    var pubArgumentsKeywords = argumentsKeywords;

    if (options?.pptScheme == 'wamp') {
      pubArguments = E2EEPayload.packE2EEPayload(
        arguments,
        argumentsKeywords,
        options!,
      );
      pubArgumentsKeywords = null;
    } else if (options?.pptScheme != null) {
      pubArguments = PPTPayload.packPPTPayload(
        arguments,
        argumentsKeywords,
        options!,
      );
      pubArgumentsKeywords = null;
    }

    final publish = Publish(
      nextPublishId++,
      topic,
      arguments: pubArguments,
      argumentsKeywords: pubArgumentsKeywords,
      options: options,
    );
    if (options?.acknowledge != true) {
      _transport.send(publish);
      return Future<Published?>.value(null);
    }
    final completer = Completer<Published>();
    _pendingPublishes[publish.requestId] = completer;
    _transport.send(publish);
    return completer.future;
  }

  /// This registers a [procedure] with the given [options] that may be called
  /// by other sessions.
  Future<Registered> register(String procedure, {RegisterOptions? options}) {
    final register = Register(nextRegisterId++, procedure, options: options);
    final completer = Completer<Registered>();
    _pendingRegisters[register.requestId] = _PendingRegister(
      procedure: procedure,
      completer: completer,
    );
    _transport.send(register);
    return completer.future;
  }

  /// This registers a [procedure] and routes invocations directly to [onInvoke]
  /// without requiring the caller to touch [Registered.invocationStream].
  Future<Registered> registerHandler(
    String procedure,
    FutureOr<void> Function(Invocation invocation) onInvoke, {
    RegisterOptions? options,
  }) async {
    final registered = await register(procedure, options: options);
    registered.onInvoke(onInvoke);
    return registered;
  }

  /// This unregisters a procedure by its [registrationId]. Use the [Registered.registrationId]
  /// to unregister.
  Future<void> unregister(int registrationId) {
    final unregister = Unregister(nextUnregisterId++, registrationId);
    final completer = Completer<void>();
    _pendingUnregisters[unregister.requestId] = _PendingUnregister(
      registrationId: registrationId,
      completer: completer,
    );
    _transport.send(unregister);
    return completer.future;
  }

  /// Sends a goodbye message and closes the transport after a given [timeout].
  /// If no timeout is set, the client waits for the server to close the transport forever.
  Future<void> close({String message = 'Regular closing', Duration? timeout}) {
    final goodbye = Goodbye(
      GoodbyeMessage(message),
      Goodbye.reasonGoodbyeAndOut,
    );
    _transport.send(goodbye);
    if (timeout != null) {
      return Future.delayed(timeout, () => _transport.close());
    }
    return Future<void>.value();
  }

  void _handleTransportMessage(AbstractMessage? message) {
    if (message == null) {
      return;
    }
    if (message is Result) {
      _handleResult(message);
      return;
    }
    if (message is Published) {
      _pendingPublishes.remove(message.publishRequestId)?.complete(message);
      return;
    }
    if (message is Subscribed) {
      subscriptions[message.subscriptionId] = message;
      _pendingSubscribes.remove(message.subscribeRequestId)?.complete(message);
      return;
    }
    if (message is Unsubscribed) {
      _handleUnsubscribed(message);
      return;
    }
    if (message is Event) {
      subscriptions[message.subscriptionId]?.addEvent(_decodeEvent(message));
      return;
    }
    if (message is Registered) {
      registrations[message.registrationId] = message;
      final pending = _pendingRegisters.remove(message.registerRequestId);
      if (pending != null) {
        message.procedure = pending.procedure;
        pending.completer.complete(message);
      }
      return;
    }
    if (message is Unregistered) {
      final pending = _pendingUnregisters.remove(message.unregisterRequestId);
      if (pending != null) {
        _removeRegistration(pending.registrationId);
        pending.completer.complete();
      }
      return;
    }
    if (message is Invocation) {
      final registered = registrations[message.registrationId];
      if (registered != null) {
        message.onResponse((response) => _transport.send(response));
        registered.addInvocation(message);
        return;
      }
      _transport.send(
        Error(
          MessageTypes.codeInvocation,
          message.requestId,
          {},
          Error.noSuchRegistration,
        ),
      );
      return;
    }
    if (message is Error) {
      _handleError(message);
    }
  }

  void _handleResult(Result message) {
    final pending = _pendingCalls[message.callRequestId];
    if (pending == null) {
      return;
    }
    if (pending.addResult(message)) {
      _pendingCalls.remove(message.callRequestId);
      unawaited(pending.close());
    }
  }

  void _handleUnsubscribed(Unsubscribed message) {
    final pending = _pendingUnsubscribes.remove(message.unsubscribeRequestId);
    if (pending != null) {
      _removeSubscription(pending.subscriptionId);
      pending.completer.complete();
    }
    final revokedSubscription = message.details?.subscription;
    if (revokedSubscription != null) {
      final subscribed = _removeSubscription(revokedSubscription);
      subscribed?.revoke(message.details?.reason);
    }
  }

  void _handleError(Error message) {
    if (message.requestTypeId == MessageTypes.codeCall) {
      final pendingCall = _pendingCalls.remove(message.requestId);
      if (pendingCall != null) {
        pendingCall.addError(message);
        unawaited(pendingCall.close());
      }
      return;
    }
    if (message.requestTypeId == MessageTypes.codePublish) {
      _completePendingError(
        _pendingPublishes.remove(message.requestId),
        message,
      );
      return;
    }
    if (message.requestTypeId == MessageTypes.codeSubscribe) {
      _completePendingError(
        _pendingSubscribes.remove(message.requestId),
        message,
      );
      return;
    }
    if (message.requestTypeId == MessageTypes.codeUnsubscribe) {
      final pendingUnsubscribe = _pendingUnsubscribes.remove(message.requestId);
      _completePendingError(pendingUnsubscribe?.completer, message);
      return;
    }
    if (message.requestTypeId == MessageTypes.codeRegister) {
      _completePendingError(
        _pendingRegisters.remove(message.requestId)?.completer,
        message,
      );
      return;
    }
    if (message.requestTypeId == MessageTypes.codeUnregister) {
      final pendingUnregister = _pendingUnregisters.remove(message.requestId);
      _completePendingError(pendingUnregister?.completer, message);
    }
  }

  Event _decodeEvent(Event event) {
    var eventUpdated = event;
    if (event.details.pptScheme == 'wamp') {
      final e2eePayload = E2EEPayload.unpackE2EEPayload(
        event.arguments,
        event.details,
      );
      eventUpdated.arguments = e2eePayload.arguments;
      eventUpdated.argumentsKeywords = e2eePayload.argumentsKeywords;
    } else if (event.details.pptScheme != null) {
      final pptPayload = PPTPayload.unpackPPTPayload(
        event.arguments,
        event.details,
      );
      eventUpdated.arguments = pptPayload.arguments;
      eventUpdated.argumentsKeywords = pptPayload.argumentsKeywords;
    }
    return eventUpdated;
  }

  Subscribed? _removeSubscription(int subscriptionId) {
    final subscribed = subscriptions.remove(subscriptionId);
    if (subscribed != null) {
      unawaited(subscribed.closeEventStream());
    }
    return subscribed;
  }

  Registered? _removeRegistration(int registrationId) {
    final registered = registrations.remove(registrationId);
    if (registered != null) {
      unawaited(registered.closeInvocationStream());
    }
    return registered;
  }

  Future<void> _handleTransportClosed([
    Object? error,
    StackTrace? stackTrace,
  ]) async {
    if (_incomingClosed) {
      return;
    }
    _incomingClosed = true;
    final closureError = error ?? StateError('Session transport closed');

    final pendingCalls = _pendingCalls.values.toList(growable: false);
    _pendingCalls.clear();
    for (final pending in pendingCalls) {
      pending.addError(closureError, stackTrace);
      await pending.close();
    }

    final publishCompleters = _pendingPublishes.values.toList(growable: false);
    final subscribeCompleters = _pendingSubscribes.values.toList(
      growable: false,
    );
    final unsubscribeCompleters = _pendingUnsubscribes.values
        .map((pending) => pending.completer)
        .toList(growable: false);
    final registerCompleters = _pendingRegisters.values
        .map((pending) => pending.completer)
        .toList(growable: false);
    final unregisterCompleters = _pendingUnregisters.values
        .map((pending) => pending.completer)
        .toList(growable: false);

    _pendingPublishes.clear();
    _pendingSubscribes.clear();
    _pendingUnsubscribes.clear();
    _pendingRegisters.clear();
    _pendingUnregisters.clear();

    for (final completer in publishCompleters) {
      _completePendingError(completer, closureError, stackTrace);
    }
    for (final completer in subscribeCompleters) {
      _completePendingError(completer, closureError, stackTrace);
    }
    for (final completer in unsubscribeCompleters) {
      _completePendingError(completer, closureError, stackTrace);
    }
    for (final completer in registerCompleters) {
      _completePendingError(completer, closureError, stackTrace);
    }
    for (final completer in unregisterCompleters) {
      _completePendingError(completer, closureError, stackTrace);
    }

    final activeSubscriptions = subscriptions.values.toList(growable: false);
    final activeRegistrations = registrations.values.toList(growable: false);
    subscriptions.clear();
    registrations.clear();

    for (final subscription in activeSubscriptions) {
      await subscription.closeEventStream();
    }
    for (final registration in activeRegistrations) {
      await registration.closeInvocationStream();
    }
  }

  void _completePendingError<T>(
    Completer<T>? completer,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.completeError(error, stackTrace);
  }

  Call _buildCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    CallOptions? options,
  }) {
    var callArguments = arguments;
    var callArgumentsKeywords = argumentsKeywords;

    if (options?.pptScheme == 'wamp') {
      callArguments = E2EEPayload.packE2EEPayload(
        arguments,
        argumentsKeywords,
        options!,
      );
      callArgumentsKeywords = null;
    } else if (options?.pptScheme != null) {
      callArguments = PPTPayload.packPPTPayload(
        arguments,
        argumentsKeywords,
        options!,
      );
      callArgumentsKeywords = null;
    }

    return Call(
      nextCallId++,
      procedure,
      arguments: callArguments,
      argumentsKeywords: callArgumentsKeywords,
      options: options,
    );
  }

  void _attachCallCancellation(
    int requestId,
    Completer<String>? cancelCompleter,
  ) {
    if (cancelCompleter == null) {
      return;
    }
    unawaited(
      cancelCompleter.future.then((cancelMode) {
        CancelOptions? options;
        if (CancelOptions.modeKillNoWait == cancelMode ||
            CancelOptions.modeKill == cancelMode ||
            CancelOptions.modeSkip == cancelMode) {
          options = CancelOptions()..mode = cancelMode;
        }
        _transport.send(Cancel(requestId, options: options));
      }),
    );
  }
}

abstract class _PendingCall {
  bool addResult(Result result);

  void addError(Object error, [StackTrace? stackTrace]);

  Future<void> close();
}

class _PendingCallStream implements _PendingCall {
  _PendingCallStream(this.controller);

  final StreamController<Result> controller;

  @override
  bool addResult(Result result) {
    controller.add(result);
    return !result.isProgressive();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    controller.addError(error, stackTrace);
  }

  @override
  Future<void> close() {
    if (controller.isClosed) {
      return Future<void>.value();
    }
    return controller.close();
  }
}

class _PendingCallFuture implements _PendingCall {
  _PendingCallFuture(this.completer);

  final Completer<Result> completer;

  @override
  bool addResult(Result result) {
    if (result.isProgressive()) {
      return false;
    }
    if (!completer.isCompleted) {
      completer.complete(result);
    }
    return true;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (completer.isCompleted) {
      return;
    }
    completer.completeError(error, stackTrace);
  }

  @override
  Future<void> close() => Future<void>.value();
}

class _PendingUnsubscribe {
  _PendingUnsubscribe({required this.subscriptionId, required this.completer});

  final int subscriptionId;
  final Completer<void> completer;
}

class _PendingRegister {
  _PendingRegister({required this.procedure, required this.completer});

  final String procedure;
  final Completer<Registered> completer;
}

class _PendingUnregister {
  _PendingUnregister({required this.registrationId, required this.completer});

  final int registrationId;
  final Completer<void> completer;
}

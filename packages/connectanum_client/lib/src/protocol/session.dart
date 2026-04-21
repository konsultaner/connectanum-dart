import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';

import '../transport/abstract_transport.dart';
import '../transport/native/message_binding.dart';
import '../transport/native/message_protocol.dart';

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
  final WampE2eeProvider? _e2eeProvider;

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

  late StreamSubscription<Object?> _transportStreamSubscription;
  final Map<int, _PendingCall> _pendingCalls = {};
  final Map<int, _PendingInvocationResponder> _pendingInvocations = {};
  final Map<int, String?> _pendingInvocationInterrupts = {};
  final Map<int, Completer<Published>> _pendingPublishes = {};
  final Map<int, Completer<Subscribed>> _pendingSubscribes = {};
  final Map<int, _PendingUnsubscribe> _pendingUnsubscribes = {};
  final Map<int, _PendingRegister> _pendingRegisters = {};
  final Map<int, _PendingUnregister> _pendingUnregisters = {};
  bool _incomingClosed = false;

  Session(this.realm, this._transport, {WampE2eeProvider? e2eeProvider})
    : _e2eeProvider = e2eeProvider,
      assert(realm == null || UriPattern.match(realm), _transport.isOpen);

  /// Starting the session will also start the authentication process.
  static Future<Session> start(
    String? realm,
    AbstractTransport transport, {
    String? authId,
    String? authRole,
    Map<String, dynamic>? authExtra,
    List<AbstractAuthentication>? authMethods,
    Duration? reconnect,
    WampE2eeProvider? e2eeProvider,
  }) async {
    final session = Session(realm, transport, e2eeProvider: e2eeProvider);

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
    session
        ._transportStreamSubscription = session._receiveSessionMessages().listen(
      (message) {
        final materialized = session._materializeTransportMessage(message);
        if (materialized is Challenge) {
          final foundAuthMethod = authMethods
              ?.where(
                (authenticationMethod) =>
                    authenticationMethod.getName() == materialized.authMethod,
              )
              .first;
          if (foundAuthMethod != null) {
            try {
              foundAuthMethod
                  .challenge(materialized.extra)
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

        if (materialized is Welcome) {
          session.id = materialized.sessionId;
          if ((session.realm ?? materialized.details.realm) == null) {
            welcomeCompleter.completeError(
              Abort(
                Error.authorizationFailed,
                message:
                    'No realm specified! Neither by the client nor by the router',
              ),
            );
            return;
          }
          if (materialized.details.realm == null) {
            if (_logger.level <= Level.INFO) {
              _logger.info('Warning! No realm returned by the router');
            }
          } else {
            session.realm = materialized.details.realm;
          }
          session.authId = materialized.details.authid;
          session.authRole = materialized.details.authrole;
          session.authMethod = materialized.details.authmethod;
          session.authProvider = materialized.details.authprovider;
          session.authExtra = materialized.details.authextra;
          session._transportStreamSubscription.onData(
            session._handleTransportMessage,
          );
          session._transportStreamSubscription.onDone(() {
            unawaited(session._handleTransportClosed());
          });
          welcomeCompleter.complete(session);
          return;
        }

        if (materialized is Abort) {
          try {
            transport.close();
          } catch (_) {
            /* transport may already be closed */
          }
          welcomeCompleter.completeError(materialized);
          return;
        }

        if (materialized is Goodbye) {
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

  Stream<Object?> _receiveSessionMessages() {
    if (_transport is SessionOptimizedTransport) {
      return (_transport as SessionOptimizedTransport).receiveSessionMessages();
    }
    return _transport.receive()!.cast<Object?>();
  }

  AbstractMessage? _materializeTransportMessage(Object? message) {
    if (message == null) {
      return null;
    }
    if (message is NativeSessionMessage) {
      message.attachE2eeProvider(_e2eeProvider);
      return message.materialize();
    }
    if (message is AbstractMessageWithPayload) {
      message.attachE2eeProvider(_e2eeProvider);
    }
    return message as AbstractMessage?;
  }

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

  /// This calls a [procedure] with a [LazyMessagePayload] so encoded args /
  /// kwargs bytes can flow through the serializer without eager decode.
  Stream<Result> callLazyPayload(
    String procedure, {
    required LazyMessagePayload payload,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    final call = _buildCallLazyPayload(
      procedure,
      payload: payload,
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
    return callSingleWithLazyPayload(
      procedure,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: options,
      cancelCompleter: cancelCompleter,
    );
  }

  /// This calls a [procedure] with a [LazyMessagePayload] and waits for the
  /// final non-progressive [Result].
  Future<Result> callSingleWithLazyPayload(
    String procedure, {
    required LazyMessagePayload payload,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) async {
    final result = await callSingleLazyPayloadView(
      procedure,
      payload: payload,
      options: options,
      cancelCompleter: cancelCompleter,
    );
    return resultFromLazyPayload(result);
  }

  /// This calls a [procedure] and waits for the final non-progressive payload
  /// without materializing a [Result] object on the native fast path.
  Future<ResultPayload> callSinglePayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    return callSinglePayloadWithLazyPayload(
      procedure,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: options,
      cancelCompleter: cancelCompleter,
    );
  }

  /// This calls a [procedure] with a [LazyMessagePayload] and waits for the
  /// final non-progressive payload without materializing a [Result] object.
  Future<ResultPayload> callSinglePayloadWithLazyPayload(
    String procedure, {
    required LazyMessagePayload payload,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) async {
    final result = await callSingleLazyPayloadView(
      procedure,
      payload: payload,
      options: options,
      cancelCompleter: cancelCompleter,
    );
    return result.toPayload();
  }

  /// This calls a [procedure] and returns the final non-progressive payload
  /// as a lazy view over the transport payload when possible.
  Future<LazyResultPayload> callSingleLazyPayload(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    return callSingleLazyPayloadView(
      procedure,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: options,
      cancelCompleter: cancelCompleter,
    );
  }

  /// This calls a [procedure] with a [LazyMessagePayload] and returns the
  /// final non-progressive payload as a lazy view over the transport payload.
  Future<LazyResultPayload> callSingleLazyPayloadView(
    String procedure, {
    required LazyMessagePayload payload,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    final call = _buildCallLazyPayload(
      procedure,
      payload: payload,
      options: options,
    );
    final completer = Completer<LazyResultPayload>();
    _pendingCalls[call.requestId] = _PendingCallLazyPayloadFuture(completer);
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

  /// This subscribes the session to a [topic] and routes payloads directly to
  /// [onEvent] without forcing [Event] allocation on the native fast path.
  Future<Subscribed> subscribePayloadHandler(
    String topic,
    void Function(EventPayload event) onEvent, {
    SubscribeOptions? options,
  }) async {
    final subscribed = await subscribe(topic, options: options);
    subscribed.onEventPayload(onEvent);
    return subscribed;
  }

  /// This subscribes the session to a [topic] and routes lazy payload views
  /// directly to [onEvent] so encoded payload bytes can be forwarded without
  /// forcing immediate decode.
  Future<Subscribed> subscribeLazyPayloadHandler(
    String topic,
    void Function(LazyEventPayload event) onEvent, {
    SubscribeOptions? options,
  }) async {
    final subscribed = await subscribe(topic, options: options);
    subscribed.onLazyEventPayload(onEvent);
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
    return publishLazyPayload(
      topic,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: options,
    );
  }

  /// This publishes an event with a [LazyMessagePayload] so encoded args /
  /// kwargs bytes can pass through the serializer without eager decode.
  Future<Published?> publishLazyPayload(
    String topic, {
    required LazyMessagePayload payload,
    PublishOptions? options,
  }) {
    final publish = _buildPublishLazyPayload(
      topic,
      payload: payload,
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

  /// This registers a [procedure] and routes invocation payloads directly to
  /// [onInvoke] without forcing [Invocation] allocation on the native fast path.
  Future<Registered> registerPayloadHandler(
    String procedure,
    FutureOr<void> Function(InvocationPayload invocation) onInvoke, {
    RegisterOptions? options,
  }) async {
    final registered = await register(procedure, options: options);
    registered.onInvokePayload(onInvoke);
    return registered;
  }

  /// This registers a [procedure] and routes invocation payloads directly to
  /// [onInvoke] as lazy payload views.
  Future<Registered> registerLazyPayloadHandler(
    String procedure,
    FutureOr<void> Function(LazyInvocationPayload invocation) onInvoke, {
    RegisterOptions? options,
  }) async {
    final registered = await register(procedure, options: options);
    registered.onLazyInvokePayload(onInvoke);
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

  void _handleTransportMessage(Object? message) {
    if (message == null) {
      return;
    }
    if (message is AbstractMessageWithPayload) {
      message.attachE2eeProvider(_e2eeProvider);
    }
    if (message is NativeSessionMessage) {
      _handleNativeSessionMessage(message);
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
      subscriptions[message.subscriptionId]?.addEvent(message);
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
        message.onResponse((response) {
          _transport.send(response);
          if (response is Error ||
              response is! Yield ||
              response.options?.progress != true) {
            _pendingInvocations.remove(message.requestId);
          }
        });
        final responder = _PendingInvocationResponder(
          isClosed: () => message.responseClosed,
          cancel: (mode) {
            if (message.responseClosed) {
              return;
            }
            message.respondWith(
              isError: true,
              errorUri: Error.errorInvocationCanceled,
              arguments: mode == null ? null : [mode],
            );
          },
        );
        _pendingInvocations[message.requestId] = responder;
        if (_cancelInterruptedInvocation(message.requestId, responder)) {
          return;
        }
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
    if (message is Interrupt) {
      final pendingInvocation = _pendingInvocations.remove(message.requestId);
      if (pendingInvocation != null && !pendingInvocation.isClosed()) {
        pendingInvocation.cancel(message.options?.mode);
      } else {
        _pendingInvocationInterrupts[message.requestId] = message.options?.mode;
        _logger.finer(
          'Ignoring callee interrupt for request ${message.requestId} '
          'mode=${message.options?.mode}',
        );
      }
      return;
    }
    if (message is Error) {
      _handleError(message);
    }
  }

  void _handleNativeSessionMessage(NativeSessionMessage message) {
    message.attachE2eeProvider(_e2eeProvider);
    final code = message.metadata.messageCode;
    if (code == MessageTypes.codeResult) {
      _handleNativeResult(message);
      return;
    }
    if (code == MessageTypes.codeEvent) {
      _handleNativeEvent(message);
      return;
    }
    if (code == MessageTypes.codeInvocation) {
      _handleNativeInvocation(message);
      return;
    }
    if (code == MessageTypes.codeInterrupt) {
      final pendingInvocation = _pendingInvocations.remove(
        message.metadata.primaryId,
      );
      if (pendingInvocation != null && !pendingInvocation.isClosed()) {
        pendingInvocation.cancel(message.metadata.stringA);
      } else {
        _pendingInvocationInterrupts[message.metadata.primaryId] =
            message.metadata.stringA;
        _logger.finer(
          'Ignoring native callee interrupt for request ${message.metadata.primaryId} '
          'mode=${message.metadata.stringA}',
        );
      }
      return;
    }
    _handleTransportMessage(message.materialize());
  }

  void _handleNativeResult(NativeSessionMessage message) {
    final pending = _pendingCalls[message.metadata.primaryId];
    if (pending == null) {
      return;
    }
    if (pending is _PendingCallLazyPayloadFuture) {
      if (pending.addDirectResult(_lazyResultPayloadFromNative(message))) {
        _pendingCalls.remove(message.metadata.primaryId);
        unawaited(pending.close());
      }
      return;
    }
    _handleResult(message.materialize() as Result);
  }

  void _handleNativeEvent(NativeSessionMessage message) {
    final subscribed = subscriptions[message.metadata.primaryId];
    if (subscribed == null) {
      return;
    }
    if (subscribed.hasMaterializedEventConsumers) {
      subscribed.addEvent(message.materialize() as Event);
      return;
    }
    final lazyEvent = _lazyEventPayloadFromNative(message);
    if (subscribed.hasLazyPayloadEventHandler) {
      subscribed.addLazyEventPayload(lazyEvent);
      return;
    }
    if (subscribed.hasPayloadEventHandler) {
      subscribed.addEventPayload(lazyEvent.toPayload());
    }
  }

  void _handleNativeInvocation(NativeSessionMessage message) {
    final registered = registrations[message.metadata.secondaryId];
    if (registered == null) {
      _transport.send(
        Error(
          MessageTypes.codeInvocation,
          message.metadata.primaryId,
          {},
          Error.noSuchRegistration,
        ),
      );
      return;
    }
    if (registered.hasMaterializedInvocationConsumers) {
      final invocation = message.materialize() as Invocation;
      invocation.onResponse((response) => _transport.send(response));
      final responder = _PendingInvocationResponder(
        isClosed: () => invocation.responseClosed,
        cancel: (mode) {
          if (invocation.responseClosed) {
            return;
          }
          invocation.respondWith(
            isError: true,
            errorUri: Error.errorInvocationCanceled,
            arguments: mode == null ? null : [mode],
          );
        },
      );
      _pendingInvocations[message.metadata.primaryId] = responder;
      if (_cancelInterruptedInvocation(message.metadata.primaryId, responder)) {
        return;
      }
      registered.addInvocation(invocation);
      return;
    }
    final lazyInvocation = _lazyInvocationPayloadFromNative(message);
    final responder = _pendingInvocations[message.metadata.primaryId];
    if (responder != null &&
        _cancelInterruptedInvocation(message.metadata.primaryId, responder)) {
      return;
    }
    if (registered.hasLazyPayloadInvocationHandler) {
      registered.addLazyInvocationPayload(lazyInvocation);
      return;
    }
    if (registered.hasPayloadInvocationHandler) {
      registered.addInvocationPayload(lazyInvocation.toPayload());
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
    if (message.requestTypeId == MessageTypes.codeCancel) {
      final pendingCall = _pendingCalls.remove(message.requestId);
      if (pendingCall != null) {
        pendingCall.addError(message);
        unawaited(pendingCall.close());
        return;
      }
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

  LazyResultPayload _lazyResultPayloadFromNative(NativeSessionMessage message) {
    return LazyResultPayload(
      callRequestId: message.metadata.primaryId,
      progress: message.metadata.hasFlag(
        NativeMessageMetadata.flagDetailBoolATrue,
      ),
      pptScheme: message.metadata.stringA,
      pptSerializer: message.metadata.stringB,
      pptCipher: message.metadata.stringC,
      pptKeyId: message.metadata.stringD,
      customDetails: null,
      payload: unwrapLazyPayloadView(
        message.toLazyPayload(anchor: message),
        pptScheme: message.metadata.stringA,
        pptSerializer: message.metadata.stringB,
        pptCipher: message.metadata.stringC,
        pptKeyId: message.metadata.stringD,
        e2eeProvider: message.e2eeProvider,
      ),
    );
  }

  LazyEventPayload _lazyEventPayloadFromNative(NativeSessionMessage message) {
    return LazyEventPayload(
      subscriptionId: message.metadata.primaryId,
      publicationId: message.metadata.secondaryId,
      publisher:
          message.metadata.hasFlag(
            NativeMessageMetadata.flagDetailNumberAPresent,
          )
          ? message.metadata.detailNumberA
          : null,
      trustlevel:
          message.metadata.hasFlag(
            NativeMessageMetadata.flagDetailNumberBPresent,
          )
          ? message.metadata.detailNumberB
          : null,
      topic: message.metadata.stringA,
      pptScheme: message.metadata.stringB,
      pptSerializer: message.metadata.stringC,
      pptCipher: message.metadata.stringD,
      pptKeyId: message.metadata.stringE,
      customDetails: null,
      payload: unwrapLazyPayloadView(
        message.toLazyPayload(anchor: message),
        pptScheme: message.metadata.stringB,
        pptSerializer: message.metadata.stringC,
        pptCipher: message.metadata.stringD,
        pptKeyId: message.metadata.stringE,
        e2eeProvider: message.e2eeProvider,
      ),
    );
  }

  LazyInvocationPayload _lazyInvocationPayloadFromNative(
    NativeSessionMessage message,
  ) {
    var responseClosed = false;

    void respondWith({
      LazyMessagePayload? lazyPayload,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords,
      bool isError = false,
      String? errorUri,
      YieldOptions? options,
    }) {
      if (responseClosed) {
        throw StateError('Invocation response handler already completed');
      }
      if (isError) {
        _transport.send(
          Error(
            MessageTypes.codeInvocation,
            message.metadata.primaryId,
            {},
            errorUri,
            arguments: arguments,
            argumentsKeywords: argumentsKeywords,
          ),
        );
        responseClosed = true;
        _pendingInvocations.remove(message.metadata.primaryId);
        return;
      }
      final yieldMessage = Yield(
        message.metadata.primaryId,
        options: options,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
      if (lazyPayload != null) {
        final matchesPackedEncoding = switch ((
          lazyPayload.encoding,
          options?.pptSerializer,
        )) {
          (LazyPayloadEncoding.json, 'json') => true,
          (LazyPayloadEncoding.messagePack, 'msgpack') => true,
          (LazyPayloadEncoding.cbor, 'cbor') => true,
          _ => false,
        };
        if (options?.pptScheme != null &&
            lazyPayload.packedPayloadBytes != null &&
            matchesPackedEncoding) {
          yieldMessage.arguments = [lazyPayload.packedPayloadBytes!];
          yieldMessage.argumentsKeywords = null;
        } else if (options?.pptScheme == null) {
          yieldMessage.setLazyPayload(
            argumentsBytes: lazyPayload.argumentsBytes,
            argumentsDecoder: lazyPayload.argumentsBytes == null
                ? null
                : (_) => lazyPayload.arguments ?? const <dynamic>[],
            argumentsKeywordsBytes: lazyPayload.argumentsKeywordsBytes,
            argumentsKeywordsDecoder: lazyPayload.argumentsKeywordsBytes == null
                ? null
                : (_) =>
                      lazyPayload.argumentsKeywords ??
                      const <String, dynamic>{},
            encoding: lazyPayload.encoding,
          );
          if (!lazyPayload.hasEncodedArguments) {
            yieldMessage.arguments = lazyPayload.arguments;
          }
          if (!lazyPayload.hasEncodedArgumentsKeywords) {
            yieldMessage.argumentsKeywords = lazyPayload.argumentsKeywords;
          }
        }
      }
      yieldMessage.attachE2eeProvider(
        lazyPayload?.e2eeProvider ?? _e2eeProvider,
      );
      _transport.send(yieldMessage);
      if (options?.progress != true) {
        responseClosed = true;
        _pendingInvocations.remove(message.metadata.primaryId);
      }
    }

    final invocation = LazyInvocationPayload(
      requestId: message.metadata.primaryId,
      registrationId: message.metadata.secondaryId,
      caller:
          message.metadata.hasFlag(
            NativeMessageMetadata.flagDetailNumberAPresent,
          )
          ? message.metadata.detailNumberA
          : null,
      procedure: message.metadata.stringA,
      receiveProgress: message.metadata.hasFlag(
        NativeMessageMetadata.flagDetailBoolATrue,
      ),
      pptScheme: message.metadata.stringB,
      pptSerializer: message.metadata.stringC,
      pptCipher: message.metadata.stringD,
      pptKeyId: message.metadata.stringE,
      customDetails: null,
      respondWith:
          ({
            LazyMessagePayload? lazyPayload,
            List<dynamic>? arguments,
            Map<String, dynamic>? argumentsKeywords,
            bool isError = false,
            String? errorUri,
            YieldOptions? options,
          }) {
            respondWith(
              lazyPayload: lazyPayload,
              arguments: arguments,
              argumentsKeywords: argumentsKeywords,
              isError: isError,
              errorUri: errorUri,
              options: options,
            );
          },
      isResponseClosed: () => responseClosed,
      payload: unwrapLazyPayloadView(
        message.toLazyPayload(anchor: message),
        pptScheme: message.metadata.stringB,
        pptSerializer: message.metadata.stringC,
        pptCipher: message.metadata.stringD,
        pptKeyId: message.metadata.stringE,
        e2eeProvider: message.e2eeProvider,
      ),
    );
    _pendingInvocations[message.metadata.primaryId] =
        _PendingInvocationResponder(
          isClosed: () => responseClosed,
          cancel: (mode) {
            if (responseClosed) {
              return;
            }
            respondWith(
              isError: true,
              errorUri: Error.errorInvocationCanceled,
              arguments: mode == null ? null : [mode],
            );
          },
        );
    return invocation;
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
    _pendingInvocationInterrupts.clear();

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
    _pendingInvocations.clear();
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

  bool _cancelInterruptedInvocation(
    int requestId,
    _PendingInvocationResponder responder,
  ) {
    final hasQueuedInterrupt = _pendingInvocationInterrupts.containsKey(
      requestId,
    );
    final mode = _pendingInvocationInterrupts.remove(requestId);
    if (!hasQueuedInterrupt) {
      return false;
    }
    if (!responder.isClosed()) {
      responder.cancel(mode);
    }
    return true;
  }

  Call _buildCallLazyPayload(
    String procedure, {
    required LazyMessagePayload payload,
    CallOptions? options,
  }) {
    final call = Call(nextCallId++, procedure, options: options);
    _applyOutboundLazyPayload(call, payload, options);
    return call;
  }

  Publish _buildPublishLazyPayload(
    String topic, {
    required LazyMessagePayload payload,
    PublishOptions? options,
  }) {
    final publish = Publish(nextPublishId++, topic, options: options);
    _applyOutboundLazyPayload(publish, payload, options);
    return publish;
  }

  void _applyOutboundLazyPayload(
    AbstractMessageWithPayload message,
    LazyMessagePayload payload,
    PPTOptions? options,
  ) {
    message.attachE2eeProvider(payload.e2eeProvider ?? _e2eeProvider);
    message.transparentBinaryPayload = payload.transparentBinaryPayload;
    Uint8List? packedPayload;
    if (options?.pptScheme != null) {
      packedPayload = _packMatchingLazyPayload(payload, options!.pptSerializer);
    }
    if (options?.pptScheme == 'wamp') {
      message.arguments = packedPayload == null
          ? E2EEPayload.packE2EEPayload(
              payload.arguments,
              payload.argumentsKeywords,
              options!,
              provider: payload.e2eeProvider ?? message.e2eeProvider,
            )
          : <dynamic>[packedPayload];
      message.argumentsKeywords = null;
      return;
    }
    if (options?.pptScheme != null) {
      message.arguments = packedPayload == null
          ? PPTPayload.packPPTPayload(
              payload.arguments,
              payload.argumentsKeywords,
              options!,
            )
          : [packedPayload];
      message.argumentsKeywords = null;
      return;
    }
    if (payload.packedPayloadBytes != null) {
      message.arguments = payload.arguments;
      message.argumentsKeywords = payload.argumentsKeywords;
      if (payload.pptDecoded) {
        message.markPptPayloadDecoded();
      }
      return;
    }
    message.setLazyPayload(
      argumentsBytes: payload.argumentsBytes,
      argumentsDecoder: payload.argumentsBytes == null
          ? null
          : (_) => payload.arguments ?? const <dynamic>[],
      argumentsKeywordsBytes: payload.argumentsKeywordsBytes,
      argumentsKeywordsDecoder: payload.argumentsKeywordsBytes == null
          ? null
          : (_) => payload.argumentsKeywords ?? const <String, dynamic>{},
      encoding: payload.encoding,
    );
    if (!payload.hasEncodedArguments) {
      message.arguments = payload.arguments;
    }
    if (!payload.hasEncodedArgumentsKeywords) {
      message.argumentsKeywords = payload.argumentsKeywords;
    }
    if (payload.pptDecoded) {
      message.markPptPayloadDecoded();
    }
  }

  Uint8List? _packMatchingLazyPayload(
    LazyMessagePayload payload,
    String? serializerName,
  ) {
    if (!_matchesPayloadEncoding(payload.encoding, serializerName)) {
      return null;
    }
    if (payload.packedPayloadBytes != null) {
      return payload.packedPayloadBytes;
    }
    return PPTPayload.packSerializedPayload(
      serializerName,
      argumentsBytes: payload.argumentsBytes,
      argumentsKeywordsBytes: payload.argumentsKeywordsBytes,
      arguments: payload.argumentsBytes == null ? payload.arguments : null,
      argumentsKeywords: payload.argumentsKeywordsBytes == null
          ? payload.argumentsKeywords
          : null,
    );
  }

  bool _matchesPayloadEncoding(
    LazyPayloadEncoding? encoding,
    String? serializerName,
  ) {
    return switch ((encoding, serializerName)) {
      (LazyPayloadEncoding.json, 'json') => true,
      (LazyPayloadEncoding.messagePack, 'msgpack') => true,
      (LazyPayloadEncoding.cbor, 'cbor') => true,
      _ => false,
    };
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

class _PendingCallLazyPayloadFuture implements _PendingCall {
  _PendingCallLazyPayloadFuture(this.completer);

  final Completer<LazyResultPayload> completer;

  bool addDirectResult(LazyResultPayload result) {
    if (result.progress) {
      return false;
    }
    if (!completer.isCompleted) {
      completer.complete(result);
    }
    return true;
  }

  @override
  bool addResult(Result result) {
    return addDirectResult(result.toLazyResultPayload(anchor: result));
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

class _PendingInvocationResponder {
  _PendingInvocationResponder({required this.isClosed, required this.cancel});

  final bool Function() isClosed;
  final void Function(String? mode) cancel;
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

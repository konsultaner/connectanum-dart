import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';

import '../transport/abstract_transport.dart';
import '../transport/native/message_binding.dart';
import '../transport/native/message_protocol.dart';

typedef SessionE2eeProviderResolver =
    FutureOr<WampE2eeProvider?> Function(SessionE2eeProviderContext context);

class ProgressiveCall {
  ProgressiveCall._({
    required this.requestId,
    required this.results,
    required void Function(LazyMessagePayload payload, bool progress) send,
  }) : _send = send;

  final int requestId;
  final Stream<Result> results;
  final void Function(LazyMessagePayload payload, bool progress) _send;
  bool _finished = false;

  bool get isFinished => _finished;

  void sendChunk({
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    sendLazyChunk(
      LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
    );
  }

  void sendLazyChunk(LazyMessagePayload payload) {
    if (_finished) {
      throw StateError('The progressive call is already finished');
    }
    _send(payload, true);
  }

  void finish({
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    finishLazy(
      LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
    );
  }

  void finishLazy(LazyMessagePayload payload) {
    if (_finished) {
      throw StateError('The progressive call is already finished');
    }
    _send(payload, false);
    _finished = true;
  }
}

class SessionE2eeProviderContext {
  const SessionE2eeProviderContext({
    required this.sessionId,
    required this.realm,
    required this.authId,
    required this.authRole,
    required this.authMethod,
    required this.authProvider,
    required this.authExtra,
    required this.negotiatedE2ee,
    required this.configuredProvider,
  });

  final int? sessionId;
  final String? realm;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final Map<String, dynamic>? authExtra;
  final NegotiatedSessionE2ee? negotiatedE2ee;
  final WampE2eeProvider? configuredProvider;
}

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
  final WampE2eeProvider? _configuredE2eeProvider;
  final SessionE2eeProviderResolver? _e2eeProviderResolver;
  WampE2eeProvider? _sessionE2eeProvider;

  WampE2eeProvider? get e2eeProvider =>
      _sessionE2eeProvider ?? _configuredE2eeProvider;

  NegotiatedSessionE2ee? get negotiatedE2ee {
    final authExtraMap = authExtra;
    if (authExtraMap == null) {
      return null;
    }
    final e2eeMap = _asStringDynamicMap(authExtraMap['e2ee']);
    if (e2eeMap == null) {
      return null;
    }
    return NegotiatedSessionE2ee(e2eeMap);
  }

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
  final Map<int, _PendingSubscribe> _pendingSubscribes = {};
  final Map<int, _PendingUnsubscribe> _pendingUnsubscribes = {};
  final Map<int, _PendingRegister> _pendingRegisters = {};
  final Map<int, _PendingUnregister> _pendingUnregisters = {};
  bool _incomingClosed = false;

  Session(
    this.realm,
    this._transport, {
    WampE2eeProvider? e2eeProvider,
    SessionE2eeProviderResolver? e2eeProviderResolver,
  }) : _configuredE2eeProvider = e2eeProvider,
       _e2eeProviderResolver = e2eeProviderResolver,
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
    SessionE2eeProviderResolver? e2eeProviderResolver,
  }) async {
    final session = Session(
      realm,
      transport,
      e2eeProvider: e2eeProvider,
      e2eeProviderResolver: e2eeProviderResolver,
    );

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
          session._initializeSessionE2eeProvider().then(
            (_) {
              if (welcomeCompleter.isCompleted) {
                return;
              }
              session._transportStreamSubscription.onData(
                session._handleTransportMessage,
              );
              session._transportStreamSubscription.onDone(() {
                unawaited(session._handleTransportClosed());
              });
              welcomeCompleter.complete(session);
            },
            onError: (error, stackTrace) {
              try {
                transport.close();
              } catch (_) {
                /* transport may already be closed */
              }
              if (!welcomeCompleter.isCompleted) {
                welcomeCompleter.completeError(error, stackTrace);
              }
            },
          );
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

  Future<void> _initializeSessionE2eeProvider() async {
    final resolver = _e2eeProviderResolver;
    if (resolver == null) {
      _sessionE2eeProvider = null;
      negotiatedE2ee?.verifyRequiredProfile(provider: e2eeProvider);
      return;
    }
    _sessionE2eeProvider = await resolver(
      SessionE2eeProviderContext(
        sessionId: id,
        realm: realm,
        authId: authId,
        authRole: authRole,
        authMethod: authMethod,
        authProvider: authProvider,
        authExtra: authExtra,
        negotiatedE2ee: negotiatedE2ee,
        configuredProvider: _configuredE2eeProvider,
      ),
    );
    negotiatedE2ee?.verifyRequiredProfile(provider: e2eeProvider);
  }

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
      _attachSessionE2eeState(message);
      return message.materialize();
    }
    if (message is AbstractMessageWithPayload) {
      _attachSessionE2eeState(message);
    }
    return message as AbstractMessage?;
  }

  void _attachSessionE2eeState(AbstractMessageWithPayload message) {
    message.attachE2eeProvider(_resolveRuntimeE2eeProvider());
    if (message is NativeSessionMessage) {
      message.attachE2eeRuntimeContext(
        _buildInboundRuntimeContextForNative(message),
      );
      return;
    }
    message.attachE2eeRuntimeContext(
      _buildInboundRuntimeContextForMessage(message),
    );
  }

  WampE2eeRuntimeContext? _buildOutboundRuntimeContext({
    required WampE2eeMessageType messageType,
    String? uri,
    WampE2eePartyContext? peer,
  }) {
    return WampE2eeRuntimeContext(
      direction: WampE2eeDirection.outbound,
      messageType: messageType,
      realm: realm,
      uri: uri,
      local: _localE2eePartyContext(),
      peer: peer,
      negotiated: _negotiatedE2eeRaw(),
    );
  }

  WampE2eeRuntimeContext? _buildInboundRuntimeContextForMessage(
    AbstractMessageWithPayload message,
  ) {
    if (message is Result) {
      return _buildInboundRuntimeContext(
        messageType: WampE2eeMessageType.result,
        uri: _pendingCalls[message.callRequestId]?.procedure,
        peer: _partyContextFromDetails(details: message.details.custom),
      );
    }
    if (message is Event) {
      return _buildInboundRuntimeContext(
        messageType: WampE2eeMessageType.event,
        uri:
            message.details.topic ??
            subscriptions[message.subscriptionId]?.topic,
        peer: _partyContextFromDetails(
          sessionId: message.details.publisher,
          trustLevel: message.details.trustlevel,
          details: message.details.custom,
        ),
      );
    }
    if (message is Invocation) {
      return _buildInboundRuntimeContext(
        messageType: WampE2eeMessageType.invocation,
        uri:
            message.details.procedure ??
            registrations[message.registrationId]?.procedure,
        peer: _partyContextFromDetails(
          sessionId: message.details.caller,
          details: message.details.custom,
        ),
      );
    }
    return null;
  }

  WampE2eeRuntimeContext? _buildInboundRuntimeContextForNative(
    NativeSessionMessage message,
  ) {
    final metadata = message.metadata;
    if (metadata.messageCode == MessageTypes.codeResult) {
      return _buildInboundRuntimeContext(
        messageType: WampE2eeMessageType.result,
        uri: _pendingCalls[metadata.primaryId]?.procedure,
      );
    }
    if (metadata.messageCode == MessageTypes.codeEvent) {
      return _buildInboundRuntimeContext(
        messageType: WampE2eeMessageType.event,
        uri: metadata.stringA ?? subscriptions[metadata.primaryId]?.topic,
        peer: _partyContextFromNativeMetadata(
          metadata,
          sessionIdFlag: NativeMessageMetadata.flagDetailNumberAPresent,
          trustLevelFlag: NativeMessageMetadata.flagDetailNumberBPresent,
        ),
      );
    }
    if (metadata.messageCode == MessageTypes.codeInvocation) {
      return _buildInboundRuntimeContext(
        messageType: WampE2eeMessageType.invocation,
        uri: metadata.stringA ?? registrations[metadata.secondaryId]?.procedure,
        peer: _partyContextFromNativeMetadata(
          metadata,
          sessionIdFlag: NativeMessageMetadata.flagDetailNumberAPresent,
        ),
      );
    }
    return null;
  }

  WampE2eeRuntimeContext _buildInboundRuntimeContext({
    required WampE2eeMessageType messageType,
    String? uri,
    WampE2eePartyContext? peer,
  }) {
    return WampE2eeRuntimeContext(
      direction: WampE2eeDirection.inbound,
      messageType: messageType,
      realm: realm,
      uri: uri,
      local: _localE2eePartyContext(),
      peer: peer,
      negotiated: _negotiatedE2eeRaw(),
    );
  }

  WampE2eePartyContext? _localE2eePartyContext() {
    final context = WampE2eePartyContext(
      sessionId: id,
      authId: authId,
      authRole: authRole,
      authMethod: authMethod,
      authProvider: authProvider,
      authExtra: _copyStringDynamicMap(authExtra),
    );
    return context.isEmpty ? null : context;
  }

  WampE2eePartyContext? _partyContextFromDetails({
    int? sessionId,
    int? trustLevel,
    Map<String, dynamic>? details,
  }) {
    final context = WampE2eePartyContext.fromDetails(
      sessionId: sessionId,
      trustLevel: trustLevel,
      details: details,
    );
    return context.isEmpty ? null : context;
  }

  WampE2eePartyContext? _partyContextFromNativeMetadata(
    NativeMessageMetadata metadata, {
    required int sessionIdFlag,
    int? trustLevelFlag,
  }) {
    final sessionId = metadata.hasFlag(sessionIdFlag)
        ? metadata.detailNumberA
        : null;
    final trustLevel =
        trustLevelFlag != null && metadata.hasFlag(trustLevelFlag)
        ? metadata.detailNumberB
        : null;
    final context = WampE2eePartyContext(
      sessionId: sessionId,
      trustLevel: trustLevel,
    );
    return context.isEmpty ? null : context;
  }

  Map<String, dynamic>? _negotiatedE2eeRaw() {
    final negotiated = negotiatedE2ee?.raw;
    return _copyStringDynamicMap(negotiated);
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
    _pendingCalls[call.requestId] = _PendingCallStream(
      procedure: procedure,
      controller: controller,
    );
    _transport.send(call);
    _attachCallCancellation(call.requestId, cancelCompleter);
    return controller.stream;
  }

  ProgressiveCall startProgressiveCall(
    String procedure, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    CallOptions? options,
    Completer<String>? cancelCompleter,
  }) {
    final initiatingOptions = CallOptions(
      progress: true,
      receiveProgress: options?.receiveProgress,
      timeout: options?.timeout,
      discloseMe: options?.discloseMe,
      pptScheme: options?.pptScheme,
      pptSerializer: options?.pptSerializer,
      pptCipher: options?.pptCipher,
      pptKeyId: options?.pptKeyId,
      custom: options?.custom,
    );
    final call = _buildCallLazyPayload(
      procedure,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      ),
      options: initiatingOptions,
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
    _pendingCalls[call.requestId] = _PendingCallStream(
      procedure: procedure,
      controller: controller,
    );
    _transport.send(call);
    _attachCallCancellation(call.requestId, cancelCompleter);

    return ProgressiveCall._(
      requestId: call.requestId,
      results: controller.stream,
      send: (payload, progress) {
        if (!_pendingCalls.containsKey(call.requestId)) {
          throw StateError('The progressive call is no longer active');
        }
        final chunk = Call(
          call.requestId,
          procedure,
          options: CallOptions(progress: progress),
        );
        chunk.attachE2eeRuntimeContext(
          _buildOutboundRuntimeContext(
            messageType: WampE2eeMessageType.call,
            uri: procedure,
          ),
        );
        _applyOutboundLazyPayload(chunk, payload, initiatingOptions);
        _transport.send(chunk);
      },
    );
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
    _pendingCalls[call.requestId] = _PendingCallLazyPayloadFuture(
      procedure: procedure,
      completer: completer,
    );
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
    _pendingSubscribes[subscribe.requestId] = _PendingSubscribe(
      topic: topic,
      completer: completer,
    );
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
      _attachSessionE2eeState(message);
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
      final pending = _pendingSubscribes.remove(message.subscribeRequestId);
      if (pending != null) {
        message.topic = pending.topic;
        pending.completer.complete(message);
      }
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
          if (response is Yield && response.options?.progress == true) {
            _pendingInvocations[message.requestId]?.resetTimeout();
          } else {
            _takeInvocation(message.requestId);
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
          timeout: () {
            if (message.responseClosed) {
              return;
            }
            message.respondWith(
              isError: true,
              errorUri: Error.timeout,
              arguments: const ['Call timed out'],
            );
          },
        );
        _trackInvocation(message.requestId, responder, message.details.timeout);
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
      final pendingInvocation = _takeInvocation(message.requestId);
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
    _attachSessionE2eeState(message);
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
      final pendingInvocation = _takeInvocation(message.metadata.primaryId);
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
      invocation.onResponse((response) {
        _transport.send(response);
        if (response is Yield && response.options?.progress == true) {
          _pendingInvocations[message.metadata.primaryId]?.resetTimeout();
        } else {
          _takeInvocation(message.metadata.primaryId);
        }
      });
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
        timeout: () {
          if (invocation.responseClosed) {
            return;
          }
          invocation.respondWith(
            isError: true,
            errorUri: Error.timeout,
            arguments: const ['Call timed out'],
          );
        },
      );
      _trackInvocation(
        message.metadata.primaryId,
        responder,
        invocation.details.timeout,
      );
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
        _pendingSubscribes.remove(message.requestId)?.completer,
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
    final yieldRuntimeContext = message.e2eeRuntimeContext?.copyWith(
      direction: WampE2eeDirection.outbound,
      messageType: WampE2eeMessageType.yield,
      uri: message.metadata.stringA ?? message.e2eeRuntimeContext?.uri,
    );

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
        _takeInvocation(message.metadata.primaryId);
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
        _resolveRuntimeE2eeProvider(lazyPayload?.e2eeProvider),
      );
      yieldMessage.attachE2eeRuntimeContext(yieldRuntimeContext);
      _transport.send(yieldMessage);
      if (options?.progress == true) {
        _pendingInvocations[message.metadata.primaryId]?.resetTimeout();
      } else {
        responseClosed = true;
        _takeInvocation(message.metadata.primaryId);
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
      progress: message.metadata.hasFlag(
        NativeMessageMetadata.flagDetailBoolBTrue,
      ),
      receiveProgress: message.metadata.hasFlag(
        NativeMessageMetadata.flagDetailBoolATrue,
      ),
      timeout:
          message.metadata.hasFlag(
            NativeMessageMetadata.flagDetailNumberBPresent,
          )
          ? message.metadata.detailNumberB
          : null,
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
    final responder = _PendingInvocationResponder(
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
      timeout: () {
        if (responseClosed) {
          return;
        }
        respondWith(
          isError: true,
          errorUri: Error.timeout,
          arguments: const ['Call timed out'],
        );
      },
    );
    _trackInvocation(message.metadata.primaryId, responder, invocation.timeout);
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
    final subscribeCompleters = _pendingSubscribes.values
        .map((pending) => pending.completer)
        .toList(growable: false);
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
    for (final invocation in _pendingInvocations.values) {
      invocation.dispose();
    }
    _pendingInvocations.clear();
    subscriptions.clear();
    registrations.clear();

    for (final subscription in activeSubscriptions) {
      await subscription.closeEventStream();
    }
    for (final registration in activeRegistrations) {
      await registration.closeInvocationStream();
    }

    final sessionProvider = _sessionE2eeProvider;
    _sessionE2eeProvider = null;
    if (sessionProvider is DisposableWampE2eeProvider) {
      sessionProvider.release();
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

  void _trackInvocation(
    int requestId,
    _PendingInvocationResponder responder,
    int? timeoutMilliseconds,
  ) {
    _pendingInvocations.remove(requestId)?.dispose();
    _pendingInvocations[requestId] = responder;
    responder.armTimeout(timeoutMilliseconds);
  }

  _PendingInvocationResponder? _takeInvocation(int requestId) {
    final responder = _pendingInvocations.remove(requestId);
    responder?.dispose();
    return responder;
  }

  Call _buildCallLazyPayload(
    String procedure, {
    required LazyMessagePayload payload,
    CallOptions? options,
  }) {
    final call = Call(nextCallId++, procedure, options: options);
    call.attachE2eeRuntimeContext(
      _buildOutboundRuntimeContext(
        messageType: WampE2eeMessageType.call,
        uri: procedure,
      ),
    );
    _applyOutboundLazyPayload(call, payload, options);
    return call;
  }

  Publish _buildPublishLazyPayload(
    String topic, {
    required LazyMessagePayload payload,
    PublishOptions? options,
  }) {
    final publish = Publish(nextPublishId++, topic, options: options);
    publish.attachE2eeRuntimeContext(
      _buildOutboundRuntimeContext(
        messageType: WampE2eeMessageType.publish,
        uri: topic,
      ),
    );
    _applyOutboundLazyPayload(publish, payload, options);
    return publish;
  }

  void _applyOutboundLazyPayload(
    AbstractMessageWithPayload message,
    LazyMessagePayload payload,
    PPTOptions? options,
  ) {
    final runtimeE2eeProvider = _resolveRuntimeE2eeProvider(
      payload.e2eeProvider,
    );
    message.attachE2eeProvider(runtimeE2eeProvider);
    message.transparentBinaryPayload = payload.transparentBinaryPayload;
    Uint8List? packedPayload;
    if (options?.pptScheme == 'wamp') {
      if (payload.packedPayloadBytes != null &&
          _matchesPayloadEncoding(payload.encoding, options!.pptSerializer)) {
        packedPayload = payload.packedPayloadBytes;
      }
    } else if (options?.pptScheme != null) {
      packedPayload = _packMatchingLazyPayload(payload, options!.pptSerializer);
    }
    if (options?.pptScheme == 'wamp') {
      message.arguments = packedPayload == null
          ? E2EEPayload.packE2EEPayload(
              payload.arguments,
              payload.argumentsKeywords,
              options!,
              provider: runtimeE2eeProvider ?? message.e2eeProvider,
              runtimeContext: message.e2eeRuntimeContext,
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

  WampE2eeProvider? _resolveRuntimeE2eeProvider([WampE2eeProvider? provider]) {
    final resolvedProvider = provider ?? e2eeProvider;
    if (resolvedProvider == null) {
      return null;
    }
    if (resolvedProvider is _NegotiatedSessionE2eeProvider) {
      return resolvedProvider;
    }
    final negotiated = negotiatedE2ee;
    if (negotiated == null) {
      return resolvedProvider;
    }
    return _NegotiatedSessionE2eeProvider(
      provider: resolvedProvider,
      negotiated: negotiated,
      realm: realm,
      local: _localE2eePartyContext(),
    );
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
        final options = CancelOptions()..mode = cancelMode;
        _transport.send(Cancel(requestId, options: options));
      }),
    );
  }
}

class SessionE2eeNegotiationException implements Exception {
  SessionE2eeNegotiationException(this.reason, {required this.negotiated});

  final String reason;
  final Map<String, dynamic> negotiated;

  @override
  String toString() => 'SessionE2eeNegotiationException: $reason';
}

class NegotiatedSessionE2ee {
  NegotiatedSessionE2ee(this.raw);

  final Map<String, dynamic> raw;

  int? get version => raw['version'] is int ? raw['version'] as int : null;

  bool? get isRequired =>
      raw['required'] is bool ? raw['required'] as bool : null;

  bool? get established =>
      raw['established'] is bool ? raw['established'] as bool : null;

  String? get scheme =>
      raw['scheme'] as String? ?? raw['selected_scheme'] as String?;

  String? get serializer =>
      raw['serializer'] as String? ?? raw['selected_serializer'] as String?;

  String? get cipher =>
      raw['cipher'] as String? ?? raw['selected_cipher'] as String?;

  String? get acceptedKeyId =>
      raw['accepted_key_id'] as String? ?? raw['key_id'] as String?;

  String? get sendKeyId => raw['send_key_id'] as String?;

  String? get receiveKeyId => raw['receive_key_id'] as String?;

  String? get outboundKeyId => sendKeyId ?? peerKeyId ?? acceptedKeyId;

  String? get inboundKeyId => receiveKeyId ?? acceptedKeyId ?? peerKeyId;

  String? get peerKeyId => raw['peer_key_id'] as String?;

  String? get kex => raw['kex'] as String?;

  String? get clientPublicKey => raw['client_pubkey'] as String?;

  String? get serverPublicKey => raw['server_pubkey'] as String?;

  String? get peerPublicKey => raw['peer_pubkey'] as String?;

  Object? operator [](String key) => raw[key];

  void verifyRequiredProfile({required WampE2eeProvider? provider}) {
    if (isRequired != true) {
      return;
    }
    if (version != ConnectanumE2eeProfile.version) {
      _reject(
        'Required E2EE uses unsupported profile version ${version ?? 'null'}',
      );
    }
    if (established != true) {
      _reject('Required E2EE was not established by the router');
    }
    if (scheme != ConnectanumE2eeProfile.scheme ||
        serializer != ConnectanumE2eeProfile.serializer) {
      _reject(
        'Required E2EE must select wamp/cbor, got '
        '${scheme ?? 'null'}/${serializer ?? 'null'}',
      );
    }
    if (cipher != ConnectanumE2eeProfile.xsalsa20Poly1305 &&
        cipher != ConnectanumE2eeProfile.aes256Gcm) {
      _reject('Required E2EE selected unsupported cipher ${cipher ?? 'null'}');
    }
    if (outboundKeyId == null || inboundKeyId == null) {
      _reject('Required E2EE must select outbound and inbound key ids');
    }
    if (provider == null) {
      _reject('Required E2EE has no configured or resolved payload provider');
    }
    if (provider is! WampE2eeProfileSupport) {
      _reject('Required E2EE provider does not declare profile support');
    }
    final profileSupport = provider as WampE2eeProfileSupport;
    if (!profileSupport.supportsE2eeProfile(
      version: version!,
      scheme: scheme!,
      serializer: serializer!,
      cipher: cipher!,
    )) {
      _reject(
        'Required E2EE provider does not support the negotiated '
        '$scheme/$serializer/$cipher profile',
      );
    }
  }

  Never _reject(String reason) {
    throw SessionE2eeNegotiationException(
      reason,
      negotiated: Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(raw),
      ),
    );
  }
}

class _NegotiatedSessionE2eeProvider implements WampE2eeProvider {
  _NegotiatedSessionE2eeProvider({
    required this.provider,
    required this.negotiated,
    required this.realm,
    required this.local,
  });

  final WampE2eeProvider provider;
  final NegotiatedSessionE2ee negotiated;
  final String? realm;
  final WampE2eePartyContext? local;
  late final WampE2eeKeySelectionPolicy _keySelectionPolicy =
      WampE2eeKeySelectionPolicies.firstDefined([
        if (provider case WampE2eePolicyAwareProvider(
          :final keySelectionPolicy,
        ))
          keySelectionPolicy,
        WampE2eeKeySelectionPolicies.negotiated(),
      ]);

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    final mergedRuntimeContext = _mergeRuntimeContext(runtimeContext);
    _applyDefaults(
      options,
      outbound: true,
      runtimeContext: mergedRuntimeContext,
    );
    return provider.packPayload(
      arguments,
      argumentsKeywords,
      options,
      runtimeContext: mergedRuntimeContext,
    );
  }

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    final mergedRuntimeContext = _mergeRuntimeContext(runtimeContext);
    _applyDefaults(
      options,
      outbound: false,
      runtimeContext: mergedRuntimeContext,
    );
    return provider.unpackPayload(
      arguments,
      options,
      runtimeContext: mergedRuntimeContext,
    );
  }

  void _applyDefaults(
    PPTOptions options, {
    required bool outbound,
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    if (options.pptScheme != 'wamp') {
      return;
    }
    options.pptSerializer ??= negotiated.serializer;
    options.pptCipher ??= negotiated.cipher;
    options.pptKeyId ??= runtimeContext == null
        ? null
        : _keySelectionPolicy(runtimeContext, options);
    options.pptKeyId ??= outbound
        ? negotiated.outboundKeyId
        : negotiated.inboundKeyId;
  }

  WampE2eeRuntimeContext? _mergeRuntimeContext(
    WampE2eeRuntimeContext? runtimeContext,
  ) {
    if (runtimeContext == null) {
      return null;
    }
    return runtimeContext.copyWith(
      realm: runtimeContext.realm ?? realm,
      local: runtimeContext.local ?? local,
      negotiated:
          runtimeContext.negotiated ??
          Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(negotiated.raw),
          ),
    );
  }
}

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, entryValue) => MapEntry(key.toString(), entryValue));
  }
  return null;
}

abstract class _PendingCall {
  String get procedure;

  bool addResult(Result result);

  void addError(Object error, [StackTrace? stackTrace]);

  Future<void> close();
}

class _PendingCallStream implements _PendingCall {
  _PendingCallStream({required this.procedure, required this.controller});

  @override
  final String procedure;

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
  _PendingCallLazyPayloadFuture({
    required this.procedure,
    required this.completer,
  });

  @override
  final String procedure;

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
  _PendingInvocationResponder({
    required this.isClosed,
    required this.cancel,
    required this.timeout,
  });

  final bool Function() isClosed;
  final void Function(String? mode) cancel;
  final void Function() timeout;
  Timer? _timeoutTimer;
  int? _timeoutMilliseconds;

  void armTimeout(int? timeoutMilliseconds) {
    _timeoutTimer?.cancel();
    _timeoutMilliseconds = timeoutMilliseconds;
    if (timeoutMilliseconds == null || timeoutMilliseconds <= 0) {
      _timeoutTimer = null;
      return;
    }
    _timeoutTimer = Timer(Duration(milliseconds: timeoutMilliseconds), () {
      if (!isClosed()) {
        timeout();
      }
    });
  }

  void resetTimeout() {
    armTimeout(_timeoutMilliseconds);
  }

  void dispose() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
}

class _PendingSubscribe {
  _PendingSubscribe({required this.topic, required this.completer});

  final String topic;
  final Completer<Subscribed> completer;
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

Map<String, dynamic>? _copyStringDynamicMap(Map<String, dynamic>? value) {
  if (value == null) {
    return null;
  }
  return Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(value));
}

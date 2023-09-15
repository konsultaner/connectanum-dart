import 'dart:async';

import 'package:logging/logging.dart';

import '../message/abort.dart';
import '../message/abstract_message.dart';
import '../message/abstract_message_with_payload.dart';
import '../message/authenticate.dart';
import '../message/cancel.dart';
import '../message/challenge.dart';
import '../message/goodbye.dart';
import '../message/message_types.dart';
import '../message/unsubscribed.dart';
import '../message/welcome.dart';
import '../message/uri_pattern.dart';
import '../message/details.dart' as details_package;
import '../message/call.dart';
import '../message/event.dart';
import '../message/hello.dart';
import '../message/invocation.dart';
import '../message/publish.dart';
import '../message/published.dart';
import '../message/register.dart';
import '../message/registered.dart';
import '../message/result.dart';
import '../message/subscribe.dart';
import '../message/subscribed.dart';
import '../message/unregister.dart';
import '../message/unregistered.dart';
import '../message/unsubscribe.dart';
import '../message/error.dart';
import '../transport/abstract_transport.dart';
import '../authentication/abstract_authentication.dart';
import '../message/e2ee_payload.dart';
import '../message/ppt_payload.dart';

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
  final _openSessionStreamController = StreamController.broadcast();

  Session(this.realm, this._transport)

      /// The realm object my be null but must mach the uri pattern if it was
      /// passed The connection should have been established before initializing
      /// the session.
      : assert(realm == null || UriPattern.match(realm), _transport.isOpen);

  /// Starting the session will also start the authentication process.
  static Future<Session> start(String? realm, AbstractTransport transport,
      {String? authId,
      String? authRole,
      Map<String, dynamic>? authExtra,
      List<AbstractAuthentication>? authMethods,
      Duration? reconnect}) async {
    /// Initialize the session object with the realm it belongs to
    final session = Session(realm, transport);

    /// Initialize the sub protocol with a hello message
    final hello = Hello(realm, details_package.Details.forHello());
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

    /// Either return the welcome or execute a challenge before and eventually return the welcome after this
    var welcomeCompleter = Completer<Session>();
    session._transportStreamSubscription = transport.receive()!.listen(
        (message) {
          if (message is Challenge) {
            final foundAuthMethod = authMethods
                ?.where((authenticationMethod) =>
                    authenticationMethod.getName() == message.authMethod)
                .first;
            if (foundAuthMethod != null) {
              try {
                foundAuthMethod
                    .challenge(message.extra)
                    .then((authenticate) => session.authenticate(authenticate),
                        onError: (error) {
                  session._transport.send(Abort(Error.authorizationFailed,
                      message: error.toString()));
                  session._transport.close();
                });
              } catch (exception) {
                try {
                  transport.close();
                } catch (ignore) {/* my be already closed */}
                welcomeCompleter.completeError(Abort(Error.authorizationFailed,
                    message: exception.toString()));
              }
            } else {
              final goodbye = Goodbye(
                  GoodbyeMessage('Authmethod $foundAuthMethod not supported'),
                  Goodbye.reasonGoodbyeAndOut);
              session._transport.send(goodbye);
              welcomeCompleter.completeError(goodbye);
            }
          } else if (message is Welcome) {
            session.id = message.sessionId;

            if ((session.realm ?? message.details.realm) == null) {
              welcomeCompleter.completeError(Abort(Error.authorizationFailed,
                  message:
                      'No realm specified! Neither by the client nor by the router'));
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
            session._transportStreamSubscription.onData((message) {
              session._openSessionStreamController.add(message);
            });
            session._transportStreamSubscription.onDone(() {
              session._openSessionStreamController.close();
            });
            welcomeCompleter.complete(session);
          } else if (message is Abort) {
            try {
              transport.close();
            } catch (ignore) {/* my be already closed */}
            welcomeCompleter.completeError(message);
          } else if (message is Goodbye) {
            try {
              transport.close();
            } catch (ignore) {/* my be already closed */}
          }
        },
        cancelOnError: true,
        onError: (error) {
          _logger.warning(error);
          transport.close(error: error);
        },
        onDone: () => transport.close());
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
    return _transport.isReady && !_openSessionStreamController.isClosed;
  }

  /// This sends the [authenticate] message to the transport outgoing stream.
  void authenticate(Authenticate authenticate) {
    _transport.send(authenticate);
  }

  /// This calls a [procedure] with the given [arguments] and/or [argumentsKeywords]
  /// with the given [options]. The WAMP router will either respond with one or
  /// more results or the caller may cancel the call by calling [cancelCompleter.complete()].
  Stream<Result> call(String procedure,
      {List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords,
      CallOptions? options,
      Completer<String>? cancelCompleter}) async* {
    var callArguments = arguments;
    var callArgumentsKeywords = argumentsKeywords;

    if (options?.pptScheme == 'wamp') {
      // It's E2EE payload
      callArguments =
          E2EEPayload.packE2EEPayload(arguments, argumentsKeywords, options!);
      callArgumentsKeywords = null;
    } else if (options?.pptScheme != null) {
      // It's some variation of PPT
      callArguments =
          PPTPayload.packPPTPayload(arguments, argumentsKeywords, options!);
      callArgumentsKeywords = null;
    }

    var call = Call(nextCallId++, procedure,
        arguments: callArguments,
        argumentsKeywords: callArgumentsKeywords,
        options: options);
    _transport.send(call);
    if (cancelCompleter != null) {
      unawaited(cancelCompleter.future.then((cancelMode) {
        CancelOptions? options;
        if (CancelOptions.modeKillNoWait == cancelMode ||
            CancelOptions.modeKill == cancelMode ||
            CancelOptions.modeSkip == cancelMode) {
          options = CancelOptions();
          options.mode = cancelMode;
        }
        var cancel = Cancel(call.requestId, options: options);
        _transport.send(cancel);
      }));
    }
    await for (AbstractMessageWithPayload result
        in _openSessionStreamController.stream.where((message) =>
            (message is Result && message.callRequestId == call.requestId) ||
            (message is Error &&
                message.requestTypeId == MessageTypes.codeCall &&
                message.requestId == call.requestId))) {
      if (result is Result) {
        yield result;
        if (!result.isProgressive()) {
          break;
        }
      } else if (result is Error) {
        throw result;
      }
    }
  }

  /// This subscribes the session to a [topic]. The subscriber may pass [options]
  /// while subscribing. The resulting events are passed to the [Subscribed.eventStream].
  /// The subscriber should therefore subscribe to that stream to receive the events.
  Future<Subscribed> subscribe(String topic,
      {SubscribeOptions? options}) async {
    var subscribe = Subscribe(nextSubscribeId++, topic, options: options);
    _transport.send(subscribe);
    AbstractMessage subscribed = await _openSessionStreamController.stream
        .where((message) =>
            (message is Subscribed &&
                message.subscribeRequestId == subscribe.requestId) ||
            (message is Error &&
                message.requestTypeId == MessageTypes.codeSubscribe &&
                message.requestId == subscribe.requestId))
        .first;
    if (subscribed is Subscribed) {
      subscriptions[subscribed.subscriptionId] = subscribed;
      subscribed.eventStream =
          _openSessionStreamController.stream.where((message) {
        if (message is Unsubscribed &&
            message.details?.subscription == subscribed.subscriptionId) {
          subscriptions.remove(subscribed.subscriptionId);
          subscribed.revoke(message.details!.reason);
          return false;
        }
        return message is Event &&
            subscriptions[subscribed.subscriptionId] != null &&
            message.subscriptionId == subscribed.subscriptionId;
      }).map((event) {
        var eventUpdated = event;

        if (event.details.pptScheme == 'wamp') {
          // It's E2EE payload
          var e2eePayload =
              E2EEPayload.unpackE2EEPayload(event.arguments, event.details);

          event.arguments = e2eePayload.arguments;
          event.argumentsKeywords = e2eePayload.argumentsKeywords;
        } else if (event.details.pptScheme != null) {
          // It's some variation of PPT
          var pptPayload =
              PPTPayload.unpackPPTPayload(event.arguments, event.details);

          event.arguments = pptPayload.arguments;
          event.argumentsKeywords = pptPayload.argumentsKeywords;
        }
        return eventUpdated;
      }).cast();
      return subscribed;
    } else {
      throw subscribed;
    }
  }

  /// This unsubscribes the session from a subscription. Use the [Subscribed.subscriptionId]
  /// to unsubscribe.
  Future<void> unsubscribe(int subscriptionId) async {
    var unsubscribe = Unsubscribe(nextUnsubscribeId++, subscriptionId);
    _transport.send(unsubscribe);
    await _openSessionStreamController.stream.where((message) {
      if (message is Unsubscribed &&
          message.unsubscribeRequestId == unsubscribe.requestId) {
        return true;
      }
      if (message is Error &&
          message.requestTypeId == MessageTypes.codeUnsubscribe &&
          message.requestId == unsubscribe.requestId) {
        throw message;
      }
      return false;
    }).first;
    subscriptions.remove(subscriptionId);
  }

  /// This publishes an event to a [topic] with the given [arguments] and [argumentsKeywords].
  Future<Published?> publish(String topic,
      {List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords,
      PublishOptions? options}) {
    var pubArguments = arguments;
    var pubArgumentsKeywords = argumentsKeywords;

    if (options?.pptScheme == 'wamp') {
      // It's E2EE payload
      pubArguments =
          E2EEPayload.packE2EEPayload(arguments, argumentsKeywords, options!);
      pubArgumentsKeywords = null;
    } else if (options?.pptScheme != null) {
      // It's some variation of PPT
      pubArguments =
          PPTPayload.packPPTPayload(arguments, argumentsKeywords, options!);
      pubArgumentsKeywords = null;
    }

    var publish = Publish(nextPublishId++, topic,
        arguments: pubArguments,
        argumentsKeywords: pubArgumentsKeywords,
        options: options);
    _transport.send(publish);
    if (options?.acknowledge == null || options?.acknowledge == false) {
      return Future.value(null);
    }
    var publishStream = _openSessionStreamController.stream.where((message) {
      if (message is Published &&
          message.publishRequestId == publish.requestId) {
        return true;
      }
      if (message is Error &&
          message.requestTypeId == MessageTypes.codePublish &&
          message.requestId == publish.requestId) {
        throw message;
      }
      return false;
    }).cast<Published>();
    return publishStream.first;
  }

  /// This registers a [procedure] with the given [options] that may be called
  /// by other sessions.
  Future<Registered> register(String procedure,
      {RegisterOptions? options}) async {
    var register = Register(nextRegisterId++, procedure, options: options);
    _transport.send(register);
    AbstractMessage registered = await _openSessionStreamController.stream
        .where((message) =>
            (message is Registered &&
                message.registerRequestId == register.requestId) ||
            (message is Error &&
                message.requestTypeId == MessageTypes.codeRegister &&
                message.requestId == register.requestId))
        .first;
    if (registered is Registered) {
      registrations[registered.registrationId] = registered;
      registered.procedure = procedure;
      registered.invocationStream =
          _openSessionStreamController.stream.where((message) {
        if (message is Invocation &&
            message.registrationId == registered.registrationId) {
          // Check if there is a registration that has not been unregistered yet
          if (registrations[registered.registrationId] != null) {
            message.onResponse((message) => _transport.send(message));
            return true;
          } else {
            _transport.send(Error(MessageTypes.codeInvocation,
                message.requestId, {}, Error.noSuchRegistration));
            return false;
          }
        }
        return false;
      }).cast();
      return registered;
    } else {
      throw (registered as Error?)!;
    }
  }

  /// This unregisters a procedure by its [registrationId]. Use the [Registered.registrationId]
  /// to unregister.
  Future<void> unregister(int registrationId) async {
    var unregister = Unregister(nextUnregisterId++, registrationId);
    _transport.send(unregister);
    await _openSessionStreamController.stream.where((message) {
      if (message is Unregistered &&
          message.unregisterRequestId == unregister.requestId) {
        return true;
      }
      if (message is Error &&
          message.requestTypeId == MessageTypes.codeUnregister &&
          message.requestId == unregister.requestId) {
        throw message;
      }
      return false;
    }).first;
    registrations.remove(registrationId);
  }

  /// Sends a goodbye message and closes the transport after a given [timeout].
  /// If no timeout is set, the client waits for the server to close the transport forever.
  Future<void> close({String message = 'Regular closing', Duration? timeout}) {
    final goodbye =
        Goodbye(GoodbyeMessage(message), Goodbye.reasonGoodbyeAndOut);
    _transport.send(goodbye);
    if (timeout != null) {
      return Future.delayed(timeout, () => _transport.close());
    }
    return Future.value();
  }
}

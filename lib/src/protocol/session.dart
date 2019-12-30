import 'dart:async';
import 'dart:collection';

import 'package:connectanum_dart/src/message/abort.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/goodbye.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/unsubscribed.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:connectanum_dart/src/protocol/session_model.dart';
import 'package:connectanum_dart/src/message/uri_pattern.dart';
import 'package:rxdart/rxdart.dart';
import 'package:rxdart/subjects.dart';

import 'protocol_processor.dart';
import '../message/details.dart' as detailsPackage;
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

class Session extends SessionModel {

  ProtocolProcessor _protocolProcessor = new ProtocolProcessor();
  AbstractTransport _transport;

  int nextCallId = 1;
  int nextPublishId = 1;
  int nextSubscribeId = 1;
  int nextUnsubscribeId = 1;
  int nextRegisterId = 1;
  int nextUnregisterId = 1;

  final Map<int, Registered> registrations = {};

  final Map<int, BehaviorSubject<Subscribed>> subscribes = new HashMap();
  final Map<int, BehaviorSubject<Unsubscribed>> unsubscribes = new HashMap();
  final Map<int, BehaviorSubject<Published>> publishes = new HashMap();
  final Map<int, BehaviorSubject<Event>> events = new HashMap();

  StreamSubscription<AbstractMessage> _transportStreamSubscription;
  StreamController _openSessionStreamController = new StreamController.broadcast();

  ProtocolProcessor get protocolProcessor => _protocolProcessor;

  static Future<Session> start(
      String realm,
      AbstractTransport transport,
      {
        String authId: null,
        List<AbstractAuthentication> authMethods: null,
        Duration reconnect: null
      }
  ) async
  {
    /**
     * The realm object is mandatory and must mach the uri pattern
     */
    assert(realm != null && UriPattern.match(realm));
    /**
     * The connection should have been established before initializing the
     * session.
     */
    assert(transport != null && transport.isOpen());

    /**
     * Initialize the session object with the realm it belongs to
     */
    final session = new Session();
    session.realm = realm;
    session._transport = transport;

    /**
     * Initialize the sub protocol with a hello message
     */
    final hello = new Hello(realm, detailsPackage.Details.forHello());
    if (authId != null) {
      hello.details.authid = authId;
    }
    if (authMethods != null && authMethods.length > 0) {
      hello.details.authmethods = authMethods.map<String>((authMethod) => authMethod.getName()).toList();
    }
    transport.send(hello);

    /**
     * Either return the welcome or execute a challenge before and eventually return the welcome after this
     */
    Completer<Session> welcomeCompleter = new Completer<Session>();
    session._transportStreamSubscription = transport.receive().listen((message) {
      if (message is Challenge) {
        final AbstractAuthentication foundAuthMethod = authMethods.where((authenticationMethod) => authenticationMethod.getName() == message.authMethod).first;
        if (foundAuthMethod != null) {
          foundAuthMethod.challenge(message.extra).then((authenticate) => session.authenticate(authenticate));
        } else {
          final goodbye = new Goodbye(new GoodbyeMessage("Authmethod ${foundAuthMethod} not supported"), Goodbye.REASON_GOODBYE_AND_OUT);
          session._transport.send(goodbye);
          throw goodbye;
        }
      } else if (message is Welcome) {
        session.id = message.sessionId;
        session.authId = message.details.authid;
        session.authMethod = message.details.authmethod;
        session.authProvider = message.details.authprovider;
        session.authRole = message.details.authrole;
        session._transportStreamSubscription.onData((message) {
          session._openSessionStreamController.add(message);
        });
        session._transportStreamSubscription.onDone(() {
          session._openSessionStreamController.close();
        });
        welcomeCompleter.complete(session);
      } else if (message is Abort) {
        welcomeCompleter.completeError(message);
      } else if (message is Goodbye) {
        try {
          transport.close();
        } catch (ignore) {/* my be already closed */}
      }
    }, cancelOnError: true);
    return welcomeCompleter.future;
  }

  bool isConnected() {
    return this._transport != null && this._transport.isOpen() && this._openSessionStreamController != null && !this._openSessionStreamController.isClosed;
  }

  authenticate(Authenticate authenticate) {
    this._transport.send(authenticate);
  }

  Stream<Result> call(String procedure,
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      CallOptions options}) async* {
    Call call = new Call(nextCallId++, procedure,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        options: options);
    this._transport.send(call);
    await for(AbstractMessageWithPayload result in this._openSessionStreamController.stream.where(
            (message) => (message is Result && message.callRequestId == call.requestId) ||
            (message is Error && message.requestTypeId == MessageTypes.CODE_CALL && message.requestId == call.requestId)
    )) {
      if (result is Result) {
        yield result;
      } else if (result is Error) {
        throw result;
      }
    }
  }

  /**
   * The events are passed to the {@see Subscribed#events subject}
   */
  subscribe(String topic, {SubscribeOptions options}) {
    Subscribe subscribe =
        new Subscribe(nextSubscribeId++, topic, options: options);
    subscribes[subscribe.requestId] = new BehaviorSubject();
    return subscribes[subscribe.requestId].map((subscribed) {
      subscribed.eventStream = new BehaviorSubject();
      events[subscribed.subscriptionId] = subscribed.eventStream;
      return subscribed;
    }).doOnEach((notification) {
      subscribes.remove(subscribe.requestId);
    }).take(1);
  }

  unsubscribe(int subscriptionId) {
    Unsubscribe unsubscribe =
        new Unsubscribe(nextUnsubscribeId++, subscriptionId);
    unsubscribes[unsubscribe.requestId] = new BehaviorSubject();
    return unsubscribes[unsubscribe.requestId].doOnEach((notification) {
      unsubscribes.remove(unsubscribe.requestId);
    }).take(1);
  }

  publish(String topic,
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      PublishOptions options}) {
    Publish publish = new Publish(nextPublishId++, topic,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        options: options);
    publishes[publish.requestId] = new BehaviorSubject();
    return publishes[publish.requestId].doOnEach((notification) {
      publishes.remove(publish.requestId);
    }).take(1);
  }

  Future<Registered> register(String procedure, {RegisterOptions options}) async {
    Register register = new Register(nextRegisterId++, procedure, options: options);
    this._transport.send(register);
    AbstractMessage registered = await this._openSessionStreamController.stream.where(
            (message) => (message is Registered && message.registerRequestId == register.requestId) ||
            (message is Error && message.requestTypeId == MessageTypes.CODE_REGISTER && message.requestId == register.requestId)
    ).first;
    if (registered is Registered) {
      registrations[registered.registrationId] = registered;
      registered.procedure = procedure;
      registered.invocationStream = this._openSessionStreamController.stream.where(
          (message) {
            if (message is Invocation && message.registrationId == registered.registrationId) {
              // Check if there is a registration that has not been unregistered yet
              if (registrations[registered.registrationId] != null) {
                message.onResponse((message) => this._transport.send(message));
                return true;
              } else {
                this._transport.send(new Error(MessageTypes.CODE_INVOCATION, message.requestId, {}, Error.NO_SUCH_REGISTRATION));
                return false;
              }
            }
            return false;
          }
      ).cast();
      return registered;
    } else throw registered as Error;
  }

  unregister(int registrationId) async {
    Unregister unregister = new Unregister(nextUnregisterId++, registrationId);
    this._transport.send(unregister);
    await this._openSessionStreamController.stream.where(
        (message) => message is Unregistered && message.unregisterRequestId == unregister.requestId
    ).first;
    registrations.remove(registrationId);
  }

  void setInvocationTransportChannel(Invocation message) {
    message.onResponse((AbstractMessageWithPayload invocationResultMessage) {
      _transport.send(invocationResultMessage);
    });
  }
}

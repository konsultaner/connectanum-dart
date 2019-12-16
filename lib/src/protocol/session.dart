import 'dart:async';
import 'dart:collection';

import 'package:connectanum_dart/src/message/authenticate.dart';
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
import '../message/unsubscribed.dart';
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

  final Map<int, BehaviorSubject<Result>> calls = new HashMap();
  final Map<int, BehaviorSubject<Subscribed>> subscribes = new HashMap();
  final Map<int, BehaviorSubject<Unsubscribed>> unsubscribes = new HashMap();
  final Map<int, BehaviorSubject<Published>> publishes = new HashMap();
  final Map<int, BehaviorSubject<Registered>> registers = new HashMap();
  final Map<int, BehaviorSubject<Unregistered>> unregisters = new HashMap();
  final Map<int, BehaviorSubject<Event>> events = new HashMap();
  final Map<int, BehaviorSubject<Invocation>> invocations = new HashMap();

  BehaviorSubject<SessionModel> get authenticateSubject => _protocolProcessor.authenticateSubject;
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
    final completer = new Completer<Session>();
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
     * If an authentication process is successful the session should be filled
     * with all session information.
     */
    session.authenticateSubject.listen((sessionModel) {
      session.id = sessionModel.id;
      session.authId = sessionModel.authId;
      session.authMethod = sessionModel.authMethod;
      session.authProvider = sessionModel.authProvider;
      session.authRole = sessionModel.authRole;
      completer.complete(session);
    });

    /**
     * If the transport receives new messages the sessions protocol processor
     * should receive the message
     */
    transport.onMessage((message) {
      session.protocolProcessor.process(message, session, authMethods);
    });

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
    return completer.future;
  }

  authenticate(Authenticate authenticate) {
    this._transport.send(authenticate);
  }

  call(String procedure,
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      CallOptions options}) {
    Call call = new Call(nextCallId++, procedure,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        options: options);
    calls[call.requestId] = new BehaviorSubject();
    return calls[call.requestId].doOnEach((notification) {
      calls.remove(call.requestId);
      if (notification.isOnData) {
        if (!notification.value.isProgressive()) {
          calls[call.requestId].close();
          calls.remove(call.requestId);
        } else if (notification.isOnError) {
          calls[call.requestId].close();
          calls.remove(call.requestId);
        }
      }
    });
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

  Observable<Registered> register(String procedure, {RegisterOptions options}) {
    Register register =
        new Register(nextRegisterId++, procedure, options: options);
    registers[register.requestId] = new BehaviorSubject();
    final observable = registers[register.requestId].map((registered) {
      registered.invocationStream = new BehaviorSubject();
      invocations[registered.registrationId] = registered.invocationStream;
      return registered;
    }).doOnEach((notification) {
      registers.remove(register.requestId);
    }).take(1);
    this._transport.send(register);
    return observable;
  }

  unregister(int registrationId) {
    Unregister unregister = new Unregister(nextUnregisterId++, registrationId);
    unregisters[unregister.requestId] = new BehaviorSubject();
    return unregisters[unregister.requestId].map((unregister) {
      invocations[registrationId].close();
      invocations.remove(registrationId);
    }).doOnEach((notification) {
      unregisters.remove(unregister.requestId);
    }).take(1);
  }
}

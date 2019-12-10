import 'dart:collection';

import 'package:rxdart/subjects.dart';

import '../../protocol_processor.dart';
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
import 'abstract_authentication.dart';
import 'basic_authentication.dart';

class Session {
  int id;
  String realm;
  String authId;
  String authRole;
  String authMethod;
  String authProvider;

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

  //factory Session.start(String authId, String realm, AbstractTransport transport, {AbstractAuthentication authMethods: null,Duration reconnect: null}) {
  //  if (authMethods == null) {
  //    authMethods = new BasicAuthentication();
  //  }
  //  transport.onMessage((message) {
  //    ProtocolProcessor().process(message);
  //  });
  //  transport.send(Hello());
  //}

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

  register(String procedure, {RegisterOptions options}) {
    Register register =
        new Register(nextRegisterId++, procedure, options: options);
    registers[register.requestId] = new BehaviorSubject();
    return registers[register.requestId].map((registered) {
      registered.invocationStream = new BehaviorSubject();
      invocations[registered.registrationId] = registered.invocationStream;
      return registered;
    }).doOnEach((notification) {
      registers.remove(register.requestId);
    }).take(1);
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

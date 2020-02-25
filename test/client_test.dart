import 'dart:async';
import 'dart:collection';

import 'package:connectanum/src/authentication/cra_authentication.dart';
import 'package:connectanum/src/client.dart';
import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/abstract_message.dart';
import 'package:connectanum/src/message/authenticate.dart';
import 'package:connectanum/src/message/call.dart';
import 'package:connectanum/src/message/cancel.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/event.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/register.dart';
import 'package:connectanum/src/message/registered.dart';
import 'package:connectanum/src/message/invocation.dart';
import 'package:connectanum/src/message/result.dart';
import 'package:connectanum/src/message/subscribe.dart';
import 'package:connectanum/src/message/subscribed.dart';
import 'package:connectanum/src/message/unregister.dart';
import 'package:connectanum/src/message/unregistered.dart';
import 'package:connectanum/src/message/unsubscribe.dart';
import 'package:connectanum/src/message/unsubscribed.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/message/yield.dart';
import 'package:connectanum/src/transport/abstract_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Client', () {
    test("session creation without authentication process", () async {
      final transport = _MockTransport();
      final client = Client(realm: "test.realm", transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(
              42,
              Details.forWelcome(
                  authId: "Richi",
                  authMethod: "none",
                  authProvider: "noProvider",
                  authRole: "client")));
        }
      });
      final session = await client.connect();
      expect(session.realm, equals("test.realm"));
      expect(session.id, equals(42));
      expect(session.authId, equals("Richi"));
      expect(session.authRole, equals("client"));
      expect(session.authProvider, equals("noProvider"));
      expect(session.authMethod, equals("none"));
    });
    test("session creation router abort", () async {
      final transport = _MockTransport();
      final client = Client(realm: "test.realm", transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Abort(Error.NO_SUCH_REALM,
              message: "The given realm is not valid"));
        }
      });
      Completer abortCompleter = Completer<Abort>();
      client.connect().catchError((abort) => abortCompleter.complete(abort));
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.NO_SUCH_REALM));
      expect(abort.message.message, equals("The given realm is not valid"));
      expect(transport.isOpen, isFalse);
    });
    test("session creation with cra authentication process", () async {
      final transport = _MockTransport();
      final client = Client(
          realm: "test.realm",
          transport: transport,
          authId: "11111111",
          authenticationMethods: [CraAuthentication("3614")]);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Challenge(
              (message as Hello).details.authmethods[0],
              Extra(
                  challenge:
                      "{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}",
                  keylen: 32,
                  iterations: 1000,
                  salt: "gbnk5ji1b0dgoeavu31er567nb")));
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE &&
            (message as Authenticate).signature ==
                "APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=") {
          transport.receiveMessage(Welcome(
              586844620777222,
              Details.forWelcome(
                  authId: "11111111",
                  authMethod: "wampcra",
                  authProvider: "cra",
                  authRole: "client")));
        }
      });
      final session = await client.connect();
      expect(session.realm, equals("test.realm"));
      expect(session.id, equals(586844620777222));
      expect(session.authId, equals("11111111"));
      expect(session.authRole, equals("client"));
      expect(session.authProvider, equals("cra"));
      expect(session.authMethod, equals("wampcra"));
    });
    test("session creation with cra authentication process and router abort",
        () async {
      final transport = _MockTransport();
      final client = Client(
          realm: "test.realm",
          transport: transport,
          authId: "11111111",
          authenticationMethods: [CraAuthentication("3614")]);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Challenge(
              (message as Hello).details.authmethods[0],
              Extra(
                  challenge:
                      "{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}",
                  keylen: 32,
                  iterations: 1000,
                  salt: "gbnk5ji1b0dgoeavu31er567nb")));
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE) {
          transport.receiveMessage(Abort(Error.AUTHORIZATION_FAILED,
              message: "Wrong user credentials"));
        }
      });
      Completer abortCompleter = Completer<Abort>();
      client.connect().catchError((abort) => abortCompleter.complete(abort));
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(abort.message.message, equals("Wrong user credentials"));
      expect(transport.isOpen, isFalse);
    });
    test("procedure registration and invocation", () async {
      final transport = _MockTransport();
      final client = Client(realm: "test.realm", transport: transport);

      final yieldCompleter = Completer<Yield>();
      final progressiveCallYieldCompleter = Completer<Yield>();
      final error1completer = Completer<Error>();
      final error2completer = Completer<Error>();
      final error3completer = Completer<Error>();

      // ALL ROUTER MOCK RESULTS
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        }
        if (message.id == MessageTypes.CODE_REGISTER) {
          if ((message as Register).procedure == "my.procedure") {
            transport.receiveMessage(
                Registered((message as Register).requestId, 1010));
          }
          if ((message as Register).procedure == "my.error") {
            transport.receiveMessage(Error(MessageTypes.CODE_REGISTER,
                (message as Register).requestId, {}, Error.NOT_AUTHORIZED));
          }
        }
        if (message.id == MessageTypes.CODE_UNREGISTER) {
          if ((message as Unregister).registrationId > 0) {
            transport.receiveMessage(
                Unregistered((message as Unregister).requestId));
          } else {
            transport.receiveMessage(Error(
                MessageTypes.CODE_UNREGISTER,
                (message as Unregister).requestId,
                {},
                Error.NO_SUCH_REGISTRATION));
          }
        }
        if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).argumentsKeywords["value"] != -3) {
          transport.receiveMessage(Result(
              (message as Call).requestId, ResultDetails(true),
              arguments: (message as Call).arguments));
          transport.receiveMessage(Result(
              (message as Call).requestId, ResultDetails(false),
              argumentsKeywords: (message as Call).argumentsKeywords));
        }
        if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).argumentsKeywords["value"] == -3) {
          transport.receiveMessage(Error(
              MessageTypes.CODE_CALL,
              (message as Call).requestId,
              HashMap(),
              Error.NO_SUCH_REGISTRATION,
              arguments: (message as Call).arguments,
              argumentsKeywords: (message as Call).argumentsKeywords));
        }
        if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).argumentsKeywords["value"] == -4) {
          // ignored because it will not complete before cancelation happens
        }
        if (message.id == MessageTypes.CODE_CANCEL) {
          transport.receiveMessage(Error(
              MessageTypes.CODE_CALL,
              (message as Cancel).requestId,
              HashMap(),
              Error.ERROR_INVOCATION_CANCELED,
              arguments: [(message as Cancel).options.mode]));
        }
        if (message.id == MessageTypes.CODE_YIELD &&
            (message as Yield).argumentsKeywords["value"] == 0) {
          yieldCompleter.complete(message as Yield);
        }
        if (message.id == MessageTypes.CODE_YIELD &&
            (message as Yield).argumentsKeywords["progressiveCalls"] != null) {
          progressiveCallYieldCompleter.complete(message as Yield);
        }
        if (message.id == MessageTypes.CODE_ERROR &&
            (message as Error).error == Error.UNKNOWN) {
          error1completer.complete(message as Error);
        }
        if (message.id == MessageTypes.CODE_ERROR &&
            (message as Error).error == Error.NOT_AUTHORIZED) {
          error2completer.complete(message as Error);
        }
        if (message.id == MessageTypes.CODE_ERROR &&
            (message as Error).error == Error.NO_SUCH_REGISTRATION) {
          error3completer.complete(message as Error);
        }
      });

      final session = await client.connect();
      final registrationErrorCompleter = Completer<Error>();

      // NOT WORKING REGISTRATION

      session.register("my.error").then((registered) {}, onError: (error) {
        registrationErrorCompleter.complete(error);
      });

      final registrationError = await registrationErrorCompleter.future;
      expect(registrationError, isNotNull);
      expect(
          registrationError.requestTypeId, equals(MessageTypes.CODE_REGISTER));
      expect(registrationError.id, equals(MessageTypes.CODE_ERROR));

      // WORKING REGISTRATION

      final registered = await session.register("my.procedure");
      expect(registered, isNotNull);
      expect(registered.registrationId, equals(1010));

      int progressiveCalls = 0;
      registered.onInvoke((invocation) {
        if (invocation.argumentsKeywords["value"] == 0) {
          invocation.respondWith(
              arguments: invocation.arguments,
              argumentsKeywords: invocation.argumentsKeywords);
        }
        if (invocation.argumentsKeywords["value"] == 1) {
          progressiveCalls++;
          if (!invocation.isProgressive()) {
            invocation.argumentsKeywords["progressiveCalls"] = progressiveCalls;
            invocation.respondWith(
                arguments: invocation.arguments,
                argumentsKeywords: invocation.argumentsKeywords);
          }
        }
        if (invocation.argumentsKeywords["value"] == -1) {
          throw Exception("Something went wrong");
        }
        if (invocation.argumentsKeywords["value"] == -2) {
          invocation.respondWith(
              isError: true,
              errorUri: Error.NOT_AUTHORIZED,
              arguments: invocation.arguments,
              argumentsKeywords: invocation.argumentsKeywords);
        }
      });

      // REGULAR RESULT

      final argumentsKeywords = HashMap<String, Object>();
      argumentsKeywords["value"] = 0;
      transport.receiveMessage(Invocation(11001100,
          registered.registrationId, InvocationDetails(null, null, false),
          arguments: ["did work"], argumentsKeywords: argumentsKeywords));
      final yieldMessage = await yieldCompleter.future;
      expect(yieldMessage, isNotNull);
      expect(yieldMessage.argumentsKeywords["value"], equals(0));
      expect(yieldMessage.arguments[0], equals("did work"));

      // PROGRESSIVE CALL

      final progressiveArgumentsKeywords = HashMap<String, Object>();
      progressiveArgumentsKeywords["value"] = 1;
      transport.receiveMessage(Invocation(21001100,
          registered.registrationId, InvocationDetails(null, null, true),
          arguments: ["did work?"],
          argumentsKeywords: progressiveArgumentsKeywords));
      transport.receiveMessage(Invocation(21001101,
          registered.registrationId, InvocationDetails(null, null, false),
          arguments: ["did work again"],
          argumentsKeywords: progressiveArgumentsKeywords));
      final finalYieldMessage = await progressiveCallYieldCompleter.future;
      expect(finalYieldMessage, isNotNull);
      expect(finalYieldMessage.argumentsKeywords["value"], equals(1));
      expect(
          finalYieldMessage.argumentsKeywords["progressiveCalls"], equals(2));
      expect(finalYieldMessage.arguments[0], equals("did work again"));

      // PROGRESSIVE RESULT

      final progressiveCallArgumentsKeywords = HashMap<String, Object>();
      progressiveArgumentsKeywords["value"] = 2;
      final callCompleter = Completer<List<Result>>();
      final List<Result> resultList = [];
      session
          .call("my.procedure",
              options: CallOptions(receive_progress: true),
              arguments: ["called"],
              argumentsKeywords: progressiveCallArgumentsKeywords)
          .listen((result) {
        resultList.add(result);
        if (!result.isProgressive()) {
          callCompleter.complete(resultList);
        }
      });
      await callCompleter.future;
      expect(resultList.length, equals(2));

      // ERROR BY EXCEPTION

      final argumentsKeywords2 = HashMap<String, Object>();
      argumentsKeywords2["value"] = -1;
      transport.receiveMessage(Invocation(11001101,
          registered.registrationId, InvocationDetails(null, null, false),
          arguments: ["did work"], argumentsKeywords: argumentsKeywords2));
      final error1 = await error1completer.future;
      expect(error1.requestTypeId, equals(MessageTypes.CODE_INVOCATION));
      expect(error1.requestId, equals(11001101));
      expect(error1, isNotNull);
      expect(error1.error, equals(Error.UNKNOWN));
      expect(error1.arguments[0], equals("Exception: Something went wrong"));

      // ERROR BY HANDLER

      final argumentsKeywords3 = HashMap<String, Object>();
      argumentsKeywords3["value"] = -2;
      transport.receiveMessage(Invocation(11001102,
          registered.registrationId, InvocationDetails(null, null, false),
          arguments: ["did work"], argumentsKeywords: argumentsKeywords3));
      final error2 = await error2completer.future;
      expect(error2, isNotNull);
      expect(error2.requestTypeId, equals(MessageTypes.CODE_INVOCATION));
      expect(error2.requestId, equals(11001102));
      expect(error2.error, equals(Error.NOT_AUTHORIZED));
      expect(error2.arguments[0], equals("did work"));
      expect(error2.argumentsKeywords["value"], equals(-2));

      // ERROR RESULT

      final errorCallArgumentsKeywords = HashMap<String, Object>();
      errorCallArgumentsKeywords["value"] = -3;
      final errorCallCompleter = Completer<Error>();
      session
          .call("my.procedure",
              options: CallOptions(receive_progress: true),
              arguments: ["was an error"],
              argumentsKeywords: errorCallArgumentsKeywords)
          .listen((result) {},
              onError: (error) => errorCallCompleter.complete(error));
      Error callError = await errorCallCompleter.future;
      expect(callError, isNotNull);
      expect(callError.requestTypeId, equals(MessageTypes.CODE_CALL));
      expect(callError.arguments[0], equals("was an error"));
      expect(callError.argumentsKeywords["value"], equals(-3));

      // ERROR BY CANCELLATION

      final errorCallCancellation = HashMap<String, Object>();
      errorCallCancellation["value"] = -4;
      final errorCallCancellationCompleter = Completer<Error>();
      final CancellationCompleter = Completer<String>();
      session
          .call("my.procedure",
              argumentsKeywords: errorCallCancellation,
              cancelCompleter: CancellationCompleter)
          .listen((result) {},
              onError: (error) =>
                  errorCallCancellationCompleter.complete(error));
      CancellationCompleter.complete(CancelOptions.MODE_KILL_NO_WAIT);
      Error cancelError = await errorCallCancellationCompleter.future;
      expect(cancelError, isNotNull);
      expect(cancelError.requestTypeId, equals(MessageTypes.CODE_CALL));
      expect(cancelError.arguments[0], equals(CancelOptions.MODE_KILL_NO_WAIT));

      // UNREGISTER

      await session.unregister(registered.registrationId);

      final argumentsKeywordsRegular = HashMap<String, Object>();
      argumentsKeywordsRegular["value"] = 0;
      transport.receiveMessage(Invocation(11001199,
          registered.registrationId, InvocationDetails(null, null, false),
          arguments: ["did not work"],
          argumentsKeywords: argumentsKeywordsRegular));
      final error3Message = await error3completer.future;
      expect(error3Message, isNotNull);
      expect(error3Message.requestTypeId, MessageTypes.CODE_INVOCATION);
      expect(error3Message.requestId, 11001199);
      expect(error3Message.argumentsKeywords, isNull);
      expect(error3Message.arguments, isNull);

      // UNREGISTER ERROR

      final errorUnregisterCompleter = Completer<Error>();
      session.unregister(-1).then((message) {},
          onError: (error) => errorUnregisterCompleter.complete(error));
      Error unregisterError = await errorUnregisterCompleter.future;
      expect(unregisterError, isNotNull);
      expect(
          unregisterError.requestTypeId, equals(MessageTypes.CODE_UNREGISTER));
      expect(unregisterError.error, equals(Error.NO_SUCH_REGISTRATION));
    });
    test("event subscription and publish", () async {
      final transport = _MockTransport();
      final client = Client(realm: "test.realm", transport: transport);

      // ALL ROUTER MOCK RESULTS
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        }
        if (message.id == MessageTypes.CODE_SUBSCRIBE) {
          if ((message as Subscribe).topic == "topic.my.de") {
            transport.receiveMessage(
                Subscribed((message as Subscribe).requestId, 10));
          }
          if ((message as Subscribe).topic == "topic.my.error") {
            transport.receiveMessage(Error(MessageTypes.CODE_SUBSCRIBE,
                (message as Subscribe).requestId, {}, Error.NOT_AUTHORIZED));
          }
        }
        if (message.id == MessageTypes.CODE_UNSUBSCRIBE) {
          if ((message as Unsubscribe).subscriptionId == -1) {
            transport.receiveMessage(Error(
                MessageTypes.CODE_UNSUBSCRIBE,
                (message as Unsubscribe).requestId,
                {},
                Error.NO_SUCH_SUBSCRIPTION));
          } else {
            transport.receiveMessage(
                Unsubscribed((message as Unsubscribe).requestId));
          }
        }
      });
      final session = await client.connect();

      // REGULAR SUBSCRIBE

      Subscribed subscribed = await session.subscribe("topic.my.de");
      expect(subscribed, isNotNull);
      expect(subscribed.eventStream, isNotNull);
      expect(subscribed.subscribeRequestId, isNotNull);
      expect(subscribed.subscriptionId, equals(10));

      // SUBSCRIBE ERROR

      Completer<Error> subscribeErrorCompleter = Completer<Error>();
      session.subscribe("topic.my.error").then((message) {},
          onError: (error) => subscribeErrorCompleter.complete(error));
      Error subscribeError = await subscribeErrorCompleter.future;
      expect(subscribeError, isNotNull);
      expect(subscribeError.error, equals(Error.NOT_AUTHORIZED));
      expect(subscribeError.requestTypeId, equals(MessageTypes.CODE_SUBSCRIBE));

      // EVENT

      Completer<Event> eventCompleter = Completer<Event>();
      Completer<Event> eventCompleter2 = Completer<Event>();
      Completer<Event> eventCompleter3 = Completer<Event>();
      subscribed.eventStream.listen((event) {
        if (event.publicationId == 1122) {
          eventCompleter.complete(event);
        }
        if (event.publicationId == 1133) {
          eventCompleter2.complete(event);
        }
        if (event.publicationId == 1144) {
          eventCompleter3.complete(event);
        }
      });
      transport.receiveMessage(
          Event(subscribed.subscriptionId, 1122, EventDetails()));
      Event event = await eventCompleter.future;
      expect(event, isNotNull);
      expect(event.publicationId, equals(1122));

      transport.receiveMessage(
          Event(subscribed.subscriptionId, 1133, EventDetails()));
      Event event2 = await eventCompleter2.future;
      expect(event2, isNotNull);
      expect(event2.publicationId, equals(1133));

      // UNSUBSCRIBE ERROR

      Error unsubscribeError;
      try {
        await session.unsubscribe(-1);
      } on Error catch (error) {
        unsubscribeError = error;
      }
      expect(unsubscribeError, isNotNull);
      expect(unsubscribeError.error, Error.NO_SUCH_SUBSCRIPTION);

      unsubscribeError = null;
      try {
        await session.unsubscribe(subscribed.subscriptionId);
      } on Error catch (error) {
        unsubscribeError = error;
      }
      expect(unsubscribeError, isNull);

      // DO NOT RECEIVE EVENTS WHEN UNSUBSCRIBED

      transport.receiveMessage(
          Event(subscribed.subscriptionId, 1144, EventDetails()));
      Event event3;
      eventCompleter3.future.then((event) => event3 = event);
      await Future.delayed(Duration(milliseconds: 3));
      expect(event3, isNull);
    });
  });
}

class _MockTransport extends AbstractTransport {
  final StreamController<AbstractMessage> inbound = StreamController();

  bool _open = false;
  final StreamController<AbstractMessage> outbound = StreamController();

  @override
  bool get isOpen {
    return _open;
  }

  @override
  void send(AbstractMessage message) {
    outbound.add(message);
  }

  void receiveMessage(AbstractMessage message) {
    Future.delayed(
        Duration(milliseconds: 1), () => this.inbound.add(message));
  }

  @override
  Future<void> close() {
    this._open = false;
    this.inbound.close();
    return Future.value();
  }

  @override
  Future<void> open() {
    this._open = true;
    return Future.value();
  }

  @override
  Stream<AbstractMessage> receive() {
    return this.inbound.stream;
  }
}

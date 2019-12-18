import 'dart:async';
import 'dart:collection';

import 'package:connectanum_dart/src/authentication/cra_authentication.dart';
import 'package:connectanum_dart/src/client.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/call.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/details.dart';
import 'package:connectanum_dart/src/message/error.dart';
import 'package:connectanum_dart/src/message/hello.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/register.dart';
import 'package:connectanum_dart/src/message/registered.dart';
import 'package:connectanum_dart/src/message/invocation.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:connectanum_dart/src/message/yield.dart';
import 'package:connectanum_dart/src/transport/abstract_transport.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

void main() {
  group('Client', () {
    test("session creation without authentication process", () async {
      final transport = _MockTransport();
      final client = new Client(
        realm: "test.realm",
        transport: transport
      );
      transport.outbound.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receive(
              new Welcome(
                  42,
                  Details.forWelcome(
                    authId: "Richi",
                    authMethod: "none",
                    authProvider: "noProvider",
                    authRole: "client"
                  )
              )
          );
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
    test("session creation with cra authentication process", () async {
      final transport = _MockTransport();
      final client = new Client(
          realm: "test.realm",
          transport: transport,
          authId: "11111111",
          authenticationMethods: [new CraAuthentication("3614")]
      );
      transport.outbound.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receive(
              new Challenge(
                (message as Hello).details.authmethods[0],
                new Extra(
                    challenge : "{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}",
                    keylen : 32,
                    iterations : 1000,
                    salt : "gbnk5ji1b0dgoeavu31er567nb"
                )
              )
          );
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE && (message as Authenticate).signature == "APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=") {
          transport.receive(
              new Welcome(
                  586844620777222,
                  Details.forWelcome(
                      authId: "11111111",
                      authMethod: "wampcra",
                      authProvider: "cra",
                      authRole: "client"
                  )
              )
          );
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
    test("procedure registration and invocation", () async {
      final transport = _MockTransport();
      final client = new Client(
          realm: "test.realm",
          transport: transport
      );
      final yieldCompleter = new Completer<Yield>();
      final progressiveCallYieldCompleter = new Completer<Yield>();
      final error1completer = new Completer<Error>();
      final error2completer = new Completer<Error>();
      transport.outbound.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receive(new Welcome(42, Details.forWelcome()));
        }
        if (message.id == MessageTypes.CODE_REGISTER) {
          transport.receive(new Registered((message as Register).requestId, 1010));
        }
        if (message.id == MessageTypes.CODE_YIELD && (message as Yield).argumentsKeywords["value"] == 0) {
          yieldCompleter.complete(message as Yield);
        }
        if (message.id == MessageTypes.CODE_YIELD && (message as Yield).argumentsKeywords["progressiveCalls"] != null) {
          progressiveCallYieldCompleter.complete(message as Yield);
        }
        if (message.id == MessageTypes.CODE_ERROR && (message as Error).error == Error.UNKNOWN) {
          error1completer.complete(message as Error);
        }
        if (message.id == MessageTypes.CODE_ERROR && (message as Error).error == Error.NOT_AUTHORIZED) {
          error2completer.complete(message as Error);
        }
      });
      final session = await client.connect();
      final registration = await session.register("my.procedure");
      final registrationCompleter = new Completer<Registered>();
      final registrationErrorCompleter = new Completer<Error>();
      registration.listen((registered) {
        registrationCompleter.complete(registered);
      }, onError: (error) {
        registrationErrorCompleter.complete(error);
      });
      final registered = await registrationCompleter.future;
      expect(registered, isNotNull);
      expect(registered.registrationId, equals(1010));

      int progressiveCalls = 0;
      registered.onInvocation((invocation) {
        if (invocation.argumentsKeywords["value"] == 0) {
          invocation.respondWith(arguments: invocation.arguments, argumentsKeywords: invocation.argumentsKeywords);
        }
        if (invocation.argumentsKeywords["value"] == 1) {
          progressiveCalls++;
          if (!invocation.isProgressive()) {
            invocation.argumentsKeywords["progressiveCalls"] = progressiveCalls;
            invocation.respondWith(arguments: invocation.arguments, argumentsKeywords: invocation.argumentsKeywords);
          }
        }
        if (invocation.argumentsKeywords["value"] == -1) {
          throw new Exception("Something went wrong");
        }
        if (invocation.argumentsKeywords["value"] == -2) {
          invocation.respondWith(isError: true, errorUri: Error.NOT_AUTHORIZED, arguments: invocation.arguments, argumentsKeywords: invocation.argumentsKeywords);
        }
      });

      // REGULAR RESULT

      final argumentsKeywords = new HashMap<String, Object>();
      argumentsKeywords["value"] = 0;
      transport.receive(new Invocation(11001100, registered.registrationId, new InvocationDetails(null, null, false), arguments: ["did work"], argumentsKeywords: argumentsKeywords));
      final yieldMessage = await yieldCompleter.future;
      expect(yieldMessage, isNotNull);
      expect(yieldMessage.argumentsKeywords["value"], equals(0));
      expect(yieldMessage.arguments[0], equals("did work"));

      // PROGRESSIVE CALL

      final progressiveArgumentsKeywords = new HashMap<String, Object>();
      progressiveArgumentsKeywords["value"] = 1;
      transport.receive(new Invocation(21001100, registered.registrationId, new InvocationDetails(null, null, true), arguments: ["did work?"], argumentsKeywords: progressiveArgumentsKeywords));
      transport.receive(new Invocation(21001101, registered.registrationId, new InvocationDetails(null, null, false), arguments: ["did work again"], argumentsKeywords: progressiveArgumentsKeywords));
      final finalYieldMessage = await progressiveCallYieldCompleter.future;
      expect(finalYieldMessage, isNotNull);
      expect(finalYieldMessage.argumentsKeywords["value"], equals(1));
      expect(finalYieldMessage.argumentsKeywords["progressiveCalls"], equals(2));
      expect(finalYieldMessage.arguments[0], equals("did work again"));

      // PROGRESSIVE RESULT

      //final result = await session.call("my.procedure", options: new CallOptions(receive_progress: true));

      // ERROR BY EXCEPTION

      final argumentsKeywords2 = new HashMap<String, Object>();
      argumentsKeywords2["value"] = -1;
      transport.receive(new Invocation(11001101, registered.registrationId, new InvocationDetails(null, null, false), arguments: ["did work"], argumentsKeywords: argumentsKeywords2));
      final error1 = await error1completer.future;
      expect(error1.requestTypeId, equals(MessageTypes.CODE_INVOCATION));
      expect(error1.requestId, equals(11001101));
      expect(error1, isNotNull);
      expect(error1.error, equals(Error.UNKNOWN));
      expect(error1.arguments[0], equals("Exception: Something went wrong"));

      // ERROR BY HANDLER

      final argumentsKeywords3 = new HashMap<String, Object>();
      argumentsKeywords3["value"] = -2;
      transport.receive(new Invocation(11001102, registered.registrationId, new InvocationDetails(null, null, false), arguments: ["did work"], argumentsKeywords: argumentsKeywords3));
      final error2 = await error2completer.future;
      expect(error2, isNotNull);
      expect(error2.requestTypeId, equals(MessageTypes.CODE_INVOCATION));
      expect(error2.requestId, equals(11001102));
      expect(error2.error, equals(Error.NOT_AUTHORIZED));
      expect(error2.arguments[0], equals("did work"));
      expect(error2.argumentsKeywords["value"], equals(-2));
    });
  });
}

class _MockTransport extends AbstractTransport {

  bool _open = false;
  final BehaviorSubject<AbstractMessage> outbound = new BehaviorSubject();

  @override
  bool isOpen() {
    return _open;
  }

  @override
  void send(AbstractMessage message) {
    outbound.add(message);
  }

  void receive(AbstractMessage message) {
    this.inbound.add(message);
  }

  @override
  Future<void> close() {
    this._open = false;
    return Future.value();
  }

  @override
  Future<void> open() {
    this._open = true;
    return Future.value();
  }

}
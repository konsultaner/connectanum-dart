import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum/authentication.dart';
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/src/message/authenticate.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/message/yield.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

void main() {
  group('Client', () {
    test('session creation without authentication process', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(
              42,
              Details.forWelcome(
                  authId: 'Richi',
                  authMethod: 'none',
                  authProvider: 'noProvider',
                  authRole: 'client')));
        }
      });
      late LogRecord measuredRecord;
      Logger.root.onRecord.listen((record) {
        measuredRecord = record;
      });
      final session = await client.connect().first;
      expect(session.realm, equals('test.realm'));
      expect(session.id, equals(42));
      expect(session.authId, equals('Richi'));
      expect(session.authRole, equals('client'));
      expect(session.authProvider, equals('noProvider'));
      expect(session.authMethod, equals('none'));
      expect(measuredRecord.message,
          equals('Warning! No realm returned by the router'));
    });
    test('realm creation', () async {
      final transport = _MockTransport();
      final client = Client(transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(
              42,
              Details.forWelcome(
                  authId: 'Richi',
                  authMethod: 'none',
                  authProvider: 'noProvider',
                  authRole: 'client')));
        }
      });
      late Abort foundAbort;
      try {
        await client.connect().first;
      } catch (abort) {
        foundAbort = abort as Abort;
      }
      expect(
          foundAbort.message!.message,
          equals(
              'No realm specified! Neither by the client nor by the router'));

      var transport2 = _MockTransport();
      transport2.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport2.receiveMessage(Welcome(
              42,
              Details.forWelcome(
                  authId: 'Richi',
                  authMethod: 'none',
                  authProvider: 'noProvider',
                  realm: 'some.dynamic.realm',
                  authRole: 'client')));
        }
      });
      var session = await Client(transport: transport2).connect().first;
      expect(session, isA<Session>());
      expect(session.realm, equals('some.dynamic.realm'));
    });
    test('session creation router abort', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Abort(Error.NO_SUCH_REALM,
              message: 'The given realm is not valid'));
        }
      });
      Completer abortCompleter = Completer<Abort>();
      client
          .connect()
          .listen((_) {}, onError: ((abort) => abortCompleter.complete(abort)));
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.NO_SUCH_REALM));
      expect(abort.message!.message, equals('The given realm is not valid'));
      expect(transport.isOpen, isFalse);
    });
    test('session creation router abort not authorized', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Abort(Error.NOT_AUTHORIZED,
              message: 'The given realm is not valid'));
        }
      });
      Completer abortCompleter = Completer<Abort>();
      client
          .connect()
          .listen((_) {}, onError: ((abort) => abortCompleter.complete(abort)));
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.NOT_AUTHORIZED));
      expect(abort.message!.message, equals('The given realm is not valid'));
      expect(transport.isOpen, isFalse);
    });
    test('session creation with cra authentication process and regular close',
        () async {
      final transport = _MockTransport();
      final client = Client(
          realm: 'test.realm',
          transport: transport,
          authId: '11111111',
          authenticationMethods: [CraAuthentication('3614')]);
      final goodbyeCompleter = Completer();
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Challenge(
              (message as Hello).details.authmethods![0],
              Extra(
                  challenge:
                      '{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}',
                  keylen: 32,
                  iterations: 1000,
                  salt: 'gbnk5ji1b0dgoeavu31er567nb')));
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE &&
            (message as Authenticate).signature ==
                'APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=') {
          transport.receiveMessage(Welcome(
              586844620777222,
              Details.forWelcome(
                  authId: '11111111',
                  authMethod: 'wampcra',
                  authProvider: 'cra',
                  realm: 'changed.realm',
                  authRole: 'client')));
        }
        if (message.id == MessageTypes.CODE_GOODBYE) {
          goodbyeCompleter.complete(message);
        }
      });
      final session = await client.connect().first;
      expect(session.realm, equals('changed.realm'));
      expect(session.id, equals(586844620777222));
      expect(session.authId, equals('11111111'));
      expect(session.authRole, equals('client'));
      expect(session.authProvider, equals('cra'));
      expect(session.authMethod, equals('wampcra'));
      expect(transport.isOpen, isTrue);
      await session.close(message: 'GBY', timeout: Duration(milliseconds: 1));
      expect(transport.isOpen, isFalse);
      Goodbye goodbye = await goodbyeCompleter.future;
      expect(goodbye.message!.message, equals('GBY'));
    });
    test('session creation with cra authentication process and router abort',
        () async {
      final transport = _MockTransport();
      final client = Client(
          realm: 'test.realm',
          transport: transport,
          authId: '11111111',
          authenticationMethods: [CraAuthentication('3614')]);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Challenge(
              (message as Hello).details.authmethods![0],
              Extra(
                  challenge:
                      '{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}',
                  keylen: 32,
                  iterations: 1000,
                  salt: 'gbnk5ji1b0dgoeavu31er567nb')));
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE) {
          transport.receiveMessage(Abort(Error.AUTHORIZATION_FAILED,
              message: 'Wrong user credentials'));
        }
      });
      Completer abortCompleter = Completer<Abort>();
      unawaited(client.connect().first.catchError((abort) {
        abortCompleter.complete(abort);
        return Future.value(Session(null, _MockTransport()));
      }));
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(abort.message!.message, equals('Wrong user credentials'));
      expect(transport.isOpen, isFalse);
    });
    test('session creation with failing authentication challenge', () async {
      final transport = _MockTransport();
      final client = Client(
          realm: 'test.realm',
          transport: transport,
          authId: '11111111',
          authenticationMethods: [_MockChallengeFailAuthenticator()]);
      var receivedAbortCompleter = Completer<Abort>();
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Challenge(
              (message as Hello).details.authmethods![0],
              Extra(challenge: 'nothing')));
        }
        if (message.id == MessageTypes.CODE_ABORT) {
          receivedAbortCompleter.complete(message as Abort);
        }
      });
      client.connect();
      var abort = await receivedAbortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(abort.message!.message, equals('Exception: Did not work'));
      expect(transport.isOpen, isFalse);
    });
    test('session creation with ticket authentication process', () async {
      final transport = _MockTransport();
      final client = Client(
          realm: 'test.realm',
          authId: 'joe',
          transport: transport,
          authenticationMethods: [TicketAuthentication('secret!!!')]);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(
              Challenge((message as Hello).details.authmethods![0], Extra()));
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE &&
            (message as Authenticate).signature == 'secret!!!') {
          transport.receiveMessage(Welcome(
              3251278072152162,
              Details.forWelcome(
                  authId: 'joe',
                  authMethod: 'static',
                  authProvider: 'ticket',
                  authRole: 'user')));
        }
      });
      final session = await client.connect().first;
      expect(session.realm, equals('test.realm'));
      expect(session.id, equals(3251278072152162));
      expect(session.authId, equals('joe'));
      expect(session.authRole, equals('user'));
      expect(session.authProvider, equals('ticket'));
      expect(session.authMethod, equals('static'));
    });
    test('session creation with scram authentication process', () async {
      final user = {
        'cost': 4096,
        'salt': 'b7f4f8f864924168a91fa5bba5a3bdfe',
        'serverKey': 'T4DYBMMjNWlhFQc4A98cLTzoRBEVZPlkWI4hv8ug+Yg=',
        'storedKey': 'sni3TU4pWemjrglGNWdwRD5cRaJAaClIMO5DaElkQOM=',
        'username': 'admin',
        'helloNonce': '',
        'nonce': ''
      };
      final transport = _MockTransport();
      final client = Client(
          realm: 'test.realm',
          authId: 'admin',
          transport: transport,
          authenticationMethods: [ScramAuthentication('admin')]);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          var hello = message as Hello;
          user['helloNonce'] = hello.details.authextra!['nonce'];
          user['nonce'] =
              hello.details.authextra!['nonce'] + 'KOyl+L29eqUe9cVKbVUUgQ==';
          var challengeExtra = Extra();
          challengeExtra.nonce = user['nonce'] as String?;
          challengeExtra.salt = user['salt'] as String?;
          challengeExtra.kdf = ScramAuthentication.KDF_PBKDF2;
          challengeExtra.iterations = user['cost'] as int?;
          var authExtra = HashMap<String, Object?>();
          authExtra['channel_binding'] = null;
          authExtra['cbind_data'] = null;
          authExtra['nonce'] = user['nonce'];
          transport.receiveMessage(
              Challenge(message.details.authmethods![0], challengeExtra));
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE) {
          var authenticate = message as Authenticate;
          var challengeExtra = Extra();
          challengeExtra.nonce = user['nonce'] as String?;
          challengeExtra.salt = user['salt'] as String?;
          challengeExtra.iterations = user['cost'] as int?;
          var authMessage = ScramAuthentication.createAuthMessage(
              user['username'] as String,
              user['helloNonce'] as String,
              authenticate.extra as HashMap,
              challengeExtra);
          if (ScramAuthentication.verifyClientProof(
              base64.decode(authenticate.signature!),
              base64.decode(user['storedKey'] as String),
              authMessage)) {
            transport.receiveMessage(Welcome(
                3251278072152162,
                Details.forWelcome(
                    authId: 'admin',
                    authMethod: 'wamp-scram',
                    authProvider: 'test',
                    authRole: 'admin')));
          }
        }
      });
      final session = await client.connect().first;
      expect(session.realm, equals('test.realm'));
      expect(session.id, equals(3251278072152162));
      expect(session.authId, equals('admin'));
      expect(session.authRole, equals('admin'));
      expect(session.authProvider, equals('test'));
      expect(session.authMethod, equals('wamp-scram'));
    });

    test('procedure registration and invocation', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);

      final yieldCompleter = Completer<Yield>();
      final yieldCompleter2 = Completer<Yield>();
      final progressiveCallYieldCompleter = Completer<Yield>();
      final error1completer = Completer<Error>();
      final error2completer = Completer<Error>();
      final error3completer = Completer<Error>();

      // ALL ROUTER MOCK RESULTS
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        } else if (message.id == MessageTypes.CODE_REGISTER) {
          if ((message as Register).procedure == 'my.procedure') {
            transport.receiveMessage(Registered(message.requestId, 1010));
          }
          if (message.procedure == 'my.error') {
            transport.receiveMessage(Error(MessageTypes.CODE_REGISTER,
                message.requestId, {}, Error.NOT_AUTHORIZED));
          }
        } else if (message.id == MessageTypes.CODE_UNREGISTER) {
          if ((message as Unregister).registrationId > 0) {
            transport.receiveMessage(Unregistered(message.requestId));
          } else {
            transport.receiveMessage(Error(MessageTypes.CODE_UNREGISTER,
                message.requestId, {}, Error.NO_SUCH_REGISTRATION));
          }
        } else if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).options?.ppt_scheme == 'x_custom_scheme') {
            transport.receiveMessage(Invocation(message.requestId, 1010,
                InvocationDetails(null, null, false, 'x_custom_scheme', 'cbor'),
                arguments: [Uint8List.fromList(   // Data below is the same as in cbor serializer deserializePPT test
                    [162, 100, 97, 114, 103, 115, 131, 24,
                        100, 99, 116, 119, 111, 245, 102, 107, 119, 97, 114, 103, 115,
                        163, 100, 107, 101, 121, 49, 24, 100, 100, 107, 101, 121, 50,
                        99, 116, 119, 111, 100, 107, 101, 121, 51, 245])]));
        } else if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).argumentsKeywords!['value'] != -3 &&
            (message).argumentsKeywords!['value'] != -4) {
          transport.receiveMessage(Result(
              message.requestId, ResultDetails(progress: true),
              arguments: message.arguments));
          transport.receiveMessage(Result(
              message.requestId, ResultDetails(progress: false),
              argumentsKeywords: message.argumentsKeywords));
        } else if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).argumentsKeywords!['value'] == -3) {
          transport.receiveMessage(Error(MessageTypes.CODE_CALL,
              message.requestId, HashMap(), Error.NO_SUCH_REGISTRATION,
              arguments: message.arguments,
              argumentsKeywords: message.argumentsKeywords));
        } else if (message.id == MessageTypes.CODE_CALL &&
            (message as Call).argumentsKeywords!['value'] == -4) {
          // ignored because it will not complete before cancellation happens
        } else if (message.id == MessageTypes.CODE_CANCEL) {
          transport.receiveMessage(Error(
              MessageTypes.CODE_CALL,
              (message as Cancel).requestId,
              HashMap(),
              Error.ERROR_INVOCATION_CANCELED,
              arguments: [message.options!.mode]));
        } else if (message.id == MessageTypes.CODE_YIELD &&
            (message as Yield).invocationRequestId == 55001100) {
            yieldCompleter2.complete(message);
        } else if (message.id == MessageTypes.CODE_YIELD &&
            (message as Yield).options?.ppt_scheme == 'x_custom_scheme') {
            transport.receiveMessage(message);
        } else if (message.id == MessageTypes.CODE_YIELD &&
            (message as Yield).argumentsKeywords!['value'] == 0) {
          yieldCompleter.complete(message);
        } else if (message.id == MessageTypes.CODE_YIELD &&
            (message as Yield).argumentsKeywords!['progressiveCalls'] != null) {
          progressiveCallYieldCompleter.complete(message);
        } else if (message.id == MessageTypes.CODE_ERROR &&
            (message as Error).error == Error.UNKNOWN) {
          error1completer.complete(message);
        } else if (message.id == MessageTypes.CODE_ERROR &&
            (message as Error).error == Error.NOT_AUTHORIZED) {
          error2completer.complete(message);
        } else if (message.id == MessageTypes.CODE_ERROR &&
            (message as Error).error == Error.NO_SUCH_REGISTRATION) {
          error3completer.complete(message);
        }
      });

      final session = await client.connect().first;
      final registrationErrorCompleter = Completer<Error>();

      // NOT WORKING REGISTRATION

      unawaited(
          session.register('my.error').then((registered) {}, onError: (error) {
        registrationErrorCompleter.complete(error);
      }));

      final registrationError = await registrationErrorCompleter.future;
      expect(registrationError, isNotNull);
      expect(
          registrationError.requestTypeId, equals(MessageTypes.CODE_REGISTER));
      expect(registrationError.id, equals(MessageTypes.CODE_ERROR));

      // WORKING REGISTRATION

      final registered = await session.register('my.procedure');
      expect(registered, isNotNull);
      expect(registered.registrationId, equals(1010));

      var progressiveCalls = 0;
      registered.onInvoke((invocation) {
        if (invocation.argumentsKeywords!['value'] == 0) {
          invocation.respondWith(
              arguments: invocation.arguments,
              argumentsKeywords: invocation.argumentsKeywords);
        }
        if (invocation.argumentsKeywords!['value'] == 1) {
          progressiveCalls++;
          if (!invocation.isProgressive()) {
            invocation.argumentsKeywords!['progressiveCalls'] =
                progressiveCalls;
            invocation.respondWith(
                arguments: invocation.arguments,
                argumentsKeywords: invocation.argumentsKeywords);
          }
        }
        if (invocation.argumentsKeywords!['value'] == -1) {
          throw Exception('Something went wrong');
        }
        // PPT Payload received
        if (invocation.details.ppt_scheme != null) {
            expect(invocation.details.ppt_scheme, equals('x_custom_scheme'));
            expect(invocation.details.ppt_serializer, equals('cbor'));
            invocation.respondWith(
                arguments: invocation.arguments,
                argumentsKeywords: invocation.argumentsKeywords,
                options: YieldOptions(ppt_scheme: 'x_custom_scheme', ppt_serializer: 'cbor')
            );
        }
        if (invocation.argumentsKeywords!['value'] == -2) {
          invocation.respondWith(
              isError: true,
              errorUri: Error.NOT_AUTHORIZED,
              arguments: invocation.arguments,
              argumentsKeywords: invocation.argumentsKeywords);
        }
      });

      // REGULAR YIELD

      final argumentsKeywords = HashMap<String, Object>();
      argumentsKeywords['value'] = 0;
      transport.receiveMessage(Invocation(11001100, registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work'], argumentsKeywords: argumentsKeywords));
      final yieldMessage = await yieldCompleter.future;
      expect(yieldMessage, isNotNull);
      expect(yieldMessage.argumentsKeywords!['value'], equals(0));
      expect(yieldMessage.arguments![0], equals('did work'));

      // PPT YIELD

      transport.receiveMessage(Invocation(55001100, registered.registrationId,
          InvocationDetails(null, null, false, 'x_custom_scheme', 'cbor'),
          arguments: [Uint8List.fromList(   // Data below is the same as in cbor serializer deserializePPT test
              [162, 100, 97, 114, 103, 115, 131, 24,
                  100, 99, 116, 119, 111, 245, 102, 107, 119, 97, 114, 103, 115,
                  163, 100, 107, 101, 121, 49, 24, 100, 100, 107, 101, 121, 50,
                  99, 116, 119, 111, 100, 107, 101, 121, 51, 245])]));
      final pptYieldMessage = await yieldCompleter2.future;
      expect(pptYieldMessage, isNotNull);

      // PPT RESULT
      session.call('my.procedure',
          arguments: <dynamic>[100, 'two', true],
          argumentsKeywords: { 'key1': 100, 'key2': 'two', 'key3': true },
          options: CallOptions(ppt_scheme: 'x_custom_scheme', ppt_serializer: 'cbor'))
          .listen((result) => () {
              expect(result, isNotNull);
              expect(result.details.ppt_scheme, equals('x_custom_scheme'));
              expect(result.details.ppt_serializer, equals('cbor'));
              expect(result.argumentsKeywords!['key1'], equals(100));
              expect(result.argumentsKeywords!['key2'], equals('two'));
              expect(result.argumentsKeywords!['key3'], equals(true));
              expect(result.arguments![0], equals(100));
              expect(result.arguments![1], equals('two'));
              expect(result.arguments![2], equals(true));
            });

      // PROGRESSIVE CALL

      final progressiveArgumentsKeywords = HashMap<String, Object>();
      progressiveArgumentsKeywords['value'] = 1;
      transport.receiveMessage(Invocation(21001100, registered.registrationId,
          InvocationDetails(null, null, true),
          arguments: ['did work?'],
          argumentsKeywords: progressiveArgumentsKeywords));
      transport.receiveMessage(Invocation(21001101, registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work again'],
          argumentsKeywords: progressiveArgumentsKeywords));
      final finalYieldMessage = await progressiveCallYieldCompleter.future;
      expect(finalYieldMessage, isNotNull);
      expect(finalYieldMessage.argumentsKeywords!['value'], equals(1));
      expect(
          finalYieldMessage.argumentsKeywords!['progressiveCalls'], equals(2));
      expect(finalYieldMessage.arguments![0], equals('did work again'));

      // PROGRESSIVE RESULT

      final progressiveCallArgumentsKeywords = HashMap<String, Object>();
      progressiveArgumentsKeywords['value'] = 2;
      final resultList = <Result>[];
      await for (final result in session.call('my.procedure',
          options: CallOptions(receive_progress: true),
          arguments: ['called'],
          argumentsKeywords: progressiveCallArgumentsKeywords)) {
        resultList.add(result);
      }
      expect(resultList.length, equals(2));

      // ERROR BY EXCEPTION

      final argumentsKeywords2 = HashMap<String, Object>();
      argumentsKeywords2['value'] = -1;
      transport.receiveMessage(Invocation(11001101, registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work'], argumentsKeywords: argumentsKeywords2));
      final error1 = await error1completer.future;
      expect(error1.requestTypeId, equals(MessageTypes.CODE_INVOCATION));
      expect(error1.requestId, equals(11001101));
      expect(error1, isNotNull);
      expect(error1.error, equals(Error.UNKNOWN));
      expect(error1.arguments![0], equals('Exception: Something went wrong'));

      // ERROR BY HANDLER

      final argumentsKeywords3 = HashMap<String, Object>();
      argumentsKeywords3['value'] = -2;
      transport.receiveMessage(Invocation(11001102, registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work'], argumentsKeywords: argumentsKeywords3));
      final error2 = await error2completer.future;
      expect(error2, isNotNull);
      expect(error2.requestTypeId, equals(MessageTypes.CODE_INVOCATION));
      expect(error2.requestId, equals(11001102));
      expect(error2.error, equals(Error.NOT_AUTHORIZED));
      expect(error2.arguments![0], equals('did work'));
      expect(error2.argumentsKeywords!['value'], equals(-2));

      // ERROR RESULT

      final errorCallArgumentsKeywords = HashMap<String, Object>();
      errorCallArgumentsKeywords['value'] = -3;
      final errorCallCompleter = Completer<Error>();
      session
          .call('my.procedure',
              options: CallOptions(receive_progress: true),
              arguments: ['was an error'],
              argumentsKeywords: errorCallArgumentsKeywords)
          .listen((result) {},
              onError: (error) => errorCallCompleter.complete(error));
      var callError = await errorCallCompleter.future;
      expect(callError, isNotNull);
      expect(callError.requestTypeId, equals(MessageTypes.CODE_CALL));
      expect(callError.arguments![0], equals('was an error'));
      expect(callError.argumentsKeywords!['value'], equals(-3));

      // ERROR BY CANCELLATION

      final errorCallCancellation = HashMap<String, Object>();
      errorCallCancellation['value'] = -4;
      final errorCallCancellationCompleter = Completer<Error>();
      final CancellationCompleter = Completer<String>();
      session
          .call('my.procedure',
              argumentsKeywords: errorCallCancellation,
              cancelCompleter: CancellationCompleter)
          .listen((result) {},
              onError: (error) =>
                  errorCallCancellationCompleter.complete(error));
      CancellationCompleter.complete(CancelOptions.MODE_KILL_NO_WAIT);
      var cancelError = await errorCallCancellationCompleter.future;
      expect(cancelError, isNotNull);
      expect(cancelError.requestTypeId, equals(MessageTypes.CODE_CALL));
      expect(
          cancelError.arguments![0], equals(CancelOptions.MODE_KILL_NO_WAIT));

      // UNREGISTER

      await session.unregister(registered.registrationId);

      final argumentsKeywordsRegular = HashMap<String, Object>();
      argumentsKeywordsRegular['value'] = 0;
      transport.receiveMessage(Invocation(11001199, registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did not work'],
          argumentsKeywords: argumentsKeywordsRegular));
      final error3Message = await error3completer.future;
      expect(error3Message, isNotNull);
      expect(error3Message.requestTypeId, MessageTypes.CODE_INVOCATION);
      expect(error3Message.requestId, 11001199);
      expect(error3Message.argumentsKeywords, isNull);
      expect(error3Message.arguments, isNull);

      // UNREGISTER ERROR

      final errorUnregisterCompleter = Completer<Error>();
      unawaited(session.unregister(-1).then((message) {},
          onError: (error) => errorUnregisterCompleter.complete(error)));
      var unregisterError = await errorUnregisterCompleter.future;
      expect(unregisterError, isNotNull);
      expect(
          unregisterError.requestTypeId, equals(MessageTypes.CODE_UNREGISTER));
      expect(unregisterError.error, equals(Error.NO_SUCH_REGISTRATION));
    });
    test('event subscription and publish', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);

      // ALL ROUTER MOCK RESULTS
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        }
        if (message.id == MessageTypes.CODE_PUBLISH &&
            (message as Publish).options?.acknowledge != null &&
            (message).options?.acknowledge == true) {
          transport.receiveMessage(Published((message).requestId, 1));
        }
        if (message.id == MessageTypes.CODE_SUBSCRIBE) {
          if ((message as Subscribe).topic == 'topic.my.de') {
            transport.receiveMessage(Subscribed(message.requestId, 10));
          }
          if (message.topic == 'topic.revoke') {
            transport.receiveMessage(Subscribed(message.requestId, 11));
            transport.receiveMessage(
                Unsubscribed(0, UnsubscribedDetails(11, 'error.500')));
          }
          if (message.topic == 'topic.my.error') {
            transport.receiveMessage(Error(MessageTypes.CODE_SUBSCRIBE,
                message.requestId, {}, Error.NOT_AUTHORIZED));
          }
        }
        if (message.id == MessageTypes.CODE_UNSUBSCRIBE) {
          if ((message as Unsubscribe).subscriptionId == -1) {
            transport.receiveMessage(Error(MessageTypes.CODE_UNSUBSCRIBE,
                message.requestId, {}, Error.NO_SUCH_SUBSCRIPTION));
          } else {
            transport.receiveMessage(Unsubscribed(message.requestId, null));
          }
        }
      });
      final session = await client.connect().first;

      // SUBSCRIPTION REVOCATION

      var subscribed = await session.subscribe('topic.revoke');
      expect(subscribed, isNotNull);
      expect(subscribed.eventStream, isNotNull);
      expect(subscribed.subscribeRequestId, isNotNull);
      expect(subscribed.subscriptionId, equals(11));
      subscribed.eventStream!.listen((_) {});
      var reason = await subscribed.onRevoke;
      expect(reason, equals('error.500'));

      // REGULAR SUBSCRIBE

      subscribed = await session.subscribe('topic.my.de');
      expect(subscribed, isNotNull);
      expect(subscribed.eventStream, isNotNull);
      expect(subscribed.subscribeRequestId, isNotNull);
      expect(subscribed.subscriptionId, equals(10));

      // SUBSCRIBE ERROR

      var subscribeErrorCompleter = Completer<Error>();
      unawaited(session.subscribe('topic.my.error').then((message) {},
          onError: (error) => subscribeErrorCompleter.complete(error)));
      var subscribeError = await subscribeErrorCompleter.future;
      expect(subscribeError, isNotNull);
      expect(subscribeError.error, equals(Error.NOT_AUTHORIZED));
      expect(subscribeError.requestTypeId, equals(MessageTypes.CODE_SUBSCRIBE));

      // REGULAR PUBLISH

      var published = await session.publish('my.test.topic',
          arguments: ['some data'], options: PublishOptions(acknowledge: true));
      expect(published, isNotNull);
      expect(published?.publishRequestId, isNotNull);
      expect(published?.publicationId, equals(1));

      published = await session.publish('my.test.topic',
          arguments: ['some data'],
          options: PublishOptions(acknowledge: false));
      expect(published, isNull);

      published =
          await session.publish('my.test.topic',
              arguments: <dynamic>[100, 'two', true],
              argumentsKeywords: { 'key1': 100, 'key2': 'two', 'key3': true },
              options: PublishOptions(ppt_scheme: 'x_custom_scheme', ppt_serializer: 'cbor')
        );
      expect(published, isNull);

      published =
          await session.publish('my.test.topic', arguments: ['some data']);
      expect(published, isNull);

      // EVENT

      var eventCompleter = Completer<Event>();
      var eventCompleter2 = Completer<Event>();
      var eventCompleter3 = Completer<Event>();
      var eventCompleter4 = Completer<Event>();
      subscribed.eventStream!.listen((event) {
        if (event.publicationId == 1122) {
          eventCompleter.complete(event);
        } else if (event.publicationId == 1133) {
          eventCompleter2.complete(event);
        } else if (event.publicationId == 1144) {
          eventCompleter3.complete(event);
        } else if (event.publicationId == 1155) {
          eventCompleter4.complete(event);
        }
      });
      transport.receiveMessage(
          Event(subscribed.subscriptionId, 1122, EventDetails()));
      var event = await eventCompleter.future;
      expect(event, isNotNull);
      expect(event.publicationId, equals(1122));

      transport.receiveMessage(
          Event(subscribed.subscriptionId, 1133, EventDetails()));
      var event2 = await eventCompleter2.future;
      expect(event2, isNotNull);
      expect(event2.publicationId, equals(1133));

      transport.receiveMessage(
          Event(subscribed.subscriptionId, 1155,
              EventDetails(ppt_scheme: 'x_custom_scheme', ppt_serializer: 'cbor')));
      var event4 = await eventCompleter4.future;
      expect(event4, isNotNull);
      expect(event4.publicationId, equals(1155));

      // UNSUBSCRIBE ERROR

      Error? unsubscribeError;
      try {
        await session.unsubscribe(-1);
      } on Error catch (error) {
        unsubscribeError = error;
      }
      expect(unsubscribeError, isNotNull);
      expect(unsubscribeError!.error, Error.NO_SUCH_SUBSCRIPTION);

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
      Event? event3;
      unawaited(eventCompleter3.future.then((event) => event3 = event));
      await Future.delayed(Duration(milliseconds: 3));
      expect(event3, isNull);
    });
  });
}

class _MockChallengeFailAuthenticator extends AbstractAuthentication {
  @override
  Future<Authenticate> challenge(Extra extra) {
    return Future.error(Exception('Did not work'));
  }

  @override
  String getName() {
    return 'mock';
  }

  @override
  Future<void> hello(String? realm, Details details) {
    return Future.value();
  }
}

class _MockTransport extends AbstractTransport {
  final StreamController<AbstractMessage> inbound = StreamController();
  Completer? _onConnectionLost;
  Completer? _onDisconnect;

  bool _open = false;
  final StreamController<AbstractMessage> outbound = StreamController();

  @override
  Completer? get onConnectionLost => _onConnectionLost;

  @override
  Completer? get onDisconnect => _onDisconnect;

  @override
  bool get isOpen {
    return _open;
  }

  @override
  bool get isReady => isOpen;
  @override
  Future<void> get onReady => Future.value();

  @override
  void send(AbstractMessage message) {
    outbound.add(message);
  }

  void receiveMessage(AbstractMessage message) {
    Future.delayed(Duration(milliseconds: 1), () => inbound.add(message));
  }

  @override
  Future<void> close({error}) {
    _open = false;
    inbound.close();
    complete(_onDisconnect, error);
    return Future.value();
  }

  @override
  Future<void> open({Duration? pingInterval}) {
    _open = true;
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    return Future.value();
  }

  @override
  Stream<AbstractMessage> receive() {
    return inbound.stream;
  }
}

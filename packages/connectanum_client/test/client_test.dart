import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/message_binding.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('Client', () {
    test('session creation without authentication process', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Welcome(
              42,
              Details.forWelcome(
                authId: 'Richi',
                authMethod: 'none',
                authProvider: 'noProvider',
                authRole: 'client',
              ),
            ),
          );
        }
      });

      final session = await client.connect().first;
      expect(session.realm, equals('test.realm'));
      expect(session.id, equals(42));
      expect(session.authId, equals('Richi'));
      expect(session.authRole, equals('client'));
      expect(session.authProvider, equals('noProvider'));
      expect(session.authMethod, equals('none'));
    });
    test('realm creation', () async {
      final transport = _MockTransport();
      final client = Client(transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Welcome(
              42,
              Details.forWelcome(
                authId: 'Richi',
                authMethod: 'none',
                authProvider: 'noProvider',
                authRole: 'client',
              ),
            ),
          );
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
        equals('No realm specified! Neither by the client nor by the router'),
      );

      var transport2 = _MockTransport();
      transport2.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport2.receiveMessage(
            Welcome(
              42,
              Details.forWelcome(
                authId: 'Richi',
                authMethod: 'none',
                authProvider: 'noProvider',
                realm: 'some.dynamic.realm',
                authRole: 'client',
              ),
            ),
          );
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
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Abort(Error.noSuchRealm, message: 'The given realm is not valid'),
          );
        }
      });
      Completer abortCompleter = Completer<Abort>();
      client.connect().listen(
        (_) {},
        onError: ((abort) => abortCompleter.complete(abort)),
      );
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.noSuchRealm));
      expect(abort.message!.message, equals('The given realm is not valid'));
      expect(transport.isOpen, isFalse);
    });
    test('session creation router abort not authorized', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Abort(Error.notAuthorized, message: 'The given realm is not valid'),
          );
        }
      });
      Completer abortCompleter = Completer<Abort>();
      client.connect().listen(
        (_) {},
        onError: ((abort) => abortCompleter.complete(abort)),
      );
      Abort abort = await abortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.notAuthorized));
      expect(abort.message!.message, equals('The given realm is not valid'));
      expect(transport.isOpen, isFalse);
    });
    test(
      'session creation with cra authentication process and regular close',
      () async {
        final transport = _MockTransport();
        final client = Client(
          realm: 'test.realm',
          transport: transport,
          authId: '11111111',
          authenticationMethods: [CraAuthentication('3614')],
        );
        final goodbyeCompleter = Completer();
        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(
              Challenge(
                (message as Hello).details.authmethods![0],
                Extra(
                  challenge:
                      '{"authid":"11111111","authrole":"client","authmethod":"wampcra","authprovider":"mssql","nonce":"1280303478343404","timestamp":"2015-10-27T14:28Z","session":586844620777222}',
                  keyLen: 32,
                  iterations: 1000,
                  salt: 'gbnk5ji1b0dgoeavu31er567nb',
                ),
              ),
            );
          }
          if (message.id == MessageTypes.codeAuthenticate &&
              (message as Authenticate).signature ==
                  'APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=') {
            transport.receiveMessage(
              Welcome(
                586844620777222,
                Details.forWelcome(
                  authId: '11111111',
                  authMethod: 'wampcra',
                  authProvider: 'cra',
                  realm: 'changed.realm',
                  authRole: 'client',
                ),
              ),
            );
          }
          if (message.id == MessageTypes.codeGoodbye) {
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
      },
    );
    test(
      'session creation with cra authentication process and router abort',
      () async {
        final transport = _MockTransport();
        final client = Client(
          realm: 'test.realm',
          transport: transport,
          authId: '11111111',
          authenticationMethods: [CraAuthentication('3614')],
        );
        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(
              Challenge(
                (message as Hello).details.authmethods![0],
                Extra(
                  challenge:
                      '{"authid":"11111111","authrole":"client","authmethod":"wampcra","authprovider":"mssql","nonce":"1280303478343404","timestamp":"2015-10-27T14:28Z","session":586844620777222}',
                  keyLen: 32,
                  iterations: 1000,
                  salt: 'gbnk5ji1b0dgoeavu31er567nb',
                ),
              ),
            );
          }
          if (message.id == MessageTypes.codeAuthenticate) {
            transport.receiveMessage(
              Abort(
                Error.authorizationFailed,
                message: 'Wrong user credentials',
              ),
            );
          }
        });
        Completer abortCompleter = Completer<Abort>();
        unawaited(
          client.connect().first.catchError((abort) {
            abortCompleter.complete(abort);
            return Future.value(Session(null, _MockTransport()));
          }),
        );
        Abort abort = await abortCompleter.future;
        expect(abort, isNotNull);
        expect(abort.reason, equals(Error.authorizationFailed));
        expect(abort.message!.message, equals('Wrong user credentials'));
        expect(transport.isOpen, isFalse);
      },
    );
    test('session creation with failing authentication challenge', () async {
      final transport = _MockTransport();
      final client = Client(
        realm: 'test.realm',
        transport: transport,
        authId: '11111111',
        authenticationMethods: [_MockChallengeFailAuthenticator()],
      );
      var receivedAbortCompleter = Completer<Abort>();
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Challenge(
              (message as Hello).details.authmethods![0],
              Extra(challenge: 'nothing'),
            ),
          );
        }
        if (message.id == MessageTypes.codeAbort) {
          receivedAbortCompleter.complete(message as Abort);
        }
      });
      client.connect().listen((_) {}, onError: (_) {});
      var abort = await receivedAbortCompleter.future;
      expect(abort, isNotNull);
      expect(abort.reason, equals(Error.authorizationFailed));
      expect(abort.message!.message, equals('Exception: Did not work'));
      expect(transport.isOpen, isFalse);
    });
    test('session creation with ticket authentication process', () async {
      final transport = _MockTransport();
      final client = Client(
        realm: 'test.realm',
        authId: 'joe',
        transport: transport,
        authenticationMethods: [TicketAuthentication('secret!!!')],
      );
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Challenge((message as Hello).details.authmethods![0], Extra()),
          );
        }
        if (message.id == MessageTypes.codeAuthenticate &&
            (message as Authenticate).signature == 'secret!!!') {
          transport.receiveMessage(
            Welcome(
              3251278072152162,
              Details.forWelcome(
                authId: 'joe',
                authMethod: 'static',
                authProvider: 'ticket',
                authRole: 'user',
              ),
            ),
          );
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
        'nonce': '',
      };
      final transport = _MockTransport();
      final client = Client(
        realm: 'test.realm',
        authId: 'admin',
        transport: transport,
        authenticationMethods: [ScramAuthentication('admin')],
      );
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          var hello = message as Hello;
          user['helloNonce'] = hello.details.authextra!['nonce'];
          user['nonce'] =
              hello.details.authextra!['nonce'] + 'KOyl+L29eqUe9cVKbVUUgQ==';
          var challengeExtra = Extra();
          challengeExtra.nonce = user['nonce'] as String?;
          challengeExtra.salt = user['salt'] as String?;
          challengeExtra.kdf = ScramAuthentication.kdfPbkdf2;
          challengeExtra.iterations = user['cost'] as int?;
          var authExtra = HashMap<String, Object?>();
          authExtra['channel_binding'] = null;
          authExtra['cbind_data'] = null;
          authExtra['nonce'] = user['nonce'];
          transport.receiveMessage(
            Challenge(message.details.authmethods![0], challengeExtra),
          );
        }
        if (message.id == MessageTypes.codeAuthenticate) {
          var authenticate = message as Authenticate;
          var challengeExtra = Extra();
          challengeExtra.nonce = user['nonce'] as String?;
          challengeExtra.salt = user['salt'] as String?;
          challengeExtra.iterations = user['cost'] as int?;
          var authMessage = ScramAuthentication.createAuthMessage(
            user['username'] as String,
            user['helloNonce'] as String,
            authenticate.extra as HashMap,
            challengeExtra,
          );
          if (ScramAuthentication.verifyClientProof(
            base64.decode(authenticate.signature!),
            base64.decode(user['storedKey'] as String),
            authMessage,
          )) {
            transport.receiveMessage(
              Welcome(
                3251278072152162,
                Details.forWelcome(
                  authId: 'admin',
                  authMethod: 'wamp-scram',
                  authProvider: 'test',
                  authRole: 'admin',
                ),
              ),
            );
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
      final cancelRequestErrorRequestIds = <int>{};

      // ALL ROUTER MOCK RESULTS
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        } else if (message.id == MessageTypes.codeRegister) {
          if ((message as Register).procedure == 'my.procedure') {
            transport.receiveMessage(Registered(message.requestId, 1010));
          }
          if (message.procedure == 'my.error') {
            transport.receiveMessage(
              Error(
                MessageTypes.codeRegister,
                message.requestId,
                {},
                Error.notAuthorized,
              ),
            );
          }
        } else if (message.id == MessageTypes.codeUnregister) {
          if ((message as Unregister).registrationId > 0) {
            transport.receiveMessage(Unregistered(message.requestId));
          } else {
            transport.receiveMessage(
              Error(
                MessageTypes.codeUnregister,
                message.requestId,
                {},
                Error.noSuchRegistration,
              ),
            );
          }
        } else if (message.id == MessageTypes.codeCall &&
            (message as Call).options?.pptScheme == 'x_custom_scheme') {
          transport.receiveMessage(
            Invocation(
              message.requestId,
              1010,
              InvocationDetails(null, null, false, 'x_custom_scheme', 'cbor'),
              arguments: [
                Uint8List.fromList(
                  // Data below is the same as in cbor serializer deserializePPT test
                  [
                    162,
                    100,
                    97,
                    114,
                    103,
                    115,
                    131,
                    24,
                    100,
                    99,
                    116,
                    119,
                    111,
                    245,
                    102,
                    107,
                    119,
                    97,
                    114,
                    103,
                    115,
                    163,
                    100,
                    107,
                    101,
                    121,
                    49,
                    24,
                    100,
                    100,
                    107,
                    101,
                    121,
                    50,
                    99,
                    116,
                    119,
                    111,
                    100,
                    107,
                    101,
                    121,
                    51,
                    245,
                  ],
                ),
              ],
            ),
          );
        } else if (message.id == MessageTypes.codeCall &&
            (message as Call).argumentsKeywords!['value'] != -3 &&
            (message).argumentsKeywords!['value'] != -4 &&
            (message).argumentsKeywords!['value'] != -5) {
          transport.receiveMessage(
            Result(
              message.requestId,
              ResultDetails(progress: true),
              arguments: message.arguments,
            ),
          );
          transport.receiveMessage(
            Result(
              message.requestId,
              ResultDetails(progress: false),
              argumentsKeywords: message.argumentsKeywords,
            ),
          );
        } else if (message.id == MessageTypes.codeCall &&
            (message as Call).argumentsKeywords!['value'] == -3) {
          transport.receiveMessage(
            Error(
              MessageTypes.codeCall,
              message.requestId,
              HashMap(),
              Error.noSuchRegistration,
              arguments: message.arguments,
              argumentsKeywords: message.argumentsKeywords,
            ),
          );
        } else if (message.id == MessageTypes.codeCall &&
            (message as Call).argumentsKeywords!['value'] == -4) {
          // ignored because it will not complete before cancellation happens
        } else if (message.id == MessageTypes.codeCall &&
            (message as Call).argumentsKeywords!['value'] == -5) {
          cancelRequestErrorRequestIds.add(message.requestId);
        } else if (message.id == MessageTypes.codeCancel) {
          final cancel = message as Cancel;
          if (cancelRequestErrorRequestIds.remove(cancel.requestId)) {
            transport.receiveMessage(
              Error(
                MessageTypes.codeCancel,
                cancel.requestId,
                HashMap(),
                Error.invalidArgument,
                arguments: ['cancel failed'],
              ),
            );
          } else {
            transport.receiveMessage(
              Error(
                MessageTypes.codeCall,
                cancel.requestId,
                HashMap(),
                Error.errorInvocationCanceled,
                arguments: [cancel.options!.mode],
              ),
            );
          }
        } else if (message.id == MessageTypes.codeYield &&
            (message as Yield).invocationRequestId == 55001100) {
          yieldCompleter2.complete(message);
        } else if (message.id == MessageTypes.codeYield &&
            (message as Yield).options?.pptScheme == 'x_custom_scheme') {
          transport.receiveMessage(message);
        } else if (message.id == MessageTypes.codeYield &&
            (message as Yield).argumentsKeywords!['value'] == 0) {
          yieldCompleter.complete(message);
        } else if (message.id == MessageTypes.codeYield &&
            (message as Yield).argumentsKeywords!['progressiveCalls'] != null) {
          progressiveCallYieldCompleter.complete(message);
        } else if (message.id == MessageTypes.codeError &&
            (message as Error).error == Error.unknown) {
          error1completer.complete(message);
        } else if (message.id == MessageTypes.codeError &&
            (message as Error).error == Error.notAuthorized) {
          error2completer.complete(message);
        } else if (message.id == MessageTypes.codeError &&
            (message as Error).error == Error.noSuchRegistration) {
          error3completer.complete(message);
        }
      });

      final session = await client.connect().first;
      final registrationErrorCompleter = Completer<Error>();

      // NOT WORKING REGISTRATION

      unawaited(
        session
            .register('my.error')
            .then(
              (registered) {},
              onError: (error) {
                registrationErrorCompleter.complete(error);
              },
            ),
      );

      final registrationError = await registrationErrorCompleter.future;
      expect(registrationError, isNotNull);
      expect(
        registrationError.requestTypeId,
        equals(MessageTypes.codeRegister),
      );
      expect(registrationError.id, equals(MessageTypes.codeError));

      // WORKING REGISTRATION

      final registered = await session.register('my.procedure');
      expect(registered, isNotNull);
      expect(registered.registrationId, equals(1010));
      expect(registered.procedure, equals('my.procedure'));

      var progressiveCalls = 0;
      registered.onInvoke((invocation) {
        if (invocation.argumentsKeywords?['value'] == 0) {
          invocation.respondWith(
            arguments: invocation.arguments,
            argumentsKeywords: invocation.argumentsKeywords,
          );
        }
        if (invocation.argumentsKeywords?['value'] == 1) {
          progressiveCalls++;
          if (!invocation.isProgressive()) {
            invocation.argumentsKeywords!['progressiveCalls'] =
                progressiveCalls;
            invocation.respondWith(
              arguments: invocation.arguments,
              argumentsKeywords: invocation.argumentsKeywords,
            );
          }
        }
        if (invocation.argumentsKeywords?['value'] == -1) {
          throw Exception('Something went wrong');
        }
        // PPT Payload received
        if (invocation.details.pptScheme != null) {
          expect(invocation.details.pptScheme, equals('x_custom_scheme'));
          expect(invocation.details.pptSerializer, equals('cbor'));
          invocation.respondWith(
            arguments: invocation.arguments,
            argumentsKeywords: invocation.argumentsKeywords,
            options: YieldOptions(
              pptScheme: 'x_custom_scheme',
              pptSerializer: 'cbor',
            ),
          );
        }
        if (invocation.argumentsKeywords?['value'] == -2) {
          invocation.respondWith(
            isError: true,
            errorUri: Error.notAuthorized,
            arguments: invocation.arguments,
            argumentsKeywords: invocation.argumentsKeywords,
          );
        }
      });

      // REGULAR YIELD

      final argumentsKeywords = HashMap<String, Object>();
      argumentsKeywords['value'] = 0;
      transport.receiveMessage(
        Invocation(
          11001100,
          registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work'],
          argumentsKeywords: argumentsKeywords,
        ),
      );
      final yieldMessage = await yieldCompleter.future;
      expect(yieldMessage, isNotNull);
      expect(yieldMessage.argumentsKeywords!['value'], equals(0));
      expect(yieldMessage.arguments![0], equals('did work'));

      // PPT YIELD

      transport.receiveMessage(
        Invocation(
          55001100,
          registered.registrationId,
          InvocationDetails(null, null, false, 'x_custom_scheme', 'cbor'),
          arguments: [
            Uint8List.fromList(
              // Data below is the same as in cbor serializer deserializePPT test
              [
                162,
                100,
                97,
                114,
                103,
                115,
                131,
                24,
                100,
                99,
                116,
                119,
                111,
                245,
                102,
                107,
                119,
                97,
                114,
                103,
                115,
                163,
                100,
                107,
                101,
                121,
                49,
                24,
                100,
                100,
                107,
                101,
                121,
                50,
                99,
                116,
                119,
                111,
                100,
                107,
                101,
                121,
                51,
                245,
              ],
            ),
          ],
        ),
      );
      final pptYieldMessage = await yieldCompleter2.future;
      expect(pptYieldMessage, isNotNull);

      // PPT RESULT
      session
          .call(
            'my.procedure',
            arguments: <dynamic>[100, 'two', true],
            argumentsKeywords: {'key1': 100, 'key2': 'two', 'key3': true},
            options: CallOptions(
              pptScheme: 'x_custom_scheme',
              pptSerializer: 'cbor',
            ),
          )
          .listen(
            (result) => () {
              expect(result, isNotNull);
              expect(result.details.pptScheme, equals('x_custom_scheme'));
              expect(result.details.pptSerializer, equals('cbor'));
              expect(result.argumentsKeywords!['key1'], equals(100));
              expect(result.argumentsKeywords!['key2'], equals('two'));
              expect(result.argumentsKeywords!['key3'], equals(true));
              expect(result.arguments![0], equals(100));
              expect(result.arguments![1], equals('two'));
              expect(result.arguments![2], equals(true));
            },
          );

      // PROGRESSIVE CALL

      final progressiveArgumentsKeywords = HashMap<String, Object>();
      progressiveArgumentsKeywords['value'] = 1;
      transport.receiveMessage(
        Invocation(
          21001100,
          registered.registrationId,
          InvocationDetails(null, null, true),
          arguments: ['did work?'],
          argumentsKeywords: progressiveArgumentsKeywords,
        ),
      );
      transport.receiveMessage(
        Invocation(
          21001101,
          registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work again'],
          argumentsKeywords: progressiveArgumentsKeywords,
        ),
      );
      final finalYieldMessage = await progressiveCallYieldCompleter.future;
      expect(finalYieldMessage, isNotNull);
      expect(finalYieldMessage.argumentsKeywords!['value'], equals(1));
      expect(
        finalYieldMessage.argumentsKeywords!['progressiveCalls'],
        equals(2),
      );
      expect(finalYieldMessage.arguments![0], equals('did work again'));

      // PROGRESSIVE RESULT

      final progressiveCallArgumentsKeywords = HashMap<String, Object>();
      progressiveArgumentsKeywords['value'] = 2;
      final resultList = <Result>[];
      await for (final result in session.call(
        'my.procedure',
        options: CallOptions(receiveProgress: true),
        arguments: ['called'],
        argumentsKeywords: progressiveCallArgumentsKeywords,
      )) {
        resultList.add(result);
      }
      expect(resultList.length, equals(2));

      // ERROR BY EXCEPTION

      final argumentsKeywords2 = HashMap<String, Object>();
      argumentsKeywords2['value'] = -1;
      transport.receiveMessage(
        Invocation(
          11001101,
          registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work'],
          argumentsKeywords: argumentsKeywords2,
        ),
      );
      final error1 = await error1completer.future;
      expect(error1.requestTypeId, equals(MessageTypes.codeInvocation));
      expect(error1.requestId, equals(11001101));
      expect(error1, isNotNull);
      expect(error1.error, equals(Error.unknown));
      expect(error1.arguments![0], equals('Exception: Something went wrong'));

      // ERROR BY HANDLER

      final argumentsKeywords3 = HashMap<String, Object>();
      argumentsKeywords3['value'] = -2;
      transport.receiveMessage(
        Invocation(
          11001102,
          registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did work'],
          argumentsKeywords: argumentsKeywords3,
        ),
      );
      final error2 = await error2completer.future;
      expect(error2, isNotNull);
      expect(error2.requestTypeId, equals(MessageTypes.codeInvocation));
      expect(error2.requestId, equals(11001102));
      expect(error2.error, equals(Error.notAuthorized));
      expect(error2.arguments![0], equals('did work'));
      expect(error2.argumentsKeywords!['value'], equals(-2));

      // ERROR RESULT

      final errorCallArgumentsKeywords = HashMap<String, Object>();
      errorCallArgumentsKeywords['value'] = -3;
      final errorCallCompleter = Completer<Error>();
      session
          .call(
            'my.procedure',
            options: CallOptions(receiveProgress: true),
            arguments: ['was an error'],
            argumentsKeywords: errorCallArgumentsKeywords,
          )
          .listen(
            (result) {},
            onError: (error) => errorCallCompleter.complete(error),
          );
      var callError = await errorCallCompleter.future;
      expect(callError, isNotNull);
      expect(callError.requestTypeId, equals(MessageTypes.codeCall));
      expect(callError.arguments![0], equals('was an error'));
      expect(callError.argumentsKeywords!['value'], equals(-3));

      // ERROR BY CANCELLATION

      final errorCallCancellation = HashMap<String, Object>();
      errorCallCancellation['value'] = -4;
      final errorCallCancellationCompleter = Completer<Error>();
      final cancellationCompleter = Completer<String>();
      session
          .call(
            'my.procedure',
            argumentsKeywords: errorCallCancellation,
            cancelCompleter: cancellationCompleter,
          )
          .listen(
            (result) {},
            onError: (error) => errorCallCancellationCompleter.complete(error),
          );
      cancellationCompleter.complete(CancelOptions.modeKillNoWait);
      var cancelError = await errorCallCancellationCompleter.future;
      expect(cancelError, isNotNull);
      expect(cancelError.requestTypeId, equals(MessageTypes.codeCall));
      expect(cancelError.arguments![0], equals(CancelOptions.modeKillNoWait));

      // ERROR BY CANCELLATION REQUEST

      final cancelRequestErrorCompleter = Completer<Error>();
      final cancelRequestCompleter = Completer<String>();
      session
          .call(
            'my.procedure',
            argumentsKeywords: HashMap<String, Object>()..['value'] = -5,
            cancelCompleter: cancelRequestCompleter,
          )
          .listen(
            (result) {},
            onError: (error) => cancelRequestErrorCompleter.complete(error),
          );
      cancelRequestCompleter.complete(CancelOptions.modeKillNoWait);
      var cancelRequestError = await cancelRequestErrorCompleter.future;
      expect(cancelRequestError, isNotNull);
      expect(cancelRequestError.requestTypeId, equals(MessageTypes.codeCancel));
      expect(cancelRequestError.arguments![0], equals('cancel failed'));

      // UNREGISTER

      await session.unregister(registered.registrationId);

      final argumentsKeywordsRegular = HashMap<String, Object>();
      argumentsKeywordsRegular['value'] = 0;
      transport.receiveMessage(
        Invocation(
          11001199,
          registered.registrationId,
          InvocationDetails(null, null, false),
          arguments: ['did not work'],
          argumentsKeywords: argumentsKeywordsRegular,
        ),
      );
      final error3Message = await error3completer.future;
      expect(error3Message, isNotNull);
      expect(error3Message.requestTypeId, MessageTypes.codeInvocation);
      expect(error3Message.requestId, 11001199);
      expect(error3Message.argumentsKeywords, isNull);
      expect(error3Message.arguments, isNull);

      // UNREGISTER ERROR

      final errorUnregisterCompleter = Completer<Error>();
      unawaited(
        session
            .unregister(-1)
            .then(
              (message) {},
              onError: (error) => errorUnregisterCompleter.complete(error),
            ),
      );
      var unregisterError = await errorUnregisterCompleter.future;
      expect(unregisterError, isNotNull);
      expect(
        unregisterError.requestTypeId,
        equals(MessageTypes.codeUnregister),
      );
      expect(unregisterError.error, equals(Error.noSuchRegistration));
    });
    test('ignores interrupt messages without closing the session', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);

      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        }
      });

      final session = await client.connect().first;

      transport.receiveMessage(
        Interrupt(
          31337,
          options: InterruptOptions()..mode = CancelOptions.modeKillNoWait,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(session.id, equals(42));
      expect(transport.isOpen, isTrue);
    });
    test('interrupt auto-cancels pending materialized invocations', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      final invocationCancelError = Completer<Error>();

      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
          return;
        }
        if (message.id == MessageTypes.codeRegister) {
          transport.receiveMessage(
            Registered((message as Register).requestId, 1010),
          );
          return;
        }
        if (message is Error &&
            message.requestTypeId == MessageTypes.codeInvocation &&
            !invocationCancelError.isCompleted) {
          invocationCancelError.complete(message);
        }
      });

      final session = await client.connect().first;
      final registered = await session.registerHandler(
        'bench.cancel.proc',
        (_) {},
      );

      transport.receiveMessage(
        Invocation(
          31338,
          registered.registrationId,
          InvocationDetails(null, 'bench.cancel.proc', false),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      transport.receiveMessage(
        Interrupt(
          31338,
          options: InterruptOptions()..mode = CancelOptions.modeKillNoWait,
        ),
      );

      final error = await invocationCancelError.future;
      expect(error.error, equals(Error.errorInvocationCanceled));
      expect(error.arguments, equals([CancelOptions.modeKillNoWait]));
    });
    test(
      'queues early interrupts until materialized invocations arrive',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        final invocationCancelError = Completer<Error>();
        var invocationDelivered = false;

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveMessage(
              Registered((message as Register).requestId, 1011),
            );
            return;
          }
          if (message is Error &&
              message.requestTypeId == MessageTypes.codeInvocation &&
              !invocationCancelError.isCompleted) {
            invocationCancelError.complete(message);
          }
        });

        final session = await client.connect().first;
        final registered = await session.registerHandler('bench.cancel.proc', (
          _,
        ) {
          invocationDelivered = true;
        });

        transport.receiveMessage(
          Interrupt(
            31339,
            options: InterruptOptions()..mode = CancelOptions.modeKillNoWait,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        transport.receiveMessage(
          Invocation(
            31339,
            registered.registrationId,
            InvocationDetails(null, 'bench.cancel.proc', false),
          ),
        );

        final error = await invocationCancelError.future;
        expect(error.error, equals(Error.errorInvocationCanceled));
        expect(error.arguments, equals([CancelOptions.modeKillNoWait]));
        expect(invocationDelivered, isFalse);
      },
    );
    test(
      'registered invocationStream lazily receives routed invocations',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        final yieldCompleter = Completer<Yield>();

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveMessage(
              Registered((message as Register).requestId, 2020),
            );
            return;
          }
          if (message.id == MessageTypes.codeYield &&
              !yieldCompleter.isCompleted) {
            yieldCompleter.complete(message as Yield);
          }
        });

        final session = await client.connect().first;
        final registered = await session.register('lazy.proc');
        final invocationFuture = registered.invocationStream!.first;

        transport.receiveMessage(
          Invocation(
            9001,
            registered.registrationId,
            InvocationDetails(null, null, false),
            arguments: const ['payload'],
          ),
        );

        final invocation = await invocationFuture;
        expect(invocation.requestId, equals(9001));
        expect(invocation.arguments, equals(const ['payload']));

        invocation.respondWith(arguments: const ['done']);

        final yieldMessage = await yieldCompleter.future;
        expect(yieldMessage.invocationRequestId, equals(9001));
        expect(yieldMessage.arguments, equals(const ['done']));
      },
    );
    test('subscribed onEvent lazily receives routed events', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);

      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
          return;
        }
        if (message.id == MessageTypes.codeSubscribe) {
          transport.receiveMessage(
            Subscribed((message as Subscribe).requestId, 3030),
          );
        }
      });

      final session = await client.connect().first;
      final subscribed = await session.subscribe('lazy.topic');
      final eventCompleter = Completer<Event>();

      subscribed.onEvent((event) {
        if (!eventCompleter.isCompleted) {
          eventCompleter.complete(event);
        }
      });

      transport.receiveMessage(
        Event(
          subscribed.subscriptionId,
          7001,
          EventDetails(),
          argumentsKeywords: const {'worker': 1},
        ),
      );

      final event = await eventCompleter.future;
      expect(event.publicationId, equals(7001));
      expect(event.argumentsKeywords, equals(const {'worker': 1}));
    });
    test(
      'subscribeHandler routes events without touching eventStream',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeSubscribe) {
            transport.receiveMessage(
              Subscribed((message as Subscribe).requestId, 4040),
            );
          }
        });

        final session = await client.connect().first;
        final eventCompleter = Completer<Event>();
        final subscribed = await session.subscribeHandler('handler.topic', (
          event,
        ) {
          if (!eventCompleter.isCompleted) {
            eventCompleter.complete(event);
          }
        });

        transport.receiveMessage(
          Event(
            subscribed.subscriptionId,
            8001,
            EventDetails(),
            arguments: const ['payload'],
          ),
        );

        final event = await eventCompleter.future;
        expect(event.publicationId, equals(8001));
        expect(event.arguments, equals(const ['payload']));
      },
    );
    test(
      'subscribePayloadHandler routes payloads without requiring Event wrappers',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeSubscribe) {
            transport.receiveMessage(
              Subscribed((message as Subscribe).requestId, 4141),
            );
          }
        });

        final session = await client.connect().first;
        final eventCompleter = Completer<EventPayload>();
        final subscribed = await session.subscribePayloadHandler(
          'payload.topic',
          (event) {
            if (!eventCompleter.isCompleted) {
              eventCompleter.complete(event);
            }
          },
        );

        transport.receiveMessage(
          Event(
            subscribed.subscriptionId,
            8101,
            EventDetails(topic: 'payload.topic'),
            argumentsKeywords: const {'worker': 1},
          ),
        );

        final event = await eventCompleter.future;
        expect(event.publicationId, equals(8101));
        expect(event.topic, equals('payload.topic'));
        expect(event.argumentsKeywords, equals(const {'worker': 1}));
      },
    );
    test('subscribeLazyPayloadHandler routes lazy payload views', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);

      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
          return;
        }
        if (message.id == MessageTypes.codeSubscribe) {
          transport.receiveMessage(
            Subscribed((message as Subscribe).requestId, 4242),
          );
        }
      });

      final session = await client.connect().first;
      final eventCompleter = Completer<LazyEventPayload>();
      final subscribed = await session.subscribeLazyPayloadHandler(
        'lazy.topic',
        (event) {
          if (!eventCompleter.isCompleted) {
            eventCompleter.complete(event);
          }
        },
      );

      transport.receiveMessage(
        Event(
          subscribed.subscriptionId,
          8201,
          EventDetails(topic: 'lazy.topic'),
          argumentsKeywords: const {'worker': 2},
        ),
      );

      final event = await eventCompleter.future;
      expect(event.publicationId, equals(8201));
      expect(event.topic, equals('lazy.topic'));
      expect(event.argumentsKeywords, equals(const {'worker': 2}));
    });
    test(
      'native direct event path keeps PPT lazy bytes and exposes unpacked payloads',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeSubscribe) {
            transport.receiveObject(
              Subscribed((message as Subscribe).requestId, 4343),
            );
          }
        });

        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final lazyCompleter = Completer<LazyEventPayload>();
        final payloadCompleter = Completer<EventPayload>();
        final subscribed = await session.subscribeLazyPayloadHandler(
          'ppt.topic',
          (event) {
            if (!lazyCompleter.isCompleted) {
              lazyCompleter.complete(event);
            }
          },
        );
        subscribed.onEventPayload((event) {
          if (!payloadCompleter.isCompleted) {
            payloadCompleter.complete(event);
          }
        });

        final argsBytes = _encodeNativePptArguments(
          arguments: const ['ppt-event'],
          argumentsKeywords: const {'worker': 7},
        );
        final packedPayloadBytes = _encodeNativePptPayload(
          arguments: const ['ppt-event'],
          argumentsKeywords: const {'worker': 7},
        );
        transport.receiveObject(
          _nativeDirectEventMessage(
            subscriptionId: subscribed.subscriptionId,
            publicationId: 8401,
            topic: 'ppt.topic',
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
            argsBytes: argsBytes,
          ),
        );

        final lazyEvent = await lazyCompleter.future;
        final payloadEvent = await payloadCompleter.future;
        expect(lazyEvent.publicationId, equals(8401));
        expect(lazyEvent.topic, equals('ppt.topic'));
        expect(lazyEvent.pptScheme, equals('x_custom_scheme'));
        expect(lazyEvent.argumentsBytes, isNull);
        expect(lazyEvent.packedPayloadBytes, orderedEquals(packedPayloadBytes));
        expect(payloadEvent.arguments, equals(const ['ppt-event']));
        expect(payloadEvent.argumentsKeywords, equals(const {'worker': 7}));
      },
    );
    test(
      'subscribeHandler lazily unpacks PPT payloads on the native direct event path',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeSubscribe) {
            transport.receiveObject(
              Subscribed((message as Subscribe).requestId, 4343),
            );
          }
        });

        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final eventCompleter = Completer<Event>();
        final subscribed = await session.subscribeHandler('ppt.topic', (event) {
          if (!eventCompleter.isCompleted) {
            eventCompleter.complete(event);
          }
        });

        transport.receiveObject(
          _nativeDirectEventMessage(
            subscriptionId: subscribed.subscriptionId,
            publicationId: 8401,
            topic: 'ppt.topic',
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
            argsBytes: _encodeNativePptArguments(
              arguments: const ['ppt-event'],
              argumentsKeywords: const {'worker': 7},
            ),
          ),
        );

        final event = await eventCompleter.future;
        expect(event.hasDecodedPptPayload, isFalse);
        expect(event.arguments, equals(const ['ppt-event']));
        expect(event.argumentsKeywords, equals(const {'worker': 7}));
        expect(event.hasDecodedPptPayload, isTrue);
      },
    );
    test(
      'registerHandler catches async failures and ignores late failures after final yields',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        final unknownErrors = <Error>[];
        final yields = <Yield>[];

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveMessage(
              Registered((message as Register).requestId, 5050),
            );
            return;
          }
          if (message.id == MessageTypes.codeYield) {
            yields.add(message as Yield);
            return;
          }
          if (message.id == MessageTypes.codeError &&
              (message as Error).error == Error.unknown) {
            unknownErrors.add(message);
          }
        });

        final session = await client.connect().first;
        final registered = await session.registerHandler('handler.proc', (
          invocation,
        ) async {
          final value = invocation.argumentsKeywords?['value'];
          if (value == 1) {
            await Future<void>.delayed(Duration.zero);
            throw StateError('async failure');
          }
          invocation.respondWith(arguments: const ['done']);
          await Future<void>.delayed(Duration.zero);
          throw StateError('late failure');
        });

        transport.receiveMessage(
          Invocation(
            9101,
            registered.registrationId,
            InvocationDetails(null, null, false),
            argumentsKeywords: const {'value': 1},
          ),
        );
        transport.receiveMessage(
          Invocation(
            9102,
            registered.registrationId,
            InvocationDetails(null, null, false),
            argumentsKeywords: const {'value': 2},
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(yields, hasLength(1));
        expect(yields.single.invocationRequestId, equals(9102));
        expect(unknownErrors, hasLength(1));
        expect(unknownErrors.single.requestId, equals(9101));
        expect(
          unknownErrors.single.arguments,
          equals(const ['Bad state: async failure']),
        );
      },
    );
    test(
      'registerPayloadHandler routes invocation payloads and responses',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        final yields = <Yield>[];

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveMessage(
              Registered((message as Register).requestId, 5151),
            );
            return;
          }
          if (message.id == MessageTypes.codeYield) {
            yields.add(message as Yield);
          }
        });

        final session = await client.connect().first;
        final invocationCompleter = Completer<InvocationPayload>();
        final registered = await session.registerPayloadHandler(
          'payload.proc',
          (invocation) {
            if (!invocationCompleter.isCompleted) {
              invocationCompleter.complete(invocation);
            }
            invocation.respondWith(arguments: const ['done']);
          },
        );

        transport.receiveMessage(
          Invocation(
            9201,
            registered.registrationId,
            InvocationDetails(9, 'payload.proc', false),
            argumentsKeywords: const {'value': 3},
          ),
        );

        final invocation = await invocationCompleter.future;
        await Future<void>.delayed(Duration.zero);
        expect(invocation.requestId, equals(9201));
        expect(invocation.caller, equals(9));
        expect(invocation.procedure, equals('payload.proc'));
        expect(invocation.argumentsKeywords, equals(const {'value': 3}));
        expect(yields, hasLength(1));
        expect(yields.single.invocationRequestId, equals(9201));
        expect(yields.single.arguments, equals(const ['done']));
      },
    );
    test(
      'registerLazyPayloadHandler routes lazy invocation payloads and responses',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        final yields = <Yield>[];

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveMessage(
              Registered((message as Register).requestId, 5252),
            );
            return;
          }
          if (message.id == MessageTypes.codeYield) {
            yields.add(message as Yield);
          }
        });

        final session = await client.connect().first;
        final invocationCompleter = Completer<LazyInvocationPayload>();
        final registered = await session.registerLazyPayloadHandler(
          'lazy.proc',
          (invocation) {
            if (!invocationCompleter.isCompleted) {
              invocationCompleter.complete(invocation);
            }
            invocation.respondWith(arguments: const ['lazy-done']);
          },
        );

        transport.receiveMessage(
          Invocation(
            9301,
            registered.registrationId,
            InvocationDetails(11, 'lazy.proc', false),
            argumentsKeywords: const {'value': 4},
          ),
        );

        final invocation = await invocationCompleter.future;
        await Future<void>.delayed(Duration.zero);
        expect(invocation.requestId, equals(9301));
        expect(invocation.caller, equals(11));
        expect(invocation.procedure, equals('lazy.proc'));
        expect(invocation.argumentsKeywords, equals(const {'value': 4}));
        expect(yields, hasLength(1));
        expect(yields.single.invocationRequestId, equals(9301));
        expect(yields.single.arguments, equals(const ['lazy-done']));
      },
    );
    test(
      'native direct invocation path keeps PPT lazy bytes and exposes unpacked payloads',
      () async {
        final yields = <Yield>[];
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveObject(
              Registered((message as Register).requestId, 5353),
            );
            return;
          }
          if (message.id == MessageTypes.codeYield) {
            yields.add(message as Yield);
          }
        });

        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final lazyCompleter = Completer<LazyInvocationPayload>();
        final payloadCompleter = Completer<InvocationPayload>();
        final registered = await session.registerLazyPayloadHandler(
          'ppt.proc',
          (invocation) {
            if (!lazyCompleter.isCompleted) {
              lazyCompleter.complete(invocation);
            }
            invocation.respondWith(arguments: const ['ppt-ok']);
          },
        );
        registered.onInvokePayload((invocation) {
          if (!payloadCompleter.isCompleted) {
            payloadCompleter.complete(invocation);
          }
        });

        final argsBytes = _encodeNativePptArguments(
          arguments: const ['ppt-invocation'],
          argumentsKeywords: const {'worker': 8},
        );
        final packedPayloadBytes = _encodeNativePptPayload(
          arguments: const ['ppt-invocation'],
          argumentsKeywords: const {'worker': 8},
        );
        transport.receiveObject(
          _nativeDirectInvocationMessage(
            requestId: 9401,
            registrationId: registered.registrationId,
            procedure: 'ppt.proc',
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
            argsBytes: argsBytes,
          ),
        );

        final lazyInvocation = await lazyCompleter.future;
        final payloadInvocation = await payloadCompleter.future;
        await Future<void>.delayed(Duration.zero);
        expect(lazyInvocation.requestId, equals(9401));
        expect(lazyInvocation.pptScheme, equals('x_custom_scheme'));
        expect(lazyInvocation.argumentsBytes, isNull);
        expect(
          lazyInvocation.packedPayloadBytes,
          orderedEquals(packedPayloadBytes),
        );
        expect(payloadInvocation.arguments, equals(const ['ppt-invocation']));
        expect(
          payloadInvocation.argumentsKeywords,
          equals(const {'worker': 8}),
        );
        expect(yields, hasLength(1));
        expect(yields.single.arguments, equals(const ['ppt-ok']));
      },
    );
    test(
      'registerHandler lazily unpacks PPT payloads on the native direct invocation path',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveObject(
              Registered((message as Register).requestId, 5050),
            );
            return;
          }
        });
        final yields = <Yield>[];
        transport.outbound.stream.listen((message) {
          if (message is Yield) {
            yields.add(message);
          }
        });

        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final invocationCompleter = Completer<Invocation>();
        final registered = await session.registerHandler('ppt.proc', (
          invocation,
        ) {
          if (!invocationCompleter.isCompleted) {
            invocationCompleter.complete(invocation);
          }
          invocation.respondWith(arguments: const ['ppt-ok']);
        });

        transport.receiveObject(
          _nativeDirectInvocationMessage(
            requestId: 9401,
            registrationId: registered.registrationId,
            procedure: 'ppt.proc',
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
            argsBytes: _encodeNativePptArguments(
              arguments: const ['ppt-invocation'],
              argumentsKeywords: const {'worker': 8},
            ),
          ),
        );

        final invocation = await invocationCompleter.future;
        await Future<void>.delayed(Duration.zero);
        expect(invocation.hasDecodedPptPayload, isFalse);
        expect(invocation.arguments, equals(const ['ppt-invocation']));
        expect(invocation.argumentsKeywords, equals(const {'worker': 8}));
        expect(invocation.hasDecodedPptPayload, isTrue);
        expect(yields, hasLength(1));
        expect(yields.single.arguments, equals(const ['ppt-ok']));
      },
    );
    test('native direct interrupt auto-cancels pending invocations', () async {
      final transport = _SessionOptimizedMockTransport((message, transport) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveObject(Welcome(42, Details.forWelcome()));
          return;
        }
        if (message.id == MessageTypes.codeRegister) {
          transport.receiveObject(
            Registered((message as Register).requestId, 6060),
          );
          return;
        }
      });
      final invocationCancelError = Completer<Error>();
      transport.outbound.stream.listen((message) {
        if (message is Error &&
            message.requestTypeId == MessageTypes.codeInvocation &&
            !invocationCancelError.isCompleted) {
          invocationCancelError.complete(message);
        }
      });

      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final registered = await session.registerLazyPayloadHandler(
        'bench.cancel.proc',
        (_) {},
      );

      transport.receiveObject(
        _nativeDirectInvocationMessage(
          requestId: 9501,
          registrationId: registered.registrationId,
          procedure: 'bench.cancel.proc',
          pptScheme: '',
          pptSerializer: '',
          argsBytes: Uint8List.fromList(
            cbor.cborEncode(cbor.CborValue(const <Object?>[])),
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      transport.receiveObject(
        _nativeDirectInterruptMessage(
          requestId: 9501,
          mode: CancelOptions.modeKillNoWait,
        ),
      );

      final error = await invocationCancelError.future;
      expect(error.error, equals(Error.errorInvocationCanceled));
      expect(error.arguments, equals([CancelOptions.modeKillNoWait]));
    });
    test(
      'queues early native direct interrupts until invocations arrive',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeRegister) {
            transport.receiveObject(
              Registered((message as Register).requestId, 6061),
            );
            return;
          }
        });
        final invocationCancelError = Completer<Error>();
        var invocationDelivered = false;
        transport.outbound.stream.listen((message) {
          if (message is Error &&
              message.requestTypeId == MessageTypes.codeInvocation &&
              !invocationCancelError.isCompleted) {
            invocationCancelError.complete(message);
          }
        });

        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final registered = await session.registerLazyPayloadHandler(
          'bench.cancel.proc',
          (_) {
            invocationDelivered = true;
          },
        );

        transport.receiveObject(
          _nativeDirectInterruptMessage(
            requestId: 9502,
            mode: CancelOptions.modeKillNoWait,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        transport.receiveObject(
          _nativeDirectInvocationMessage(
            requestId: 9502,
            registrationId: registered.registrationId,
            procedure: 'bench.cancel.proc',
            pptScheme: '',
            pptSerializer: '',
            argsBytes: Uint8List.fromList(
              cbor.cborEncode(cbor.CborValue(const <Object?>[])),
            ),
          ),
        );

        final error = await invocationCancelError.future;
        expect(error.error, equals(Error.errorInvocationCanceled));
        expect(error.arguments, equals([CancelOptions.modeKillNoWait]));
        expect(invocationDelivered, isFalse);
      },
    );
    test('event subscription and publish', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);

      // ALL ROUTER MOCK RESULTS
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(Welcome(42, Details.forWelcome()));
        }
        if (message.id == MessageTypes.codePublish &&
            (message as Publish).options?.acknowledge != null &&
            (message).options?.acknowledge == true) {
          transport.receiveMessage(Published((message).requestId, 1));
        }
        if (message.id == MessageTypes.codeSubscribe) {
          if ((message as Subscribe).topic == 'topic.my.de') {
            transport.receiveMessage(Subscribed(message.requestId, 10));
          }
          if (message.topic == 'topic.revoke') {
            transport.receiveMessage(Subscribed(message.requestId, 11));
            transport.receiveMessage(
              Unsubscribed(0, UnsubscribedDetails(11, 'error.500')),
            );
          }
          if (message.topic == 'topic.my.error') {
            transport.receiveMessage(
              Error(
                MessageTypes.codeSubscribe,
                message.requestId,
                {},
                Error.notAuthorized,
              ),
            );
          }
        }
        if (message.id == MessageTypes.codeUnsubscribe) {
          if ((message as Unsubscribe).subscriptionId == -1) {
            transport.receiveMessage(
              Error(
                MessageTypes.codeUnsubscribe,
                message.requestId,
                {},
                Error.noSuchSubscription,
              ),
            );
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
      unawaited(
        session
            .subscribe('topic.my.error')
            .then(
              (message) {},
              onError: (error) => subscribeErrorCompleter.complete(error),
            ),
      );
      var subscribeError = await subscribeErrorCompleter.future;
      expect(subscribeError, isNotNull);
      expect(subscribeError.error, equals(Error.notAuthorized));
      expect(subscribeError.requestTypeId, equals(MessageTypes.codeSubscribe));

      // REGULAR PUBLISH

      var published = await session.publish(
        'my.test.topic',
        arguments: ['some data'],
        options: PublishOptions(acknowledge: true),
      );
      expect(published, isNotNull);
      expect(published?.publishRequestId, isNotNull);
      expect(published?.publicationId, equals(1));

      published = await session.publish(
        'my.test.topic',
        arguments: ['some data'],
        options: PublishOptions(acknowledge: false),
      );
      expect(published, isNull);

      published = await session.publish(
        'my.test.topic',
        arguments: <dynamic>[100, 'two', true],
        argumentsKeywords: {'key1': 100, 'key2': 'two', 'key3': true},
        options: PublishOptions(
          pptScheme: 'x_custom_scheme',
          pptSerializer: 'cbor',
        ),
      );
      expect(published, isNull);

      published = await session.publish(
        'my.test.topic',
        arguments: ['some data'],
      );
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
        Event(subscribed.subscriptionId, 1122, EventDetails()),
      );
      var event = await eventCompleter.future;
      expect(event, isNotNull);
      expect(event.publicationId, equals(1122));

      transport.receiveMessage(
        Event(subscribed.subscriptionId, 1133, EventDetails()),
      );
      var event2 = await eventCompleter2.future;
      expect(event2, isNotNull);
      expect(event2.publicationId, equals(1133));

      transport.receiveMessage(
        Event(
          subscribed.subscriptionId,
          1155,
          EventDetails(pptScheme: 'x_custom_scheme', pptSerializer: 'cbor'),
          arguments: [
            Uint8List.fromList([
              162,
              100,
              97,
              114,
              103,
              115,
              131,
              24,
              100,
              99,
              116,
              119,
              111,
              245,
              102,
              107,
              119,
              97,
              114,
              103,
              115,
              163,
              100,
              107,
              101,
              121,
              49,
              24,
              100,
              100,
              107,
              101,
              121,
              50,
              99,
              116,
              119,
              111,
              100,
              107,
              101,
              121,
              51,
              245,
            ]),
          ],
        ),
      );
      var event4 = await eventCompleter4.future;
      expect(event4, isNotNull);
      expect(event4.publicationId, equals(1155));
      expect(event4.arguments, equals([100, 'two', true]));
      expect(
        event4.argumentsKeywords,
        equals({'key1': 100, 'key2': 'two', 'key3': true}),
      );

      // UNSUBSCRIBE ERROR

      Error? unsubscribeError;
      try {
        await session.unsubscribe(-1);
      } on Error catch (error) {
        unsubscribeError = error;
      }
      expect(unsubscribeError, isNotNull);
      expect(unsubscribeError!.error, Error.noSuchSubscription);

      unsubscribeError = null;
      try {
        await session.unsubscribe(subscribed.subscriptionId);
      } on Error catch (error) {
        unsubscribeError = error;
      }
      expect(unsubscribeError, isNull);

      // DO NOT RECEIVE EVENTS WHEN UNSUBSCRIBED

      transport.receiveMessage(
        Event(subscribed.subscriptionId, 1144, EventDetails()),
      );
      Event? event3;
      unawaited(eventCompleter3.future.then((event) => event3 = event));
      await Future.delayed(Duration(milliseconds: 3));
      expect(event3, isNull);
    });
    test('session creation with authextra', () async {
      final transport = _MockTransport();
      Hello? sentHello;
      final client = Client(
        realm: 'test.realm',
        transport: transport,
        authExtra: {'test': true},
      );
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          sentHello = message as Hello;
          transport.receiveMessage(
            Welcome(
              42,
              Details.forWelcome(
                authId: 'Richi',
                authMethod: 'none',
                authProvider: 'noProvider',
                authRole: 'client',
                authExtra: {'test': true},
              ),
            ),
          );
        }
      });

      List<LogRecord> logRecords = [];
      Logger.root.onRecord.listen((record) {
        logRecords.add(record);
      });

      final session = await client.connect().first;
      expect(session.realm, equals('test.realm'));
      expect(session.id, equals(42));
      expect(session.authId, equals('Richi'));
      expect(session.authRole, equals('client'));
      expect(session.authProvider, equals('noProvider'));
      expect(session.authMethod, equals('none'));
      expect(session.authExtra, equals({'test': true}));
      expect(sentHello?.details.authextra, equals({'test': true}));
      expect(
        logRecords[2].message,
        equals('Warning! No realm returned by the router'),
      );
    });

    test('session exposes negotiated e2ee auth extra state', () async {
      final transport = _MockTransport();
      final helloAuthExtra = {
        'e2ee': {
          'version': 1,
          'required': false,
          'schemes': ['wamp'],
          'ciphers': ['xsalsa20poly1305'],
        },
      };
      final welcomeAuthExtra = {
        'e2ee': {
          'established': true,
          'scheme': 'wamp',
          'serializer': 'cbor',
          'cipher': 'xsalsa20poly1305',
          'send_key_id': 'kid-server-a',
          'receive_key_id': 'kid-client-a',
          'peer_pubkey': 'server-pubkey',
        },
      };
      Hello? sentHello;
      final client = Client(
        realm: 'test.realm',
        transport: transport,
        authExtra: helloAuthExtra,
      );

      transport.outbound.stream.listen((message) {
        if (message.id != MessageTypes.codeHello) {
          return;
        }
        sentHello = message as Hello;
        transport.receiveMessage(
          Welcome(
            42,
            Details.forWelcome(
              authId: 'Richi',
              authMethod: 'ticket',
              authProvider: 'auth-service',
              authRole: 'client',
              authExtra: welcomeAuthExtra,
            ),
          ),
        );
      });

      final session = await client.connect().first;
      expect(sentHello?.details.authextra, equals(helloAuthExtra));
      expect(session.authExtra, equals(welcomeAuthExtra));
      expect(session.e2eeProvider, isNull);
      expect(session.negotiatedE2ee, isNotNull);
      expect(session.negotiatedE2ee?.established, isTrue);
      expect(session.negotiatedE2ee?.scheme, 'wamp');
      expect(session.negotiatedE2ee?.serializer, 'cbor');
      expect(session.negotiatedE2ee?.cipher, 'xsalsa20poly1305');
      expect(session.negotiatedE2ee?.sendKeyId, 'kid-server-a');
      expect(session.negotiatedE2ee?.receiveKeyId, 'kid-client-a');
      expect(session.negotiatedE2ee?.peerPublicKey, 'server-pubkey');
    });
    test('session creation transport open fail', () async {
      final transport = _MockTransport();
      transport.failToOpen = true;

      final client = Client(realm: 'test.realm', transport: transport);
      final connection = client.connect();
      connection.listen(
        null,
        onError: expectAsync1((abort) {
          expect(
            abort,
            isA<Abort>()
                .having(
                  (a) => a.reason,
                  'reason',
                  equals(Error.couldNotConnect),
                )
                .having(
                  (a) => a.message?.message,
                  'message',
                  equals(
                    'Could not connect to server. '
                    'Please configure reconnectTime to retry automatically.',
                  ),
                ),
          );
        }),
      );
    });
    test('session disconnect on goodbye', () async {
      final transport = _MockTransport();
      final client = Client(
        realm: 'test.realm',
        transport: transport,
        authId: '11111111',
        authenticationMethods: null,
      );
      final goodbyeSentCompleter = Completer();

      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Challenge(
              'this is not a valid auth method',
              Extra(challenge: 'nothing'),
            ),
          );
        }
        if (message.id == MessageTypes.codeGoodbye) {
          goodbyeSentCompleter.complete(message);
        }
      });
      final connection = client.connect();

      final message = await goodbyeSentCompleter.future;
      expect(
        message,
        isA<Goodbye>().having(
          (g) => g.reason,
          'reason',
          Goodbye.reasonGoodbyeAndOut,
        ),
      );
      expect(connection.drain(), completes);
    });
    test('client disconnect closes transport and session', () async {
      final transport = _MockTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      transport.outbound.stream.listen((message) {
        if (message.id == MessageTypes.codeHello) {
          transport.receiveMessage(
            Welcome(
              42,
              Details.forWelcome(
                authId: 'Richi',
                authMethod: 'none',
                authProvider: 'noProvider',
                authRole: 'client',
              ),
            ),
          );
        }
      });
      final session = await client.connect().first;
      await client.disconnect();

      expect(transport.isOpen, isFalse);
      expect(session.isConnected(), isFalse);
      expect(session.onDisconnect, completes);
    });
    test('request-response APIs handle immediate router replies', () async {
      const stepTimeout = Duration(seconds: 1);
      final transport = _ImmediateResponseTransport();
      final client = Client(realm: 'test.realm', transport: transport);
      final session = await client.connect().first.timeout(stepTimeout);

      final result = await session
          .call('bench.fast')
          .first
          .timeout(stepTimeout);
      expect(result.arguments, equals(['ok']));

      final singleResult = await session
          .callSingle('bench.fast')
          .timeout(stepTimeout);
      expect(singleResult.arguments, equals(['ok']));

      final published = await session
          .publish('bench.topic', options: PublishOptions(acknowledge: true))
          .timeout(stepTimeout);
      expect(published, isNotNull);
      expect(published!.publicationId, equals(1));

      final subscribed = await session
          .subscribe('bench.topic')
          .timeout(stepTimeout);
      expect(subscribed.subscriptionId, equals(10));
      await session.unsubscribe(subscribed.subscriptionId).timeout(stepTimeout);

      final registered = await session
          .register('bench.proc')
          .timeout(stepTimeout);
      expect(registered.registrationId, equals(20));
      await session.unregister(registered.registrationId).timeout(stepTimeout);
    });
    test(
      'callSingle waits for final result and surfaces call errors',
      () async {
        const stepTimeout = Duration(seconds: 1);
        final transport = _ImmediateResponseTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first.timeout(stepTimeout);

        final finalResult = await session
            .callSingle('bench.progressive')
            .timeout(stepTimeout);
        expect(finalResult.arguments, equals(['final']));

        await expectLater(
          session.callSingle('bench.error').timeout(stepTimeout),
          throwsA(
            isA<Error>().having(
              (error) => error.requestTypeId,
              'requestTypeId',
              MessageTypes.codeCall,
            ),
          ),
        );
      },
    );
    test('callSinglePayload returns the final payload result', () async {
      const stepTimeout = Duration(seconds: 1);
      final transport = _ImmediateResponseTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first.timeout(stepTimeout);

      final finalResult = await session
          .callSinglePayload('bench.progressive')
          .timeout(stepTimeout);
      expect(finalResult.arguments, equals(['final']));
      expect(finalResult.progress, isFalse);
    });
    test(
      'callSingleLazyPayload returns the final lazy payload result',
      () async {
        const stepTimeout = Duration(seconds: 1);
        final transport = _ImmediateResponseTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first.timeout(stepTimeout);

        final finalResult = await session
            .callSingleLazyPayload('bench.progressive')
            .timeout(stepTimeout);
        expect(finalResult.arguments, equals(['final']));
        expect(finalResult.progress, isFalse);
      },
    );
    test(
      'callSinglePayload unpacks PPT payloads on the native direct result path',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeCall) {
            transport.receiveObject(
              _nativeDirectResultMessage(
                requestId: (message as Call).requestId,
                pptScheme: 'x_custom_scheme',
                pptSerializer: 'cbor',
                argsBytes: _encodeNativePptArguments(
                  arguments: const ['ppt-result'],
                  argumentsKeywords: const {'worker': 9},
                ),
              ),
            );
          }
        });
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;

        final result = await session.callSinglePayload('ppt.result');
        expect(result.progress, isFalse);
        expect(result.pptScheme, equals('x_custom_scheme'));
        expect(result.arguments, equals(const ['ppt-result']));
        expect(result.argumentsKeywords, equals(const {'worker': 9}));
      },
    );
    test(
      'callSingle lazily unpacks PPT payloads on the native direct result path',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeCall) {
            transport.receiveObject(
              _nativeDirectResultMessage(
                requestId: (message as Call).requestId,
                pptScheme: 'x_custom_scheme',
                pptSerializer: 'cbor',
                argsBytes: _encodeNativePptArguments(
                  arguments: const ['ppt-result'],
                  argumentsKeywords: const {'worker': 9},
                ),
              ),
            );
          }
        });
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;

        final result = await session.callSingle('ppt.result');
        expect(result.hasDecodedPptPayload, isFalse);
        expect(result.arguments, equals(const ['ppt-result']));
        expect(result.argumentsKeywords, equals(const {'worker': 9}));
        expect(result.hasDecodedPptPayload, isTrue);
      },
    );
    test(
      'callSingle decodes wamp payloads on the native direct result path with a session provider',
      () async {
        final provider = _testWampE2eeProvider();
        final details = ResultDetails(pptScheme: 'wamp', pptSerializer: 'cbor');
        final packedArguments = provider.packPayload(
          const ['wrapped-result'],
          const {'worker': 12},
          details,
        );
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeCall) {
            transport.receiveObject(
              _nativeDirectResultMessage(
                requestId: (message as Call).requestId,
                pptScheme: 'wamp',
                pptSerializer: 'cbor',
                pptCipher: details.pptCipher,
                pptKeyId: details.pptKeyId,
                argsBytes: Uint8List.fromList(
                  cbor.cborEncode(
                    cbor.CborValue(<Object?>[packedArguments.single]),
                  ),
                ),
              ),
            );
          }
        });
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
          e2eeProvider: provider,
        ).connect().first;

        final result = await session.callSingle('wamp.result');
        expect(result.hasDecodedPptPayload, isFalse);
        expect(result.arguments, equals(const ['wrapped-result']));
        expect(result.argumentsKeywords, equals(const {'worker': 12}));
        expect(result.hasDecodedPptPayload, isTrue);
      },
    );
    test(
      'callSingleLazyPayload preserves packed PPT bytes on the native direct result path',
      () async {
        final transport = _SessionOptimizedMockTransport((message, transport) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveObject(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeCall) {
            transport.receiveObject(
              _nativeDirectResultMessage(
                requestId: (message as Call).requestId,
                pptScheme: 'x_custom_scheme',
                pptSerializer: 'cbor',
                argsBytes: _encodeNativePptArguments(
                  arguments: const ['ppt-result'],
                  argumentsKeywords: const {'worker': 9},
                ),
              ),
            );
          }
        });
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;

        final result = await session.callSingleLazyPayload('ppt.result');
        expect(result.pptScheme, equals('x_custom_scheme'));
        expect(
          result.packedPayloadBytes,
          orderedEquals(
            _encodeNativePptPayload(
              arguments: const ['ppt-result'],
              argumentsKeywords: const {'worker': 9},
            ),
          ),
        );
        expect(result.arguments, equals(const ['ppt-result']));
        expect(result.argumentsKeywords, equals(const {'worker': 9}));
      },
    );
    test(
      'callSingleLazyPayloadView sends mixed lazy args and materialized kwargs',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codeCall) {
            final call = message as Call;
            expect(call.debugEncodedArgumentsBytes, isNotNull);
            expect(call.argumentsKeywords, equals(const {'worker': 7}));
            transport.receiveMessage(
              Result(
                call.requestId,
                ResultDetails(progress: false),
                arguments: const ['done'],
              ),
            );
          }
        });

        final session = await client.connect().first;
        final result = await session.callSingleLazyPayloadView(
          'lazy.call',
          payload: LazyMessagePayload.encoded(
            encoding: LazyPayloadEncoding.json,
            argumentsBytes: Uint8List.fromList(utf8.encode('["lazy"]')),
            argumentsDecoder: (_) => throw StateError('should not decode args'),
            argumentsKeywords: const {'worker': 7},
          ),
        );

        expect(result.arguments, equals(const ['done']));
      },
    );
    test(
      'publishLazyPayload packs matching PPT fragments without decoding',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        var decodeCount = 0;

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codePublish) {
            final publish = message as Publish;
            expect(publish.arguments, hasLength(1));
            expect(publish.arguments!.single, isA<Uint8List>());
            expect(publish.argumentsKeywords, isNull);
          }
        });

        final session = await client.connect().first;
        await session.publishLazyPayload(
          'ppt.topic',
          payload: LazyMessagePayload.encoded(
            encoding: LazyPayloadEncoding.cbor,
            argumentsBytes: Uint8List.fromList(
              cbor.cborEncode(cbor.CborValue(const ['ppt'])),
            ),
            argumentsDecoder: (_) {
              decodeCount += 1;
              return const ['ppt'];
            },
            argumentsKeywordsBytes: Uint8List.fromList(
              cbor.cborEncode(cbor.CborValue(const {'worker': 3})),
            ),
            argumentsKeywordsDecoder: (_) {
              decodeCount += 1;
              return const {'worker': 3};
            },
          ),
          options: PublishOptions(
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'cbor',
          ),
        );

        expect(decodeCount, 0);
      },
    );
    test(
      'publishLazyPayload reuses matching wamp wrapped payload bytes without decoding',
      () async {
        final transport = _MockTransport();
        final client = Client(realm: 'test.realm', transport: transport);
        var decodeCount = 0;
        final packedPayloadBytes = Uint8List.fromList(
          cbor.cborEncode(cbor.CborValue(const ['wrapped'])),
        );

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codePublish) {
            final publish = message as Publish;
            expect(publish.arguments, hasLength(1));
            expect(
              publish.arguments!.single,
              orderedEquals(packedPayloadBytes),
            );
            expect(publish.argumentsKeywords, isNull);
          }
        });

        final session = await client.connect().first;
        await session.publishLazyPayload(
          'ppt.topic',
          payload: LazyMessagePayload.packed(
            encoding: LazyPayloadEncoding.cbor,
            packedPayloadBytes: packedPayloadBytes,
            packedPayloadDecoder: (_) {
              decodeCount += 1;
              return (
                arguments: const ['wrapped'],
                argumentsKeywords: const <String, dynamic>{},
              );
            },
          ),
          options: PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
        );

        expect(decodeCount, 0);
      },
    );
    test(
      'publishLazyPayload throws for wamp payloads without an E2EE provider',
      () async {
        final transport = _ImmediateResponseTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;

        expect(
          () => session.publishLazyPayload(
            'ppt.topic',
            payload: LazyMessagePayload.materialized(
              arguments: const ['wrapped'],
              argumentsKeywords: const {'worker': 4},
            ),
            options: PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
          ),
          throwsA(isA<WampE2eeProviderUnavailableException>()),
        );
      },
    );
    test(
      'publishLazyPayload uses the client E2EE provider for wamp payloads',
      () async {
        final transport = _MockTransport();
        final provider = _testWampE2eeProvider();
        final client = Client(
          realm: 'test.realm',
          transport: transport,
          e2eeProvider: provider,
        );

        transport.outbound.stream.listen((message) {
          if (message.id == MessageTypes.codeHello) {
            transport.receiveMessage(Welcome(42, Details.forWelcome()));
            return;
          }
          if (message.id == MessageTypes.codePublish) {
            final publish = message as Publish;
            expect(publish.options?.pptCipher, equals('xsalsa20poly1305'));
            expect(publish.options?.pptKeyId, equals('test-key'));
            final decoded = provider.unpackPayload(
              publish.arguments,
              publish.options!,
            );
            expect(decoded.arguments, equals(const ['wrapped']));
            expect(decoded.argumentsKeywords, equals(const {'worker': 4}));
            expect(publish.argumentsKeywords, isNull);
          }
        });

        final session = await client.connect().first;
        await session.publishLazyPayload(
          'ppt.topic',
          payload: LazyMessagePayload.materialized(
            arguments: const ['wrapped'],
            argumentsKeywords: const {'worker': 4},
          ),
          options: PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
        );
      },
    );
    test('request routing handles out-of-order router replies', () async {
      const stepTimeout = Duration(seconds: 1);
      final transport = _OutOfOrderResponseTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first.timeout(stepTimeout);

      final callResults = await Future.wait([
        session.call('bench.first').first.timeout(stepTimeout),
        session.call('bench.second').first.timeout(stepTimeout),
        session.call('bench.third').first.timeout(stepTimeout),
      ]);
      expect(
        callResults.map((result) => result.arguments!.first).toList(),
        equals(['bench.first', 'bench.second', 'bench.third']),
      );

      final singleCallResults = await Future.wait([
        session.callSingle('bench.first').timeout(stepTimeout),
        session.callSingle('bench.second').timeout(stepTimeout),
        session.callSingle('bench.third').timeout(stepTimeout),
      ]);
      expect(
        singleCallResults.map((result) => result.arguments!.first).toList(),
        equals(['bench.first', 'bench.second', 'bench.third']),
      );

      final published = await Future.wait([
        session
            .publish('bench.topic', options: PublishOptions(acknowledge: true))
            .timeout(stepTimeout),
        session
            .publish('bench.topic', options: PublishOptions(acknowledge: true))
            .timeout(stepTimeout),
        session
            .publish('bench.topic', options: PublishOptions(acknowledge: true))
            .timeout(stepTimeout),
      ]);
      expect(
        published.map((value) => value!.publicationId).toList(),
        equals([100, 200, 300]),
      );

      final subscribed = await Future.wait([
        session.subscribe('bench.topic.1').timeout(stepTimeout),
        session.subscribe('bench.topic.2').timeout(stepTimeout),
        session.subscribe('bench.topic.3').timeout(stepTimeout),
      ]);
      expect(
        subscribed.map((value) => value.subscriptionId).toList(),
        equals([10, 20, 30]),
      );

      final registered = await Future.wait([
        session.register('bench.proc.1').timeout(stepTimeout),
        session.register('bench.proc.2').timeout(stepTimeout),
        session.register('bench.proc.3').timeout(stepTimeout),
      ]);
      expect(
        registered.map((value) => value.registrationId).toList(),
        equals([20, 40, 60]),
      );
      expect(
        registered.map((value) => value.procedure).toList(),
        equals(['bench.proc.1', 'bench.proc.2', 'bench.proc.3']),
      );
    });
    test('pending request APIs fail when the transport closes', () async {
      const stepTimeout = Duration(seconds: 1);
      final transport = _PendingCloseTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first.timeout(stepTimeout);

      final subscribed = await session
          .subscribe('bench.ready')
          .timeout(stepTimeout);
      final registered = await session
          .register('bench.ready.proc')
          .timeout(stepTimeout);

      final callFuture = session.call('bench.hang').first.timeout(stepTimeout);
      final callSingleFuture = session
          .callSingle('bench.hang')
          .timeout(stepTimeout);
      final publishFuture = session
          .publish('bench.topic', options: PublishOptions(acknowledge: true))
          .timeout(stepTimeout);
      final subscribeFuture = session
          .subscribe('bench.hang.topic')
          .timeout(stepTimeout);
      final registerFuture = session
          .register('bench.hang.proc')
          .timeout(stepTimeout);
      final unsubscribeFuture = session.unsubscribe(subscribed.subscriptionId);
      final unregisterFuture = session.unregister(registered.registrationId);

      final matcher = throwsA(isA<StateError>());
      final expectations = [
        expectLater(callFuture, matcher),
        expectLater(callSingleFuture, matcher),
        expectLater(publishFuture, matcher),
        expectLater(subscribeFuture, matcher),
        expectLater(registerFuture, matcher),
        expectLater(unsubscribeFuture, matcher),
        expectLater(unregisterFuture, matcher),
      ];

      await transport.close();
      await Future.wait(expectations);
    });
  });
}

class _MockChallengeFailAuthenticator extends AbstractAuthentication {
  @override
  Stream<Extra> get onChallenge => Stream.empty();

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

WampCborXsalsa20Poly1305Provider _testWampE2eeProvider() {
  return WampCborXsalsa20Poly1305Provider.single(
    keyId: 'test-key',
    key: Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
  );
}

class _MockTransport extends AbstractTransport {
  bool failToOpen = false;
  final StreamController<AbstractMessage> inbound =
      StreamController.broadcast();
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
    if (failToOpen) return Future.value();
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

class _SessionOptimizedMockTransport extends AbstractTransport
    implements SessionOptimizedTransport {
  _SessionOptimizedMockTransport(this._onSend);

  final void Function(
    AbstractMessage message,
    _SessionOptimizedMockTransport transport,
  )
  _onSend;

  final StreamController<Object?> inbound = StreamController.broadcast(
    sync: true,
  );
  final StreamController<AbstractMessage> outbound = StreamController(
    sync: true,
  );

  Completer? _onConnectionLost;
  Completer? _onDisconnect;
  bool _open = false;

  @override
  Completer? get onConnectionLost => _onConnectionLost;

  @override
  Completer? get onDisconnect => _onDisconnect;

  @override
  bool get isOpen => _open;

  @override
  bool get isReady => _open;

  @override
  Future<void> get onReady => Future.value();

  @override
  Future<void> open({Duration? pingInterval}) {
    _open = true;
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    return Future.value();
  }

  @override
  Future<void> close({error}) {
    _open = false;
    complete(_onDisconnect, error);
    return inbound.close();
  }

  @override
  void send(AbstractMessage message) {
    outbound.add(message);
    _onSend(message, this);
  }

  void receiveObject(Object? message) {
    inbound.add(message);
  }

  @override
  Stream<AbstractMessage?> receive() {
    return inbound.stream
        .where((message) => message is AbstractMessage)
        .cast<AbstractMessage?>();
  }

  @override
  Stream<Object?> receiveSessionMessages() {
    return inbound.stream;
  }
}

Uint8List _encodeNativePptArguments({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
}) {
  final payloadBytes = _encodeNativePptPayload(
    arguments: arguments,
    argumentsKeywords: argumentsKeywords,
  );
  return Uint8List.fromList(
    cbor.cborEncode(cbor.CborValue(<Object?>[payloadBytes])),
  );
}

Uint8List _encodeNativePptPayload({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
}) {
  return Uint8List.fromList(
    cbor.cborEncode(
      cbor.CborValue(<String, Object?>{
        'args': arguments,
        'kwargs': argumentsKeywords,
      }),
    ),
  );
}

NativeSessionMessage _nativeDirectResultMessage({
  required int requestId,
  required String pptScheme,
  required String pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  required Uint8List argsBytes,
}) {
  return NativeSessionMessage(
    serializer: NativeMessageSerializer.cbor,
    metadata: NativeMessageMetadata(
      messageCode: MessageTypes.codeResult,
      primaryId: requestId,
      secondaryId: 0,
      detailNumberA: 0,
      detailNumberB: 0,
      flags:
          NativeMessageMetadata.flagDirectBind |
          NativeMessageMetadata.flagMetadataBind,
      stringA: pptScheme,
      stringB: pptSerializer,
      stringC: pptCipher,
      stringD: pptKeyId,
    ),
    argsBytes: argsBytes,
  );
}

NativeSessionMessage _nativeDirectEventMessage({
  required int subscriptionId,
  required int publicationId,
  required String topic,
  required String pptScheme,
  required String pptSerializer,
  required Uint8List argsBytes,
}) {
  return NativeSessionMessage(
    serializer: NativeMessageSerializer.cbor,
    metadata: NativeMessageMetadata(
      messageCode: MessageTypes.codeEvent,
      primaryId: subscriptionId,
      secondaryId: publicationId,
      detailNumberA: 0,
      detailNumberB: 0,
      flags:
          NativeMessageMetadata.flagDirectBind |
          NativeMessageMetadata.flagMetadataBind,
      stringA: topic,
      stringB: pptScheme,
      stringC: pptSerializer,
    ),
    argsBytes: argsBytes,
  );
}

NativeSessionMessage _nativeDirectInvocationMessage({
  required int requestId,
  required int registrationId,
  required String procedure,
  required String pptScheme,
  required String pptSerializer,
  required Uint8List argsBytes,
}) {
  return NativeSessionMessage(
    serializer: NativeMessageSerializer.cbor,
    metadata: NativeMessageMetadata(
      messageCode: MessageTypes.codeInvocation,
      primaryId: requestId,
      secondaryId: registrationId,
      detailNumberA: 0,
      detailNumberB: 0,
      flags:
          NativeMessageMetadata.flagDirectBind |
          NativeMessageMetadata.flagMetadataBind,
      stringA: procedure,
      stringB: pptScheme,
      stringC: pptSerializer,
    ),
    argsBytes: argsBytes,
  );
}

NativeSessionMessage _nativeDirectInterruptMessage({
  required int requestId,
  required String mode,
}) {
  return NativeSessionMessage(
    serializer: NativeMessageSerializer.json,
    metadata: NativeMessageMetadata(
      messageCode: MessageTypes.codeInterrupt,
      primaryId: requestId,
      secondaryId: 0,
      detailNumberA: 0,
      detailNumberB: 0,
      flags:
          NativeMessageMetadata.flagDirectBind |
          NativeMessageMetadata.flagMetadataBind,
      stringA: mode,
    ),
  );
}

class _ImmediateResponseTransport extends AbstractTransport {
  final StreamController<AbstractMessage> inbound = StreamController.broadcast(
    sync: true,
  );
  final StreamController<AbstractMessage> outbound = StreamController(
    sync: true,
  );

  Completer? _onConnectionLost;
  Completer? _onDisconnect;
  bool _open = false;
  int _nextPublicationId = 1;
  final int _nextSubscriptionId = 10;
  final int _nextRegistrationId = 20;

  @override
  Completer? get onConnectionLost => _onConnectionLost;

  @override
  Completer? get onDisconnect => _onDisconnect;

  @override
  bool get isOpen => _open;

  @override
  bool get isReady => _open;

  @override
  Future<void> get onReady => Future.value();

  @override
  Future<void> open({Duration? pingInterval}) {
    _open = true;
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    return Future.value();
  }

  @override
  void send(AbstractMessage message) {
    outbound.add(message);
    if (message is Hello) {
      inbound.add(Welcome(42, Details.forWelcome()));
      return;
    }
    if (message is Call) {
      if (message.procedure == 'bench.progressive') {
        inbound.add(
          Result(
            message.requestId,
            ResultDetails(progress: true),
            arguments: const ['progress'],
          ),
        );
        inbound.add(
          Result(
            message.requestId,
            ResultDetails(progress: false),
            arguments: const ['final'],
          ),
        );
        return;
      }
      if (message.procedure == 'bench.error') {
        inbound.add(
          Error(
            MessageTypes.codeCall,
            message.requestId,
            const {},
            'wamp.error.runtime_error',
          ),
        );
        return;
      }
      inbound.add(
        Result(message.requestId, ResultDetails(), arguments: const ['ok']),
      );
      return;
    }
    if (message is Publish && message.options?.acknowledge == true) {
      inbound.add(Published(message.requestId, _nextPublicationId++));
      return;
    }
    if (message is Subscribe) {
      inbound.add(Subscribed(message.requestId, _nextSubscriptionId));
      return;
    }
    if (message is Unsubscribe) {
      inbound.add(
        Unsubscribed(
          message.requestId,
          UnsubscribedDetails(message.subscriptionId, null),
        ),
      );
      return;
    }
    if (message is Register) {
      inbound.add(Registered(message.requestId, _nextRegistrationId));
      return;
    }
    if (message is Unregister) {
      inbound.add(Unregistered(message.requestId));
      return;
    }
    if (message is Goodbye) {
      unawaited(close());
    }
  }

  @override
  Future<void> close({error}) {
    _open = false;
    complete(_onDisconnect, error);
    return Future.value();
  }

  @override
  Stream<AbstractMessage> receive() {
    return inbound.stream;
  }
}

class _OutOfOrderResponseTransport extends _ImmediateResponseTransport {
  @override
  void send(AbstractMessage message) {
    outbound.add(message);
    if (message is Hello) {
      inbound.add(Welcome(42, Details.forWelcome()));
      return;
    }
    if (message is Call) {
      _schedule(
        message.requestId,
        () => inbound.add(
          Result(
            message.requestId,
            ResultDetails(),
            arguments: [message.procedure],
          ),
        ),
      );
      return;
    }
    if (message is Publish && message.options?.acknowledge == true) {
      _schedule(
        message.requestId,
        () =>
            inbound.add(Published(message.requestId, message.requestId * 100)),
      );
      return;
    }
    if (message is Subscribe) {
      _schedule(
        message.requestId,
        () =>
            inbound.add(Subscribed(message.requestId, message.requestId * 10)),
      );
      return;
    }
    if (message is Register) {
      _schedule(
        message.requestId,
        () =>
            inbound.add(Registered(message.requestId, message.requestId * 20)),
      );
      return;
    }
    if (message is Goodbye) {
      unawaited(close());
    }
  }

  void _schedule(int requestId, void Function() callback) {
    Timer(_delayFor(requestId), callback);
  }

  Duration _delayFor(int requestId) {
    final bounded = requestId.clamp(1, 3);
    return Duration(milliseconds: 5 - bounded);
  }
}

class _PendingCloseTransport extends _ImmediateResponseTransport {
  @override
  void send(AbstractMessage message) {
    outbound.add(message);
    if (message is Hello) {
      inbound.add(Welcome(42, Details.forWelcome()));
      return;
    }
    if (message is Subscribe && message.topic == 'bench.ready') {
      inbound.add(Subscribed(message.requestId, 10));
      return;
    }
    if (message is Register && message.procedure == 'bench.ready.proc') {
      inbound.add(Registered(message.requestId, 20));
      return;
    }
    if (message is Goodbye) {
      unawaited(close());
    }
  }

  @override
  Future<void> close({error}) async {
    _open = false;
    await inbound.close();
    complete(_onDisconnect, error);
  }
}

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';
import 'support/native_lib.dart';

class _FlatPeer {
  _FlatPeer(this.socket) : input = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<Uint8List> input;
  final codec = flat.Serializer();
  var profile = const flat.FlatBuffersSessionProfile.client();
  Uint8List pending = Uint8List(0);
  var offset = 0;
  var maxFrameLength = 0;

  static Future<_FlatPeer> connect(int port) async {
    final peer = _FlatPeer(await Socket.connect('127.0.0.1', port));
    try {
      peer.socket.add([0x7f, 0xf5, 0, 0]);
      await peer.socket.flush();
      final handshake = await peer.read(4);
      expect(handshake[0], 0x7f);
      expect(handshake[1] & 15, 5);
      peer.maxFrameLength = 1 << ((handshake[1] >> 4) + 9);
      expect(handshake.sublist(2), [0, 0]);
      return peer;
    } catch (_) {
      await peer.close();
      rethrow;
    }
  }

  Future<Uint8List> read(int length) async {
    final result = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (offset == pending.length) {
        if (!await input.moveNext().timeout(const Duration(seconds: 5))) {
          throw StateError(
            'FlatBuffers peer closed before the frame completed',
          );
        }
        pending = input.current;
        offset = 0;
      }
      final available = pending.length - offset;
      final take = available < length - written ? available : length - written;
      result.setRange(written, written + take, pending, offset);
      offset += take;
      written += take;
    }
    return result;
  }

  Future<void> send(core.AbstractMessage message) async {
    final next = profile.prepareOutgoing(message);
    final bytes = codec.serialize(message);
    if (bytes.length > maxFrameLength) {
      throw StateError('Test frame exceeds negotiated maximum $maxFrameLength');
    }
    final header = Uint8List(4);
    header[1] = bytes.length >> 16;
    header[2] = bytes.length >> 8;
    header[3] = bytes.length;
    socket.add(header);
    socket.add(bytes);
    await socket.flush();
    profile = next;
  }

  Future<core.AbstractMessage> next() async {
    final header = await read(4);
    expect(header[0], 0);
    final length = (header[1] << 16) | (header[2] << 8) | header[3];
    final message = codec.deserialize(await read(length))!;
    profile = profile.acceptIncoming(message);
    return message;
  }

  Future<void> hello({bool authenticated = false}) async {
    await send(
      core.Hello(
        'realm1',
        core.Details.forHello()
          ..authmethods = [authenticated ? 'ticket' : 'anonymous']
          ..authid = authenticated ? 'alice' : null,
      ),
    );
    if (authenticated) {
      final challenge = await next();
      expect(challenge, isA<core.Challenge>());
      expect(profile.isEstablished, isFalse);
      await send(
        await core.TicketAuthentication(
          'profile-ticket',
        ).challenge((challenge as core.Challenge).extra),
      );
    }
    final welcome = await next();
    expect(welcome, isA<core.Welcome>());
    if (authenticated) {
      expect((welcome as core.Welcome).details.authid, 'alice');
    }
    expect(profile.isEstablished, isTrue);
  }

  Future<void> close() async {
    socket.destroy();
    await input.cancel();
  }
}

void main() {
  final library = resolveOrBuildNativeLib();
  for (final authenticated in [false, true]) {
    test(
      'live FlatBuffers router ${authenticated ? 'ticket' : 'anonymous'} RPC/pubsub/progress/error/opaque',
      () async {
        final settings =
            (RouterSettingsBuilder()
                  ..addRealmFromBuilder(
                    RealmSettingsBuilder('realm1')
                      ..addAuthMethod('anonymous')
                      ..addAuthMethod(
                        'ticket',
                        options: const {'authenticator': 'profile-ticket'},
                      )
                      ..addRoleFromBuilder(
                        RoleSettingsBuilder('anonymous')
                          ..addPermissionFromBuilder(
                            PermissionSettingsBuilder('')
                              ..setMatchPolicy(PermissionMatchPolicy.prefix)
                              ..allowOperations([
                                'call',
                                'register',
                                'subscribe',
                                'publish',
                              ]),
                          ),
                      ),
                  )
                  ..addListenerFromBuilder(
                    ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
                      ..addAuthMethod('anonymous')
                      ..addAuthMethod('ticket')
                      ..setOptions({'max_rawsocket_size_exponent': 20}),
                  )
                  ..addAuthenticator(
                    'profile-ticket',
                    const AuthenticatorDefinition(
                      type: 'ticket',
                      options: {
                        'secrets': {
                          'alice': {
                            'ticket': 'profile-ticket',
                            'role': 'anonymous',
                          },
                        },
                      },
                    ),
                  ))
                .build();
        final runtime = NativeTransportRuntime(libraryPath: library);
        runtime.start();
        final router = Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.disabled,
                maxRawSocketSizeExponent: 20,
              ),
            ],
          ),
          settings: settings,
        );
        final errors = <Object>[];
        final events = <Object>[];
        var step = 'connecting';
        final binding = router.start(
          runtime,
          onEvent: (event) {
            events.add(event);
            if (event is Map && event['type'] == 'worker_error') {
              errors.add(event);
            }
          },
        );
        final peers = <_FlatPeer>[];
        try {
          final port = binding.listeners.single.port;
          final caller = await _FlatPeer.connect(port);
          peers.add(caller);
          final callee = await _FlatPeer.connect(port);
          peers.add(callee);
          step = 'caller HELLO';
          await caller.hello(authenticated: authenticated);
          step = 'callee HELLO';
          await callee.hello(authenticated: authenticated);
          step = 'registration';
          await callee.send(core.Register(1, 'com.profile.echo'));
          expect(await callee.next(), isA<core.Registered>());
          final binary = Uint8List.fromList(
            List.generate(128 * 1024, (i) => i & 255),
          );
          await caller.send(
            core.Call(
              2,
              'com.profile.echo',
              arguments: ['value', binary],
              argumentsKeywords: {'count': 7},
            ),
          );
          step = 'invocation';
          final invocation = await callee.next();
          expect(invocation, isA<core.Invocation>());
          final request = invocation as core.Invocation;
          expect(request.arguments, ['value', binary]);
          expect(request.argumentsKeywords, {'count': 7});
          await callee.send(
            core.Yield(
              request.requestId,
              arguments: request.arguments,
              argumentsKeywords: request.argumentsKeywords,
            ),
          );
          step = 'result';
          final result = await caller.next();
          expect(result, isA<core.Result>());
          expect((result as core.Result).arguments, ['value', binary]);
          expect(result.argumentsKeywords, {'count': 7});
          step = 'progressive invocation';
          await caller.send(
            core.Call(
              5,
              'com.profile.echo',
              options: core.CallOptions(receiveProgress: true),
              arguments: ['progress'],
            ),
          );
          final progressive = await callee.next() as core.Invocation;
          expect(progressive.details.receiveProgress, isTrue);
          await callee.send(
            core.Yield(
              progressive.requestId,
              options: core.YieldOptions(progress: true),
              arguments: [binary],
            ),
          );
          final intermediate = await caller.next() as core.Result;
          expect(intermediate.callRequestId, 5);
          expect(intermediate.details.progress, isTrue);
          expect(intermediate.arguments, [binary]);
          await callee.send(
            core.Yield(progressive.requestId, arguments: ['finished']),
          );
          final completed = await caller.next() as core.Result;
          expect(completed.callRequestId, 5);
          expect(completed.arguments, ['finished']);
          step = 'callee error';
          await caller.send(core.Call(6, 'com.profile.echo'));
          final failed = await callee.next() as core.Invocation;
          await callee.send(
            core.Error(
              68,
              failed.requestId,
              {'retry': false},
              'wamp.error.test',
              arguments: [binary],
              argumentsKeywords: {'why': 'test'},
            ),
          );
          final error = await caller.next() as core.Error;
          expect(error.requestTypeId, 48);
          expect(error.requestId, 6);
          expect(error.details, {'retry': false});
          expect(error.arguments, [binary]);
          expect(error.argumentsKeywords, {'why': 'test'});
          step = 'opaque invocation';
          await caller.send(
            core.Call(
              7,
              'com.profile.echo',
              options: core.CallOptions(
                pptScheme: 'opaque',
                pptSerializer: 'flatbuffers',
              ),
            )..transparentBinaryPayload = binary,
          );
          final opaque = await callee.next() as core.Invocation;
          expect(opaque.transparentBinaryPayload, binary);
          expect(opaque.arguments, isNull);
          expect(opaque.argumentsKeywords, isNull);
          expect(opaque.details.pptScheme, 'opaque');
          expect(opaque.details.pptSerializer, 'flatbuffers');
          await callee.send(
            core.Yield(
              opaque.requestId,
              options: core.YieldOptions(
                pptScheme: 'opaque',
                pptSerializer: 'flatbuffers',
              ),
            )..transparentBinaryPayload = opaque.transparentBinaryPayload,
          );
          final opaqueResult = await caller.next() as core.Result;
          expect(opaqueResult.callRequestId, 7);
          expect(opaqueResult.transparentBinaryPayload, binary);
          expect(opaqueResult.details.pptSerializer, 'flatbuffers');
          step = 'subscription';
          await callee.send(core.Subscribe(3, 'com.profile.events'));
          expect(await callee.next(), isA<core.Subscribed>());
          await caller.send(
            core.Publish(
              4,
              'com.profile.events',
              options: core.PublishOptions(acknowledge: true),
              arguments: ['event', binary],
              argumentsKeywords: {'count': 8},
            ),
          );
          step = 'published';
          expect(await caller.next(), isA<core.Published>());
          step = 'event';
          final event = await callee.next();
          expect(event, isA<core.Event>());
          expect((event as core.Event).arguments, ['event', binary]);
          expect(event.argumentsKeywords, {'count': 8});
          step = 'opaque event';
          await caller.send(
            core.Publish(
              8,
              'com.profile.events',
              options: core.PublishOptions(
                acknowledge: true,
                pptScheme: 'opaque',
                pptSerializer: 'flatbuffers',
              ),
            )..transparentBinaryPayload = binary,
          );
          expect(await caller.next(), isA<core.Published>());
          final opaqueEvent = await callee.next() as core.Event;
          expect(opaqueEvent.transparentBinaryPayload, binary);
          expect(opaqueEvent.details.pptSerializer, 'flatbuffers');
          step = 'goodbye';
          for (final peer in peers) {
            await peer.send(core.Goodbye(null, 'wamp.close.normal'));
            expect(await peer.next(), isA<core.Goodbye>());
            expect(peer.profile.isEstablished, isFalse);
          }
          expect(errors, isEmpty);
        } catch (error) {
          fail(
            '$step: $error; events=${events.skip(events.length > 10 ? events.length - 10 : 0).toList()}',
          );
        } finally {
          for (final peer in peers) {
            await peer.close();
          }
          await binding.dispose();
          runtime.shutdown();
          runtime.dispose();
        }
      },
      skip: library == null ? 'native library unavailable' : false,
    );
  }
}

part of '../runtime_file_segment_test.dart';

void _deferredSessionMessageCases(NativeClientRuntime Function() getRuntime) {
  _deferredTransportSessionCases(getRuntime);
  _deferredCborShapeCases(getRuntime);
  for (final (wire, serializer) in [
    _wireCases.first,
    (NativeMessageSerializer.cbor, cbor.Serializer()),
    (NativeMessageSerializer.messagePack, msgpack.Serializer()),
    (NativeMessageSerializer.flatbuffers, flat.Serializer()),
  ]) {
    for (final cipher in ['aes256gcm', 'xsalsa20poly1305']) {
      for (final code in [
        MessageTypes.codeResult,
        MessageTypes.codeEvent,
        MessageTypes.codeInvocation,
      ]) {
        for (final access in [
          'consume',
          'export',
          'portable',
          'failure',
          'release',
          'mutate',
          'policy-mutate',
          'policy-export',
        ]) {
          test(
            'deferred Session ${wire.name} $cipher code=$code $access',
            () async {
              final runtime = getRuntime();
              final peer = await _WirePeer.start(wire);
              addTearDown(peer.dispose);
              final connection = _connect(runtime, peer, wire);
              addTearDown(() => runtime.closeConnection(connection));
              final key = List<int>.filled(32, 31);
              final plaintext = Uint8List.fromList(
                List.generate(1024, (index) => index % 256),
              );
              final portable = cipher == 'aes256gcm'
                  ? WampFlatBuffersAes256GcmProvider.single(
                      keyId: 'typed',
                      key: key,
                    )
                  : WampFlatBuffersXsalsa20Poly1305Provider.single(
                      keyId: 'typed',
                      key: key,
                    );
              final encrypted = portable.packPayload(
                [plaintext],
                null,
                PublishOptions(),
              );
              final ciphertext = Uint8List.fromList(
                (encrypted.single as List).cast<int>(),
              );
              var policyCalls = 0;
              NativeSessionMessage? policyMessage;
              String? select(
                WampE2eeRuntimeContext context,
                PPTOptions options,
              ) {
                policyCalls++;
                expect(context.realm, 'typed.realm');
                if (access == 'policy-mutate') {
                  policyMessage!.arguments = portable.packPayload(
                    [Uint8List.fromList(List.filled(1024, 42))],
                    null,
                    PublishOptions(),
                  );
                } else if (access == 'policy-export') {
                  policyMessage!.materialize();
                }
                return 'typed';
              }

              final providerKey = access == 'failure'
                  ? List<int>.filled(32, 7)
                  : key;
              final native = cipher == 'aes256gcm'
                  ? NativeWampFlatBuffersAes256GcmProvider(
                      keys: {'typed': providerKey},
                      keySelectionPolicy: select,
                    )
                  : NativeWampFlatBuffersXsalsa20Poly1305Provider(
                      keys: {'typed': providerKey},
                      keySelectionPolicy: select,
                    );
              addTearDown(native.release);
              final AbstractMessage outgoing = switch (code) {
                final value when value == MessageTypes.codeResult => Result(
                  71,
                  ResultDetails(
                    pptScheme: 'wamp',
                    pptSerializer: 'flatbuffers',
                    pptCipher: cipher,
                    custom: {'trace': 'deferred'},
                  ),
                  arguments: encrypted,
                ),
                final value when value == MessageTypes.codeEvent => Event(
                  71,
                  81,
                  EventDetails(
                    topic: 'typed.read',
                    pptScheme: 'wamp',
                    pptSerializer: 'flatbuffers',
                    pptCipher: cipher,
                    custom: {'trace': 'deferred'},
                  ),
                  arguments: encrypted,
                ),
                _ => Invocation(
                  71,
                  81,
                  InvocationDetails(
                    null,
                    'typed.read',
                    false,
                    'wamp',
                    'flatbuffers',
                    cipher,
                    null,
                    {'trace': 'deferred'},
                  ),
                  arguments: encrypted,
                ),
              };
              peer.control.send(_encode(serializer, outgoing));
              final handle = runtime.waitMessageHandle(
                connection,
                timeout: const Duration(seconds: 3),
              );
              expect(handle, greaterThan(0));
              // Peek does not export or retain a payload owner. Record the actual
              // ciphertext address before constructing the Session wrapper.
              final bindings = CtFfiBindings(
                ffi.DynamicLibrary.open(runtime.libraryPath),
              );
              final info = calloc<CtMessageInfo>();
              int? ciphertextAddress;
              try {
                expect(
                  bindings.ctMessagePeek(handle, info),
                  NativeTransportErrorCode.success,
                );
                if (info.ref.binaryArgPtr != ffi.nullptr) {
                  ciphertextAddress = info.ref.binaryArgPtr.address;
                } else if (wire == NativeMessageSerializer.cbor ||
                    wire == NativeMessageSerializer.messagePack ||
                    wire == NativeMessageSerializer.flatbuffers) {
                  expect(info.ref.argsLen, greaterThan(4));
                  final prefix = info.ref.argsPtr.asTypedList(4);
                  expect(
                    prefix[0],
                    wire == NativeMessageSerializer.messagePack ? 0x91 : 0x81,
                  );
                  expect(
                    prefix[1],
                    wire == NativeMessageSerializer.messagePack ? 0xc5 : 0x59,
                  );
                  ciphertextAddress = info.ref.argsPtr.address + 4;
                }
              } finally {
                calloc.free(info);
              }
              final incoming = runtime.materialize(
                handle,
                consumeTypedE2eePayloads: true,
              );
              addTearDown(incoming.release);
              final message = incoming.sessionMessage as NativeSessionMessage;
              policyMessage = message;
              expect(incoming.sessionMessage, same(message));
              expect(message.metadata.primaryId, 71);
              expect(message.customDetails, {'trace': 'deferred'});
              expect(policyCalls, 0);
              message.attachE2eeProvider(
                access == 'portable' ? portable : native,
              );
              message.attachE2eeRuntimeContext(
                WampE2eeRuntimeContext(
                  direction: WampE2eeDirection.inbound,
                  messageType: switch (code) {
                    final value when value == MessageTypes.codeResult =>
                      WampE2eeMessageType.result,
                    final value when value == MessageTypes.codeEvent =>
                      WampE2eeMessageType.event,
                    _ => WampE2eeMessageType.invocation,
                  },
                  realm: 'typed.realm',
                  payloadAnchor: message,
                ),
              );
              final payload = message.toLazyPayload();
              final alias = payload.withAnchor(message);
              expect(payload.pptDecoded, isTrue);
              expect(payload.argumentsBytes, isNull);
              expect(payload.transparentBinaryPayload, isNull);
              expect(policyCalls, 0);
              Uint8List expected = plaintext;
              AbstractMessage? exportedWire;
              if (access == 'export') {
                exportedWire = message.materialize();
                expect(
                  (exportedWire as AbstractMessageWithPayload).wireArguments,
                  [ciphertext],
                );
                expect(policyCalls, 0);
              } else if (access == 'mutate') {
                expected = Uint8List.fromList(List.filled(1024, 42));
                message.arguments = portable.packPayload(
                  [expected],
                  null,
                  PublishOptions(),
                );
                expect(message.e2eeRuntimeContext!.payloadAnchor, isNull);
                expect(message.e2eeRuntimeContext!.realm, 'typed.realm');
              } else if (access == 'release') {
                incoming.release();
              }
              if (access == 'failure' ||
                  access == 'release' ||
                  access == 'policy-mutate') {
                Object? error;
                StackTrace? origin;
                try {
                  payload.arguments;
                  fail('Expected terminal deferred decrypt failure');
                } catch (failure, stack) {
                  error = failure;
                  origin = stack;
                  expect(failure, isA<WampE2eeException>());
                  if (access == 'policy-mutate') {
                    expect(failure, isA<WampE2eeInvalidPayloadException>());
                  }
                }
                for (final get in <Object? Function()>[
                  () => alias.argumentsKeywords,
                  () => payload.arguments,
                  () => alias.toOwned(),
                ]) {
                  try {
                    get();
                    fail('Expected cached failure');
                  } catch (failure, stack) {
                    expect(failure, same(error));
                    expect(stack.toString(), origin.toString());
                  }
                }
                expect(policyCalls, access == 'release' ? 0 : 1);
                final exported =
                    access == 'policy-mutate' ||
                    (access == 'failure' &&
                        !runtime.supportsMessageBinaryArgumentLengthInspection);
                expect(
                  () => message.materialize(),
                  exported ? returnsNormally : throwsStateError,
                );
                return;
              }
              final output = payload.arguments!.single as Uint8List;
              addTearDown(
                () => NativeClientRuntime.releaseOwnedExternalBytes(output),
              );
              expect(output, orderedEquals(expected));
              expect(alias.arguments!.single, same(output));
              expect(alias.argumentsKeywords, isNull);
              if (access != 'portable') {
                expect(() => output[0] = 0, throwsUnsupportedError);
              }
              expect(policyCalls, access == 'portable' ? 0 : 1);
              final outputAddress =
                  NativeClientRuntime.debugExternalByteAddress(output);
              if (access == 'consume' &&
                  cipher == 'aes256gcm' &&
                  ciphertextAddress != null) {
                expect(
                  outputAddress,
                  runtime.supportsMessageBinaryArgumentLengthInspection
                      ? ciphertextAddress + 12
                      : isNot(ciphertextAddress + 12),
                );
              }
              if (access == 'export' ||
                  access == 'policy-export' ||
                  cipher == 'xsalsa20poly1305') {
                if (ciphertextAddress != null && outputAddress != null) {
                  expect(outputAddress, isNot(ciphertextAddress + 12));
                }
              }
              if (access == 'consume' ||
                  access == 'export' ||
                  access == 'policy-export') {
                final exported =
                    access == 'export' ||
                    access == 'policy-export' ||
                    !runtime.supportsMessageBinaryArgumentLengthInspection;
                expect(
                  () => incoming.bytes,
                  exported ? returnsNormally : throwsStateError,
                );
                expect(
                  () => message.materialize(),
                  exported ? returnsNormally : throwsStateError,
                );
              }
              final owned = alias.toOwned();
              expect(owned.arguments!.single, orderedEquals(expected));
              expect(owned.arguments!.single, isNot(same(output)));
              expect(owned.anchor, isNull);
              incoming.release();
              expect(output, orderedEquals(expected));
              if (exportedWire != null) {
                expect(
                  (exportedWire as AbstractMessageWithPayload).wireArguments,
                  [ciphertext],
                );
              }
            },
          );
        }
      }
    }
  }
}

void _deferredCborShapeCases(NativeClientRuntime Function() getRuntime) {
  for (final code in [MessageTypes.codeResult, MessageTypes.codeEvent]) {
    for (final cipher in ['aes256gcm', 'xsalsa20poly1305']) {
      test(
        'deferred Session cbor $cipher code=$code rejects array bytes',
        () async {
          final runtime = getRuntime();
          final peer = await _WirePeer.start(NativeMessageSerializer.cbor);
          addTearDown(peer.dispose);
          final connection = _connect(
            runtime,
            peer,
            NativeMessageSerializer.cbor,
          );
          addTearDown(() => runtime.closeConnection(connection));
          var policyCalls = 0;
          String? policy(WampE2eeRuntimeContext _, PPTOptions __) {
            policyCalls++;
            throw StateError('policy-before-binary-shape-validation');
          }

          final keys = {'typed': List<int>.filled(32, 23)};
          final provider = cipher == 'aes256gcm'
              ? NativeWampFlatBuffersAes256GcmProvider(
                  keys: keys,
                  keySelectionPolicy: policy,
                )
              : NativeWampFlatBuffersXsalsa20Poly1305Provider(
                  keys: keys,
                  keySelectionPolicy: policy,
                );
          addTearDown(provider.release);
          final minimum = cipher == 'aes256gcm' ? 28 : 40;
          for (final argument in [
            List<int>.filled(minimum, 0),
            Uint8List(minimum - 1),
            'not-binary',
          ]) {
            final AbstractMessage outgoing = code == MessageTypes.codeResult
                ? Result(
                    71,
                    ResultDetails(
                      pptScheme: 'wamp',
                      pptSerializer: 'flatbuffers',
                      pptCipher: cipher,
                    ),
                    arguments: [argument],
                  )
                : Event(
                    71,
                    81,
                    EventDetails(
                      pptScheme: 'wamp',
                      pptSerializer: 'flatbuffers',
                      pptCipher: cipher,
                    ),
                    arguments: [argument],
                  );
            peer.control.send(_encode(cbor.Serializer(), outgoing));
            final handle = runtime.waitMessageHandle(
              connection,
              timeout: const Duration(seconds: 3),
            );
            expect(handle, greaterThan(0));
            final incoming = runtime.materialize(
              handle,
              consumeTypedE2eePayloads: true,
            );
            addTearDown(incoming.release);
            final message = incoming.sessionMessage as NativeSessionMessage;
            message.attachE2eeProvider(provider);
            message.attachE2eeRuntimeContext(
              WampE2eeRuntimeContext(
                direction: WampE2eeDirection.inbound,
                messageType: code == MessageTypes.codeResult
                    ? WampE2eeMessageType.result
                    : WampE2eeMessageType.event,
                payloadAnchor: message,
              ),
            );
            expect(
              () => message.toLazyPayload().arguments,
              throwsA(isA<WampE2eeInvalidPayloadException>()),
            );
            expect(policyCalls, 0);
          }
        },
      );
    }
  }
}

void _deferredTransportSessionCases(NativeClientRuntime Function() getRuntime) {
  for (final (wire, codec) in [
    _wireCases.first,
    (NativeMessageSerializer.cbor, cbor.Serializer()),
    (NativeMessageSerializer.messagePack, msgpack.Serializer()),
    (NativeMessageSerializer.flatbuffers, flat.Serializer()),
  ]) {
    for (final websocket in [false, true]) {
      for (final consume in [false, true]) {
        for (final cipher in ['aes256gcm', 'xsalsa20poly1305']) {
          test(
            'typed Session transport ${wire.name} websocket=$websocket consume=$consume $cipher',
            () async {
              final runtime = getRuntime();
              final peer = await _WirePeer.start(wire, websocket: websocket);
              addTearDown(peer.dispose);
              final AbstractTransport transport = websocket
                  ? NativeWebSocketTransport(
                      'ws://127.0.0.1:${peer.port}/wamp',
                      codec,
                      _websocketProtocol(wire.id),
                    )
                  : NativeRawSocketTransport(
                      '127.0.0.1',
                      peer.port,
                      codec,
                      wire.id,
                    );
              void setConsume(bool value) {
                if (transport is NativeWebSocketTransport) {
                  transport.consumeTypedE2eePayloads = value;
                } else {
                  (transport as NativeRawSocketTransport)
                          .consumeTypedE2eePayloads =
                      value;
                }
              }

              setConsume(consume);
              var policyCalls = 0;
              final key = List<int>.filled(32, 31);
              String? select(
                WampE2eeRuntimeContext context,
                PPTOptions options,
              ) {
                policyCalls++;
                expect(context.direction, WampE2eeDirection.inbound);
                expect(context.realm, 'typed.realm');
                expect(context.messageType, WampE2eeMessageType.result);
                return 'typed';
              }

              final native = cipher == 'aes256gcm'
                  ? NativeWampFlatBuffersAes256GcmProvider(
                      keys: {'typed': key},
                      keySelectionPolicy: select,
                    )
                  : NativeWampFlatBuffersXsalsa20Poly1305Provider(
                      keys: {'typed': key},
                      keySelectionPolicy: select,
                    );
              addTearDown(native.release);
              final client = Client(
                realm: 'typed.realm',
                transport: transport,
                e2eeProvider: native,
              );
              addTearDown(client.disconnect);
              final connected = client.connect().first.timeout(
                const Duration(seconds: 5),
              );
              final hello = codec.deserialize(await peer.nextFrame())!;
              expect(hello, isA<Hello>());
              flat.FlatBuffersSessionProfile? profile =
                  wire == NativeMessageSerializer.flatbuffers
                  ? const flat.FlatBuffersSessionProfile.router()
                        .acceptIncoming(hello)
                  : null;
              void send(AbstractMessage message) {
                profile = profile?.prepareOutgoing(message);
                peer.control.send(_encode(codec, message));
              }

              send(
                Welcome(
                  42,
                  Details.forWelcome(
                    authExtra: {
                      'e2ee': {
                        'version': 2,
                        'required': true,
                        'established': true,
                        'scheme': 'wamp',
                        'serializer': 'flatbuffers',
                        'cipher': cipher,
                        'send_key_id': 'typed',
                        'receive_key_id': 'typed',
                      },
                    },
                  ),
                ),
              );
              final session = await connected;
              expect(session.id, 42);
              expect(() => setConsume(!consume), throwsStateError);
              final pending = session.callSingleLazyPayloadView(
                'typed.read',
                payload: LazyMessagePayload.materialized(),
              );
              final call = codec.deserialize(await peer.nextFrame()) as Call;
              profile = profile?.acceptIncoming(call);
              final plaintext = Uint8List.fromList(
                List.generate(1024, (index) => index % 256),
              );
              final portable = cipher == 'aes256gcm'
                  ? WampFlatBuffersAes256GcmProvider.single(
                      keyId: 'typed',
                      key: key,
                    )
                  : WampFlatBuffersXsalsa20Poly1305Provider.single(
                      keyId: 'typed',
                      key: key,
                    );
              send(
                Result(
                  call.requestId,
                  ResultDetails(
                    pptScheme: 'wamp',
                    pptSerializer: 'flatbuffers',
                    pptCipher: cipher,
                    custom: {'trace': 'actual-session'},
                  ),
                  arguments: portable.packPayload(
                    [plaintext],
                    null,
                    PublishOptions(),
                  ),
                ),
              );
              final view = await pending.timeout(const Duration(seconds: 5));
              expect(view.callRequestId, call.requestId);
              expect(view.customDetails, {'trace': 'actual-session'});
              expect(policyCalls, 0);
              final incoming =
                  sessionMessageAnchorFor(view.payload.anchor)
                      as NativeIncomingMessage;
              final bindings = CtFfiBindings(
                ffi.DynamicLibrary.open(runtime.libraryPath),
              );
              final info = calloc<CtMessageInfo>();
              int? ciphertextAddress;
              try {
                expect(
                  bindings.ctMessagePeek(incoming.handle, info),
                  NativeTransportErrorCode.success,
                );
                if (info.ref.binaryArgPtr != ffi.nullptr) {
                  ciphertextAddress = info.ref.binaryArgPtr.address;
                } else if (wire == NativeMessageSerializer.cbor ||
                    wire == NativeMessageSerializer.messagePack ||
                    wire == NativeMessageSerializer.flatbuffers) {
                  ciphertextAddress = info.ref.argsPtr.address + 4;
                }
              } finally {
                calloc.free(info);
              }
              final result = view.toPayload();
              final output = result.arguments!.single as Uint8List;
              addTearDown(
                () => NativeClientRuntime.releaseOwnedExternalBytes(output),
              );
              expect(output, orderedEquals(plaintext));
              expect(view.toPayload().arguments!.single, same(output));
              expect(policyCalls, consume ? 1 : greaterThanOrEqualTo(1));
              if (cipher == 'aes256gcm' &&
                  ciphertextAddress != null &&
                  !websocket) {
                final address = NativeClientRuntime.debugExternalByteAddress(
                  output,
                );
                expect(
                  address,
                  consume &&
                          runtime.supportsMessageBinaryArgumentLengthInspection
                      ? ciphertextAddress + 12
                      : isNot(ciphertextAddress + 12),
                );
              }
              if (cipher == 'aes256gcm' && ciphertextAddress != null) {
                print(
                  jsonEncode({
                    'typedSessionOwnership': wire.name,
                    'websocket': websocket,
                    'consume': consume,
                    'reusesReceiveAllocation':
                        NativeClientRuntime.debugExternalByteAddress(output) ==
                        ciphertextAddress + 12,
                  }),
                );
              }
              expect(
                () => incoming.bytes,
                consume && runtime.supportsMessageBinaryArgumentLengthInspection
                    ? throwsStateError
                    : returnsNormally,
              );
              await client.disconnect();
            },
          );
        }
      }
    }
  }
}

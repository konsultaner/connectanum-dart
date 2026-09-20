import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/message_binding.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:test/test.dart';

const _arguments = <dynamic>['answer', 7];
const _keywords = <String, dynamic>{'value': 7};
const _yieldMessageType = WampE2eeMessageType.yield;
const _representations = [
  'explicit',
  'materialized',
  'encoded-json',
  'packed-json',
  'packed-msgpack',
  'packed-cbor',
];

// Exercise the metadata boundary without claiming real native/FFI coverage.
void main() {
  for (final native in [false, true]) {
    group('native=$native lazy invocation replies', () {
      for (final representation in _representations) {
        for (final serializer in <String?>[null, 'json', 'msgpack', 'cbor']) {
          test('$representation to ${serializer ?? 'plain'}', () async {
            final fixture = await _start(native);
            final response = _ResponsePayload(representation);
            fixture.invocation.respondWith(
              lazyPayload: response.payload,
              arguments: representation == 'explicit' ? _arguments : null,
              argumentsKeywords: representation == 'explicit'
                  ? _keywords
                  : null,
              options: serializer == null
                  ? null
                  : YieldOptions(
                      pptScheme: 'x_example',
                      pptSerializer: serializer,
                    ),
            );
            expect(fixture.transport.yields, hasLength(1));
            final reply = fixture.transport.yields.single;
            expect(reply.invocationRequestId, 401);
            expect(fixture.invocation.isResponseClosed(), isTrue);
            if (serializer == null) {
              expect(reply.arguments, _arguments);
              expect(reply.argumentsKeywords, _keywords);
            } else {
              expect(reply.options!.pptScheme, 'x_example');
              expect(reply.options!.pptSerializer, serializer);
              expect(reply.arguments, hasLength(1));
              expect(reply.argumentsKeywords, isNull);
              if (response.sourceSerializer == serializer) {
                expect(response.decodeCalls, 0);
                if (response.payload?.packedPayloadBytes != null) {
                  expect(
                    identical(reply.arguments!.single, response.packedBytes),
                    isTrue,
                  );
                }
              }
              final decoded = PPTPayload.unpackPPTPayload(
                reply.arguments,
                reply.options!,
              );
              expect(decoded.arguments, _arguments);
              expect(decoded.argumentsKeywords, _keywords);
            }
            for (final wireReply in _wireRoundTrips(reply)) {
              expect(wireReply.invocationRequestId, 401);
              if (serializer == null) {
                expect(wireReply.arguments, _arguments);
                expect(wireReply.argumentsKeywords, _keywords);
              } else {
                expect(wireReply.options!.pptScheme, 'x_example');
                expect(wireReply.options!.pptSerializer, serializer);
                expect(wireReply.argumentsKeywords, isNull);
                final decoded = PPTPayload.unpackPPTPayload(
                  wireReply.arguments,
                  wireReply.options!,
                );
                expect(decoded.arguments, _arguments);
                expect(decoded.argumentsKeywords, _keywords);
              }
            }
            expect(
              () => fixture.invocation.respondWith(arguments: ['duplicate']),
              throwsStateError,
            );
            expect(fixture.transport.yields, hasLength(1));
          });
        }
      }

      for (final representation in [
        'explicit',
        'materialized',
        'encoded-json',
        'packed-json',
      ]) {
        test('$representation is encrypted with response context', () async {
          final provider = _RecordingProvider();
          final fixture = await _start(native, provider: provider);
          final response = _ResponsePayload(representation);
          fixture.invocation.respondWith(
            lazyPayload: response.payload,
            arguments: representation.startsWith('packed')
                ? ['ignored fallback']
                : representation == 'explicit'
                ? _arguments
                : null,
            argumentsKeywords: representation.startsWith('packed')
                ? {'ignored': true}
                : representation == 'explicit'
                ? _keywords
                : null,
            options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
          );
          expect(fixture.transport.yields, hasLength(1));
          final reply = fixture.transport.yields.single;
          expect(provider.contexts, hasLength(1));
          final context = provider.contexts.single!;
          expect(context.direction, WampE2eeDirection.outbound);
          expect(context.messageType, _yieldMessageType);
          expect(context.realm, 'reply.realm');
          expect(context.uri, 'reply.proc');
          expect(context.local?.sessionId, 42);
          final decoded = provider.delegate.unpackPayload(
            reply.arguments,
            reply.options!,
          );
          expect(decoded.arguments, _arguments);
          expect(decoded.argumentsKeywords, _keywords);
          expect(reply.argumentsKeywords, isNull);
          for (final wireReply in _wireRoundTrips(reply)) {
            final decoded = provider.delegate.unpackPayload(
              wireReply.arguments,
              wireReply.options!,
            );
            expect(decoded.arguments, _arguments);
            expect(decoded.argumentsKeywords, _keywords);
          }
        });
      }

      for (final arguments in <List<dynamic>?>[null, _arguments]) {
        for (final keywords in <Map<String, dynamic>?>[null, _keywords]) {
          for (final mode in ['json', 'msgpack', 'cbor', 'wamp']) {
            test(
              '$mode preserves null arguments=${arguments == null} keywords=${keywords == null}',
              () async {
                final provider = _RecordingProvider();
                final fixture = await _start(native, provider: provider);
                fixture.invocation.respondWith(
                  lazyPayload: LazyMessagePayload.materialized(
                    arguments: arguments,
                    argumentsKeywords: keywords,
                  ),
                  options: YieldOptions(
                    pptScheme: mode == 'wamp' ? 'wamp' : 'x_example',
                    pptSerializer: mode == 'wamp' ? 'cbor' : mode,
                  ),
                );
                expect(fixture.transport.yields, hasLength(1));
                final reply = fixture.transport.yields.single;
                if (mode == 'wamp') {
                  final decoded = provider.delegate.unpackPayload(
                    reply.arguments,
                    reply.options!,
                  );
                  expect(decoded.arguments, arguments);
                  expect(decoded.argumentsKeywords, keywords);
                } else {
                  final decoded = PPTPayload.unpackPPTPayload(
                    reply.arguments,
                    reply.options!,
                  );
                  expect(decoded.arguments, arguments);
                  expect(decoded.argumentsKeywords, keywords);
                }
              },
            );
          }
        }
      }

      for (final scheme in ['x_example', 'wamp']) {
        for (final missing in ['arguments', 'keywords', 'both']) {
          test('$scheme falls back to explicit $missing', () async {
            final provider = _RecordingProvider();
            final fixture = await _start(native, provider: provider);
            fixture.invocation.respondWith(
              lazyPayload: LazyMessagePayload.materialized(
                arguments: missing == 'keywords' ? _arguments : null,
                argumentsKeywords: missing == 'arguments' ? _keywords : null,
              ),
              arguments: _arguments,
              argumentsKeywords: _keywords,
              options: YieldOptions(pptScheme: scheme, pptSerializer: 'cbor'),
            );
            expect(fixture.transport.yields, hasLength(1));
            final reply = fixture.transport.yields.single;
            if (scheme == 'wamp') {
              final decoded = provider.delegate.unpackPayload(
                reply.arguments,
                reply.options!,
              );
              expect(decoded.arguments, _arguments);
              expect(decoded.argumentsKeywords, _keywords);
            } else {
              final decoded = PPTPayload.unpackPPTPayload(
                reply.arguments,
                reply.options!,
              );
              expect(decoded.arguments, _arguments);
              expect(decoded.argumentsKeywords, _keywords);
            }
          });
        }
      }

      test('empty lazy values do not fall back to explicit values', () async {
        final fixture = await _start(native);
        fixture.invocation.respondWith(
          lazyPayload: LazyMessagePayload.materialized(
            arguments: [],
            argumentsKeywords: {},
          ),
          arguments: _arguments,
          argumentsKeywords: _keywords,
          options: YieldOptions(pptScheme: 'x_example', pptSerializer: 'cbor'),
        );
        final reply = fixture.transport.yields.single;
        final decoded = PPTPayload.unpackPPTPayload(
          reply.arguments,
          reply.options!,
        );
        expect(decoded.arguments, isEmpty);
        expect(decoded.argumentsKeywords, isEmpty);
      });

      test(
        'payload encryption provider overrides the session provider',
        () async {
          final sessionProvider = _RecordingProvider();
          final payloadProvider = _RecordingProvider();
          final fixture = await _start(native, provider: sessionProvider);
          fixture.invocation.respondWith(
            lazyPayload: LazyMessagePayload.materialized(
              arguments: _arguments,
              argumentsKeywords: _keywords,
              e2eeProvider: payloadProvider,
            ),
            options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
          );
          expect(fixture.transport.yields, hasLength(1));
          expect(sessionProvider.contexts, isEmpty);
          expect(payloadProvider.contexts, hasLength(1));
          final reply = fixture.transport.yields.single;
          final decoded = payloadProvider.delegate.unpackPayload(
            reply.arguments,
            reply.options!,
          );
          expect(decoded.arguments, _arguments);
          expect(decoded.argumentsKeywords, _keywords);
        },
      );

      test(
        'failed transcoding sends nothing and leaves response open',
        () async {
          final fixture = await _start(native);
          expect(
            () => fixture.invocation.respondWith(
              lazyPayload: LazyMessagePayload.encoded(
                encoding: LazyPayloadEncoding.json,
                argumentsBytes: Uint8List.fromList(utf8.encode('not-json')),
                argumentsDecoder: (bytes) =>
                    jsonDecode(utf8.decode(bytes)) as List<dynamic>,
              ),
              options: YieldOptions(
                pptScheme: 'x_example',
                pptSerializer: 'cbor',
              ),
            ),
            throwsFormatException,
          );
          expect(fixture.transport.yields, isEmpty);
          expect(fixture.invocation.isResponseClosed(), isFalse);
          fixture.invocation.respondWith(arguments: ['retry']);
          expect(fixture.transport.yields.single.arguments, ['retry']);
        },
      );

      test(
        'matching encrypted bytes are forwarded without repacking',
        () async {
          final provider = _RecordingProvider();
          final fixture = await _start(native, provider: provider);
          final options = YieldOptions(
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
          );
          final packed =
              provider.delegate
                      .packPayload(
                        _arguments,
                        _keywords,
                        options,
                      )
                      .single
                  as Uint8List;
          var decodes = 0;
          fixture.invocation.respondWith(
            lazyPayload: LazyMessagePayload.packed(
              encoding: LazyPayloadEncoding.cbor,
              packedPayloadBytes: packed,
              packedPayloadDecoder: (_) {
                decodes++;
                return (arguments: _arguments, argumentsKeywords: _keywords);
              },
            ),
            options: options,
          );
          expect(fixture.transport.yields, hasLength(1));
          final reply = fixture.transport.yields.single;
          expect(identical(reply.arguments!.single, packed), isTrue);
          expect(decodes, 0);
          expect(provider.contexts, isEmpty);
          final decoded = provider.delegate.unpackPayload(
            reply.arguments,
            options,
          );
          expect(decoded.arguments, _arguments);
          expect(decoded.argumentsKeywords, _keywords);
        },
      );

      for (final representation in [
        'explicit',
        'materialized',
        'encoded-json',
        'packed-json',
      ]) {
        test(
          'missing encryption provider rejects $representation and permits retry',
          () async {
            final fixture = await _start(native);
            final response = _ResponsePayload(representation);
            expect(
              () => fixture.invocation.respondWith(
                lazyPayload: response.payload,
                arguments: representation == 'explicit' ? _arguments : null,
                argumentsKeywords: representation == 'explicit'
                    ? _keywords
                    : null,
                options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
              ),
              throwsA(isA<WampE2eeProviderUnavailableException>()),
            );
            expect(fixture.transport.yields, isEmpty);
            expect(fixture.invocation.isResponseClosed(), isFalse);
            fixture.invocation.respondWith(arguments: ['retry']);
            expect(fixture.transport.yields.single.arguments, ['retry']);
            expect(fixture.invocation.isResponseClosed(), isTrue);
          },
        );
      }

      test('progressive packed replies retain ownership until final', () async {
        final fixture = await _start(native);
        for (final progress in [true, false]) {
          fixture.invocation.respondWith(
            lazyPayload: LazyMessagePayload.materialized(
              arguments: [progress ? 'chunk' : 'final'],
            ),
            options: YieldOptions(
              progress: progress,
              pptScheme: 'x_example',
              pptSerializer: 'msgpack',
            ),
          );
          expect(fixture.invocation.isResponseClosed(), !progress);
        }
        expect(fixture.transport.yields, hasLength(2));
        for (var index = 0; index < 2; index++) {
          final reply = fixture.transport.yields[index];
          expect(reply.options!.progress, index == 0);
          expect(
            PPTPayload.unpackPPTPayload(
              reply.arguments,
              reply.options!,
            ).arguments,
            [index == 0 ? 'chunk' : 'final'],
          );
        }
        expect(
          () => fixture.invocation.respondWith(arguments: ['late']),
          throwsStateError,
        );
        expect(fixture.transport.yields, hasLength(2));
      });
    });
  }

  for (final mode in [
    (native: false, materialized: false),
    (native: true, materialized: false),
    (native: true, materialized: true),
  ]) {
    group('reply lifecycle $mode', () {
      for (final shutdown in ['not-ready', 'goodbye', 'incoming-done']) {
        test('dropped progressive reply is terminal after $shutdown', () async {
          final fixture = await _start(
            mode.native,
            materialized: mode.materialized,
          );
          switch (shutdown) {
            case 'not-ready':
              fixture.transport.ready = false;
            case 'goodbye':
              await fixture.session.close();
              expect(fixture.transport.isReady, isTrue);
            case 'incoming-done':
              fixture.transport.deferClose = true;
              await fixture.transport.inbound.close();
              await Future<void>.delayed(Duration.zero);
              expect(fixture.transport.isReady, isTrue);
          }

          expect(
            () => fixture.invocation.respondWith(
              arguments: ['discarded'],
              options: YieldOptions(progress: true),
            ),
            returnsNormally,
          );
          expect(fixture.transport.responseAttempts, isEmpty);
          expect(fixture.transport.yields, isEmpty);
          expect(fixture.invocation.isResponseClosed(), isTrue);
          expect(
            () => fixture.invocation.respondWith(arguments: ['too late']),
            throwsStateError,
          );
          expect(fixture.transport.responseAttempts, isEmpty);
        });
      }

      for (final losesReadiness in [false, true]) {
        for (final progress in [false, true]) {
          test(
            'send failure progress=$progress losesReadiness=$losesReadiness',
            () async {
              final fixture = await _start(
                mode.native,
                materialized: mode.materialized,
              );
              final failure = StateError('synthetic response rejection');
              fixture.transport.beforeResponse = (_) {
                if (losesReadiness) {
                  fixture.transport.ready = false;
                }
                throw failure;
              };
              expect(
                () => fixture.invocation.respondWith(
                  arguments: ['rejected'],
                  options: YieldOptions(progress: progress),
                ),
                losesReadiness ? returnsNormally : throwsA(same(failure)),
              );
              expect(fixture.transport.yields, isEmpty);
              expect(fixture.transport.responseAttempts, hasLength(1));
              expect(fixture.invocation.isResponseClosed(), losesReadiness);
              fixture.transport.beforeResponse = null;
              if (!losesReadiness) {
                expect(
                  () => fixture.invocation.respondWith(arguments: ['retry']),
                  returnsNormally,
                );
                expect(fixture.transport.yields.single.arguments, ['retry']);
                expect(
                  fixture.transport.yields.single.invocationRequestId,
                  401,
                );
                expect(fixture.invocation.isResponseClosed(), isTrue);
              }
              final attempts = fixture.transport.responseAttempts.length;
              expect(
                () => fixture.invocation.respondWith(arguments: ['duplicate']),
                throwsStateError,
              );
              expect(fixture.transport.responseAttempts, hasLength(attempts));
            },
          );
        }
      }

      for (final finish in ['final', 'error', 'timeout', 'disconnect']) {
        test('progress refreshes timeout until $finish', () async {
          await _withInvocationClock((timers) async {
            final fixture = await _start(
              mode.native,
              materialized: mode.materialized,
              timeout: 80,
            );
            expect(fixture.invocation.timeout, 80);
            expect(timers, hasLength(1));
            expect(timers.single.isActive, isTrue);
            fixture.invocation.respondWith(
              arguments: ['chunk'],
              options: YieldOptions(progress: true),
            );
            expect(fixture.invocation.isResponseClosed(), isFalse);
            expect(timers, hasLength(2));
            expect(timers.first.isActive, isFalse);
            expect(timers.last.isActive, isTrue);
            timers.first.fire();
            expect(fixture.transport.responses, hasLength(1));
            expect(fixture.transport.yields.single.arguments, ['chunk']);

            switch (finish) {
              case 'final':
                fixture.invocation.respondWith(arguments: ['final']);
                expect(fixture.transport.yields.last.arguments, ['final']);
              case 'error':
                fixture.invocation.respondWith(
                  isError: true,
                  errorUri: Error.notAuthorized,
                  arguments: ['denied'],
                );
                final error = fixture.transport.responses.last as Error;
                expect(error.error, Error.notAuthorized);
                expect(error.requestTypeId, MessageTypes.codeInvocation);
                expect(error.requestId, 401);
                expect(error.arguments, ['denied']);
              case 'timeout':
                timers.last.fire();
                final error = fixture.transport.responses.last as Error;
                expect(error.error, Error.timeout);
                expect(error.requestTypeId, MessageTypes.codeInvocation);
                expect(error.requestId, 401);
                expect(error.arguments, ['Call timed out']);
              case 'disconnect':
                await fixture.transport.close();
                await Future<void>.delayed(Duration.zero);
            }
            expect(timers, hasLength(2));
            expect(timers.every((timer) => !timer.isActive), isTrue);
            final count = finish == 'disconnect' ? 1 : 2;
            expect(fixture.transport.responses, hasLength(count));
            for (final timer in timers) {
              timer.fire();
            }
            expect(fixture.transport.responses, hasLength(count));
            if (finish != 'disconnect') {
              expect(fixture.invocation.isResponseClosed(), isTrue);
              expect(
                () => fixture.invocation.respondWith(),
                throwsStateError,
              );
            }
          });
        });
      }

      for (final directInterrupt in [false, true]) {
        for (final cancelMode in <String?>[
          null,
          CancelOptions.modeKillNoWait,
        ]) {
          test('interrupt direct=$directInterrupt mode=$cancelMode', () async {
            await _withInvocationClock((timers) async {
              final fixture = await _start(
                mode.native,
                materialized: mode.materialized,
                timeout: 80,
              );
              final interrupt = directInterrupt
                  ? NativeSessionMessage(
                      serializer: NativeMessageSerializer.json,
                      metadata: NativeMessageMetadata(
                        messageCode: MessageTypes.codeInterrupt,
                        primaryId: 401,
                        secondaryId: 0,
                        detailNumberA: 0,
                        detailNumberB: 0,
                        flags:
                            NativeMessageMetadata.flagDirectBind |
                            NativeMessageMetadata.flagMetadataBind,
                        stringA: cancelMode,
                      ),
                    )
                  : Interrupt(
                      401,
                      options: cancelMode == null
                          ? null
                          : (InterruptOptions()..mode = cancelMode),
                    );
              fixture.transport.inbound.add(interrupt);
              await Future<void>.delayed(Duration.zero);
              expect(fixture.transport.responses, hasLength(1));
              final error = fixture.transport.responses.single as Error;
              expect(error.requestTypeId, MessageTypes.codeInvocation);
              expect(error.requestId, 401);
              expect(error.error, Error.errorInvocationCanceled);
              expect(error.arguments, cancelMode == null ? null : [cancelMode]);
              expect(fixture.invocation.isResponseClosed(), isTrue);
              expect(timers.single.isActive, isFalse);
              timers.single.fire();
              fixture.transport.inbound.add(interrupt);
              await Future<void>.delayed(Duration.zero);
              expect(fixture.transport.responses, hasLength(1));
              expect(
                () => fixture.invocation.respondWith(),
                throwsStateError,
              );
            });
          });
        }
      }
    });
  }
}

Future<void> _withInvocationClock(
  Future<void> Function(List<_InvocationTimer>) action,
) {
  final timers = <_InvocationTimer>[];
  return runZoned(
    () => action(timers),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration != const Duration(milliseconds: 80)) {
          return parent.createTimer(zone, duration, callback);
        }
        final timer = _InvocationTimer(callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
}

class _InvocationTimer implements Timer {
  _InvocationTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

Iterable<Yield> _wireRoundTrips(Yield reply) sync* {
  Yield copyForSerialization() => Yield(
    reply.invocationRequestId,
    options: reply.options,
    arguments: reply.arguments == null ? null : List.of(reply.arguments!),
    argumentsKeywords: reply.argumentsKeywords == null
        ? null
        : Map.of(reply.argumentsKeywords!),
  );
  // YIELD is router ingress; its JSON binary envelope is intentionally opaque.
  final jsonWire =
      jsonDecode(json.Serializer().serialize(copyForSerialization())) as List;
  expect(jsonWire[0], MessageTypes.codeYield);
  expect(jsonWire[1], reply.invocationRequestId);
  if (reply.options?.pptScheme != null) {
    expect(jsonWire[3], [
      '\u0000${base64Encode(reply.arguments!.single as Uint8List)}',
    ]);
  } else {
    expect(jsonWire[3], reply.arguments);
  }
  if (reply.argumentsKeywords != null) {
    expect(jsonWire[4], reply.argumentsKeywords);
  }
  for (final serializer in [
    msgpack.Serializer(),
    cbor.Serializer(),
  ]) {
    final encoded = serializer.serialize(copyForSerialization());
    final bytes = encoded is String
        ? Uint8List.fromList(utf8.encode(encoded))
        : encoded as Uint8List;
    yield serializer.deserialize(bytes) as Yield;
  }
}

class _ResponsePayload {
  _ResponsePayload(String representation) {
    if (representation == 'explicit') {
      return;
    }
    if (representation == 'materialized') {
      payload = LazyMessagePayload.materialized(
        arguments: _arguments,
        argumentsKeywords: _keywords,
      );
      return;
    }
    sourceSerializer = representation.split('-').last;
    if (representation == 'encoded-json') {
      payload = LazyMessagePayload.encoded(
        encoding: LazyPayloadEncoding.json,
        argumentsBytes: Uint8List.fromList(utf8.encode(jsonEncode(_arguments))),
        argumentsDecoder: (bytes) {
          decodeCalls++;
          return jsonDecode(utf8.decode(bytes)) as List<dynamic>;
        },
        argumentsKeywordsBytes: Uint8List.fromList(
          utf8.encode(jsonEncode(_keywords)),
        ),
        argumentsKeywordsDecoder: (bytes) {
          decodeCalls++;
          return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        },
      );
      return;
    }
    final options = YieldOptions(
      pptScheme: 'x_example',
      pptSerializer: sourceSerializer,
    );
    packedBytes =
        PPTPayload.packPPTPayload(_arguments, _keywords, options).single
            as Uint8List;
    payload = LazyMessagePayload.packed(
      encoding: switch (sourceSerializer) {
        'msgpack' => LazyPayloadEncoding.messagePack,
        'cbor' => LazyPayloadEncoding.cbor,
        _ => LazyPayloadEncoding.json,
      },
      packedPayloadBytes: packedBytes!,
      packedPayloadDecoder: (bytes) {
        decodeCalls++;
        final decoded = PPTPayload.unpackPPTPayload([bytes], options);
        return (
          arguments: decoded.arguments,
          argumentsKeywords: decoded.argumentsKeywords,
        );
      },
    );
  }

  String? sourceSerializer;
  LazyMessagePayload? payload;
  Uint8List? packedBytes;
  int decodeCalls = 0;
}

Future<
  ({
    _ReplyTransport transport,
    Session session,
    LazyInvocationPayload invocation,
  })
>
_start(
  bool native, {
  WampE2eeProvider? provider,
  bool materialized = false,
  int? timeout,
}) async {
  final transport = _ReplyTransport();
  addTearDown(() async {
    transport.deferClose = false;
    await transport.close();
  });
  final session = await Client(
    realm: 'reply.realm',
    transport: transport,
    e2eeProvider: provider,
  ).connect().first;
  expect(session.isConnected(), isTrue);
  LazyInvocationPayload? received;
  final registration = materialized
      ? await session.register('reply.proc')
      : await session.registerLazyPayloadHandler(
          'reply.proc',
          (invocation) => received = invocation,
        );
  if (materialized) {
    registration.onInvoke((invocation) {
      received = invocation.toLazyInvocationPayload();
    });
  }
  if (native) {
    transport.inbound.add(
      NativeSessionMessage(
        serializer: NativeMessageSerializer.json,
        metadata: NativeMessageMetadata(
          messageCode: MessageTypes.codeInvocation,
          primaryId: 401,
          secondaryId: registration.registrationId,
          detailNumberA: 9001,
          detailNumberB: timeout ?? 0,
          flags:
              NativeMessageMetadata.flagDirectBind |
              NativeMessageMetadata.flagMetadataBind |
              NativeMessageMetadata.flagDetailNumberAPresent |
              NativeMessageMetadata.flagDetailBoolATrue |
              (timeout == null
                  ? 0
                  : NativeMessageMetadata.flagDetailNumberBPresent),
          stringA: 'reply.proc',
        ),
        argsBytes: Uint8List.fromList(utf8.encode('["request"]')),
      ),
    );
  } else {
    transport.inbound.add(
      Invocation(
        401,
        registration.registrationId,
        InvocationDetails(9001, 'reply.proc', true)..timeout = timeout,
        arguments: ['request'],
      ),
    );
  }
  await Future<void>.delayed(Duration.zero);
  expect(received, isNotNull);
  return (transport: transport, session: session, invocation: received!);
}

class _RecordingProvider implements WampE2eeProvider {
  final delegate = WampCborXsalsa20Poly1305Provider.single(
    keyId: 'reply-test',
    key: Uint8List.fromList(List.generate(32, (index) => index + 1)),
  );
  final contexts = <WampE2eeRuntimeContext?>[];

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    contexts.add(runtimeContext);
    return delegate.packPayload(
      arguments,
      argumentsKeywords,
      options,
      runtimeContext: runtimeContext,
    );
  }

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => delegate.unpackPayload(
    arguments,
    options,
    runtimeContext: runtimeContext,
  );
}

class _ReplyTransport extends AbstractTransport
    implements SessionOptimizedTransport {
  final inbound = StreamController<Object?>.broadcast(sync: true);
  final yields = <Yield>[];
  final responses = <AbstractMessageWithPayload>[];
  final responseAttempts = <AbstractMessageWithPayload>[];
  void Function(AbstractMessageWithPayload)? beforeResponse;
  bool ready = true;
  bool deferClose = false;
  Completer<void>? _disconnect;
  Completer<void>? _lost;
  bool _open = false;

  @override
  Completer<void>? get onDisconnect => _disconnect;
  @override
  Completer<void>? get onConnectionLost => _lost;
  @override
  bool get isOpen => _open;
  @override
  bool get isReady => _open && ready;
  @override
  Future<void> get onReady => Future.value();

  @override
  Future<void> open({Duration? pingInterval}) async {
    _open = true;
    _disconnect = Completer<void>();
    _lost = Completer<void>();
  }

  @override
  Future<void> close({dynamic error}) async {
    if (!_open || deferClose) {
      return;
    }
    _open = false;
    complete(_disconnect, error);
    await inbound.close();
  }

  @override
  void send(AbstractMessage message) {
    if (message is Yield || message is Error) {
      final response = message as AbstractMessageWithPayload;
      responseAttempts.add(response);
      beforeResponse?.call(response);
      responses.add(response);
    }
    switch (message) {
      case Hello():
        inbound.add(Welcome(42, Details.forWelcome()));
      case Register():
        inbound.add(Registered(message.requestId, 5353));
      case Yield():
        yields.add(message);
    }
  }

  @override
  Stream<AbstractMessage?> receive() => inbound.stream
      .where((message) => message is AbstractMessage)
      .cast<AbstractMessage?>();
  @override
  Stream<Object?> receiveSessionMessages() => inbound.stream;
}

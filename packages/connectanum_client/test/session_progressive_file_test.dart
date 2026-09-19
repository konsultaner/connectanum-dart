import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/e2ee_file_segment.dart';
import 'package:test/test.dart';

// Portable boundary tests, not a substitute for native file/crypto integration.
void main() {
  for (final encrypted in [false, true]) {
    group('encrypted=$encrypted progressive file lifecycle', () {
      for (final terminal in [
        'result',
        'wamp.error.canceled',
        'wamp.error.timeout',
        'wamp.error.not_authorized',
        'disconnect',
        'cancel-listener',
      ]) {
        for (final finish in [false, true]) {
          test('finish=$finish rejects after $terminal', () async {
            final fixture = await _connect(encrypted);
            final call = fixture.start();
            final source = call.handle.openFileSource('fixture.bin', 8);
            addTearDown(source.close);
            if (terminal == 'result') {
              fixture.transport.inbound.add(
                Result(
                  call.handle.requestId,
                  ResultDetails(),
                  arguments: ['ok'],
                ),
              );
            } else if (terminal == 'disconnect') {
              await fixture.transport.close();
            } else if (terminal == 'cancel-listener') {
              await call.subscription.cancel();
            } else {
              fixture.transport.inbound.add(
                Error(
                  MessageTypes.codeCall,
                  call.handle.requestId,
                  const {},
                  terminal,
                ),
              );
            }
            await _drain();
            if (terminal == 'result') {
              expect(call.results.single.arguments, ['ok']);
              expect(call.errors, isEmpty);
              expect(call.done, isTrue);
            } else if (terminal == 'disconnect') {
              expect(call.errors.single, isA<StateError>());
              expect(call.done, isTrue);
            } else if (terminal != 'cancel-listener') {
              expect(
                call.errors.single,
                isA<Error>().having((e) => e.error, 'uri', terminal),
              );
              expect(call.done, isTrue);
            }
            final packedBefore = fixture.provider.packCalls;
            expect(() => _send(call.handle, source, finish), throwsStateError);
            expect(fixture.transport.segments, isEmpty);
            expect(fixture.provider.prepared, isEmpty);
            expect(fixture.provider.packCalls, packedBefore);
            expect(call.handle.isFinished, isFalse);
            expect((source as _Source).closed, isFalse);
          });
        }
      }

      for (final finish in [false, true]) {
        test(
          'finish=$finish preserves native source, options and context',
          () async {
            final fixture = await _connect(encrypted);
            final call = fixture.start();
            final source = call.handle.openFileSource('fixture.bin', 8);
            addTearDown(source.close);
            expect(fixture.transport.opened, [('fixture.bin', 8)]);
            expect(call.handle.supportsFileSegments, isTrue);
            final initial = fixture.transport.sent.whereType<Call>().single;
            expect(initial.requestId, call.handle.requestId);
            expect(initial.options!.progress, isTrue);
            expect(initial.options!.receiveProgress, isTrue);
            expect(initial.options!.timeout, 1234);
            expect(initial.options!.discloseMe, isTrue);
            expect(initial.options!.custom, {'x_trace': 'file'});

            fixture.transport.inbound.add(
              Result(
                call.handle.requestId,
                ResultDetails(progress: true),
                arguments: ['ready'],
              ),
            );
            await _drain();
            expect(call.results.single.arguments, ['ready']);
            expect(call.done, isFalse);
            final packedBefore = fixture.provider.packCalls;
            _send(call.handle, source, finish);
            final segment = fixture.transport.segments.single;
            expect(segment.source, same(source));
            expect(segment.offset, 2);
            expect(segment.length, 4);
            expect(segment.message.requestId, call.handle.requestId);
            expect(segment.message.procedure, 'files.upload');
            expect(segment.message.options!.progress, !finish);
            expect(segment.message.options!.receiveProgress, isNull);
            expect(segment.message.options!.timeout, isNull);
            expect(
              segment.message.arguments!.single,
              isA<Uint8List>().having((b) => b.length, 'placeholder length', 0),
            );
            expect(fixture.transport.sent.whereType<Call>(), hasLength(1));
            expect(fixture.provider.packCalls, packedBefore);
            expect(call.handle.isFinished, finish);
            expect((source as _Source).closed, isFalse);
            if (encrypted) {
              expect(segment.e2ee, same(fixture.provider.context));
              expect(segment.message.e2eeProvider, same(fixture.provider));
              final prepared = fixture.provider.prepared.single;
              expect(prepared.$1, same(segment.message.options));
              expect(prepared.$1.pptScheme, 'wamp');
              expect(prepared.$1.pptSerializer, 'cbor');
              expect(prepared.$1.pptCipher, ConnectanumE2eeProfile.aes256Gcm);
              expect(prepared.$1.pptKeyId, 'fixture');
              expect(prepared.$2!.direction, WampE2eeDirection.outbound);
              expect(prepared.$2!.messageType, WampE2eeMessageType.call);
              expect(prepared.$2!.realm, 'test.realm');
              expect(prepared.$2!.uri, 'files.upload');
              expect(prepared.$2!.local!.sessionId, 17);
            } else {
              expect(segment.e2ee, isNull);
              expect(fixture.provider.prepared, isEmpty);
            }
            if (finish) {
              expect(() => _send(call.handle, source, false), throwsStateError);
              expect(() => _send(call.handle, source, true), throwsStateError);
              expect(
                () => call.handle.sendChunk(arguments: ['late']),
                throwsStateError,
              );
              expect(() => call.handle.finish(), throwsStateError);
              expect(fixture.transport.segments, hasLength(1));
            }
            fixture.transport.inbound.add(
              Result(call.handle.requestId, ResultDetails(), arguments: ['ok']),
            );
            await _drain();
            expect(call.results.map((r) => r.arguments), [
              ['ready'],
              ['ok'],
            ]);
            expect(call.errors, isEmpty);
            expect(call.done, isTrue);
          },
        );

        test(
          'finish=$finish transport failure is retryable and keeps ownership',
          () async {
            final fixture = await _connect(encrypted);
            final call = fixture.start();
            final source = call.handle.openFileSource('fixture.bin', 8);
            addTearDown(source.close);
            final error = StateError('transport send failed');
            fixture.transport.sendError = error;
            expect(
              () => _send(call.handle, source, finish),
              throwsA(same(error)),
            );
            expect(call.handle.isFinished, isFalse);
            expect(fixture.transport.segments, isEmpty);
            expect((source as _Source).closed, isFalse);
            fixture.transport.sendError = null;
            _send(call.handle, source, finish);
            expect(fixture.transport.segments.single.source, same(source));
            expect(call.handle.isFinished, finish);
            expect(call.errors, isEmpty);
          },
        );
      }

      test(
        'retiring one call does not retire another or reopen its handle',
        () async {
          final fixture = await _connect(encrypted);
          final retired = fixture.start();
          final active = fixture.start();
          expect(active.handle.requestId, isNot(retired.handle.requestId));
          final source = active.handle.openFileSource('fixture.bin', 8);
          addTearDown(source.close);
          fixture.transport.inbound.add(
            Result(
              retired.handle.requestId,
              ResultDetails(),
              arguments: ['old'],
            ),
          );
          await _drain();
          expect(retired.done, isTrue);
          expect(retired.results.single.arguments, ['old']);
          expect(() => _send(retired.handle, source, false), throwsStateError);
          _send(active.handle, source, false);
          expect(
            fixture.transport.segments.single.message.requestId,
            active.handle.requestId,
          );
          expect(active.done, isFalse);
          expect(active.errors, isEmpty);
          expect(retired.errors, isEmpty);
        },
      );
    });
  }

  for (final finish in [false, true]) {
    test(
      'finish=$finish E2EE preparation failure never sends or finishes',
      () async {
        final fixture = await _connect(true);
        final call = fixture.start();
        final source = call.handle.openFileSource('fixture.bin', 8);
        addTearDown(source.close);
        final error = StateError('key unavailable');
        fixture.provider.prepareError = error;
        expect(() => _send(call.handle, source, finish), throwsA(same(error)));
        expect(call.handle.isFinished, isFalse);
        expect(fixture.transport.segments, isEmpty);
        expect((source as _Source).closed, isFalse);
        fixture.provider.prepareError = null;
        _send(call.handle, source, finish);
        expect(
          fixture.transport.segments.single.e2ee,
          same(fixture.provider.context),
        );
        expect(call.handle.isFinished, finish);
      },
    );
  }

  for (final unavailable in [
    'disabled',
    'transport',
    'native-transport',
    'provider',
  ]) {
    test(
      '$unavailable capability does not silently downgrade encryption',
      () async {
        final fixture = await _connect(true);
        fixture.transport.fileSupported = unavailable != 'transport';
        fixture.transport.nativeSupported = unavailable != 'native-transport';
        fixture.provider.nativeSupported = unavailable != 'provider';
        final call = fixture.start(
          enableFileSegments: unavailable != 'disabled',
        );
        expect(call.handle.supportsFileSegments, isFalse);
        expect(
          () => call.handle.openFileSource('fixture.bin', 8),
          throwsUnsupportedError,
        );
        final source = _Source();
        expect(() => _send(call.handle, source, false), throwsUnsupportedError);
        expect(() => _send(call.handle, source, true), throwsUnsupportedError);
        expect(call.handle.isFinished, isFalse);
        expect(fixture.transport.opened, isEmpty);
        expect(fixture.transport.segments, isEmpty);
        expect(fixture.provider.prepared, isEmpty);
      },
    );
  }
}

void _send(ProgressiveCall call, TransportFileSource source, bool finish) {
  if (finish) {
    call.finishFileSegment(source, offset: 2, length: 4);
  } else {
    call.sendFileSegment(source, offset: 2, length: 4);
  }
}

// This fixture has no timers or I/O: bound delivery without swallowing errors.
Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

Future<_Fixture> _connect(bool encrypted) async {
  final transport = _Segments();
  final provider = _Provider();
  final client = Client(
    realm: 'test.realm',
    transport: transport,
    e2eeProvider: encrypted ? provider : null,
  );
  addTearDown(client.disconnect);
  final session = await client.connect().first;
  expect(session.isConnected(), isTrue);
  return _Fixture(transport, provider, session, encrypted);
}

class _Fixture {
  _Fixture(this.transport, this.provider, this.session, this.encrypted);
  final _Segments transport;
  final _Provider provider;
  final Session session;
  final bool encrypted;

  _ObservedCall start({bool enableFileSegments = true}) {
    final handle = session.startProgressiveCall(
      'files.upload',
      options: CallOptions(
        receiveProgress: true,
        timeout: 1234,
        discloseMe: true,
        custom: {'x_trace': 'file'},
        pptScheme: encrypted ? 'wamp' : null,
        pptSerializer: encrypted ? 'cbor' : null,
        pptCipher: encrypted ? ConnectanumE2eeProfile.aes256Gcm : null,
        pptKeyId: encrypted ? 'fixture' : null,
      ),
      enableFileSegments: enableFileSegments,
    );
    final observed = _ObservedCall(handle);
    addTearDown(observed.subscription.cancel);
    return observed;
  }
}

class _ObservedCall {
  _ObservedCall(this.handle) {
    subscription = handle.results.listen(
      results.add,
      onError: errors.add,
      onDone: () => done = true,
    );
  }
  final ProgressiveCall handle;
  final results = <Result>[];
  final errors = <Object>[];
  bool done = false;
  late final StreamSubscription<Result> subscription;
}

class _Source implements TransportFileSource {
  bool closed = false;
  @override
  void close() => closed = true;
}

class _Segment {
  _Segment(this.message, this.source, this.offset, this.length, this.e2ee);
  final Call message;
  final TransportFileSource source;
  final int offset;
  final int length;
  final NativeE2eeFileSegmentContext? e2ee;
}

class _Segments extends AbstractTransport
    implements NativeE2eeFileSegmentTransport {
  final inbound = StreamController<AbstractMessage>.broadcast();
  final sent = <AbstractMessage>[];
  final segments = <_Segment>[];
  final opened = <(String, int)>[];
  bool fileSupported = true;
  bool nativeSupported = true;
  Object? sendError;
  bool _open = false;
  @override
  final Completer<void> onDisconnect = Completer<void>();
  @override
  final Completer<void> onConnectionLost = Completer<void>();
  @override
  bool get isOpen => _open;
  @override
  bool get isReady => _open;
  @override
  Future<void> get onReady => Future.value();
  @override
  Future<void> open({Duration? pingInterval}) async => _open = true;
  @override
  Future<void> close({dynamic error}) async {
    if (!_open) return;
    _open = false;
    unawaited(inbound.close());
    onDisconnect.complete();
  }

  @override
  Stream<AbstractMessage> receive() => inbound.stream;
  @override
  void send(AbstractMessage message) {
    sent.add(message);
    if (message is Hello) inbound.add(Welcome(17, Details.forWelcome()));
  }

  @override
  bool get supportsFileSegments => fileSupported;
  @override
  bool get supportsNativeE2eeFileSegments => nativeSupported;
  @override
  TransportFileSource openFileSegmentSource(String path, int expectedLength) {
    opened.add((path, expectedLength));
    return _Source();
  }

  @override
  void sendFileSegment(
    AbstractMessage message, {
    required TransportFileSource source,
    required int offset,
    required int length,
  }) {
    if (sendError != null) throw sendError!;
    segments.add(_Segment(message as Call, source, offset, length, null));
  }

  @override
  void sendNativeE2eeFileSegment(
    AbstractMessage message, {
    required TransportFileSource source,
    required int offset,
    required int length,
    required NativeE2eeFileSegmentContext e2ee,
  }) {
    if (sendError != null) throw sendError!;
    segments.add(_Segment(message as Call, source, offset, length, e2ee));
  }
}

class _Provider implements WampE2eeProvider, NativeE2eeFileSegmentProvider {
  bool nativeSupported = true;
  int packCalls = 0;
  Object? prepareError;
  final prepared = <(PPTOptions, WampE2eeRuntimeContext?)>[];
  final context = const NativeE2eeFileSegmentContext(
    runtimeIdentity: 'fixture',
    sessionHandle: 1,
    keyId: 'fixture',
    cipher: ConnectanumE2eeProfile.aes256Gcm,
  );
  @override
  bool get supportsNativeE2eeFileSegments => nativeSupported;
  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? keywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    packCalls++;
    return [Uint8List(1)];
  }

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw UnsupportedError('not used');
  @override
  NativeE2eeFileSegmentContext prepareNativeE2eeFileSegment(
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    prepared.add((options, runtimeContext));
    if (prepareError != null) throw prepareError!;
    return context;
  }
}

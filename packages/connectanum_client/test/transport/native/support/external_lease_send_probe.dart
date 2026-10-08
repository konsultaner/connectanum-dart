import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:ffi/ffi.dart';

typedef _CreateSizedN =
    Pointer<Void> Function(Pointer<Utf8>, IntPtr, Pointer<NativeBufferToken>);
typedef _CreateSizedD =
    Pointer<Void> Function(Pointer<Utf8>, int, Pointer<NativeBufferToken>);
typedef _StateN = Int32 Function(Pointer<Void>);
typedef _StateD = int Function(Pointer<Void>);
typedef _StopN = Void Function(Pointer<Void>);
typedef _StopD = void Function(Pointer<Void>);
typedef _DestroyN = Int32 Function(Pointer<Void>);
typedef _DestroyD = int Function(Pointer<Void>);

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Expected the external-lease fixture path');
  }
  const payloadLength = 15 * 1024 * 1024;
  final nativePath = Platform.environment['CONNECTANUM_NATIVE_LIB']!;
  final nativeLibrary = DynamicLibrary.open(nativePath);
  final fixture = DynamicLibrary.open(arguments.single);
  final create = fixture.lookupFunction<_CreateSizedN, _CreateSizedD>(
    'fixture_create_sized',
  );
  final state = fixture.lookupFunction<_StateN, _StateD>('fixture_state');
  final stop = fixture.lookupFunction<_StopN, _StopD>('fixture_stop');
  final destroy = fixture.lookupFunction<_DestroyN, _DestroyD>(
    'fixture_destroy',
  );
  final token = calloc<NativeBufferToken>();
  final nativePathUtf8 = nativePath.toNativeUtf8();
  final actor = create(nativePathUtf8, payloadLength, token);
  calloc.free(nativePathUtf8);
  if (actor == nullptr) throw StateError('C producer could not lend bytes');

  final allocator = NativeBufferAllocator(nativeLibrary);
  final peer = _PausedRawSocketPeer(payloadLength);
  NativeRawSocketTransport? transport;
  NativeOwnedBuffer? borrowed;
  NativeWriteReceipt? receipt;
  var actorDestroyed = false;
  try {
    borrowed = allocator.adoptTrustedNativeToken(token);
    if (borrowed.length != payloadLength) {
      throw StateError('Producer lease length changed during adoption');
    }

    await peer.start();
    transport = NativeRawSocketTransport.withJsonSerializer(
      '127.0.0.1',
      peer.port,
    );
    await transport.open();
    await transport.onReady;
    final nativeTransport = transport as NativeBufferTransport;
    final writeReceipt = nativeTransport.sendEncodedNativeBufferTracked(
      borrowed,
      transfer: true,
    );
    receipt = writeReceipt;
    if (!borrowed.isDisposed) {
      throw StateError(
        'Native submission did not consume the transferred view',
      );
    }
    try {
      await writeReceipt.wait(timeout: const Duration(milliseconds: 250));
      throw StateError('Native write completed while the peer was paused');
    } on TimeoutException {
      // Queue acceptance did not release the producer while the native writer
      // was still blocked on the peer's receive window.
    }
    if (state(actor) != 0) {
      throw StateError('Producer lease released before local write completion');
    }

    peer.resumeReading();
    final receivedLength = await peer.received.future.timeout(
      const Duration(seconds: 15),
    );
    if (receivedLength != payloadLength) {
      throw StateError(
        'Peer received $receivedLength bytes, expected $payloadLength',
      );
    }
    if (await writeReceipt.wait(timeout: const Duration(seconds: 10)) !=
        NativeWriteOutcome.written) {
      throw StateError('Native write did not complete successfully');
    }
    receipt.dispose();
    receipt = null;

    await _waitFor(() => (state(actor) & 1) != 0);
    final releasedState = state(actor);
    if (releasedState != 1) {
      throw StateError(
        'Producer cleanup state $releasedState was not exactly once on its owner thread',
      );
    }
    stop(actor);
    await _waitFor(() => (state(actor) & 512) != 0);
    final stoppedState = state(actor);
    if (stoppedState != 513 || destroy(actor) != 0) {
      throw StateError(
        'Producer failed owner-thread shutdown: $stoppedState',
      );
    }
    actorDestroyed = true;
    stdout.writeln(
      'external-lease-send: delayed native write preserved bytes and released once on owner thread',
    );
  } finally {
    peer.resumeReading();
    receipt?.dispose();
    if (borrowed != null && !borrowed.isDisposed) borrowed.dispose();
    await transport?.close();
    await peer.close();
    if (!actorDestroyed) {
      stop(actor);
      for (var attempt = 0; attempt < 800; attempt++) {
        if ((state(actor) & 512) != 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if ((state(actor) & 512) != 0) destroy(actor);
    }
    calloc.free(token);
  }
}

Future<void> _waitFor(bool Function() ready) async {
  for (var attempt = 0; attempt < 800; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('C producer did not complete owner-thread cleanup');
}

final class _PausedRawSocketPeer {
  _PausedRawSocketPeer(this.expectedLength) {
    unawaited(received.future.then<void>((_) {}, onError: (Object _) {}));
  }

  final int expectedLength;
  final received = Completer<int>();
  final _ready = Completer<(int, SendPort)>();
  ReceivePort? _messages;
  SendPort? _control;
  Isolate? _isolate;

  late final int port;

  Future<void> start() async {
    _messages = ReceivePort();
    _messages!.listen((message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'ready':
          final ready = (
            message['port'] as int,
            message['control'] as SendPort,
          );
          port = ready.$1;
          _control = ready.$2;
          if (!_ready.isCompleted) _ready.complete(ready);
          break;
        case 'received':
          if (!received.isCompleted) {
            received.complete(message['length'] as int);
          }
          break;
        case 'error':
          if (!received.isCompleted) {
            received.completeError(StateError(message['message'] as String));
          }
          break;
      }
    });
    _isolate = await Isolate.spawn(
      _pausedRawSocketPeerMain,
      (expectedLength, _messages!.sendPort),
      errorsAreFatal: true,
    );
    await _ready.future.timeout(const Duration(seconds: 10));
  }

  void resumeReading() => _control?.send('resume');

  Future<void> close() async {
    _control?.send('close');
    _isolate?.kill(priority: Isolate.immediate);
    _messages?.close();
  }
}

void _pausedRawSocketPeerMain((int, SendPort) arguments) async {
  final (expectedLength, reply) = arguments;
  final control = ReceivePort();
  final server = await ServerSocket.bind('127.0.0.1', 0);
  Socket? socket;
  StreamSubscription<Uint8List>? subscription;
  final reader = _RawSocketFrameReader(expectedLength, reply);

  control.listen((message) {
    if (message == 'resume') subscription?.resume();
    if (message == 'close') {
      subscription?.cancel();
      socket?.destroy();
      unawaited(server.close());
      control.close();
    }
  });
  reply.send({
    'type': 'ready',
    'port': server.port,
    'control': control.sendPort,
  });

  try {
    await for (final accepted in server) {
      socket = accepted;
      subscription = accepted.listen(
        reader.onData,
        onError: (Object error) => reader.fail(error),
        onDone: () => reader.fail(
          StateError('Client closed before the complete frame arrived'),
        ),
      );
      reader.attach(accepted, subscription);
      break;
    }
  } catch (error) {
    reader.fail(error);
  }
}

final class _RawSocketFrameReader {
  _RawSocketFrameReader(this.expectedLength, this.reply);

  final int expectedLength;
  final SendPort reply;
  final List<int> _handshake = [];
  final Uint8List _header = Uint8List(4);
  bool _handshakeComplete = false;
  bool _terminal = false;
  int _headerLength = 0;
  int _payloadLength = -1;
  int _receivedLength = 0;

  void onData(Uint8List chunk) {
    if (_terminal) return;
    if (!_handshakeComplete) {
      _handshake.addAll(chunk);
      if (_handshake.length < 4) return;
      if (_handshake[0] != 0x7f || (_handshake[1] & 0x0f) != 1) {
        fail(StateError('Unexpected RawSocket handshake: $_handshake'));
        return;
      }
      // The client sends no data frame until it receives this response. Pause
      // immediately after replying so the native write remains backpressured.
      _handshakeComplete = true;
      _socket?.add([0x7f, 0xf1, 0, 0]);
      _socketSubscription?.pause();
      if (_handshake.length > 4) {
        _readFrame(Uint8List.fromList(_handshake.skip(4).toList()));
      }
      return;
    }
    _readFrame(chunk);
  }

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  void attach(Socket socket, StreamSubscription<Uint8List> subscription) {
    _socket = socket;
    _socketSubscription = subscription;
  }

  void _readFrame(Uint8List chunk) {
    var offset = 0;
    while (offset < chunk.length && !_terminal) {
      if (_payloadLength < 0) {
        while (offset < chunk.length && _headerLength < _header.length) {
          _header[_headerLength++] = chunk[offset++];
        }
        if (_headerLength < _header.length) return;
        if (_header[0] != 0) {
          fail(StateError('Expected a RawSocket WAMP data frame'));
          return;
        }
        _payloadLength = (_header[1] << 16) | (_header[2] << 8) | _header[3];
        if (_payloadLength != expectedLength) {
          fail(StateError('Frame length $_payloadLength != $expectedLength'));
          return;
        }
      }

      final remaining = _payloadLength - _receivedLength;
      final count = chunk.length - offset < remaining
          ? chunk.length - offset
          : remaining;
      for (var i = 0; i < count; i++) {
        final expected = ((_receivedLength + i) * 31 + 7) & 0xff;
        if (chunk[offset + i] != expected) {
          fail(
            StateError(
              'External producer byte mismatch at ${_receivedLength + i}',
            ),
          );
          return;
        }
      }
      offset += count;
      _receivedLength += count;
      if (_receivedLength == _payloadLength) {
        _terminal = true;
        reply.send({'type': 'received', 'length': _receivedLength});
        _socketSubscription?.pause();
      }
    }
  }

  void fail(Object error) {
    if (_terminal) return;
    _terminal = true;
    reply.send({'type': 'error', 'message': error.toString()});
    _socketSubscription?.pause();
  }
}

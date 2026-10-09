// Native receipt finalizers return observer capacity without cancelling frames.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';

typedef _CountN = UintPtr Function();
typedef _CountD = int Function();

class _Survivor {
  _Survivor(this.receipt, this.allocator);
  final WeakReference<NativeWriteReceipt> receipt;
  final WeakReference<NativeBufferAllocator> allocator;
}

const _frame = '[48,42,{},"com.example.proc",[1]]';

@pragma('vm:never-inline')
_Survivor _abandonReceipt(
  DynamicLibrary library,
  NativeBufferTransport transport,
) {
  final allocator = NativeBufferAllocator(library);
  final builder = allocator.allocate(128);
  for (var i = 0; i < _frame.length; i++) {
    builder.setUint8(i, _frame.codeUnitAt(i));
  }
  final frozen = builder.freeze(length: _frame.length);
  final receipt = transport.sendEncodedNativeBufferTracked(
    frozen,
    transfer: true,
  );
  return _Survivor(WeakReference(receipt), WeakReference(allocator));
}

Future<void> _peer(SendPort replies) async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  replies.send(server.port);
  server.listen((socket) {
    var pending = <int>[];
    var greeted = false;
    socket.listen((bytes) {
      pending.addAll(bytes);
      if (!greeted && pending.length >= 4) {
        socket.add(pending.sublist(0, 4));
        pending = pending.sublist(4);
        greeted = true;
      }
      while (greeted && pending.length >= 4) {
        final length = pending[1] << 16 | pending[2] << 8 | pending[3];
        if (pending.length < length + 4) return;
        replies.send(pending.sublist(4, length + 4));
        pending = pending.sublist(length + 4);
      }
    });
  });
}

Future<void> main() async {
  final library = DynamicLibrary.open(
    Platform.environment['CONNECTANUM_NATIVE_LIB']!,
  );
  final count = library.lookupFunction<_CountN, _CountD>(
    'ct_test_write_receipt_live_handles',
  );
  if (count() != 0) {
    throw StateError('Probe requires an empty receipt registry');
  }
  final replies = ReceivePort();
  final messages = StreamIterator<dynamic>(replies);
  final peer = await Isolate.spawn(_peer, replies.sendPort);
  if (!await messages.moveNext()) throw StateError('Peer did not start');
  final transport = NativeRawSocketTransport.withJsonSerializer(
    '127.0.0.1',
    messages.current as int,
  );
  final client = HttpClient();
  try {
    await transport.open();
    final survivor = _abandonReceipt(
      library,
      transport as NativeBufferTransport,
    );
    if (!await messages.moveNext() ||
        utf8.decode(messages.current as List<int>) != _frame) {
      throw StateError('Abandoning the observer cancelled the frame');
    }
    final server = (await Service.getInfo()).serverUri;
    if (server == null) throw StateError('Probe requires VM service');
    final isolate = Service.getIsolateId(Isolate.current)!;
    for (var attempt = 0; attempt < 80; attempt++) {
      final uri = server
          .resolve('getAllocationProfile')
          .replace(queryParameters: {'isolateId': isolate, 'gc': 'true'});
      final response = await (await client.getUrl(uri)).close();
      final result =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (result.containsKey('error')) throw StateError('$result');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (survivor.receipt.target == null &&
          survivor.allocator.target == null &&
          count() == 0) {
        stdout.writeln(
          'write-receipt-gc: collected observer returned capacity without cancelling frame',
        );
        return;
      }
    }
    throw StateError('Receipt finalizer did not return capacity: ${count()}');
  } finally {
    await transport.close();
    await messages.cancel();
    replies.close();
    peer.kill(priority: Isolate.immediate);
    client.close(force: true);
  }
}

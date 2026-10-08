import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';

final _released = <int>{};
final _finalizer = Finalizer<int>(_released.add);

class _Lease {
  _Lease(this.id);
  final int id;
}

class _Survivor {
  _Survivor(this.view, this.owner);
  LazyMessagePayload? view;
  final WeakReference<_Lease> owner;
}

MaterializedPayloadView _decode(Uint8List bytes) =>
    (arguments: <dynamic>[bytes], argumentsKeywords: null);

class _QueuedTransport extends AbstractTransport {
  LazyMessagePayload? sent;
  @override
  Completer<void>? get onDisconnect => null;
  @override
  Completer<void>? get onConnectionLost => null;
  @override
  bool get isOpen => true;
  @override
  bool get isReady => true;
  @override
  Future<void> get onReady => Future<void>.value();
  @override
  Future<void> open({Duration? pingInterval}) async {}
  @override
  Future<void> close({dynamic error}) async {}
  @override
  Stream<AbstractMessage?> receive() => const Stream<AbstractMessage?>.empty();
  @override
  void send(AbstractMessage message) {
    if (message is AbstractMessageWithPayload) sent = message.toLazyPayload();
  }
}

@pragma('vm:never-inline')
_Survivor _make(String mode) {
  final lease = _Lease(7);
  _finalizer.attach(lease, lease.id);
  final source = Uint8List.fromList([90, 1, 2, 3, 91]);
  final span = Uint8List.sublistView(source, 1, 4);
  final payload = mode == 'opaque'
      ? LazyMessagePayload.encoded(
          transparentBinaryPayload: span,
          anchor: lease,
        )
      : LazyMessagePayload.packed(
          encoding: LazyPayloadEncoding.cbor,
          packedPayloadBytes: span,
          packedPayloadDecoder: _decode,
          anchor: lease,
        );
  final transport = _QueuedTransport();
  final session = Session('lease.realm', transport);
  switch (mode) {
    case 'call':
      session.callLazyPayload(
        'com.lease',
        payload: payload,
        options: CallOptions(pptScheme: 'x_retention', pptSerializer: 'cbor'),
      );
    case 'publish':
      session.publishLazyPayload(
        'com.lease',
        payload: payload,
        options: PublishOptions(
          pptScheme: 'x_retention',
          pptSerializer: 'cbor',
        ),
      );
    case 'progress':
      session
          .startProgressiveCall(
            'com.lease',
            options: CallOptions(
              pptScheme: 'x_retention',
              pptSerializer: 'cbor',
            ),
          )
          .sendLazyChunk(payload);
    case 'plain':
    case 'opaque':
      session.publishLazyPayload('com.lease', payload: payload);
    default:
      throw ArgumentError(mode);
  }
  return _Survivor(transport.sent!, WeakReference(lease));
}

@pragma('vm:never-inline')
bool _gone(_Survivor survivor) =>
    survivor.owner.target == null && _released.contains(7);
Future<void> main(List<String> arguments) async {
  final mode = arguments.single;
  final service = await Service.getInfo();
  final server = service.serverUri!;
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collect() async {
    final uri = server
        .resolve('getAllocationProfile')
        .replace(queryParameters: {'isolateId': isolate, 'gc': 'true'});
    final response = await (await client.getUrl(uri)).close();
    final result = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    if (result.containsKey('error')) throw StateError('$result');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  try {
    final survivor = _make(mode);
    for (var i = 0; i < 8; i++) {
      await collect();
    }
    if (mode == 'owned') {
      if (!_gone(survivor)) {
        throw StateError('Owned copy retains external lease');
      }
    } else if (_gone(survivor)) {
      throw StateError('Premature external lease finalization: $mode');
    }
    final bytes =
        survivor.view!.packedPayloadBytes ??
        survivor.view!.transparentBinaryPayload ??
        survivor.view!.arguments!.single as Uint8List;
    if (bytes.join(',') != '1,2,3') throw StateError('Payload changed');
    survivor.view = null;
    for (var i = 0; i < 40 && !_gone(survivor); i++) {
      await collect();
    }
    if (!_gone(survivor)) {
      throw StateError('Lease not released after last view: $mode');
    }
    print('ANCHOR_GC_OK $mode');
  } finally {
    client.close(force: true);
  }
}

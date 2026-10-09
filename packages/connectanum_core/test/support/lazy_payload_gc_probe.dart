import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';

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
@pragma('vm:never-inline')
_Survivor _make(String mode) {
  final lease = _Lease(7);
  _finalizer.attach(lease, lease.id);
  final source = Uint8List.fromList([90, 1, 2, 3, 91]);
  final payload = LazyMessagePayload.packed(
    encoding: LazyPayloadEncoding.cbor,
    packedPayloadBytes: Uint8List.sublistView(source, 1, 4),
    packedPayloadDecoder: _decode,
    anchor: lease,
  );
  final LazyMessagePayload view;
  switch (mode) {
    case 'control':
      view = payload;
    case 'reanchor':
      view = payload.withAnchor(Object());
    case 'clear':
      view = payload.withAnchor(null);
    case 'metadata':
      view = payload
          .withAnchor(Object())
          .withE2eeRuntimeContext(
            const WampE2eeRuntimeContext(
              direction: WampE2eeDirection.outbound,
              messageType: WampE2eeMessageType.call,
            ),
          )
          .withAnchor(null);
    case 'unwrap':
      view = unwrapLazyPayloadView(
        LazyMessagePayload.encoded(
          transparentBinaryPayload: Uint8List.sublistView(source, 1, 4),
          anchor: lease,
        ).withAnchor(Object()),
        pptScheme: 'x_retention',
        pptSerializer: 'flatbuffers',
      );
    case 'restore':
      final message = Call(1, 'com.retention');
      message.restoreLazyPayload(payload);
      view = message.toLazyPayload();
    case 'yield':
    case 'error':
    case 'progress':
    case 'plain':
      LazyMessagePayload? forwarded;
      final invocation = Invocation(
        1,
        2,
        InvocationDetails(null, 'com.retention', true),
      );
      invocation.onResponse((response) {
        forwarded = response.toLazyPayload();
      });
      invocation.respondWith(
        lazyPayload: payload,
        isError: mode == 'error',
        errorUri: mode == 'error' ? 'com.error' : null,
        options: mode == 'plain'
            ? null
            : YieldOptions(
                pptScheme: 'x_retention',
                pptSerializer: 'cbor',
                progress: mode == 'progress',
              ),
      );
      view = forwarded!;
    case 'mutation':
    case 'resnapshot':
    case 'mutation-owned':
      final message = Call(1, 'com.mutation');
      message.restoreLazyPayload(
        LazyMessagePayload.encoded(
          transparentBinaryPayload: Uint8List.sublistView(source, 1, 4),
          anchor: lease,
        ),
      );
      message.arguments = <dynamic>[42];
      view = mode == 'mutation-owned'
          ? message.toLazyPayload().toOwned()
          : message.toLazyPayload();
      if (mode == 'resnapshot') {
        message.transparentBinaryPayload = null;
        message.argumentsKeywords = <String, dynamic>{'changed': true};
      }
    case 'owned':
      view = payload.toOwned();
    default:
      throw ArgumentError(mode);
  }
  return _Survivor(view, WeakReference(lease));
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
    if (mode.endsWith('owned')) {
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

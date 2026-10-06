import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';

var released = 0;
final finalizer = Finalizer<Object>((_) => released++);

class Survivor {
  Survivor(this.anchor, this.root);
  Object? anchor;
  final WeakReference<Uint8List> root;
}

@pragma('vm:never-inline')
Survivor make() {
  final root = allocateNativeExternalBytes(65536)..fillRange(0, 65536, 73);
  final anchor = Object();
  retainNativeExternalBytes(anchor, root);
  finalizer.attach(root, Object());
  return Survivor(anchor, WeakReference(root));
}

@pragma('vm:never-inline')
bool alive(Survivor survivor) => survivor.root.target != null;

Future<void> main() async {
  final service = await Service.getInfo();
  final server = service.serverUri!;
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collect() async {
    final uri = server
        .resolve('getAllocationProfile')
        .replace(
          queryParameters: {'isolateId': isolate, 'gc': 'true'},
        );
    final response = await (await client.getUrl(uri)).close();
    final result = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    if (result.containsKey('error')) throw StateError('$result');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  try {
    final survivor = make();
    for (var i = 0; i < 8; i++) {
      await collect();
    }
    if (!alive(survivor) || released != 0) {
      throw StateError('Live anchor did not retain its allocation');
    }
    identityHashCode(survivor.anchor);
    survivor.anchor = null;
    for (var i = 0; i < 40 && (alive(survivor) || released == 0); i++) {
      await collect();
    }
    if (alive(survivor) || released != 1) {
      throw StateError('Allocation retained after its last anchor was dropped');
    }
    print('EXTERNAL_PROVENANCE_GC_OK');
  } finally {
    client.close(force: true);
  }
}

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';

var released = 0;
final finalizer = Finalizer<Object>((_) => released++);

class Survivor {
  Survivor(this.anchor, this.root, [this.facade]);
  Object? anchor;
  final WeakReference<Uint8List> root;
  final WeakReference<Uint8List>? facade;
}

@pragma('vm:never-inline')
Survivor make(String mode) {
  final root = allocateNativeExternalBytes(65536)..fillRange(0, 65536, 73);
  final anchor = Object();
  retainNativeExternalBytes(anchor, root);
  finalizer.attach(root, Object());
  if (mode == 'anchor') return Survivor(anchor, WeakReference(root));
  final source = mode == 'empty'
      ? Uint8List.sublistView(root, root.length, root.length)
      : Uint8List.sublistView(root, 17, root.length - 17).asUnmodifiableView();
  final alias = nativeExternalByteView(source, anchor: anchor)!;
  if (mode == 'derived') {
    final derived = Uint8List.sublistView(
      alias,
      13,
      alias.length - 29,
    ).asUnmodifiableView();
    return Survivor(derived, WeakReference(root), WeakReference(alias));
  }
  return Survivor(alias, WeakReference(root));
}

@pragma('vm:never-inline')
bool alive(Survivor survivor) => survivor.root.target != null;

@pragma('vm:never-inline')
void checkView(Survivor survivor, String mode) {
  if (mode == 'anchor') return;
  final view = survivor.anchor! as Uint8List;
  if (mode == 'empty') {
    if (view.isNotEmpty) throw StateError('Expected empty alias');
  } else if (view.first != 73 || view.last != 73) {
    throw StateError('Native alias data differs');
  }
  if (mode == 'derived' && survivor.facade!.target != null) {
    throw StateError('Derived view did not outlive its parent facade');
  }
}

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'anchor' : args.single;
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
    final survivor = make(mode);
    for (var i = 0; i < 8; i++) {
      await collect();
    }
    if (!alive(survivor) || released != 0) {
      throw StateError('Live anchor did not retain its allocation');
    }
    checkView(survivor, mode);
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

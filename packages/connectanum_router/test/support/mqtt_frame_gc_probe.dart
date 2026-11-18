import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/native/mqtt_frame_buffer.dart';

class _RetainedPayload {
  _RetainedPayload(this.bytes, this.body);
  Uint8List? bytes;
  final WeakReference<Uint8List> body;
}

Future<T> _poll<T>(T? Function() read) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final result = read();
    if (result != null) return result;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw TimeoutException('Native MQTT poll did not complete');
}

@pragma('vm:never-inline')
Future<_RetainedPayload> _receive(String library) async {
  final runtime = NativeTransportRuntime(libraryPath: library)..start();
  Socket? socket;
  try {
    final listener = runtime.listenRouterEndpoint(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': 'connectanum.router',
            'version': 1,
            'endpoints': [
              {
                'host': '127.0.0.1',
                'port': 0,
                'tls_mode': 'disabled',
                'protocols': ['mqtt'],
              },
            ],
          }),
        ),
      ),
      0,
    );
    socket = await Socket.connect('127.0.0.1', runtime.getLocalPort(listener));
    socket.add(
      MqttPacketCodec.encodeConnect(
        MqttConnect(version: MqttVersion.v5, clientId: 'gc-body'),
      ),
    );
    await socket.flush();
    final id = await _poll(() {
      final id = runtime.pollConnection(listener);
      return id == 0 ? null : id;
    });
    final decoder = MqttFrameDecoder();
    await _poll(() => runtime.pollMqttFrames(id, decoder));
    final packet = MqttPacketCodec.encodePublish(
      MqttVersion.v5,
      topic: 'owned/large',
      payload: Uint8List.fromList(List.generate(100000, (i) => i % 251)),
    );
    socket.add(packet.sublist(0, 8));
    await socket.flush();
    final partial = await _poll(() => runtime.pollMqttFrames(id, decoder));
    if (partial.isNotEmpty) {
      throw StateError('Partial publication completed early');
    }
    socket.add(packet.sublist(8));
    await socket.flush();
    final frames = await _poll(() {
      final frames = runtime.pollMqttFrames(id, decoder);
      return frames == null || frames.isEmpty ? null : frames;
    });
    final frame = frames.single;
    final view = MqttPacketCodec.decodePublish(frame, MqttVersion.v5).payload;
    return _RetainedPayload(view, WeakReference(frame.body));
  } finally {
    socket?.destroy();
    runtime.shutdown();
    runtime.dispose();
  }
}

@pragma('vm:never-inline')
void _verify(_RetainedPayload retained, {int offset = 0}) {
  if (retained.body.target == null) {
    throw StateError('Body finalized while a view survives');
  }
  final bytes = retained.bytes!;
  if (bytes.length != 100000) throw StateError('Payload length changed');
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != (i + offset) % 251)
      throw StateError('Payload changed at $i');
  }
}

@pragma('vm:never-inline')
bool _released(_RetainedPayload retained) => retained.body.target == null;

@pragma('vm:never-inline')
_RetainedPayload _snapshotView() {
  final source = Uint8List.fromList(List.generate(100014, (i) => i % 251));
  final snapshot = NativeIsolateBytes.transfer(source)!;
  final bytes = NativeIsolateBytes.materialize(snapshot);
  final view = Uint8List.sublistView(bytes, 7, 100007);
  source.fillRange(0, source.length, 0);
  return _RetainedPayload(view, WeakReference(view));
}

Future<void> main(List<String> arguments) async {
  final info = await Service.getInfo();
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collect() async {
    final uri = info.serverUri!
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
    final library = ffi.DynamicLibrary.open(arguments.single);
    final live = library.providesSymbol('ct_test_mapped_bytes_live_allocations')
        ? library.lookupFunction<ffi.UintPtr Function(), int Function()>(
            'ct_test_mapped_bytes_live_allocations',
          )
        : null;
    final retained = await _receive(arguments.single);
    if (live != null && live() == 0) {
      throw StateError('Large body did not acquire a mapped owner');
    }
    for (var i = 0; i < 4; i++) {
      await collect();
      _verify(retained);
      if (live != null && live() == 0) {
        throw StateError('Mapping released while payload view survives');
      }
    }
    retained.bytes = null;
    for (var i = 0; i < 8 && !_released(retained); i++) {
      await collect();
    }
    if (!_released(retained)) {
      throw StateError('Dropped payload retains its body');
    }
    if (live != null) {
      for (var i = 0; i < 8 && live() != 0; i++) {
        await collect();
      }
      if (live() != 0) throw StateError('Dropped payload retains native pages');
      stdout.writeln('MQTT_MAPPED_OWNER_RELEASED');
      final snapshot = _snapshotView();
      for (var i = 0; i < 4; i++) {
        await collect();
        _verify(snapshot, offset: 7);
        if (live() != 1)
          throw StateError('Snapshot view lost its native owner');
      }
      snapshot.bytes = null;
      for (var i = 0; i < 8 && (!_released(snapshot) || live() != 0); i++) {
        await collect();
      }
      if (!_released(snapshot) || live() != 0) {
        throw StateError('Dropped immutable snapshot retains its native owner');
      }
      stdout.writeln('MQTT_SNAPSHOT_OWNER_RELEASED');
    }
    stdout.writeln('MQTT_FRAME_GC_OK');
  } finally {
    client.close(force: true);
  }
}

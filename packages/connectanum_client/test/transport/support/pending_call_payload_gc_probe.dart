import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/serializer.dart'
    as flat;

// Keep the session and its pending controller rooted while testing payload GC.
final _sessions = <Session>[];

class _Peer extends AbstractTransport {
  _Peer(this.retain);
  final bool retain;
  final input = StreamController<AbstractMessage>.broadcast(sync: true);
  final codec = flat.Serializer();
  late WeakReference<Call> call;
  late WeakReference<Uint8List> payload;
  late Uint8List wire;
  late int requestId;
  Call? retained;
  bool replied = false;
  bool _open = false;
  @override
  final onDisconnect = Completer<void>();
  @override
  final onConnectionLost = Completer<void>();
  @override
  bool get isOpen => _open;
  @override
  bool get isReady => _open;
  @override
  Future<void> get onReady => Future<void>.value();
  @override
  Future<void> open({Duration? pingInterval}) async => _open = true;
  @override
  Future<void> close({dynamic error}) async {
    if (!_open) return;
    _open = false;
    onDisconnect!.complete();
    unawaited(input.close());
  }

  @override
  Stream<AbstractMessage> receive() => input.stream;
  @override
  void send(AbstractMessage message) {
    switch (message) {
      case Hello():
        input.add(Welcome(42, Details.forWelcome()));
      case Call():
        requestId = message.requestId;
        wire = codec.serialize(message);
        call = WeakReference(message);
        payload = WeakReference(message.arguments!.single as Uint8List);
        if (retain) retained = message;
      case Goodbye():
        input.add(Goodbye(null, 'wamp.close.goodbye_and_out'));
    }
  }

  void reply() {
    replied = true;
    input.add(Result(requestId, ResultDetails(), arguments: ['ok']));
  }
}

@pragma('vm:never-inline')
Future<({Client client, _Peer peer, Future<Result> result})> _make(
  bool retain,
) async {
  final peer = _Peer(retain);
  final client = Client(realm: 'gc.realm', transport: peer);
  final session = await client.connect().first;
  _sessions.add(session);
  final result = session
      .call(
        'com.delayed',
        arguments: [
          Uint8List.fromList(List.generate(65536, (i) => i % 251)),
        ],
      )
      .first;
  return (client: client, peer: peer, result: result);
}

@pragma('vm:never-inline')
bool _gone(_Peer peer) =>
    peer.call.target == null && peer.payload.target == null;
@pragma('vm:never-inline')
WeakReference<Object> _witness() => WeakReference(Object());

Future<void> main(List<String> arguments) async {
  final mode = arguments.single;
  final service = await Service.getInfo();
  final isolate = Service.getIsolateId(Isolate.current)!;
  final http = HttpClient();
  Future<void> collect() async {
    final uri = service.serverUri!
        .resolve('getAllocationProfile')
        .replace(
          queryParameters: {'isolateId': isolate, 'gc': 'true'},
        );
    final response = await (await http.getUrl(uri)).close();
    final result = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    if (result.containsKey('error')) throw StateError('$result');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  final fixture = await _make(mode == 'transport-retained');
  try {
    final witness = _witness();
    for (var i = 0; i < 8; i++) {
      await collect();
    }
    if (witness.target != null) throw StateError('Collection witness survived');
    if (mode == 'transport-retained') {
      if (_gone(fixture.peer)) {
        throw StateError('Transport lost its live payload');
      }
      fixture.peer.retained = null;
      for (var i = 0; i < 8; i++) {
        await collect();
      }
    }
    if (!_gone(fixture.peer)) {
      throw StateError('Pending RPC retained obsolete CALL payload');
    }
    final decoded = fixture.peer.codec.deserialize(fixture.peer.wire) as Call;
    final bytes = decoded.arguments!.single as Uint8List;
    if (bytes.length != 65536 ||
        bytes.asMap().entries.any((e) => e.value != e.key % 251)) {
      throw StateError('Detached transport bytes changed');
    }
    fixture.peer.reply();
    final result = await fixture.result;
    if (result.arguments!.single != 'ok') throw StateError('Reply changed');
    if (_sessions.single.realm != 'gc.realm') {
      throw StateError('Session changed');
    }
    print('PENDING_PAYLOAD_GC_OK $mode');
  } finally {
    if (!fixture.peer.replied) {
      fixture.peer.reply();
      await fixture.result;
    }
    await fixture.client.disconnect();
    _sessions.clear();
    http.close(force: true);
  }
}

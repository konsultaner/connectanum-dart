// Linux-only RawSocket PPT copy diagnostic using sdk_socket_copy_probe.c.
// This observes libc write arguments, not total SDK/TLS copies or performance.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:connectanum_client/connectanum.dart' hide SocketTransport;
import 'package:connectanum_client/src/transport/socket/socket_transport.dart';
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_client/src/transport/dart_transport_copy_metrics.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/src/serializer/flatbuffers/session_profile.dart';

final library = DynamicLibrary.process();
final reset = library
    .lookupFunction<
      Void Function(Uint16, UintPtr, Int32),
      void Function(int, int, int)
    >('probe_reset');
final count = library.lookupFunction<UintPtr Function(), int Function()>(
  'probe_count',
);
final overflow = library.lookupFunction<Int32 Function(), int Function()>(
  'probe_overflow',
);
final address = library
    .lookupFunction<UintPtr Function(UintPtr), int Function(int)>(
      'probe_address',
    );
final requested = library
    .lookupFunction<UintPtr Function(UintPtr), int Function(int)>(
      'probe_requested',
    );
final accepted = library
    .lookupFunction<IntPtr Function(UintPtr), int Function(int)>(
      'probe_accepted',
    );
final error = library
    .lookupFunction<Int32 Function(UintPtr), int Function(int)>('probe_error');

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> run(
  String codec,
  int length,
  String shape,
  bool syscallRetries,
) async {
  final serializer = switch (codec) {
    'cbor' => cbor.Serializer(),
    'msgpack' => msgpack.Serializer(),
    'flatbuffers' => flat.Serializer(),
    _ => throw ArgumentError(codec),
  };
  final code = switch (codec) {
    'cbor' => SocketHelper.serializationCbor,
    'msgpack' => SocketHelper.serializationMsgpack,
    'flatbuffers' => SocketHelper.serializationFlatBuffers,
    _ => throw ArgumentError(codec),
  };
  final partial = shape.startsWith('partial');
  final start = partial ? 32 : 0;
  final pointer = calloc<Uint8>(partial ? length + 64 : length);
  final all = pointer.asTypedList(partial ? length + 64 : length);
  for (var i = 0; i < all.length; i++) {
    all[i] = (i * 37 + 11) & 255;
  }
  var body = partial ? Uint8List.sublistView(all, start, start + length) : all;
  if (shape.endsWith('readonly')) body = body.asUnmodifiableView();
  final message = Call(
    42,
    'com.pointer.probe',
    options: CallOptions(pptScheme: 'opaque', pptSerializer: 'flatbuffers'),
  )..transparentBinaryPayload = body;
  final fragments = serializer.serializeFragments(message);
  final expectedBuilder = BytesBuilder(copy: false);
  for (final part
      in fragments ?? [serializer.serialize(message) as Uint8List]) {
    expectedBuilder.add(part);
  }
  final expectedPayload = expectedBuilder.takeBytes();
  final frame = Completer<Uint8List>();
  final welcomeReceived = Completer<void>();
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final peers = <Socket>[];
  final serverSubscription = server.listen((socket) {
    peers.add(socket);
    final bytes = <int>[];
    var handshakeDone = false;
    int? frameLength;
    var established = codec != 'flatbuffers';
    socket.listen((data) {
      bytes.addAll(data);
      if (!handshakeDone) {
        if (bytes.length < 4) return;
        check(bytes.length == 4, 'unexpected handshake trailing bytes');
        bytes.clear();
        handshakeDone = true;
        socket.add(
          SocketHelper.getInitialHandshake(
            SocketHelper.maxMessageLengthExponent,
            code,
          ),
        );
        return;
      }
      if (frameLength == null && bytes.length >= 4) {
        frameLength =
            4 +
            SocketHelper.getPayloadLength(
              Uint8List.fromList(bytes.take(4).toList()),
              4,
            );
      }
      if (frameLength != null &&
          bytes.length >= frameLength! &&
          !frame.isCompleted) {
        check(bytes.length == frameLength, 'extra frame bytes');
        if (!established) {
          final hello =
              serializer.deserialize(
                    Uint8List.fromList(bytes.sublist(4)),
                  )
                  as Hello;
          final profile = const FlatBuffersSessionProfile.router()
              .acceptIncoming(hello);
          final welcome = Welcome(9, Details.forWelcome());
          profile.prepareOutgoing(welcome);
          final encoded = serializer.serialize(welcome) as Uint8List;
          socket.add(
            SocketHelper.buildMessageHeader(
              SocketHelper.messageWamp,
              encoded.length,
              false,
            ),
          );
          socket.add(encoded);
          bytes.clear();
          frameLength = null;
          established = true;
          return;
        }
        frame.complete(Uint8List.fromList(bytes));
      }
    }, onError: frame.completeError);
  });
  final transport = SocketTransport(
    InternetAddress.loopbackIPv4.address,
    server.port,
    serializer,
    code,
    messageLengthExponent: SocketHelper.maxMessageLengthExponent,
  );
  StreamSubscription<AbstractMessage>? incoming;
  var recording = false;
  try {
    await transport.open();
    incoming = transport.receive().listen((message) {
      if (message is Welcome && !welcomeReceived.isCompleted) {
        welcomeReceived.complete();
      }
    });
    await transport.onReady.timeout(const Duration(seconds: 10));
    if (codec == 'flatbuffers') {
      transport.send(Hello('realm', Details.forHello()));
      await welcomeReceived.future.timeout(const Duration(seconds: 10));
    }
    reset(server.port, syscallRetries ? 4096 : 0, syscallRetries ? 1 : 0);
    DartTransportCopyMetrics.beginWindow();
    recording = true;
    transport.send(message);
    final wire = await frame.future.timeout(const Duration(seconds: 10));
    await transport.drain().timeout(const Duration(seconds: 10));
    final ownCopies = DartTransportCopyMetrics.endWindow();
    recording = false;
    final payload = Uint8List.sublistView(wire, 4);
    check(
      payload.length == expectedPayload.length &&
          List.generate(
            payload.length,
            (i) => payload[i] == expectedPayload[i],
          ).every((v) => v),
      'wire payload differs',
    );
    final decoded = serializer.deserialize(payload) as Call;
    check(
      decoded.requestId == 42 && decoded.procedure == message.procedure,
      'metadata differs',
    );
    final receivedBody = decoded.transparentBinaryPayload as List;
    check(
      receivedBody.length == body.length &&
          List.generate(
            body.length,
            (i) => receivedBody[i] == body[i],
          ).every((v) => v),
      'body differs',
    );
    check(count() > 0 && overflow() == 0, 'interposition inactive/overflow');
    final rows = <Map<String, int>>[];
    var matchingBytes = 0;
    var wireAccepted = 0;
    var interrupted = 0;
    for (var i = 0; i < count(); i++) {
      final n = accepted(i);
      final inBody =
          address(i) >= pointer.address + start &&
          address(i) < pointer.address + start + length;
      if (n > 0) {
        wireAccepted += n;
        if (inBody) matchingBytes += n;
      }
      if (n < 0 && error(i) == 4) interrupted++;
      rows.add({
        'requested': requested(i),
        'accepted': n,
        'errno': error(i),
        'inOriginalBody': inBody ? 1 : 0,
      });
    }
    check(wireAccepted == wire.length, 'wire write accounting differs');
    final keepsBody = fragments?.any((p) => identical(p, body)) ?? false;
    if (codec == 'flatbuffers') {
      check(keepsBody, 'FlatBuffers did not preserve the encoded body');
    }
    final segmented = keepsBody && length == 65536;
    final bodyShouldBeReused = segmented && !partial;
    check(
      ownCopies.rawSocketFramePayloadCopiedBytes ==
              (segmented ? 0 : payload.length) &&
          ownCopies.rawSocketFragmentCoalesceCopiedBytes == 0 &&
          ownCopies.rawSocketPreHandshakeQueueCopiedBytes == 0 &&
          ownCopies.webSocketFragmentCoalesceCopiedBytes == 0,
      'transport copy accounting differs',
    );
    check(
      matchingBytes == (bodyShouldBeReused ? length : 0),
      'body pointer expectation differs',
    );
    if (syscallRetries) check(interrupted == 1, 'EINTR control missing');
    print(
      jsonEncode({
        'codec': codec,
        'bodyBytes': length,
        'shape': shape,
        'forcedSyscallRetries': syscallRetries,
        'wireBytes': wire.length,
        'serializerHasFragments': fragments != null,
        'fragmentCount': fragments?.length,
        'fragmentBackings': fragments
            ?.map(
              (b) => {
                'length': b.length,
                'backing': b.buffer.lengthInBytes,
                'offset': b.offsetInBytes,
              },
            )
            .toList(),
        'originalBodyBytesAtWrite': matchingBytes,
        'connectanumCopies': ownCopies.toJson(),
        'wireEqual': true,
        'bodyEqual': true,
        'observations': rows,
      }),
    );
  } finally {
    if (recording) DartTransportCopyMetrics.endWindow();
    reset(0, 0, 0);
    await incoming?.cancel();
    await transport.close();
    for (final peer in peers) {
      peer.destroy();
    }
    await serverSubscription.cancel();
    await server.close();
    calloc.free(pointer);
  }
}

Future<void> main() async {
  print(
    jsonEncode({
      'sdk': Platform.version,
      'scope': 'actual RawSocket PPT calls; not total SDK/TLS copies or parity',
      'forcedRetryBoundary':
          'native SocketBase::Write loop; no forced Dart EAGAIN resumption',
    }),
  );
  for (final length in [23, 65536]) {
    for (final codec in ['cbor', 'msgpack', 'flatbuffers']) {
      for (final shape in [
        'full',
        'full-readonly',
        'partial',
        'partial-readonly',
      ]) {
        await run(codec, length, shape, false);
        if (length == 65536) await run(codec, length, shape, true);
      }
    }
  }
}

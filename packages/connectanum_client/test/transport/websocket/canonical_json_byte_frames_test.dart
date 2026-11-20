@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectanum_client/src/transport/websocket/canonical_json_byte_frames_io.dart';
import 'package:connectanum_client/src/transport/websocket/byte_frame_http_client_io.dart';
import 'package:connectanum_client/src/transport/websocket/native_websocket_frames_io.dart';
import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'byte_frame_http_client_test_support.dart';

String canonical([int length = 65536]) =>
    r'[50,7,{},["\u0000' + 'A' * length + r'"]]';
Uint8List frame(List<int> payload, {int opcode = 1, bool fin = true}) {
  final header = <int>[(fin ? 128 : 0) | opcode];
  if (payload.length < 126) {
    header.add(payload.length);
  } else if (payload.length <= 65535) {
    header.addAll([126, payload.length >> 8, payload.length & 255]);
  } else {
    header.add(127);
    for (var i = 7; i >= 0; i--) {
      header.add((payload.length >> (i * 8)) & 255);
    }
  }
  return Uint8List.fromList([...header, ...payload]);
}

Future<Uint8List> adapt(Iterable<Uint8List> chunks) async {
  final out = BytesBuilder(copy: false);
  await for (final bytes in canonicalJsonByteFrames(
    Stream.fromIterable(chunks),
  )) {
    out.add(bytes);
  }
  return out.takeBytes();
}

Future<int> abortedTextCloseCode(bool adapted) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  Socket? peer;
  final received = Completer<int>();
  s.listen((r) async {
    r.response.statusCode = 101;
    r.response.headers.set('Connection', 'Upgrade');
    r.response.headers.set('Upgrade', 'websocket');
    r.response.headers.set(
      'Sec-WebSocket-Accept',
      base64.encode(
        sha1
            .convert(
              ascii.encode(
                '${r.headers.value('Sec-WebSocket-Key')}258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
              ),
            )
            .bytes,
      ),
    );
    peer = await r.response.detachSocket();
    final b = BytesBuilder(copy: false);
    peer!.listen((p) {
      b.add(p);
      final x = b.toBytes();
      if (x.length >= 8 && !received.isCompleted && (x[0] & 15) == 8) {
        received.complete(((x[6] ^ x[2]) << 8) | (x[7] ^ x[3]));
      }
    });
    peer!.add(frame(ascii.encode('[50,7,{},'), fin: false));
    peer!.add(frame([...List.filled(65536, 65), 255], opcode: 0, fin: false));
    peer!.add(frame([3, 232], opcode: 8));
    await peer!.flush();
  });
  final http = HttpClient();
  try {
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${s.port}',
      customClient: adapted ? canonicalJsonByteFrameClient(http) : http,
      compression: CompressionOptions.compressionOff,
    );
    ws.listen((_) {});
    final code = await received.future.timeout(Duration(seconds: 5));
    await ws.close().timeout(Duration(seconds: 5));
    return code;
  } finally {
    peer?.destroy();
    http.close(force: true);
    await s.close(force: true);
  }
}

void main() {
  registerByteFrameHttpClientContractTests();
  test(
    'native canonical messages reach the SDK as one complete binary event',
    () async {
      final payload = Uint8List.fromList(ascii.encode(canonical()));
      final wire = Uint8List.fromList([
        ...frame(payload.sublist(0, 13), fin: false),
        ...frame(payload.sublist(13), opcode: 0),
      ]);
      final kinds = <bool>[];
      final result = await canonicalJsonByteFrames(
        coalesceNativeWebSocketFrames(Stream.value(wire)),
        onMessage: kinds.add,
      ).toList();
      expect(result, hasLength(1));
      final info = nativeWebSocketFrame(result.single)!;
      expect(result.single[0], 0x82);
      expect(result.single.sublist(info.headerLength), payload);
      expect(kinds, [true]);
    },
  );

  test(
    'native roots retain non-ASCII text and original binary provenance',
    () async {
      final asciiPayload = ascii.encode(canonical());
      for (final (opcode, payload) in [
        (1, [...asciiPayload, 0xff]),
        (1, utf8.encode('${canonical()}é')),
        (2, asciiPayload),
      ]) {
        final kinds = <bool>[];
        final result = await canonicalJsonByteFrames(
          coalesceNativeWebSocketFrames(
            Stream.value(
              Uint8List.fromList([
                ...frame(payload.sublist(0, 13), opcode: opcode, fin: false),
                ...frame(payload.sublist(13), opcode: 0),
              ]),
            ),
          ),
          onMessage: kinds.add,
        ).toList();
        expect(result, hasLength(1));
        expect(result.single[0] & 15, opcode);
        expect(kinds, [opcode == 1]);
      }
    },
  );

  test(
    'binary SDK streams use native frames without accumulating JSON kinds',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      final payload = Uint8List.fromList(List.generate(65537, (i) => i % 251));
      Socket? peer;
      server.listen((request) async {
        request.response.statusCode = HttpStatus.switchingProtocols;
        request.response.headers.set('Connection', 'Upgrade');
        request.response.headers.set('Upgrade', 'websocket');
        request.response.headers.set(
          'Sec-WebSocket-Accept',
          base64.encode(
            sha1
                .convert(
                  ascii.encode(
                    '${request.headers.value('Sec-WebSocket-Key')}258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
                  ),
                )
                .bytes,
          ),
        );
        peer = await request.response.detachSocket();
        peer!.listen((_) {});
        // Explicit wire fragmentation exercises coalescing regardless of how
        // the operating system groups the socket's input events.
        peer!.add(frame(payload.sublist(0, 13), opcode: 2, fin: false));
        peer!.add(frame(payload.sublist(13), opcode: 0));
        peer!.add(frame([], opcode: 2));
        peer!.add(frame([3, 232], opcode: 8));
        await peer!.flush();
      });
      try {
        final frames = <Uint8List>[];
        final kinds = CanonicalJsonFrameKinds(
          adaptJson: false,
          onNativeFrame: frames.add,
        );
        final client = await WebSocket.connect(
          'ws://127.0.0.1:${server.port}',
          customClient: canonicalJsonByteFrameClient(http, kinds: kinds),
          compression: CompressionOptions.compressionOff,
        );
        final messages = await client.toList().timeout(
          const Duration(seconds: 5),
        );
        expect(messages, hasLength(2));
        expect(messages.first, payload);
        expect(messages.last, isEmpty);
        expect(kinds.active, isTrue);
        expect(kinds.take(), isNull);
        final received = messages.first as Uint8List;
        expect(
          frames,
          hasLength(1),
          reason: 'SDK must retain the native backing allocation',
        );
        final native = frames.single;
        final info = nativeWebSocketFrame(native)!;
        retainNativeExternalBytes(received, native);
        final rootSlice = nativeExternalByteSlice(native)!;
        final payloadSlice = nativeExternalByteSlice(received)!;
        expect(
          payloadSlice.pointer.address - rootSlice.pointer.address,
          info.headerLength,
        );
        expect(payloadSlice.length, payload.length);
        received[0] = 0x91;
        expect(
          native[info.headerLength],
          0x91,
          reason: 'SDK payload must be a view, not a copy',
        );
      } finally {
        peer?.destroy();
        http.close(force: true);
        await server.close(force: true);
      }
    },
  );

  test(
    'aborted invalid text keeps the SDK close result until message completion',
    () async {
      final baseline = await abortedTextCloseCode(false);
      expect(await abortedTextCloseCode(true), baseline);
    },
  );

  test(
    'each complete empty message has one provenance entry and orphan continuation has none',
    () async {
      final wire = Uint8List.fromList([
        ...frame(ascii.encode(canonical())),
        ...frame([]),
        ...frame([], opcode: 2),
        ...frame([], opcode: 0),
      ]);
      final kinds = <bool>[], out = BytesBuilder(copy: false);
      await for (final bytes in canonicalJsonByteFrames(
        Stream.value(wire),
        onMessage: kinds.add,
      )) {
        out.add(bytes);
      }
      final expected = Uint8List.fromList(wire)..[0] = 130;
      expect(out.takeBytes(), expected);
      expect(kinds, [true, true, false]);
    },
  );

  test(
    'staged metadata forwards ping before waiting for large continuation and validates split Unicode',
    () async {
      final source = StreamController<Uint8List>();
      final kinds = <bool>[];
      final output = StreamIterator(
        canonicalJsonByteFrames(source.stream, onMessage: kinds.add),
      );
      final metadata = frame(ascii.encode('[50,7,{},'), fin: false);
      final ping = frame([1, 2, 3], opcode: 9);
      source.add(metadata);
      source.add(ping);
      expect(await output.moveNext().timeout(Duration(seconds: 1)), isTrue);
      expect(output.current, ping.sublist(0, 2));
      expect(await output.moveNext().timeout(Duration(seconds: 1)), isTrue);
      expect(output.current, [1, 2, 3]);
      final emoji = utf8.encode('💡');
      final first = frame(
        [...ascii.encode('A' * 65536), ...emoji.sublist(0, 2)],
        opcode: 0,
        fin: false,
      );
      final last = frame(emoji.sublist(2), opcode: 0, fin: false);
      source.add(first);
      source.add(last);
      source.add(frame([], opcode: 0));
      final closing = source.close();
      final out = BytesBuilder(copy: false);
      while (await output.moveNext()) {
        out.add(output.current);
      }
      await closing;
      final expected = Uint8List.fromList([
        ...metadata,
        ...first,
        ...last,
        ...frame([], opcode: 0),
      ])..[0] = 2;
      expect(out.takeBytes(), expected);
      expect(kinds, [true]);
    },
  );
  test(
    'original fragmented binary is never UTF-8 checked and retains binary provenance',
    () async {
      final wire = Uint8List.fromList([
        ...frame([255, 254], opcode: 2, fin: false),
        ...frame([0xc2], opcode: 0, fin: false),
        ...frame([], opcode: 0),
      ]);
      final kinds = <bool>[], out = BytesBuilder(copy: false);
      await for (final b in canonicalJsonByteFrames(
        Stream.value(wire),
        onMessage: kinds.add,
      )) {
        out.add(b);
      }
      expect(out.takeBytes(), wire);
      expect(kinds, [false]);
    },
  );

  test(
    'native metadata continuation sequence streams the original text body',
    () async {
      final parts = [
        frame(ascii.encode('[68,12,15,'), fin: false),
        frame(ascii.encode('{} ,'), opcode: 0, fin: false),
        frame(
          ascii.encode(r'["\u0000' + 'A' * 65536 + r'"]'),
          opcode: 0,
          fin: false,
        ),
        frame(ascii.encode(']'), opcode: 0),
        frame([1, 2], opcode: 2),
        frame(ascii.encode('small')),
      ];
      final kinds = <bool>[];
      final all = Uint8List.fromList(parts.expand((p) => p).toList());
      final out = BytesBuilder(copy: false);
      await for (final part in canonicalJsonByteFrames(
        Stream.fromIterable([
          Uint8List.sublistView(all, 0, 13),
          Uint8List.sublistView(all, 13, 4097),
          Uint8List.sublistView(all, 4097),
        ]),
        onMessage: kinds.add,
      )) {
        out.add(part);
      }
      final expected = Uint8List.fromList(all)..[0] = 2;
      expect(out.takeBytes(), expected);
      expect(kinds, [true, false, true]);
    },
  );
  for (final adapted in [false, true]) {
    for (final emptyFinal in [false, true]) {
      test(
        'SDK strict UTF-8 close1007 adapted=$adapted emptyFinal=$emptyFinal',
        () async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          Socket? peer;
          final clientClosed = Completer<int>();
          server.listen((request) async {
            request.response.statusCode = HttpStatus.switchingProtocols;
            request.response.headers.set('Connection', 'Upgrade');
            request.response.headers.set('Upgrade', 'websocket');
            request.response.headers.set(
              'Sec-WebSocket-Accept',
              base64.encode(
                sha1
                    .convert(
                      ascii.encode(
                        '${request.headers.value('Sec-WebSocket-Key')!}258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
                      ),
                    )
                    .bytes,
              ),
            );
            peer = await request.response.detachSocket();
            final received = BytesBuilder(copy: false);
            peer!.listen((part) {
              received.add(part);
              final b = received.toBytes();
              if (b.length >= 8 && !clientClosed.isCompleted) {
                final n = b[1] & 127;
                if ((b[0] & 15) == 8 && n >= 2 && b.length >= 6 + n) {
                  final code = ((b[6] ^ b[2]) << 8) | (b[7] ^ b[3]);
                  clientClosed.complete(code);
                  peer!.add(frame([code >> 8, code & 255], opcode: 8));
                }
              }
            });
            final payload = Uint8List.fromList(ascii.encode(canonical()));
            payload[payload.length - 1] = emptyFinal ? 0xc2 : 0xff;
            if (emptyFinal) {
              peer!.add(frame(payload, fin: false));
              peer!.add(frame([], opcode: 0));
            } else {
              peer!.add(frame(payload));
            }
            await peer!.flush();
          });
          final http = HttpClient();
          WebSocket? ws;
          try {
            ws = await WebSocket.connect(
              'ws://127.0.0.1:${server.port}',
              customClient: adapted ? canonicalJsonByteFrameClient(http) : http,
              compression: CompressionOptions.compressionOff,
            );
            final messages = <dynamic>[], errors = <Object>[];
            final done = Completer<void>();
            ws.listen(
              messages.add,
              onError: (Object e) => errors.add(e),
              onDone: done.complete,
            );
            expect(
              await clientClosed.future.timeout(Duration(seconds: 5)),
              1007,
            );
            await done.future.timeout(Duration(seconds: 5));
            expect(messages, isEmpty);
            expect(errors, isEmpty);
            expect(ws.closeCode, 1007);
          } finally {
            peer?.destroy();
            http.close(force: true);
            await server.close(force: true);
          }
        },
      );
    }
  }

  for (final tail in [0, 1, 2, 3, 7]) {
    test(
      'canonical frame preserves bytes across header/word splits, tail=$tail',
      () async {
        final wire = frame(ascii.encode(canonical(65536 + tail)));
        final expected = Uint8List.fromList(wire)..[0] = 130;
        for (final cut in [
          0,
          1,
          2,
          3,
          4,
          5,
          8,
          9,
          10,
          11,
          31,
          4095,
          4096,
          4097,
          wire.length - 1,
          wire.length,
        ]) {
          expect(
            await adapt([
              Uint8List.sublistView(wire, 0, cut),
              Uint8List(0),
              Uint8List.sublistView(wire, cut),
            ]),
            expected,
            reason: 'cut=$cut',
          );
        }
      },
    );
  }
  test(
    'fragmentation and controls preserve payload with only the text opcode adapted',
    () async {
      final wire = Uint8List.fromList([
        ...frame(ascii.encode(canonical()), fin: false),
        ...frame([1, 2, 3], opcode: 9),
        ...frame(ascii.encode('continuation'), opcode: 0),
        ...frame([], opcode: 10),
        ...frame([], opcode: 8),
      ]);
      final expected = Uint8List.fromList(wire)..[0] = 2;
      expect(await adapt([wire]), expected);
    },
  );
  test(
    'noncanonical and over-limit ASCII text use the unchanged SDK path',
    () async {
      for (final text in ['"${'A' * 65536}"', canonical(8 * 1024 * 1024)]) {
        final wire = frame(ascii.encode(text));
        expect(await adapt([wire]), wire);
      }
    },
  );
  test(
    'strict UTF-8 validation covers every boundary around the staged prefix',
    () async {
      final payload = Uint8List.fromList(ascii.encode(canonical()));
      for (final index in [
        0,
        1,
        4094,
        4095,
        4096,
        4097,
        payload.length - 7,
        payload.length - 1,
      ]) {
        final modified = Uint8List.fromList(payload)..[index] = 255;
        final wire = frame(modified);
        final operation = adapt([
          Uint8List.sublistView(wire, 0, 8191),
          Uint8List.sublistView(wire, 8191),
        ]);
        if (index >= 4096) {
          await expectLater(operation, throwsFormatException);
        } else {
          expect(await operation, wire, reason: 'index=$index');
        }
      }
    },
  );
  test(
    'private payload storage is independent of reused source chunks',
    () async {
      final wire = frame(ascii.encode(canonical()));
      Stream<Uint8List> source() async* {
        final first = Uint8List.fromList(wire.sublist(0, 4095));
        yield first;
        first.fillRange(0, first.length, 255);
        yield Uint8List.sublistView(wire, 4095);
      }

      final out = BytesBuilder(copy: false);
      await for (final bytes in canonicalJsonByteFrames(source())) {
        out.add(bytes);
      }
      final expected = Uint8List.fromList(wire)..[0] = 130;
      expect(out.takeBytes(), expected);
    },
  );
  test(
    'truncated candidates flush their original header and complete prefix',
    () async {
      final wire = frame(ascii.encode(canonical()));
      for (final end in [
        1,
        2,
        3,
        9,
        10,
        100,
        4095,
        4096,
        8191,
        wire.length - 1,
      ]) {
        final partial = Uint8List.sublistView(wire, 0, end);
        final actual = await adapt([partial]);
        expect(actual.sublist(1), partial.sublist(1), reason: 'end=$end');
        expect(actual[0] & 240, partial[0] & 240);
      }
    },
  );
  test(
    'input errors retain their identity after flushing buffered bytes',
    () async {
      final wire = frame(ascii.encode(canonical()));
      final error = const SocketException('test stream interrupted');
      for (final end in [1, 2, 5, 100, 8191]) {
        Stream<Uint8List> source() async* {
          yield Uint8List.sublistView(wire, 0, end);
          throw error;
        }

        final out = BytesBuilder(copy: false), errors = <Object>[];
        final done = Completer<void>();
        canonicalJsonByteFrames(source()).listen(
          out.add,
          onError: (Object e) => errors.add(e),
          onDone: done.complete,
        );
        await done.future;
        final actual = out.takeBytes();
        expect(actual.sublist(1), Uint8List.sublistView(wire, 1, end));
        expect(actual[0] & 240, wire[0] & 240);
        expect(errors, [same(error)]);
      }
    },
  );
  for (final header in [
    [0xc1],
    [0x83],
    [0x09],
    [0x80],
    [0x81, 0x80],
    [0x89, 126],
    [0x81, 126, 0, 125],
    [0x81, 127, 128, 0, 0, 0, 0, 0, 0, 0],
  ]) {
    test(
      'invalid prefix reaches the SDK before another input byte: $header',
      () async {
        final source = StreamController<Uint8List>();
        final first = canonicalJsonByteFrames(source.stream).first;
        source.add(Uint8List.fromList(header));
        expect(await first.timeout(const Duration(seconds: 1)), header);
        await source.close();
      },
    );
  }
  for (final compression in [
    CompressionOptions.compressionOff,
    CompressionOptions.compressionDefault,
  ]) {
    test(
      'real SDK handshake/subprotocol and compression stay intact: ${compression.enabled}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <WebSocket>[];
        final text = canonical();
        server.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(
            request,
            compression: compression,
            protocolSelector: (protocols) => 'wamp.2.json',
          );
          peers.add(socket);
          socket.listen((_) {});
          socket.add(text);
        });
        final http = HttpClient();
        WebSocket? socket;
        try {
          socket = await WebSocket.connect(
            'ws://127.0.0.1:${server.port}/mcp',
            protocols: ['wamp.2.json'],
            customClient: canonicalJsonByteFrameClient(http),
          );
          expect(socket.protocol, 'wamp.2.json');
          final message = await socket.first;
          if (compression.enabled) {
            expect(message, isA<String>());
            expect(message, text);
          } else {
            expect(message, isA<Uint8List>());
            expect(message, ascii.encode(text));
          }
        } finally {
          await socket?.close();
          for (final peer in peers) {
            await peer.close();
          }
          http.close(force: true);
          await server.close(force: true);
        }
      },
    );
  }
}

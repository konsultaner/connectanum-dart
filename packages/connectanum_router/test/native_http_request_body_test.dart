import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_listener.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

void main() {
  group('NativeHttpRequestBody', () {
    test('view exposes zero-copy buffer and copy clones data', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final body = NativeHttpRequestBody.synthetic(bytes);

      expect(
        identical(body.view, body.view),
        isTrue,
        reason: 'view reuses same list',
      );
      expect(body.view, equals(bytes));

      final copied = body.copy();
      expect(copied, equals(bytes));
      expect(
        identical(copied, body.view),
        isFalse,
        reason: 'copy should allocate new buffer',
      );
    });

    test('length reflects underlying payload size', () {
      final bytes = Uint8List.fromList([4, 5, 6, 7]);
      final body = NativeHttpRequestBody.synthetic(bytes);
      expect(body.length, bytes.length);
    });

    test('openRead streams the shared view without extra copies', () async {
      final bytes = Uint8List.fromList([7, 8, 9]);
      final body = NativeHttpRequestBody.synthetic(bytes);

      final chunks = await body.openRead().toList();
      expect(chunks, hasLength(1));
      final chunk = chunks.single;
      expect(chunk, equals(bytes));
      expect(
        identical(chunk, body.view),
        isTrue,
        reason: 'stream chunk should be the shared view',
      );
    });
  });

  test('RouterHttpRequest reuses native body handle until snapshot copy', () {
    final listener = RouterListener(
      listenerId: 1,
      endpoint: Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.native,
        maxRawSocketSizeExponent: 16,
      ),
      port: 0,
      http3Port: 0,
    );
    final nativeBody = NativeHttpRequestBody.synthetic(
      Uint8List.fromList([11, 12]),
    );
    final request = RouterHttpRequest(
      listener: listener,
      connectionId: 42,
      method: 'POST',
      target: '/metrics',
      path: '/metrics',
      protocol: 'http/3',
      version: 3,
      headers: const {'content-type': 'application/json'},
      body: nativeBody,
      handshakeHandle: 99,
      query: 'foo=bar',
      realm: 'realm.metrics',
      procedure: 'connectanum.metrics.openmetrics',
    );

    expect(identical(request.nativeBody, nativeBody), isTrue);
    expect(identical(request.body, nativeBody.view), isTrue);

    final snapshot = request.toSnapshot(7);
    final snapshotBody = snapshot.body;
    expect(snapshotBody, isNotNull);
    expect(snapshotBody, equals(request.body));
    expect(
      identical(snapshotBody, request.body),
      isFalse,
      reason: 'snapshot must own its bytes',
    );
  });

  test('NativeHttpHandshake.synthetic keeps provided body handle', () {
    final bodyHandle = NativeHttpRequestBody.synthetic(Uint8List.fromList([5]));
    final handshake = NativeHttpHandshake.synthetic(
      method: 'GET',
      target: '/',
      path: '/',
      bodyHandle: bodyHandle,
    );
    expect(identical(handshake.body, bodyHandle), isTrue);
  });
}

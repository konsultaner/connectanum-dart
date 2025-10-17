@TestOn('vm')
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_dart/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  final libraryPath = _resolveLibraryPath();
  final skipReason = !Platform.isLinux
      ? 'Native runtime test only runs on Linux'
      : libraryPath == null
      ? 'Native ct_ffi library not found'
      : null;

  group('NativeTransportRuntime', () {
    test('start, listen, poll and shutdown', () async {
      final runtime = NativeTransportRuntime(libraryPath: libraryPath!);
      addTearDown(runtime.dispose);

      final listenerEvents = <(int, int)>[];
      final connectionEvents = <(int, int)>[];
      runtime.setListenerCallbacks(
        onStarted: (id, status) => listenerEvents.add((id, status)),
        onConnection: (id, conn) => connectionEvents.add((id, conn)),
      );

      runtime.start();
      addTearDown(runtime.shutdown);

      const configJson =
          '{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","max_rawsocket_size_exponent":30}]}';
      runtime.applyRouterConfig(Uint8List.fromList(utf8.encode(configJson)));

      final listenerId = runtime.listen('127.0.0.1', 0);
      expect(listenerId, greaterThan(0));
      expect(
        listenerEvents,
        contains((listenerId, NativeTransportErrorCode.success)),
      );

      final port = runtime.getLocalPort(listenerId);
      expect(port, greaterThan(0));

      final socket = await Socket.connect('127.0.0.1', port);
      await socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final polledId = runtime.pollConnection(listenerId);
      expect(polledId, greaterThan(0));
      expect(runtime.connectionMaxRawSocketExponent(polledId), 30);
      expect(connectionEvents, contains((listenerId, polledId)));

      expect(
        () => runtime.pollConnection(9999),
        throwsA(isA<NativeTransportException>()),
      );
      expect(
        () => runtime.connectionMaxRawSocketExponent(9999),
        throwsA(isA<NativeTransportException>()),
      );
    }, skip: skipReason);
  });
}

String? _resolveLibraryPath() {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && File(env).existsSync()) {
    return env;
  }
  const candidates = [
    '../../native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/release/libct_ffi.so',
    'native/transport/target/debug/libct_ffi.so',
    'native/transport/target/release/libct_ffi.so',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

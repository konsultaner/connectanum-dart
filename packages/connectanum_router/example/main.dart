// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:connectanum_router/connectanum_router.dart';

Future<void> main(List<String> args) async {
  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(
      libraryPath: args.isNotEmpty ? args.first : null,
    );
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Failed to load the native transport runtime: ${error.message}\n'
      'Build the ct_ffi library (see native/transport README) and either place it in '
      'native/transport/target/{debug,release}/libct_ffi.so or pass its path as the first argument.',
    );
    return;
  }

  runtime.setListenerCallbacks(
    onStarted: (listenerId, status) {
      if (status == NativeTransportErrorCode.success) {
        print('Listener $listenerId started');
      } else {
        print('Listener $listenerId failed with status $status');
      }
    },
    onConnection: (listenerId, connectionId) {
      print('Listener $listenerId accepted connection $connectionId');
    },
  );

  runtime.start();
  print('Native runtime started');

  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
  );

  final binding = router.start(runtime);
  final listeners = binding.listeners;
  for (final listener in listeners) {
    print(
      'Listener ${listener.listenerId} bound to ${listener.endpoint.host}:${listener.port}',
    );
  }

  final subscription = binding
      .watchNativeMessages(
        pollInterval: const Duration(milliseconds: 5),
        maxMessagesPerTick: 128,
      )
      .listen((routerMessage) {
        print(
          'Received message on connection ${routerMessage.connectionId} '
          '(${routerMessage.listener.endpoint.host}:${routerMessage.listener.port}) '
          'with serializer ${routerMessage.message.serializer}',
        );
        routerMessage.message.dispose();
      });

  print('Router running. Press Ctrl+C to stop.');

  final sigint = ProcessSignal.sigint.watch().first;
  final sigterm = ProcessSignal.sigterm.watch().first;
  await Future.any([sigint, sigterm]);

  await subscription.cancel();
  await binding.dispose();
  runtime.shutdown();
  runtime.dispose();
  print('Router stopped.');
}

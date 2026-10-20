@TestOn('vm')
library;

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart'
    show NativeIncomingMessage;
import 'package:connectanum_objectbox_adapter/connectanum_objectbox_adapter.dart';
import 'package:connectanum_router/src/native/runtime.dart'
    hide NativeIncomingMessage;
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:objectbox/objectbox.dart';
import 'package:test/test.dart';

import 'support/model.dart';

void main() {
  final library = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  const deadline = Duration(seconds: 10);
  for (final codec in ['flatbuffers', 'cbor', 'msgpack']) {
    test(
      'real native $codec receive writes ObjectBox without a Dart entity',
      () async {
        if (library == null || !File(library).existsSync()) {
          fail(
            'CONNECTANUM_NATIVE_LIB must point to a real Connectanum library',
          );
        }
        final directory = Directory.systemTemp.createTempSync(
          'objectbox-native-ingestion-',
        );
        final store = Store(fixtureModel(), directory: directory.path);
        final adapter = ObjectBoxFlatBufferAdapter<Sample>(store);
        entityReads = entityWrites = 0;
        final settings =
            (RouterSettingsBuilder()
                  ..addRealmFromBuilder(
                    RealmSettingsBuilder('realm1')
                      ..addAuthMethod('anonymous')
                      ..addRoleFromBuilder(
                        RoleSettingsBuilder('anonymous')
                          ..addPermissionFromBuilder(
                            PermissionSettingsBuilder('')
                              ..setMatchPolicy(PermissionMatchPolicy.prefix)
                              ..allowOperations(['publish', 'subscribe']),
                          ),
                      ),
                  )
                  ..addListenerFromBuilder(
                    ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
                      ..addAuthMethod('anonymous')
                      ..setOptions({'max_rawsocket_size_exponent': 20}),
                  ))
                .build();
        final runtime = NativeTransportRuntime(libraryPath: library)..start();
        final errors = <Object>[];
        final binding =
            Router(
              RouterConfig(
                endpoints: [
                  Endpoint(
                    host: '127.0.0.1',
                    port: 0,
                    tlsMode: TlsMode.disabled,
                    maxRawSocketSizeExponent: 20,
                  ),
                ],
              ),
              settings: settings,
            ).start(
              runtime,
              onEvent: (event) {
                if (event is Map && event['type'] == 'worker_error') {
                  errors.add(event);
                }
              },
            );
        final clients = <client.Client>[];
        try {
          Future<client.Session> connect() async {
            final port = binding.listeners.single.port;
            final transport = switch (codec) {
              'flatbuffers' =>
                client.NativeRawSocketTransport.withFlatBuffersSerializer(
                  '127.0.0.1',
                  port,
                  libraryPath: library,
                  messageLengthExponent: 20,
                ),
              'cbor' => client.NativeRawSocketTransport.withCborSerializer(
                '127.0.0.1',
                port,
                libraryPath: library,
                messageLengthExponent: 20,
              ),
              _ => client.NativeRawSocketTransport.withMsgpackSerializer(
                '127.0.0.1',
                port,
                libraryPath: library,
                messageLengthExponent: 20,
              ),
            };
            final instance = client.Client(
              transport: transport,
              realm: 'realm1',
            );
            clients.add(instance);
            return instance
                .connect(
                  options: client.ClientConnectOptions(reconnectCount: 0),
                )
                .first
                .timeout(deadline);
          }

          final receiver = await connect();
          final sender = await connect();
          final bytes = encodeSample(Sample(id: 77));
          final encodingCalls = entityWrites;
          final payload = core.LazyMessagePayload.packed(
            encoding: core.LazyPayloadEncoding.flatbuffers,
            packedPayloadBytes: bytes,
            packedPayloadDecoder: (_) =>
                throw StateError('Entity bytes must remain opaque'),
            anchor: bytes,
          );
          const topic = 'com.objectbox.entity';
          final received = Completer<core.LazyEventPayload>();
          await receiver
              .subscribeLazyPayloadHandler(topic, received.complete)
              .timeout(deadline);
          await sender
              .publishLazyPayload(
                topic,
                payload: payload,
                options: adapter.publishOptions(),
              )
              .timeout(deadline);
          final event = await received.future.timeout(deadline);
          final result = adapter.putEvent(event);
          expect(result.id, 77);
          expect(result.copyReasons, isEmpty);
          expect(result.borrowed, isTrue);
          expect(result.copiedBytes, 0);
          expect(entityWrites, encodingCalls);
          expect(entityReads, 0);

          // Retaining a real receive owner cannot substitute its old contents
          // for a modified application list. The changed ID must be persisted.
          final changed = Uint8List.fromList(event.packedPayloadBytes!);
          ByteData.sublistView(changed).setUint64(
            fieldPosition(changed, 0),
            78,
            Endian.little,
          );
          final modified = adapter.putBytes(
            changed,
            schemaFingerprint: adapter.schema.fingerprint,
            storageOwner: event.payload.storageOwner,
          );
          expect(modified.id, 78);
          expect(modified.copiedBytes, changed.length);
          expect(modified.copyReasons, [
            ObjectBoxCopyReason.unavailableNativeLease,
          ]);
          expect(adapter.getBytes(78), changed);

          // Exported byte views retain their native backing store, but the
          // routing handle may have been released. Never peek a stale pointer.
          Object? anchor = event.payload.storageOwner;
          for (
            var depth = 0;
            depth < 8 && anchor is! NativeIncomingMessage;
            depth++
          ) {
            anchor = sessionMessageAnchorFor(anchor!);
          }
          expect(anchor, isA<NativeIncomingMessage>());
          (anchor as NativeIncomingMessage).release();
          final afterRelease = adapter.putEvent(event);
          expect(afterRelease.id, 77);
          expect(afterRelease.copyReasons, [
            ObjectBoxCopyReason.unavailableNativeLease,
          ]);
          expect(afterRelease.copiedBytes, bytes.length);
          expect(adapter.getBytes(77), bytes);
          expect(store.box<Sample>().get(77)!.text, Sample().text);
          expect(errors, isEmpty);
        } finally {
          try {
            for (final instance in clients.reversed) {
              await instance.disconnect().timeout(deadline);
            }
          } finally {
            await binding.dispose();
            runtime.shutdown();
            runtime.dispose();
            adapter.close();
            store.close();
            directory.deleteSync(recursive: true);
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

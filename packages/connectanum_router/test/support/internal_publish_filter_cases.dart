part of '../router_runtime_test.dart';

void _internalPublishFilterCases() {
  for (final size in [16383, 16384, 65536, 65537]) {
    test(
      'internal external publication snapshots $size bytes before returning',
      () async {
        NativeMqttFrameBufferAllocator.forLibrary(
          ffi.DynamicLibrary.open(NativeLibraryLoader.resolvePath(null)),
        );
        final realm = RealmSettingsBuilder('realm1')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('internal')..addPermissionFromBuilder(
              PermissionSettingsBuilder('app.binary')
                ..allowOperations(const ['subscribe', 'publish']),
            ),
          );
        final binding = Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                maxRawSocketSizeExponent: 16,
                tlsMode: TlsMode.native,
                sniCertificates: [_cert('localhost')],
              ),
            ],
          ),
          settings: (RouterSettingsBuilder()..addRealmFromBuilder(realm))
              .build(),
        ).start(_HandleRuntime());
        addTearDown(binding.dispose);
        final publisher = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'binary-origin',
          authRole: 'internal',
        );
        addTearDown(publisher.close);
        final received = <Future<Event>>[];
        for (var index = 0; index < 2; index++) {
          final receiver = await binding.createInternalSession(
            realmUri: 'realm1',
            authId: 'binary-$index',
            authRole: 'internal',
          );
          addTearDown(receiver.close);
          final event = Completer<Event>();
          (await receiver.subscribe('app.binary')).onEvent(event.complete);
          received.add(event.future);
        }
        final externalKind = ffi.DynamicLibrary.process()
            .lookupFunction<ffi.Int Function(ffi.Handle), int Function(Object)>(
              'Dart_GetTypeOfExternalTypedData',
            );
        final backing = ffi.DynamicLibrary.process()
            .lookupFunction<
              ffi.Handle Function(ffi.Handle),
              Object Function(Object)
            >('Dart_GetDataFromByteBuffer');
        final managedKind = externalKind(backing(Uint8List(0).buffer));
        final storage = calloc<ffi.Uint8>(size + 12).asTypedList(
          size + 12,
          finalizer: calloc.nativeFree,
        );
        final nativeKind = externalKind(backing(storage.buffer));
        expect(nativeKind, isNot(managedKind));
        final expected = List.generate(size, (i) => i % 251);
        final body = Uint8List.sublistView(storage, 7, 7 + size)
          ..setAll(0, expected);
        final pending = publisher.publish(
          'app.binary',
          arguments: [body],
          options: PublishOptions(acknowledge: true),
        );
        body.fillRange(0, body.length, 0);
        final publication = await pending;
        final events = await Future.wait(
          received,
        ).timeout(const Duration(seconds: 5));
        for (final event in events) {
          expect(event.publicationId, publication!.publicationId);
          expect(event.arguments!.single, expected);
          final receivedBody = event.arguments!.single as Uint8List;
          expect(
            externalKind(backing(receivedBody.buffer)),
            size < 16 * 1024 ? nativeKind : managedKind,
          );
          receivedBody[0] = 249;
          expect(receivedBody.first, 249);
        }
      },
    );
  }

  for (final filter in [
    'exclude-session',
    'exclude-authid',
    'exclude-role',
    'eligible-session',
    'eligible-authid',
    'eligible-role',
    'empty-eligible',
    'empty-exclude',
    'include-self',
    'exclude-self',
    'intersection',
  ]) {
    test('internal publication recipient filter $filter', () async {
      final realm = RealmSettingsBuilder('realm1');
      for (final identity in ['origin', 'alice', 'bob']) {
        realm.addRoleFromBuilder(
          RoleSettingsBuilder('role-$identity')..addPermissionFromBuilder(
            PermissionSettingsBuilder('app.filtered')
              ..allowOperations(const ['subscribe', 'publish']),
          ),
        );
      }
      final binding = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              maxRawSocketSizeExponent: 16,
              tlsMode: TlsMode.native,
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: (RouterSettingsBuilder()..addRealmFromBuilder(realm)).build(),
      ).start(_HandleRuntime());
      addTearDown(binding.dispose);
      final sessions = <RouterSession>[];
      final received = <List<Event>>[];
      final barriers = <Completer<void>>[];
      for (final identity in ['origin', 'alice', 'bob']) {
        final session = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: identity,
          authRole: 'role-$identity',
        );
        addTearDown(session.close);
        sessions.add(session);
        final events = <Event>[];
        final barrier = Completer<void>();
        received.add(events);
        barriers.add(barrier);
        final subscribed = await session.subscribe('app.filtered');
        subscribed.onEvent((event) {
          events.add(event);
          if (event.arguments?.single == 'barrier' && !barrier.isCompleted) {
            barrier.complete();
          }
        });
      }
      final options = PublishOptions(acknowledge: true, excludeMe: true);
      final List<int> expected;
      switch (filter) {
        case 'exclude-session':
          options.exclude = [sessions[1].sessionId];
          expected = [2];
        case 'exclude-authid':
          options.excludeAuthId = ['alice'];
          expected = [2];
        case 'exclude-role':
          options.excludeAuthRole = ['role-alice'];
          expected = [2];
        case 'eligible-session':
          options.eligible = [sessions[1].sessionId];
          expected = [1];
        case 'eligible-authid':
          options.eligibleAuthId = ['alice'];
          expected = [1];
        case 'eligible-role':
          options.eligibleAuthRole = ['role-alice'];
          expected = [1];
        case 'empty-eligible':
          options.eligible = [];
          expected = [];
        case 'empty-exclude':
          options.exclude = [];
          expected = [1, 2];
        case 'include-self':
          options.excludeMe = false;
          expected = [0, 1, 2];
        case 'exclude-self':
          expected = [1, 2];
        case 'intersection':
          options.eligibleAuthId = ['alice', 'bob'];
          options.excludeAuthRole = ['role-bob'];
          expected = [1];
        default:
          throw StateError('Unknown test filter $filter');
      }
      final publication = await sessions.first.publish(
        'app.filtered',
        arguments: ['filtered'],
        options: options,
      );
      final barrierPublication = await sessions.first.publish(
        'app.filtered',
        arguments: ['barrier'],
        options: PublishOptions(acknowledge: true, excludeMe: false),
      );
      expect(publication, isNotNull);
      expect(barrierPublication, isNotNull);
      expect(
        barrierPublication!.publicationId,
        isNot(publication!.publicationId),
      );
      await Future.wait(barriers.map((barrier) => barrier.future)).timeout(
        const Duration(seconds: 5),
      );
      for (var index = 0; index < sessions.length; index++) {
        expect(
          received[index].map((event) => event.arguments),
          [
            if (expected.contains(index)) ['filtered'],
            ['barrier'],
          ],
          reason: '$filter delivered to ${sessions[index].authId}',
        );
        expect(
          received[index].map((event) => event.publicationId),
          [
            if (expected.contains(index)) publication.publicationId,
            barrierPublication.publicationId,
          ],
        );
      }
    });
  }
}

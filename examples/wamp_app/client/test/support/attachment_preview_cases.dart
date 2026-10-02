part of '../widget_test.dart';

void _attachmentPreviewCases() {
  group('attachment preview', () {
    late _ControlledSaveSelector selector;
    setUp(() {
      final previous = FileSelectorPlatform.instance;
      selector = _ControlledSaveSelector();
      FileSelectorPlatform.instance = selector;
      addTearDown(() => FileSelectorPlatform.instance = previous);
    });

    testWidgets('save cancellation preserves the preview', (tester) async {
      await _mountAttachmentPreview(tester);
      late Future<void> save;
      await tester.runAsync(() async {
        save = _saveAttachmentAction(tester)();
      });
      expect(selector.names, ['received.txt']);
      await tester.runAsync(() async {
        selector.destinations.single.complete(null);
        await save;
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final stage in ['open', 'closing', 'closed']) {
      final closed = stage != 'open';
      testWidgets('destination failure is sanitized with preview $stage', (
        tester,
      ) async {
        await _mountAttachmentPreview(tester);
        late Future<void> save;
        await tester.runAsync(() async {
          save = _saveAttachmentAction(tester)();
        });
        if (closed) {
          await tester.tap(find.widgetWithText(FilledButton, 'Close'));
          if (stage == 'closing') {
            await tester.pump();
          } else {
            await tester.pumpAndSettle();
          }
        }
        await tester.runAsync(() async {
          final completed = expectLater(save, completes);
          selector.destinations.single.completeError(
            StateError('private destination failure'),
          );
          await completed;
        });
        await tester.pumpAndSettle();
        expect(
          find.text('The file could not be saved. Please try again.'),
          closed ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining('private destination failure'),
          findsNothing,
        );
        expect(
          find.byType(AlertDialog),
          closed ? findsNothing : findsOneWidget,
        );
        if (!closed) {
          await tester.tap(find.widgetWithText(FilledButton, 'Close'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }

    test(
      'save failure translations are available in every supported locale',
      () async {
        const messages = {
          'en': 'The file could not be saved. Please try again.',
          'de': 'Die Datei konnte nicht gespeichert werden. Bitte versuche es erneut.',
          'fr': "Impossible d'enregistrer le fichier. Réessayez.",
          'es': 'No se pudo guardar el archivo. Inténtalo de nuevo.',
          'it': 'Impossibile salvare il file. Riprova.',
          'pt': 'Não foi possível salvar o arquivo. Tente novamente.',
        };
        expect(
          messages.keys.toSet(),
          AppLocalizations.supportedLocales
              .map((locale) => locale.languageCode)
              .toSet(),
        );
        for (final entry in messages.entries) {
          final l10n = await AppLocalizations.delegate.load(Locale(entry.key));
          expect(l10n.attachmentSaveFailed, entry.value);
        }
      },
    );

    testWidgets(
      'native in-flight save survives preview close and clears its copy',
      (tester) async {
        final probe = (await tester.runAsync(
          save_probe.AttachmentSaveProbe.create,
        ))!;
        addTearDown(probe.dispose);
        final plaintext = await _mountAttachmentPreview(tester);
        late Future<void> save;
        await tester.runAsync(() async {
          save = probe.delayWrites(_saveAttachmentAction(tester));
          selector.destinations.single.complete(FileSaveLocation(probe.path));
          await probe.writeStarted.timeout(const Duration(seconds: 10));
        });
        try {
          await tester.tap(find.widgetWithText(FilledButton, 'Close'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(probe.submittedBytes, plaintext);
        } finally {
          await tester.runAsync(() async {
            probe.releaseWrite();
            await save;
          });
        }
        await tester.runAsync(
          () async => expect(await probe.read(), plaintext),
        );
        expect(probe.submittedBytes, everyElement(0));
        expect(tester.takeException(), isNull);
      },
      skip: kIsWeb,
    );

    testWidgets('native failed write clears export copy and permits retry', (
      tester,
    ) async {
      final probe = (await tester.runAsync(
        save_probe.AttachmentSaveProbe.create,
      ))!;
      addTearDown(probe.dispose);
      final plaintext = await _mountAttachmentPreview(tester);
      late Future<void> save;
      await tester.runAsync(() async {
        save = probe.delayWrites(_saveAttachmentAction(tester));
        selector.destinations.single.complete(FileSaveLocation(probe.path));
        await probe.writeStarted.timeout(const Duration(seconds: 10));
        final failed = expectLater(save, completes);
        probe.rejectWrite();
        await failed;
        expect(await probe.exists(), isFalse);
      });
      expect(probe.submittedBytes, everyElement(0));
      await tester.pumpAndSettle();
      expect(
        find.text('The file could not be saved. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('controlled write failure'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.runAsync(() async {
        final retry = _saveAttachmentAction(tester)();
        selector.destinations.last.complete(FileSaveLocation(probe.path));
        await retry;
        expect(await probe.read(), plaintext);
      });
      expect(selector.names, ['received.txt', 'received.txt']);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, skip: kIsWeb);

    for (final destinationFails in [false, true]) {
      testWidgets('native save after owner removal fails=$destinationFails', (
        tester,
      ) async {
        final probe = (await tester.runAsync(
          save_probe.AttachmentSaveProbe.create,
        ))!;
        addTearDown(probe.dispose);
        late StateSetter updateHost;
        var visible = true;
        await _mountAttachmentPreview(
          tester,
          hostBuilder: (home) => StatefulBuilder(
            builder: (_, setState) {
              updateHost = setState;
              return visible ? home : const SizedBox.shrink();
            },
          ),
        );
        late Future<void> save;
        await tester.runAsync(() async {
          save = _saveAttachmentAction(tester)();
        });
        updateHost(() => visible = false);
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.runAsync(() async {
          if (destinationFails) {
            selector.destinations.single.completeError(
              StateError('private owner failure'),
            );
          } else {
            selector.destinations.single.complete(FileSaveLocation(probe.path));
          }
          await save;
          expect(await probe.exists(), isFalse);
        });
        expect(
          find.text('The file could not be saved. Please try again.'),
          findsNothing,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, skip: kIsWeb);
    }

    testWidgets(
      'native destination during dialog closing transition is ignored',
      (tester) async {
        final probe = (await tester.runAsync(
          save_probe.AttachmentSaveProbe.create,
        ))!;
        addTearDown(probe.dispose);
        await _mountAttachmentPreview(tester);
        final dialog = tester.element(find.byType(AlertDialog));
        late Future<void> save;
        await tester.runAsync(() async {
          save = _saveAttachmentAction(tester)();
        });
        await tester.tap(find.widgetWithText(FilledButton, 'Close'));
        await tester.pump();
        expect(
          dialog.mounted,
          isTrue,
          reason: 'The reverse transition has not completed.',
        );
        await tester.runAsync(() async {
          selector.destinations.single.complete(FileSaveLocation(probe.path));
          await save;
          expect(await probe.exists(), isFalse);
        });
        await tester.pumpAndSettle();
        expect(dialog.mounted, isFalse);
        expect(tester.takeException(), isNull);
      },
      skip: kIsWeb,
    );

    for (final closeBeforeDestination in [false, true]) {
      testWidgets('native save with preview closed=$closeBeforeDestination', (
        tester,
      ) async {
        final probe = (await tester.runAsync(
          save_probe.AttachmentSaveProbe.create,
        ))!;
        addTearDown(probe.dispose);
        final plaintext = await _mountAttachmentPreview(tester);
        late Future<void> save;
        await tester.runAsync(() async {
          save = _saveAttachmentAction(tester)();
        });
        expect(selector.names, ['received.txt']);
        if (closeBeforeDestination) {
          await tester.tap(find.widgetWithText(FilledButton, 'Close'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
        await tester.runAsync(() async {
          selector.destinations.single.complete(FileSaveLocation(probe.path));
          await save;
          if (closeBeforeDestination) {
            expect(
              await probe.exists(),
              isFalse,
              reason: 'A dismissed preview must not export a cleared plaintext buffer.',
            );
          } else {
            expect(await probe.read(), plaintext);
          }
        });
        if (!closeBeforeDestination) {
          await tester.tap(find.widgetWithText(FilledButton, 'Close'));
          await tester.pumpAndSettle();
          await tester.runAsync(
            () async => expect(await probe.read(), plaintext),
          );
        }
        expect(tester.takeException(), isNull);
      }, skip: kIsWeb);
    }
  });
}

Future<void> Function() _saveAttachmentAction(WidgetTester tester) =>
    tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save copy'))
            .onPressed!
        as Future<void> Function();

Future<Uint8List> _mountAttachmentPreview(
  WidgetTester tester, {
  Widget Function(Widget)? hostBuilder,
}) async {
  final plaintext = Uint8List.fromList(
    utf8.encode('Attachment export must preserve these bytes.'),
  );
  final endpoint = ServerEndpoint.parse('wss://localhost/ws');
  final cache = MemoryAttachmentChunkCache();
  addTearDown(cache.dispose);
  final cipher = AttachmentCipher();
  addTearDown(cipher.dispose);
  const messageId = 'preview_message_123456';
  final attachment = (await tester.runAsync(
    () async => (await cipher.encryptSources(
      scope: attachmentCacheScope(endpoint, 'alice'),
      senderUsername: 'alice',
      messageId: messageId,
      sources: [
        AttachmentPlaintextSource(
          name: 'received.txt',
          contentType: 'text/plain',
          kind: ChatAttachmentKind.file,
          byteCount: plaintext.length,
          openRead: () => Stream.value(plaintext),
        ),
      ],
      cache: cache,
    )).single,
  ))!;
  final controller = WampAppController(
    gateway: _FakeGateway(),
    attachmentCache: cache,
    trustStore: FakeDeviceTrustStore(
      initialMessages: [
        LocalChatMessage(
          messageId: messageId,
          conversationId: 'alice-bob',
          peerUsername: 'bob',
          text: '',
          sentAt: DateTime.utc(2026, 9, 28),
          outgoing: true,
          attachments: [attachment],
        ),
      ],
    ),
  );
  addTearDown(controller.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await controller.login(
    serverAddress: endpoint.websocketUri.toString(),
    username: 'alice',
    password: 'correct horse battery',
  );
  final home = HomePage(
    controller: controller,
    connection: controller.connection!,
    voiceNoteCaptureFactory: () => _ControlledVoiceCapture(),
  );
  await tester.pumpWidget(
    _LocalizedMaterialApp(home: hostBuilder?.call(home) ?? home),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final loaded = Completer<void>();
    var started = false;
    void listener() {
      if (controller.messageBusy) started = true;
      if (started && !controller.messageBusy && !loaded.isCompleted) {
        loaded.complete();
      }
    }

    controller.addListener(listener);
    try {
      tester
          .widget<InkWell>(
            find.byKey(ValueKey('attachment-open-${attachment.attachmentId}')),
          )
          .onTap!();
      await loaded.future.timeout(const Duration(seconds: 10));
    } finally {
      controller.removeListener(listener);
    }
  });
  await tester.pumpAndSettle();
  expect(controller.messageError, isNull);
  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text('received.txt'), findsNWidgets(2));
  return plaintext;
}

class _ControlledSaveSelector extends FileSelectorPlatform {
  final names = <String?>[];
  final destinations = <Completer<FileSaveLocation?>>[];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) {
    names.add(options.suggestedName);
    final destination = Completer<FileSaveLocation?>();
    destinations.add(destination);
    return destination.future;
  }
}

part of '../call_controller_test.dart';

Finder _callButton(String action) => find.descendant(
  of: find.byKey(Key('call-$action')),
  matching: find.byType(IconButton),
);

Future<void> _pumpCallReady(
  WidgetTester tester,
  CallController controller,
) async {
  for (var attempt = 0; attempt < 30 && controller.busy; attempt++) {
    // Stream cancellation can finish outside the widget fake-async zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(controller.busy, isFalse, reason: 'call operation must complete');
  await tester.pumpAndSettle();
}

Future<void> _mountCall(
  WidgetTester tester,
  CallController controller, {
  ThemeData? theme,
  String language = 'en',
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? WampAppTheme.light(),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Stack(
            children: [
              const SizedBox.expand(child: Text('Chats')),
              CallOverlay(controller: controller),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<
  ({
    _CallHarness harness,
    CallController controller,
    _FakeCallMediaSession media,
    String callId,
  })
>
_incomingCall(CallMediaKind kind) async {
  final h = _CallHarness(username: 'bob');
  final media = _FakeCallMediaSession(kind);
  h.mediaFactory.sessions.add(media);
  final id = _token(18, 70);
  final offer = h.remoteSignal(
    callId: id,
    kind: CallSignalKind.offer,
    sender: h.alice,
    payload: CallDescriptionSignalPayload(
      CallSessionDescription(type: 'offer', sdp: 'v=0\r\ns=offer\r\n'),
    ),
  );
  h.batches.add(
    CallBatch(
      nextCursor: 1,
      updates: [
        CallUpdate(cursor: 1, call: h.ringingCall(id, kind), signals: [offer]),
      ],
    ),
  );
  h.onAccept = (answer) async => CallUpdate(
    cursor: 2,
    call: CallRecord(
      callId: id,
      callerUsername: 'alice',
      callerDeviceId: h.alice.deviceId,
      calleeUsername: 'bob',
      media: kind,
      state: CallState.active,
      acceptedDeviceId: h.localDevice.deviceId,
      createdAt: DateTime.utc(2026, 9, 21),
      answeredAt: DateTime.utc(2026, 9, 21, 0, 0, 1),
    ),
    signals: [answer],
  );
  final c = h.controller();
  addTearDown(() async {
    await c.close();
    c.dispose();
    await h.close();
  });
  await c.initialize();
  expect(c.phase, CallUiPhase.incomingRinging);
  return (harness: h, controller: c, media: media, callId: id);
}

double _callContrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void _callOverlayTests() {
  group('call overlay', () {
    testWidgets('outgoing call shows peer and secure ringing label', (
      tester,
    ) async {
      final h = _CallHarness();
      h.mediaFactory.sessions.add(_FakeCallMediaSession(CallMediaKind.voice));
      h.onStart = (request) async => CallUpdate(
        cursor: 1,
        call: h.ringingCall(request.callId, CallMediaKind.voice),
        signals: request.offers,
      );
      final c = h.controller();
      addTearDown(() async {
        await c.close();
        c.dispose();
        await h.close();
      });
      await c.initialize();
      await c.startCall(recipientUsername: 'bob', media: CallMediaKind.voice);
      await _mountCall(tester, c);
      expect(c.phase, CallUiPhase.outgoingRinging);
      expect(find.text('@bob'), findsOneWidget);
      expect(
        find.text(lookupAppLocalizations(const Locale('en')).callingSecurely),
        findsOneWidget,
      );
      expect(
        tester.widget<IconButton>(_callButton('end')).onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('call-error')), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('incoming icons have contrast in ${brightness.name}', (
        tester,
      ) async {
        final f = await _incomingCall(CallMediaKind.voice);
        final theme = brightness == Brightness.light
            ? WampAppTheme.light()
            : WampAppTheme.dark();
        await _mountCall(tester, f.controller, theme: theme);
        for (final action in ['accept', 'decline']) {
          final style = tester.widget<IconButton>(_callButton(action)).style!;
          final background = style.backgroundColor!.resolve({})!;
          final foreground = style.foregroundColor!.resolve({})!;
          expect(
            _callContrast(background, foreground),
            greaterThanOrEqualTo(3),
            reason: '$action icon must remain visible on its button',
          );
        }
      });
      testWidgets('incoming labels have contrast in ${brightness.name}', (
        tester,
      ) async {
        final f = await _incomingCall(CallMediaKind.voice);
        final theme = brightness == Brightness.light
            ? WampAppTheme.light()
            : WampAppTheme.dark();
        await _mountCall(tester, f.controller, theme: theme);
        final card = tester.widget<Card>(find.byType(Card));
        final background =
            card.color ??
            theme.cardTheme.color ??
            theme.colorScheme.surfaceContainerLow;
        for (final action in ['accept', 'decline']) {
          final finder = find.descendant(
            of: find.byKey(Key('call-$action')),
            matching: find.byType(Text),
          );
          final text = tester.widget<Text>(finder);
          final color =
              text.style?.color ??
              DefaultTextStyle.of(tester.element(finder)).style.color!;
          expect(
            _callContrast(background, color),
            greaterThanOrEqualTo(4.5),
            reason: '$action text must remain readable on the call card',
          );
        }
      });
    }

    testWidgets('incoming buttons have localized accessible names', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final f = await _incomingCall(CallMediaKind.voice);
        await _mountCall(tester, f.controller, language: 'de');
        final l = lookupAppLocalizations(const Locale('de'));
        expect(
          tester.widget<IconButton>(_callButton('accept')).tooltip,
          l.accept,
        );
        expect(
          tester.widget<IconButton>(_callButton('decline')).tooltip,
          l.decline,
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    for (final language in ['de', 'fr', 'pt']) {
      testWidgets('$language enlarged incoming actions fit phone width', (
        tester,
      ) async {
        final f = await _incomingCall(CallMediaKind.voice);
        await _mountCall(tester, f.controller, language: language, scale: 2);
        expect(tester.takeException(), isNull);
        final l = lookupAppLocalizations(Locale(language));
        for (final label in [l.accept, l.decline]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(390));
          expect(rect.bottom, lessThanOrEqualTo(780));
        }
      });
    }

    for (final kind in CallMediaKind.values) {
      testWidgets('${kind.name} accepts once and disables busy actions', (
        tester,
      ) async {
        final f = await _incomingCall(kind);
        final pending = Completer<CallUpdate>();
        final accept = f.harness.onAccept!;
        EncryptedCallSignal? received;
        var accepts = 0;
        f.harness.onAccept = (signal) {
          accepts++;
          received = signal;
          return pending.future;
        };
        await _mountCall(tester, f.controller);
        final l = lookupAppLocalizations(const Locale('en'));
        expect(find.text('@alice'), findsOneWidget);
        expect(
          find.text(
            kind == CallMediaKind.video
                ? l.incomingEncryptedVideoCall
                : l.incomingEncryptedVoiceCall,
          ),
          findsOneWidget,
        );
        await tester.tap(_callButton('accept'));
        await tester.pump();
        expect(f.controller.busy, isTrue);
        for (final action in ['accept', 'decline']) {
          expect(
            tester.widget<IconButton>(_callButton(action)).onPressed,
            isNull,
          );
          await tester.tap(_callButton(action));
        }
        expect(accepts, 1);
        expect(received!.kind, CallSignalKind.answer);
        pending.complete(await accept(received!));
        await _pumpCallReady(tester, f.controller);
        expect(f.controller.phase, CallUiPhase.connecting);
        expect(find.text(l.connectingMedia), findsOneWidget);
        expect(f.media.acceptedOffers.single.sdp, contains('offer'));
        f.media.emitState(CallMediaConnectionState.connected);
        await tester.pumpAndSettle();
        expect(f.controller.phase, CallUiPhase.active);
        expect(find.text(l.encryptedSignaling), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${kind.name} media controls toggle real media state', (
        tester,
      ) async {
        final f = await _incomingCall(kind);
        await f.controller.acceptIncoming();
        await _mountCall(tester, f.controller, language: 'de');
        final l = lookupAppLocalizations(const Locale('de'));
        for (final muted in [true, false]) {
          await tester.tap(_callButton('mute'));
          await tester.pumpAndSettle();
          expect(f.media.muted, muted);
          expect(find.text(muted ? l.unmute : l.mute), findsOneWidget);
        }
        for (final speaker in [true, false]) {
          await tester.tap(_callButton('speaker'));
          await tester.pumpAndSettle();
          expect(f.media.speakerEnabled, speaker);
          expect(find.text(speaker ? l.earpiece : l.speaker), findsOneWidget);
        }
        if (kind == CallMediaKind.video) {
          for (final enabled in [false, true]) {
            await tester.tap(_callButton('camera'));
            await tester.pumpAndSettle();
            expect(f.media.cameraEnabled, enabled);
            expect(
              find.text(enabled ? l.cameraOff : l.cameraOn),
              findsOneWidget,
            );
          }
        } else {
          expect(find.byKey(const Key('call-camera')), findsNothing);
          expect(find.byKey(const Key('call-local-video')), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('unsupported speaker routing hides the control', (
      tester,
    ) async {
      final f = await _incomingCall(CallMediaKind.voice);
      f.media.routingSupported = false;
      await f.controller.acceptIncoming();
      await _mountCall(tester, f.controller);
      expect(find.byKey(const Key('call-speaker')), findsNothing);
      expect(_callButton('mute'), findsOneWidget);
      expect(_callButton('end'), findsOneWidget);
    });

    testWidgets('video renderers mirror local preview only', (tester) async {
      final f = await _incomingCall(CallMediaKind.video);
      final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
      // Uninitialized renderers exercise widget wiring, not platform media I/O.
      f.media.localVideo = FlutterWebRtcVideoRendererHandle(local);
      f.media.remoteVideo = FlutterWebRtcVideoRendererHandle(remote);
      await f.controller.acceptIncoming();
      try {
        await _mountCall(tester, f.controller);
        final views = tester
            .widgetList<RTCVideoView>(find.byType(RTCVideoView))
            .toList();
        expect(views, hasLength(2));
        RTCVideoRenderer rendererOf(RTCVideoView view) {
          // The plugin exposes this getter on the native widget, but web state.
          final dynamic owner = kIsWeb
              ? tester.state(find.byWidget(view))
              : view;
          return owner.videoRenderer as RTCVideoRenderer;
        }

        expect(
          views.singleWhere((v) => identical(rendererOf(v), local)).mirror,
          isTrue,
        );
        expect(
          views.singleWhere((v) => identical(rendererOf(v), remote)).mirror,
          isFalse,
        );
        expect(
          views.every(
            (v) =>
                v.objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          isTrue,
        );
        expect(find.byKey(const Key('call-local-video')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Web views poll for a video element until unmounted. Drain that callback.
        await tester.pump(const Duration(milliseconds: 100));
        await local.dispose();
        await remote.dispose();
      }
    });

    for (final accepted in [false, true]) {
      testWidgets('end accepted=$accepted sends control and dismisses', (
        tester,
      ) async {
        final f = await _incomingCall(CallMediaKind.video);
        if (accepted) await f.controller.acceptIncoming();
        final pending = Completer<CallUpdate>();
        final sent = <EncryptedCallSignal>[];
        f.harness.onEnd = (signal) {
          sent.add(signal);
          return pending.future;
        };
        await _mountCall(tester, f.controller);
        await tester.tap(_callButton(accepted ? 'end' : 'decline'));
        await tester.pumpAndSettle();
        expect(f.controller.phase, CallUiPhase.ending);
        expect(
          sent.single.kind,
          accepted ? CallSignalKind.hangup : CallSignalKind.decline,
        );
        final l = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l.endingCall), findsOneWidget);
        for (final button in tester.widgetList<IconButton>(
          find.byType(IconButton),
        )) {
          expect(button.onPressed, isNull);
        }
        pending.complete(
          CallUpdate(
            cursor: 3,
            call: f.harness.terminalCall(f.callId),
            signals: const [],
          ),
        );
        await _pumpCallReady(tester, f.controller);
        expect(f.controller.phase, CallUiPhase.ended);
        expect(find.text(l.callEnded), findsOneWidget);
        expect(find.byKey(const Key('call-error')), findsNothing);
        if (accepted) expect(f.media.disposed, isTrue);
        await tester.tap(find.byKey(const Key('call-dismiss')));
        await tester.pumpAndSettle();
        expect(f.controller.phase, CallUiPhase.idle);
        expect(find.byType(Card), findsNothing);
        expect(find.text('Chats'), findsOneWidget);
      });
    }

    testWidgets('accept failure keeps incoming offer available for retry', (
      tester,
    ) async {
      final f = await _incomingCall(CallMediaKind.voice);
      f.harness.onAccept = (_) async => throw StateError('answer unavailable');
      await _mountCall(tester, f.controller);
      await tester.tap(_callButton('accept'));
      await _pumpCallReady(tester, f.controller);
      expect(f.controller.phase, CallUiPhase.incomingRinging);
      expect(find.text('The call could not be completed.'), findsOneWidget);
      expect(find.byKey(const Key('call-error')), findsOneWidget);
      expect(
        tester.widget<IconButton>(_callButton('accept')).onPressed,
        isNotNull,
      );
      expect(f.media.disposed, isTrue);
    });

    testWidgets('end failure restores active controls and exposes error', (
      tester,
    ) async {
      final f = await _incomingCall(CallMediaKind.voice);
      await f.controller.acceptIncoming();
      f.harness.onEnd = (_) async => throw StateError('hangup unavailable');
      await _mountCall(tester, f.controller);
      await tester.tap(_callButton('end'));
      await _pumpCallReady(tester, f.controller);
      expect(f.controller.phase, CallUiPhase.active);
      expect(find.text('The call could not be completed.'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_callButton('end')).onPressed,
        isNotNull,
      );
      expect(f.media.disposed, isFalse);
    });

    testWidgets('answer on a sibling device shows terminal explanation', (
      tester,
    ) async {
      final f = await _incomingCall(CallMediaKind.voice);
      f.harness.onAccept = (answer) async => CallUpdate(
        cursor: 2,
        call: f.harness.activeCall(
          f.callId,
          acceptedDeviceId: f.harness.bobSibling.deviceId,
        ),
        signals: [answer],
      );
      await _mountCall(tester, f.controller);
      await tester.tap(_callButton('accept'));
      await _pumpCallReady(tester, f.controller);
      expect(f.controller.phase, CallUiPhase.answeredElsewhere);
      expect(
        find.text(
          lookupAppLocalizations(const Locale('en')).answeredOtherDevice,
        ),
        findsOneWidget,
      );
      expect(f.media.disposed, isTrue);
      expect(_callButton('accept'), findsNothing);
    });

    testWidgets('outgoing failure shows error and can return to chats', (
      tester,
    ) async {
      final h = _CallHarness();
      h.mediaFactory.sessions.add(_FakeCallMediaSession(CallMediaKind.voice));
      h.onStart = (_) async => throw StateError('start unavailable');
      final c = h.controller();
      addTearDown(() async {
        await c.close();
        c.dispose();
        await h.close();
      });
      await c.initialize();
      await _mountCall(tester, c);
      expect(find.byType(Card), findsNothing);
      await tester.runAsync(
        () => c.startCall(recipientUsername: 'bob', media: CallMediaKind.voice),
      );
      await tester.pumpAndSettle();
      expect(c.phase, CallUiPhase.failed);
      expect(
        find.text(lookupAppLocalizations(const Locale('en')).callUnavailable),
        findsOneWidget,
      );
      expect(find.text('The call could not be completed.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('call-dismiss')));
      await tester.pumpAndSettle();
      expect(c.phase, CallUiPhase.idle);
      expect(c.errorMessage, isNull);
    });
  });
}

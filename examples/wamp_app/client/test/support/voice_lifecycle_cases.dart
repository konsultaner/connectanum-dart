part of '../widget_test.dart';

void _voiceLifecycleCases() {
  group('voice lifecycle', () {
    for (final detached in [false, true]) {
      testWidgets(
        'already completed recording detached=$detached preserves ownership',
        (tester) async {
          final capture = _ControlledVoiceCapture();
          final recording = _OwnedVoiceRecording();
          capture.session.completionOverride = SynchronousFuture(recording);
          await _mountVoiceHome(tester, capture);
          _voiceAction(tester)();
          if (detached) await tester.pumpWidget(const SizedBox.shrink());
          capture.started.complete(capture.session);
          await tester.pump();
          await tester.pump();
          expect(recording.takeCalls, detached ? 0 : 1);
          expect(recording.disposeCalls, 1);
          expect(capture.session.cancelCalls, detached ? 1 : 0);
          expect(recording.bytes, everyElement(detached ? 0 : 7));
          expect(find.byKey(const Key('voice-recording-status')), findsNothing);
          expect(
            find.byKey(const Key('selected-attachment-0')),
            detached ? findsNothing : findsOneWidget,
          );
        },
      );
    }

    testWidgets('coalesces start callbacks before the next rebuild', (
      tester,
    ) async {
      final capture = _ControlledVoiceCapture();
      await _mountVoiceHome(tester, capture);
      final start = _voiceAction(tester);
      start();
      start();
      expect(capture.startCalls, 1);
      capture.started.complete(capture.session);
      await tester.pump();
      expect(find.byKey(const Key('voice-recording-status')), findsOneWidget);
      expect(capture.session.completionReads, 1);
    });

    testWidgets('coalesces stop callbacks before the next rebuild', (
      tester,
    ) async {
      final capture = _ControlledVoiceCapture();
      await _startControlledVoice(tester, capture);
      final stop = _voiceAction(tester);
      stop();
      stop();
      expect(capture.session.stopCalls, 1);
      await tester.pump();
      expect(_voiceButton(tester).onPressed, isNull);
      expect(_voiceCancelButton(tester).onPressed, isNull);
      capture.session.finish(_OwnedVoiceRecording());
      await tester.pump();
      expect(find.byKey(const Key('selected-attachment-0')), findsOneWidget);
    });

    testWidgets('does not stop while cancellation owns the session', (
      tester,
    ) async {
      final capture = _ControlledVoiceCapture();
      await _startControlledVoice(tester, capture);
      final stop = _voiceAction(tester);
      final cancel = _voiceCancelButton(tester).onPressed!;
      final cancelGate = Completer<void>();
      capture.session.cancelGate = cancelGate;
      cancel();
      stop();
      cancel();
      expect(capture.session.cancelCalls, 1);
      expect(capture.session.stopCalls, 0);
      await tester.pump();
      expect(_voiceButton(tester).onPressed, isNull);
      expect(_voiceCancelButton(tester).onPressed, isNull);
      capture.session.fail(const VoiceNoteRecordingCancelled());
      cancelGate.complete();
      await tester.pump();
      expect(find.byKey(const Key('voice-recording-status')), findsNothing);
      expect(find.byKey(const Key('selected-attachment-0')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('does not cancel while stopping owns the session', (
      tester,
    ) async {
      final capture = _ControlledVoiceCapture();
      await _startControlledVoice(tester, capture);
      final cancel = _voiceCancelButton(tester).onPressed!;
      _voiceAction(tester)();
      cancel();
      expect(capture.session.stopCalls, 1);
      expect(capture.session.cancelCalls, 0);
      capture.session.finish(_OwnedVoiceRecording());
      await tester.pump();
      expect(find.byKey(const Key('selected-attachment-0')), findsOneWidget);
    });

    testWidgets('disposes a late successful recording after unmount', (
      tester,
    ) async {
      final capture = _ControlledVoiceCapture();
      final recording = _OwnedVoiceRecording();
      await _mountVoiceHome(tester, capture);
      _voiceAction(tester)();
      await tester.pumpWidget(const SizedBox.shrink());
      capture.started.complete(capture.session);
      await tester.pump();
      expect(capture.disposeCalls, 1);
      expect(capture.session.cancelCalls, 1);
      capture.session.finish(recording);
      await tester.pump();
      expect(recording.disposeCalls, 1);
      expect(recording.takeCalls, 0);
      expect(recording.bytes, everyElement(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('observes cancellation when start resolves after unmount', (
      tester,
    ) async {
      final errors = <Object>[];
      late _ControlledVoiceCapture capture;
      late Zone captureZone;
      runZonedGuarded(() {
        captureZone = Zone.current;
        capture = _ControlledVoiceCapture();
      }, (error, _) => errors.add(error));
      await _mountVoiceHome(tester, capture);
      captureZone.run(_voiceAction(tester));
      await tester.pumpWidget(const SizedBox.shrink());
      capture.started.complete(capture.session);
      await tester.pump();
      capture.session.fail(const VoiceNoteRecordingCancelled());
      await tester.pump();
      expect(capture.session.cancelCalls, 1);
      expect(errors, isEmpty);
    });

    for (final failure in <Object>[
      const VoiceNoteRecordingException('Microphone permission was denied.'),
      StateError('private capture diagnostic'),
    ]) {
      testWidgets(
        'start failure ${failure.runtimeType} is recoverable and sanitized',
        (tester) async {
          final capture = _ControlledVoiceCapture();
          await _mountVoiceHome(tester, capture);
          _voiceAction(tester)();
          await tester.pump();
          expect(_voiceButton(tester).onPressed, isNull);
          capture.started.completeError(failure);
          await tester.pump();
          expect(_voiceButton(tester).onPressed, isNotNull);
          expect(find.byKey(const Key('voice-recording-status')), findsNothing);
          expect(
            find.text(
              failure is VoiceNoteRecordingException
                  ? failure.message
                  : 'The microphone could not start recording.',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('private capture diagnostic'),
            findsNothing,
          );
          capture.started = Completer<VoiceNoteCaptureSession>();
          _voiceAction(tester)();
          capture.started.complete(capture.session);
          await tester.pump();
          expect(capture.startCalls, 2);
          expect(
            find.byKey(const Key('voice-recording-status')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'late start failure ${failure.runtimeType} after unmount is ignored',
        (tester) async {
          final capture = _ControlledVoiceCapture();
          await _mountVoiceHome(tester, capture);
          _voiceAction(tester)();
          await tester.pumpWidget(const SizedBox.shrink());
          capture.started.completeError(failure);
          await tester.pump();
          expect(capture.disposeCalls, 1);
          expect(tester.takeException(), isNull);
        },
      );

      for (final cancel in [false, true]) {
        testWidgets(
          '${cancel ? 'cancel' : 'stop'} failure ${failure.runtimeType} cannot poison the next recording',
          (tester) async {
            final capture = _ControlledVoiceCapture();
            await _startControlledVoice(tester, capture);
            final old = capture.session;
            if (cancel) {
              old.cancelError = failure;
              _voiceCancelButton(tester).onPressed!();
            } else {
              old.stopError = failure;
              _voiceAction(tester)();
            }
            await tester.pump();
            expect(
              find.byKey(const Key('voice-recording-status')),
              findsNothing,
            );
            expect(_voiceButton(tester).onPressed, isNotNull);
            expect(
              find.text(
                failure is VoiceNoteRecordingException
                    ? failure.message
                    : 'The voice-note recording failed.',
              ),
              findsOneWidget,
            );
            expect(
              find.textContaining('private capture diagnostic'),
              findsNothing,
            );
            capture.session = _ControlledVoiceSession();
            capture.started = Completer<VoiceNoteCaptureSession>();
            _voiceAction(tester)();
            capture.started.complete(capture.session);
            await tester.pump();
            expect(
              find.byKey(const Key('voice-recording-status')),
              findsOneWidget,
            );
            if (cancel) {
              old.fail(StateError('stale recording error'));
            } else {
              final stale = _OwnedVoiceRecording();
              old.finish(stale);
              await tester.pump();
              expect(stale.takeCalls, 0);
              expect(stale.disposeCalls, 1);
              expect(stale.bytes, everyElement(0));
            }
            await tester.pump();
            expect(
              find.byKey(const Key('voice-recording-status')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('selected-attachment-0')),
              findsNothing,
            );
            capture.session.finish(_OwnedVoiceRecording());
            await tester.pump();
            expect(
              find.byKey(const Key('selected-attachment-0')),
              findsOneWidget,
            );
            expect(find.textContaining('stale recording error'), findsNothing);
          },
        );
      }
    }

    for (final automatic in [false, true]) {
      testWidgets(
        '${automatic ? 'automatic' : 'stopped'} completion transfers bytes and removal clears them',
        (tester) async {
          final capture = _ControlledVoiceCapture();
          final recording = _OwnedVoiceRecording();
          await _startControlledVoice(tester, capture);
          if (!automatic) _voiceAction(tester)();
          capture.session.finish(recording);
          await tester.pump();
          // Automatic completion schedules its rebuild from a microtask.
          await tester.pump();
          expect(capture.session.stopCalls, automatic ? 0 : 1);
          expect(recording.takeCalls, 1);
          expect(recording.disposeCalls, 1);
          expect(recording.bytes, everyElement(7));
          expect(find.byKey(const Key('voice-recording-status')), findsNothing);
          expect(find.textContaining('0:12'), findsOneWidget);
          tester
              .widget<InputChip>(find.byKey(const Key('selected-attachment-0')))
              .onDeleted!();
          await tester.pump();
          expect(recording.bytes, everyElement(0));
          expect(find.byKey(const Key('selected-attachment-0')), findsNothing);
        },
      );
    }

    testWidgets(
      'active completion after unmount cannot stage or retain audio',
      (tester) async {
        final capture = _ControlledVoiceCapture();
        final recording = _OwnedVoiceRecording();
        await _startControlledVoice(tester, capture);
        await tester.pumpWidget(const SizedBox.shrink());
        capture.session.finish(recording);
        await tester.pump();
        expect(capture.disposeCalls, 1);
        expect(recording.takeCalls, 0);
        expect(recording.disposeCalls, 1);
        expect(recording.bytes, everyElement(0));
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Future<void> _mountVoiceHome(
  WidgetTester tester,
  _ControlledVoiceCapture capture,
) async {
  final controller = WampAppController(
    gateway: _FakeGateway(),
    trustStore: FakeDeviceTrustStore(),
  );
  addTearDown(controller.dispose);
  await controller.login(
    serverAddress: 'wss://localhost/ws',
    username: 'alice',
    password: 'correct horse battery',
  );
  await tester.pumpWidget(
    _LocalizedMaterialApp(
      home: HomePage(
        controller: controller,
        connection: controller.connection!,
        voiceNoteCaptureFactory: () => capture,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _startControlledVoice(
  WidgetTester tester,
  _ControlledVoiceCapture capture,
) async {
  await _mountVoiceHome(tester, capture);
  _voiceAction(tester)();
  capture.started.complete(capture.session);
  await tester.pump();
  expect(find.byKey(const Key('voice-recording-status')), findsOneWidget);
}

IconButton _voiceButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('message-voice')));
VoidCallback _voiceAction(WidgetTester tester) =>
    _voiceButton(tester).onPressed!;
IconButton _voiceCancelButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('voice-recording-cancel')));

final class _ControlledVoiceCapture implements VoiceNoteCapture {
  var started = Completer<VoiceNoteCaptureSession>();
  var session = _ControlledVoiceSession();
  int startCalls = 0;
  int disposeCalls = 0;

  @override
  Future<VoiceNoteCaptureSession> start() {
    startCalls++;
    return started.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

final class _ControlledVoiceSession implements VoiceNoteCaptureSession {
  final _completion = Completer<VoiceNoteRecording>();
  int completionReads = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  Object? stopError;
  Object? cancelError;
  Completer<void>? cancelGate;
  Future<VoiceNoteRecording>? completionOverride;

  @override
  Future<VoiceNoteRecording> get completed {
    completionReads++;
    return completionOverride ?? _completion.future;
  }

  @override
  Future<VoiceNoteRecording> stop() {
    stopCalls++;
    if (stopError case final error?) return Future.error(error);
    return _completion.future;
  }

  @override
  Future<void> cancel() {
    cancelCalls++;
    if (cancelError case final error?) return Future.error(error);
    return cancelGate?.future ?? Future.value();
  }

  void finish(VoiceNoteRecording recording) => _completion.complete(recording);
  void fail(Object error) => _completion.completeError(error);
}

final class _OwnedVoiceRecording implements VoiceNoteRecording {
  final bytes = Uint8List.fromList(List<int>.filled(364, 7));
  int takeCalls = 0;
  int disposeCalls = 0;
  bool moved = false;

  @override
  int get byteCount => bytes.length;
  @override
  int get durationMilliseconds => 12345;
  @override
  Uint8List takeBytes() {
    takeCalls++;
    moved = true;
    return bytes;
  }

  @override
  void dispose() {
    disposeCalls++;
    if (!moved) bytes.fillRange(0, bytes.length, 0);
  }
}

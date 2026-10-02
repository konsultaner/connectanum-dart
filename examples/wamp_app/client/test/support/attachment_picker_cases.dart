part of '../widget_test.dart';

void _attachmentPickerCases() {
  group('attachment picker', () {
    late _ControlledFileSelector picker;
    setUp(() {
      final previous = FileSelectorPlatform.instance;
      picker = _ControlledFileSelector();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);
    });

    for (final firstCount in [3, 4]) {
      testWidgets(
        'overlapping selections enforce capacity with $firstCount and 5 files',
        (tester) async {
          await _mountVoiceHome(tester, _ControlledVoiceCapture());
          final firstSize = Completer<int>();
          final secondSize = Completer<int>();
          final first = _PickerFile('first.txt', () => firstSize.future);
          final second = _PickerFile('second.txt', () => secondSize.future);
          _attachmentAction(tester)();
          _attachmentAction(tester)();
          expect(picker.requests, hasLength(2));
          picker.requests[0].complete([
            first,
            ...List.generate(
              firstCount - 1,
              (i) => _sizedFile('first-$i.txt', 1),
            ),
          ]);
          picker.requests[1].complete([
            second,
            ...List.generate(4, (i) => _sizedFile('second-$i.txt', 1)),
          ]);
          await tester.pump();
          expect(first.lengthCalls, 1);
          expect(second.lengthCalls, 1);
          secondSize.complete(1);
          await tester.pumpAndSettle();
          expect(_attachmentCount(tester), 5);
          firstSize.complete(1);
          await tester.pumpAndSettle();
          expect(_attachmentCount(tester), firstCount == 3 ? 8 : 5);
          expect(
            find.text('A message can contain up to 8 attachments.'),
            firstCount == 3 ? findsNothing : findsOneWidget,
          );
          expect(find.textContaining('second.txt'), findsOneWidget);
          if (firstCount == 4) {
            expect(find.textContaining('first.txt'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'empty selection and oversized batch leave composer unchanged',
      (tester) async {
        await _mountVoiceHome(tester, _ControlledVoiceCapture());
        _attachmentAction(tester)();
        picker.requests.last.complete([]);
        await tester.pumpAndSettle();
        expect(_attachmentCount(tester), 0);
        expect(find.byType(SnackBar), findsNothing);
        final files = List.generate(9, (i) => _sizedFile('$i.txt', 1));
        _attachmentAction(tester)();
        picker.requests.last.complete(files);
        await tester.pumpAndSettle();
        expect(_attachmentCount(tester), 0);
        expect(files.every((file) => file.lengthCalls == 0), isTrue);
        expect(
          find.text('A message can contain up to 8 attachments.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('size boundaries and atomic rejection preserve prior files', (
      tester,
    ) async {
      await _mountVoiceHome(tester, _ControlledVoiceCapture());
      _attachmentAction(tester)();
      picker.requests.last.complete([
        _sizedFile('empty.txt', 0),
        _sizedFile('limit.pdf', WampAppAttachmentLimits.maxAttachmentBytes),
      ]);
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 2);
      expect(find.textContaining('empty.txt'), findsOneWidget);
      _attachmentAction(tester)();
      picker.requests.last.complete([
        _sizedFile('discard.txt', 1),
        _sizedFile(
          'oversize.pdf',
          WampAppAttachmentLimits.maxAttachmentBytes + 1,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 2);
      expect(find.textContaining('discard.txt'), findsNothing);
      expect(
        find.text('Each attachment must be 64 MiB or smaller.'),
        findsOneWidget,
      );
    });

    testWidgets('full capacity disables selection until a file is removed', (
      tester,
    ) async {
      await _mountVoiceHome(tester, _ControlledVoiceCapture());
      _attachmentAction(tester)();
      picker.requests.last.complete(
        List.generate(8, (i) => _sizedFile('$i.txt', 1)),
      );
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 8);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('message-attach')))
            .onPressed,
        isNull,
      );
      tester
          .widget<InputChip>(find.byKey(const Key('selected-attachment-0')))
          .onDeleted!();
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 7);
      expect(find.textContaining('0.txt'), findsNothing);
      _attachmentAction(tester)();
      picker.requests.last.complete([_sizedFile('replacement.txt', 1)]);
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 8);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('message-attach')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('remaining capacity rejects a batch before reading sizes', (
      tester,
    ) async {
      await _mountVoiceHome(tester, _ControlledVoiceCapture());
      _attachmentAction(tester)();
      picker.requests.last.complete(
        List.generate(7, (i) => _sizedFile('$i.txt', 1)),
      );
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 7);
      final files = [
        _sizedFile('extra-a.txt', 1),
        _sizedFile('extra-b.txt', 1),
      ];
      _attachmentAction(tester)();
      picker.requests.last.complete(files);
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 7);
      expect(files.map((file) => file.lengthCalls), [0, 0]);
      expect(
        find.text('A message can contain up to 8 attachments.'),
        findsOneWidget,
      );
    });

    testWidgets('read failure is sanitized and next selection recovers', (
      tester,
    ) async {
      await _mountVoiceHome(tester, _ControlledVoiceCapture());
      _attachmentAction(tester)();
      picker.requests.last.complete([
        _PickerFile('broken.txt', () async => throw StateError('private path')),
      ]);
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 0);
      expect(
        find.text('The selected files could not be opened.'),
        findsOneWidget,
      );
      expect(find.textContaining('private path'), findsNothing);
      _attachmentAction(tester)();
      picker.requests.last.complete([_sizedFile('recovered.txt', 1)]);
      await tester.pumpAndSettle();
      expect(_attachmentCount(tester), 1);
      expect(find.textContaining('recovered.txt'), findsOneWidget);
    });

    for (final duringLength in [false, true]) {
      testWidgets(
        'disposal ignores late ${duringLength ? 'size' : 'selection'}',
        (tester) async {
          await _mountVoiceHome(tester, _ControlledVoiceCapture());
          final size = Completer<int>();
          final file = _PickerFile('late.txt', () => size.future);
          _attachmentAction(tester)();
          if (duringLength) {
            picker.requests.last.complete([file]);
            await tester.pump();
            expect(file.lengthCalls, 1);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          if (duringLength) {
            size.completeError(StateError('late read failure'));
          } else {
            picker.requests.last.complete([file]);
          }
          await tester.pumpAndSettle();
          expect(file.lengthCalls, duringLength ? 1 : 0);
          expect(tester.takeException(), isNull);
          expect(find.byType(SnackBar), findsNothing);
        },
      );
    }
  });
}

VoidCallback _attachmentAction(WidgetTester tester) => tester
    .widget<IconButton>(find.byKey(const Key('message-attach')))
    .onPressed!;

int _attachmentCount(WidgetTester tester) {
  final list = find.byKey(const Key('selected-attachments'));
  return list.evaluate().isEmpty
      ? 0
      : tester.widget<ListView>(list).semanticChildCount!;
}

_PickerFile _sizedFile(String name, int size) =>
    _PickerFile(name, () async => size);

class _PickerFile extends XFile {
  _PickerFile(this.name, this.readLength)
    : super.fromData(Uint8List(0), name: name);

  @override
  final String name;

  final Future<int> Function() readLength;
  int lengthCalls = 0;

  @override
  Future<int> length() {
    lengthCalls++;
    return readLength();
  }
}

class _ControlledFileSelector extends FileSelectorPlatform {
  final requests = <Completer<List<XFile>>>[];

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    final request = Completer<List<XFile>>();
    requests.add(request);
    return request.future;
  }
}

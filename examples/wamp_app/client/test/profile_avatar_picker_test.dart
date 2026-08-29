import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/profile_avatar_picker.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('profile avatar selection owns its bytes', () {
    final source = Uint8List.fromList([1, 2, 3]);
    final selection = ProfileAvatarSelection(name: 'avatar.png', bytes: source);

    source[0] = 9;

    expect(selection.name, 'avatar.png');
    expect(selection.bytes, [1, 2, 3]);
  });

  test('file selector avatar picker preserves cancellation', () async {
    const picker = FileSelectorProfileAvatarPicker(_cancelSelection);

    expect(await picker.pickAvatar(), isNull);
  });

  test('file selector avatar picker returns a bounded owned image', () async {
    final source = Uint8List.fromList([1, 2, 3, 4]);
    final picker = FileSelectorProfileAvatarPicker(
      () async =>
          XFile.fromData(source, name: 'avatar.png', path: 'avatar.png'),
    );

    final selection = await picker.pickAvatar();
    source[0] = 9;

    expect(selection?.name, 'avatar.png');
    expect(selection?.bytes, [1, 2, 3, 4]);
  });

  test('file selector avatar picker rejects oversized images', () async {
    final picker = FileSelectorProfileAvatarPicker(
      () async => XFile.fromData(
        Uint8List(AccountProfileLimits.maxAvatarBytes + 1),
        name: 'avatar.png',
        path: 'avatar.png',
      ),
    );

    await expectLater(
      picker.pickAvatar(),
      throwsA(
        isA<ProfileAvatarPickerException>().having(
          (error) => error.message,
          'message',
          'Profile images must be 256 KiB or smaller.',
        ),
      ),
    );
  });

  test('file selector avatar picker rejects empty images', () async {
    final picker = FileSelectorProfileAvatarPicker(
      () async =>
          XFile.fromData(Uint8List(0), name: 'avatar.png', path: 'avatar.png'),
    );

    await expectLater(
      picker.pickAvatar(),
      throwsA(
        isA<ProfileAvatarPickerException>().having(
          (error) => error.message,
          'message',
          'Profile images must be 256 KiB or smaller.',
        ),
      ),
    );
  });

  test('file selector avatar picker redacts selector failures', () async {
    final picker = FileSelectorProfileAvatarPicker(
      () async => throw StateError('private path'),
    );

    await expectLater(
      picker.pickAvatar(),
      throwsA(
        isA<ProfileAvatarPickerException>()
            .having(
              (error) => error.message,
              'message',
              'The selected profile image could not be read.',
            )
            .having(
              (error) => error.toString(),
              'redacted error',
              isNot(contains('private path')),
            ),
      ),
    );
  });
}

Future<XFile?> _cancelSelection() async => null;

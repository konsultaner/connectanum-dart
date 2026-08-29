import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

typedef ProfileAvatarFileSelector = Future<XFile?> Function();

final class ProfileAvatarSelection {
  ProfileAvatarSelection({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes);

  final String name;
  final Uint8List bytes;
}

abstract interface class ProfileAvatarPicker {
  Future<ProfileAvatarSelection?> pickAvatar();
}

final class FileSelectorProfileAvatarPicker implements ProfileAvatarPicker {
  const FileSelectorProfileAvatarPicker([
    this._selectFile = _selectProfileAvatarFile,
  ]);

  final ProfileAvatarFileSelector _selectFile;

  @override
  Future<ProfileAvatarSelection?> pickAvatar() async {
    try {
      final file = await _selectFile();
      if (file == null) return null;
      final length = await file.length();
      if (length <= 0 || length > AccountProfileLimits.maxAvatarBytes) {
        throw const ProfileAvatarPickerException(
          'Profile images must be 256 KiB or smaller.',
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.length != length ||
          bytes.length > AccountProfileLimits.maxAvatarBytes) {
        bytes.fillRange(0, bytes.length, 0);
        throw const ProfileAvatarPickerException(
          'The selected profile image could not be read.',
        );
      }
      return ProfileAvatarSelection(name: file.name, bytes: bytes);
    } on ProfileAvatarPickerException {
      rethrow;
    } catch (_) {
      throw const ProfileAvatarPickerException(
        'The selected profile image could not be read.',
      );
    }
  }
}

final class ProfileAvatarPickerException implements Exception {
  const ProfileAvatarPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<XFile?> _selectProfileAvatarFile() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Profile image',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    ),
  ],
);

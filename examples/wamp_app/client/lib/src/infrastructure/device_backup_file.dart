import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'device_vault.dart';

abstract interface class DeviceBackupFileGateway {
  Future<bool> save(Uint8List archive, {required String suggestedName});

  Future<Uint8List?> open();
}

final class FileSelectorDeviceBackupFileGateway
    implements DeviceBackupFileGateway {
  const FileSelectorDeviceBackupFileGateway();

  static const _typeGroup = XTypeGroup(
    label: 'WampApp encrypted backup',
    extensions: ['wampbackup'],
    mimeTypes: ['application/vnd.wampapp.backup+json'],
    webWildCards: ['application/json'],
  );

  @override
  Future<bool> save(Uint8List archive, {required String suggestedName}) async {
    if (archive.isEmpty ||
        archive.length > WampAppBackupLimits.maximumArchiveBytes) {
      throw const BackupExportException();
    }
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_typeGroup],
    );
    if (location == null) return false;
    final file = XFile.fromData(
      archive,
      mimeType: 'application/vnd.wampapp.backup+json',
      name: suggestedName,
    );
    await file.saveTo(location.path);
    return true;
  }

  @override
  Future<Uint8List?> open() async {
    final file = await openFile(acceptedTypeGroups: const [_typeGroup]);
    if (file == null) return null;
    final length = await file.length();
    if (length <= 0 || length > WampAppBackupLimits.maximumArchiveBytes) {
      throw const BackupRestoreException();
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != length ||
        bytes.length > WampAppBackupLimits.maximumArchiveBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const BackupRestoreException();
    }
    return bytes;
  }
}

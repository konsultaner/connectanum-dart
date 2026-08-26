import 'dart:typed_data';

import 'account_registration.dart';

enum ProfileAvatarAction {
  keep,
  set,
  remove;

  static ProfileAvatarAction parse(Object? value) => switch (value) {
    'keep' => keep,
    'set' => set,
    'remove' => remove,
    _ => throw const FormatException('avatar_action is invalid.'),
  };
}

abstract final class AccountProfileLimits {
  static const maxStatusCharacters = 280;
  static const maxAvatarBytes = 256 * 1024;
  static const maxRevision = 0x1FFFFFFFFFFFFF;
  static const supportedAvatarContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };
}

class AccountProfile {
  AccountProfile({
    required this.username,
    required this.displayName,
    required this.status,
    required this.revision,
    required DateTime updatedAt,
    Uint8List? avatarBytes,
    this.avatarContentType,
  }) : updatedAt = updatedAt.toUtc(),
       avatarBytes = avatarBytes == null
           ? null
           : Uint8List.fromList(avatarBytes) {
    validate();
  }

  final String username;
  final String displayName;
  final String status;
  final int revision;
  final DateTime updatedAt;
  final Uint8List? avatarBytes;
  final String? avatarContentType;

  bool get hasAvatar => avatarBytes != null;

  void validate() {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    if (normalizedUsername != username ||
        !_usernamePattern.hasMatch(username)) {
      throw const FormatException('Profile username must be normalized.');
    }
    _validateDisplayName(displayName);
    _validateStatus(status);
    _validateRevision(revision, 'revision');
    _validateAvatar(avatarBytes, avatarContentType);
  }

  Map<String, dynamic> toWampKeywords() => {
    'username': username,
    'display_name': displayName,
    'status': status,
    'revision': revision,
    'updated_at': updatedAt.toIso8601String(),
    if (avatarBytes case final bytes?)
      'avatar_bytes': Uint8List.fromList(bytes),
    'avatar_content_type': ?avatarContentType,
  };

  factory AccountProfile.fromWampKeywords(Map<String, dynamic>? keywords) {
    if (keywords == null) {
      throw const FormatException('Profile response is missing.');
    }
    final rawUpdatedAt = keywords['updated_at'];
    final updatedAt = rawUpdatedAt is String
        ? DateTime.tryParse(rawUpdatedAt)
        : null;
    if (keywords case {
      'username': final String username,
      'display_name': final String displayName,
      'status': final String status,
      'revision': final int revision,
    } when updatedAt != null) {
      return AccountProfile(
        username: username,
        displayName: displayName,
        status: status,
        revision: revision,
        updatedAt: updatedAt,
        avatarBytes: _readBytes(keywords['avatar_bytes']),
        avatarContentType: _readOptionalString(
          keywords['avatar_content_type'],
          'avatar_content_type',
        ),
      );
    }
    throw const FormatException('Profile response is invalid.');
  }
}

class AccountProfileUpdate {
  AccountProfileUpdate({
    required this.expectedRevision,
    required this.displayName,
    required this.status,
    this.avatarAction = ProfileAvatarAction.keep,
    Uint8List? avatarBytes,
    this.avatarContentType,
  }) : avatarBytes = avatarBytes == null
           ? null
           : Uint8List.fromList(avatarBytes) {
    validate();
  }

  final int expectedRevision;
  final String displayName;
  final String status;
  final ProfileAvatarAction avatarAction;
  final Uint8List? avatarBytes;
  final String? avatarContentType;

  void validate() {
    _validateRevision(expectedRevision, 'expected_revision');
    _validateDisplayName(displayName);
    _validateStatus(status);
    switch (avatarAction) {
      case ProfileAvatarAction.keep:
      case ProfileAvatarAction.remove:
        if (avatarBytes != null || avatarContentType != null) {
          throw const FormatException(
            'Avatar data is only allowed when avatar_action is set.',
          );
        }
      case ProfileAvatarAction.set:
        _validateAvatar(avatarBytes, avatarContentType);
        if (avatarBytes == null) {
          throw const FormatException('A set avatar needs image bytes.');
        }
    }
  }

  Map<String, dynamic> toWampKeywords() => {
    'expected_revision': expectedRevision,
    'display_name': displayName,
    'status': status,
    'avatar_action': avatarAction.name,
    if (avatarBytes case final bytes?)
      'avatar_bytes': Uint8List.fromList(bytes),
    'avatar_content_type': ?avatarContentType,
  };

  factory AccountProfileUpdate.fromWampKeywords(
    Map<String, dynamic>? keywords,
  ) {
    if (keywords == null) {
      throw const FormatException('Profile update is missing.');
    }
    if (keywords case {
      'expected_revision': final int expectedRevision,
      'display_name': final String displayName,
      'status': final String status,
    }) {
      return AccountProfileUpdate(
        expectedRevision: expectedRevision,
        displayName: displayName,
        status: status,
        avatarAction: ProfileAvatarAction.parse(keywords['avatar_action']),
        avatarBytes: _readBytes(keywords['avatar_bytes']),
        avatarContentType: _readOptionalString(
          keywords['avatar_content_type'],
          'avatar_content_type',
        ),
      );
    }
    throw const FormatException('Profile update is invalid.');
  }
}

final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$');

void _validateDisplayName(String value) {
  if (value.isEmpty || value.length > 80 || value.trim() != value) {
    throw const FormatException(
      'Display names need 1-80 characters without outer whitespace.',
    );
  }
  if (_containsControlCharacter(value)) {
    throw const FormatException(
      'Display names cannot contain control characters.',
    );
  }
}

void _validateStatus(String value) {
  if (value.length > AccountProfileLimits.maxStatusCharacters ||
      value.trim() != value) {
    throw const FormatException(
      'Profile status needs 0-280 characters without outer whitespace.',
    );
  }
  if (_containsControlCharacter(value)) {
    throw const FormatException('Profile status must be a single text line.');
  }
}

void _validateRevision(int value, String field) {
  if (value < 0 || value > AccountProfileLimits.maxRevision) {
    throw FormatException('$field is outside the supported range.');
  }
}

void _validateAvatar(Uint8List? bytes, String? contentType) {
  if (bytes == null && contentType == null) return;
  if (bytes == null || contentType == null || bytes.isEmpty) {
    throw const FormatException(
      'Avatar bytes and content type must be paired.',
    );
  }
  if (bytes.length > AccountProfileLimits.maxAvatarBytes) {
    throw const FormatException('Avatar exceeds the 256 KiB limit.');
  }
  if (!AccountProfileLimits.supportedAvatarContentTypes.contains(contentType)) {
    throw const FormatException('Avatar content type is unsupported.');
  }
  final validSignature = switch (contentType) {
    'image/png' =>
      bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A,
    'image/jpeg' =>
      bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF,
    'image/webp' =>
      bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50,
    _ => false,
  };
  if (!validSignature) {
    throw const FormatException('Avatar bytes do not match the content type.');
  }
}

Uint8List? _readBytes(Object? value) {
  if (value == null) return null;
  if (value is Uint8List) {
    if (value.length > AccountProfileLimits.maxAvatarBytes) {
      throw const FormatException('Avatar exceeds the 256 KiB limit.');
    }
    return Uint8List.fromList(value);
  }
  if (value is List<int>) {
    if (value.length > AccountProfileLimits.maxAvatarBytes) {
      throw const FormatException('Avatar exceeds the 256 KiB limit.');
    }
    return Uint8List.fromList(value);
  }
  throw const FormatException('avatar_bytes must be binary data.');
}

String? _readOptionalString(Object? value, String field) {
  if (value == null || value is String) return value as String?;
  throw FormatException('$field must be a string.');
}

bool _containsControlCharacter(String value) {
  return value.runes.any((rune) => rune < 0x20 || rune == 0x7F);
}

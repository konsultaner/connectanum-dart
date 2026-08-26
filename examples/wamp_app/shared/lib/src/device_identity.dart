import 'dart:convert';

import 'account_registration.dart';

final class DeviceEnrollment {
  DeviceEnrollment({
    required this.deviceId,
    required String deviceName,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    required this.attestation,
    required DateTime createdAt,
  }) : deviceName = deviceName.trim(),
       createdAt = createdAt.toUtc() {
    validate();
  }

  static const attestationVersion = 'wampapp-device-v1';

  final String deviceId;
  final String deviceName;
  final String signingPublicKey;
  final String exchangePublicKey;
  final String attestation;
  final DateTime createdAt;

  void validate() {
    _validateBase64Url(deviceId, expectedBytes: 32, field: 'device_id');
    _validateDeviceName(deviceName);
    _validateBase64Url(
      signingPublicKey,
      expectedBytes: 32,
      field: 'signing_public_key',
    );
    _validateBase64Url(
      exchangePublicKey,
      expectedBytes: 32,
      field: 'exchange_public_key',
    );
    _validateBase64Url(attestation, expectedBytes: 64, field: 'attestation');
  }

  List<int> attestationPayload(String username) {
    validate();
    return attestationPayloadFor(
      username: username,
      deviceId: deviceId,
      deviceName: deviceName,
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
      createdAt: createdAt,
    );
  }

  static List<int> attestationPayloadFor({
    required String username,
    required String deviceId,
    required String deviceName,
    required String signingPublicKey,
    required String exchangePublicKey,
    required DateTime createdAt,
  }) {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    if (normalizedUsername.isEmpty) {
      throw const FormatException('Attestation username is required.');
    }
    final normalizedDeviceName = deviceName.trim();
    _validateBase64Url(deviceId, expectedBytes: 32, field: 'device_id');
    _validateDeviceName(normalizedDeviceName);
    _validateBase64Url(
      signingPublicKey,
      expectedBytes: 32,
      field: 'signing_public_key',
    );
    _validateBase64Url(
      exchangePublicKey,
      expectedBytes: 32,
      field: 'exchange_public_key',
    );
    return utf8.encode(
      <String>[
        attestationVersion,
        normalizedUsername,
        deviceId,
        normalizedDeviceName,
        signingPublicKey,
        exchangePublicKey,
        createdAt.toUtc().toIso8601String(),
      ].join('\n'),
    );
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'signing_public_key': signingPublicKey,
      'exchange_public_key': exchangePublicKey,
      'attestation': attestation,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DeviceEnrollment.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Device enrollment details are required.');
    }
    final createdAt = _readUtcDate(value['created_at'], 'created_at');
    return DeviceEnrollment(
      deviceId: _readString(value['device_id'], 'device_id'),
      deviceName: _readString(value['device_name'], 'device_name'),
      signingPublicKey: _readString(
        value['signing_public_key'],
        'signing_public_key',
      ),
      exchangePublicKey: _readString(
        value['exchange_public_key'],
        'exchange_public_key',
      ),
      attestation: _readString(value['attestation'], 'attestation'),
      createdAt: createdAt,
    );
  }
}

final class DeviceRecord {
  DeviceRecord({
    required String username,
    required this.enrollment,
    required DateTime enrolledAt,
    required DateTime lastSeenAt,
    DateTime? revokedAt,
  }) : username = AccountRegistration.normalizeUsername(username),
       enrolledAt = enrolledAt.toUtc(),
       lastSeenAt = lastSeenAt.toUtc(),
       revokedAt = revokedAt?.toUtc() {
    validate();
  }

  final String username;
  final DeviceEnrollment enrollment;
  final DateTime enrolledAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;

  String get deviceId => enrollment.deviceId;
  bool get isRevoked => revokedAt != null;

  void validate() {
    if (username.isEmpty) {
      throw const FormatException('Device username is required.');
    }
    enrollment.validate();
    if (lastSeenAt.isBefore(enrolledAt)) {
      throw const FormatException('Device last-seen time predates enrollment.');
    }
    if (revokedAt case final revoked? when revoked.isBefore(enrolledAt)) {
      throw const FormatException('Device revocation predates enrollment.');
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'username': username,
      ...enrollment.toWampKeywords(),
      'enrolled_at': enrolledAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
      if (revokedAt != null) 'revoked_at': revokedAt!.toIso8601String(),
    };
  }

  factory DeviceRecord.fromWampKeywords(Map<String, dynamic> value) {
    return DeviceRecord(
      username: _readString(value['username'], 'username'),
      enrollment: DeviceEnrollment.fromWampKeywords(value),
      enrolledAt: _readUtcDate(value['enrolled_at'], 'enrolled_at'),
      lastSeenAt: _readUtcDate(value['last_seen_at'], 'last_seen_at'),
      revokedAt: value['revoked_at'] == null
          ? null
          : _readUtcDate(value['revoked_at'], 'revoked_at'),
    );
  }
}

final class DeviceDirectory {
  DeviceDirectory(Iterable<DeviceRecord> devices)
    : devices = List<DeviceRecord>.unmodifiable(devices);

  final List<DeviceRecord> devices;

  Map<String, dynamic> toWampKeywords() => {
    'devices': devices.map((device) => device.toWampKeywords()).toList(),
  };

  factory DeviceDirectory.fromWampKeywords(Map<String, dynamic>? value) {
    final rawDevices = value?['devices'];
    if (rawDevices is! List) {
      throw const FormatException('Device directory must contain a list.');
    }
    return DeviceDirectory(
      rawDevices.map((rawDevice) {
        if (rawDevice is! Map) {
          throw const FormatException('Device directory entry must be a map.');
        }
        return DeviceRecord.fromWampKeywords(
          rawDevice.map((key, value) => MapEntry(key.toString(), value)),
        );
      }),
    );
  }
}

final class WrappedConversationKey {
  WrappedConversationKey({
    required this.conversationId,
    required String senderUsername,
    required this.senderDeviceId,
    required String recipientUsername,
    required this.recipientDeviceId,
    required this.sealedKey,
    required this.signature,
    required DateTime createdAt,
  }) : senderUsername = AccountRegistration.normalizeUsername(senderUsername),
       recipientUsername = AccountRegistration.normalizeUsername(
         recipientUsername,
       ),
       createdAt = createdAt.toUtc() {
    validate();
  }

  static const envelopeVersion = 'wampapp-conversation-key-v1';
  static const algorithm = 'x25519-xsalsa20poly1305-sealedbox';

  final String conversationId;
  final String senderUsername;
  final String senderDeviceId;
  final String recipientUsername;
  final String recipientDeviceId;
  final String sealedKey;
  final String signature;
  final DateTime createdAt;

  void validate() {
    signaturePayloadFor(
      conversationId: conversationId,
      senderUsername: senderUsername,
      senderDeviceId: senderDeviceId,
      recipientUsername: recipientUsername,
      recipientDeviceId: recipientDeviceId,
      sealedKey: sealedKey,
      createdAt: createdAt,
    );
    _validateBase64Url(signature, expectedBytes: 64, field: 'signature');
  }

  List<int> signaturePayload() {
    validate();
    return signaturePayloadFor(
      conversationId: conversationId,
      senderUsername: senderUsername,
      senderDeviceId: senderDeviceId,
      recipientUsername: recipientUsername,
      recipientDeviceId: recipientDeviceId,
      sealedKey: sealedKey,
      createdAt: createdAt,
    );
  }

  static List<int> signaturePayloadFor({
    required String conversationId,
    required String senderUsername,
    required String senderDeviceId,
    required String recipientUsername,
    required String recipientDeviceId,
    required String sealedKey,
    required DateTime createdAt,
  }) {
    final normalizedSender = AccountRegistration.normalizeUsername(
      senderUsername,
    );
    final normalizedRecipient = AccountRegistration.normalizeUsername(
      recipientUsername,
    );
    if (conversationId.isEmpty || conversationId.length > 200) {
      throw const FormatException('Conversation identifier is invalid.');
    }
    if (normalizedSender.isEmpty || normalizedRecipient.isEmpty) {
      throw const FormatException('Conversation-key usernames are required.');
    }
    _validateBase64Url(
      senderDeviceId,
      expectedBytes: 32,
      field: 'sender_device_id',
    );
    _validateBase64Url(
      recipientDeviceId,
      expectedBytes: 32,
      field: 'recipient_device_id',
    );
    _validateBase64UrlRange(
      sealedKey,
      minBytes: 80,
      maxBytes: 4096,
      field: 'sealed_key',
    );
    return utf8.encode(
      <String>[
        envelopeVersion,
        algorithm,
        conversationId,
        normalizedSender,
        senderDeviceId,
        normalizedRecipient,
        recipientDeviceId,
        sealedKey,
        createdAt.toUtc().toIso8601String(),
      ].join('\n'),
    );
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'version': envelopeVersion,
      'algorithm': algorithm,
      'conversation_id': conversationId,
      'sender_username': senderUsername,
      'sender_device_id': senderDeviceId,
      'recipient_username': recipientUsername,
      'recipient_device_id': recipientDeviceId,
      'sealed_key': sealedKey,
      'signature': signature,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory WrappedConversationKey.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null ||
        value['version'] != envelopeVersion ||
        value['algorithm'] != algorithm) {
      throw const FormatException('Unsupported conversation-key envelope.');
    }
    return WrappedConversationKey(
      conversationId: _readString(value['conversation_id'], 'conversation_id'),
      senderUsername: _readString(value['sender_username'], 'sender_username'),
      senderDeviceId: _readString(
        value['sender_device_id'],
        'sender_device_id',
      ),
      recipientUsername: _readString(
        value['recipient_username'],
        'recipient_username',
      ),
      recipientDeviceId: _readString(
        value['recipient_device_id'],
        'recipient_device_id',
      ),
      sealedKey: _readString(value['sealed_key'], 'sealed_key'),
      signature: _readString(value['signature'], 'signature'),
      createdAt: _readUtcDate(value['created_at'], 'created_at'),
    );
  }
}

String _readString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

DateTime _readUtcDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be an explicit UTC timestamp.');
  }
  return parsed.toUtc();
}

void _validateDeviceName(String value) {
  if (value.isEmpty ||
      value.length > 80 ||
      value.runes.any((rune) => rune < 32)) {
    throw const FormatException('Device names need 1-80 printable characters.');
  }
}

void _validateBase64Url(
  String value, {
  required int expectedBytes,
  required String field,
}) {
  final decoded = _decodeBase64Url(value, field);
  if (decoded.length != expectedBytes) {
    throw FormatException('$field has an invalid byte length.');
  }
}

void _validateBase64UrlRange(
  String value, {
  required int minBytes,
  required int maxBytes,
  required String field,
}) {
  final decoded = _decodeBase64Url(value, field);
  if (decoded.length < minBytes || decoded.length > maxBytes) {
    throw FormatException('$field has an invalid byte length.');
  }
}

List<int> _decodeBase64Url(String value, String field) {
  if (value.isEmpty ||
      value.contains('=') ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw FormatException('$field must use unpadded base64url.');
  }
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  try {
    final decoded = base64Url.decode(padded);
    if (base64Url.encode(decoded).replaceAll('=', '') != value) {
      throw const FormatException();
    }
    return decoded;
  } on FormatException {
    throw FormatException('$field must use canonical base64url.');
  }
}

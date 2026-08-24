import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as x;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class LocalDeviceIdentity {
  LocalDeviceIdentity._({
    required Uint8List signingSeed,
    required Uint8List exchangePrivateKey,
    required String deviceName,
    required DateTime createdAt,
  }) : _signingSeed = Uint8List.fromList(signingSeed),
       _exchangePrivateKey = Uint8List.fromList(exchangePrivateKey),
       deviceName = deviceName.trim(),
       createdAt = createdAt.toUtc() {
    if (this.deviceName.isEmpty || this.deviceName.length > 80) {
      throw const FormatException('Device name is invalid.');
    }
    final signingKey = ed.SigningKey.fromSeed(_signingSeed);
    final exchangeKey = x.PrivateKey(_exchangePrivateKey);
    signingPublicKey = _encode(signingKey.verifyKey.asTypedList);
    exchangePublicKey = _encode(exchangeKey.publicKey.asTypedList);
    deviceId = _encode(
      sha256.convert([
        ...signingKey.verifyKey.asTypedList,
        ...exchangeKey.publicKey.asTypedList,
      ]).bytes,
    );
  }

  factory LocalDeviceIdentity.generate({
    required String deviceName,
    DateTime? now,
  }) {
    final random = Random.secure();
    final signingSeed = Uint8List.fromList(
      List<int>.generate(ed.SigningKey.seedSize, (_) => random.nextInt(256)),
    );
    final exchangePrivateKey = Uint8List.fromList(
      List<int>.generate(x.PrivateKey.keyLength, (_) => random.nextInt(256)),
    );
    final identity = LocalDeviceIdentity._(
      signingSeed: signingSeed,
      exchangePrivateKey: exchangePrivateKey,
      deviceName: deviceName,
      createdAt: now ?? DateTime.now(),
    );
    signingSeed.fillRange(0, signingSeed.length, 0);
    exchangePrivateKey.fillRange(0, exchangePrivateKey.length, 0);
    return identity;
  }

  factory LocalDeviceIdentity.fromJson(Map<String, dynamic> value) {
    final deviceName = value['device_name'];
    final createdAt = DateTime.tryParse(value['created_at'] as String? ?? '');
    if (deviceName is! String || createdAt == null || !createdAt.isUtc) {
      throw const FormatException('Encrypted device identity is invalid.');
    }
    Uint8List? signingSeed;
    Uint8List? exchangePrivateKey;
    try {
      signingSeed = _decode(
        value['signing_seed'],
        'signing_seed',
        expectedBytes: ed.SigningKey.seedSize,
      );
      exchangePrivateKey = _decode(
        value['exchange_private_key'],
        'exchange_private_key',
        expectedBytes: x.PrivateKey.keyLength,
      );
      return LocalDeviceIdentity._(
        signingSeed: signingSeed,
        exchangePrivateKey: exchangePrivateKey,
        deviceName: deviceName,
        createdAt: createdAt,
      );
    } finally {
      signingSeed?.fillRange(0, signingSeed.length, 0);
      exchangePrivateKey?.fillRange(0, exchangePrivateKey.length, 0);
    }
  }

  final Uint8List _signingSeed;
  final Uint8List _exchangePrivateKey;
  final String deviceName;
  final DateTime createdAt;
  late final String signingPublicKey;
  late final String exchangePublicKey;
  late final String deviceId;
  bool _disposed = false;

  DeviceEnrollment enrollment(String username) {
    _ensureActive();
    final payload = DeviceEnrollment.attestationPayloadFor(
      username: username,
      deviceId: deviceId,
      deviceName: deviceName,
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
      createdAt: createdAt,
    );
    final signature = ed.SigningKey.fromSeed(_signingSeed)
        .sign(Uint8List.fromList(payload))
        .signature
        .asTypedList;
    return DeviceEnrollment(
      deviceId: deviceId,
      deviceName: deviceName,
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
      attestation: _encode(signature),
      createdAt: createdAt,
    );
  }

  String safetyNumberFor({
    required String username,
    required DeviceRecord contact,
  }) {
    _ensureActive();
    contact.validate();
    final local =
        '${AccountRegistration.normalizeUsername(username)}:'
        '$deviceId:$signingPublicKey:$exchangePublicKey';
    final remote =
        '${contact.username}:${contact.deviceId}:'
        '${contact.enrollment.signingPublicKey}:'
        '${contact.enrollment.exchangePublicKey}';
    final identities = [local, remote]..sort();
    final digest = sha256.convert(
      utf8.encode(['wampapp-safety-v1', ...identities].join('\n')),
    );
    return _groupFingerprint(digest.bytes);
  }

  String get ownSafetyNumber {
    _ensureActive();
    return _groupFingerprint(
      sha256
          .convert(
            utf8.encode(
              'wampapp-device-safety-v1\n$deviceId\n$signingPublicKey\n'
              '$exchangePublicKey',
            ),
          )
          .bytes,
    );
  }

  WrappedConversationKey wrapConversationKey({
    required String username,
    required String conversationId,
    required DeviceRecord recipient,
    required Uint8List conversationKey,
    DateTime? now,
  }) {
    _ensureActive();
    recipient.validate();
    if (recipient.isRevoked) {
      throw const FormatException('Cannot encrypt for a revoked device.');
    }
    if (conversationKey.length != 32) {
      throw const FormatException('Conversation keys must contain 32 bytes.');
    }
    final keyCopy = Uint8List.fromList(conversationKey);
    late final Uint8List sealed;
    try {
      sealed = x.SealedBox(
        x.PublicKey(
          _decode(
            recipient.enrollment.exchangePublicKey,
            'exchange_public_key',
            expectedBytes: x.PublicKey.keyLength,
          ),
        ),
      ).encrypt(keyCopy);
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
    final createdAt = (now ?? DateTime.now()).toUtc();
    final sealedKey = _encode(sealed);
    final payload = WrappedConversationKey.signaturePayloadFor(
      conversationId: conversationId,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedKey: sealedKey,
      createdAt: createdAt,
    );
    final signature = ed.SigningKey.fromSeed(_signingSeed)
        .sign(Uint8List.fromList(payload))
        .signature
        .asTypedList;
    return WrappedConversationKey(
      conversationId: conversationId,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedKey: sealedKey,
      signature: _encode(signature),
      createdAt: createdAt,
    );
  }

  OneTimeMessageConsumption signOneTimeConsumption({
    required String username,
    required String messageId,
  }) {
    _ensureActive();
    final payload = OneTimeMessageConsumption.signaturePayloadFor(
      username: username,
      messageId: messageId,
      deviceId: deviceId,
    );
    final signature = ed.SigningKey.fromSeed(_signingSeed)
        .sign(Uint8List.fromList(payload))
        .signature
        .asTypedList;
    return OneTimeMessageConsumption(
      messageId: messageId,
      deviceId: deviceId,
      signature: _encode(signature),
    );
  }

  Uint8List unwrapConversationKey({
    required String username,
    required WrappedConversationKey envelope,
    required DeviceRecord sender,
    bool allowRevokedSender = false,
  }) {
    _ensureActive();
    envelope.validate();
    sender.validate();
    if (sender.isRevoked && !allowRevokedSender) {
      throw const FormatException(
        'Conversation key came from a revoked device.',
      );
    }
    if (envelope.senderUsername != sender.username ||
        envelope.senderDeviceId != sender.deviceId ||
        envelope.recipientUsername !=
            AccountRegistration.normalizeUsername(username) ||
        envelope.recipientDeviceId != deviceId) {
      throw const FormatException('Conversation-key identities do not match.');
    }
    try {
      ed.VerifyKey(
        _decode(
          sender.enrollment.signingPublicKey,
          'signing_public_key',
          expectedBytes: ed.VerifyKey.keyLength,
        ),
      ).verify(
        signature: ed.Signature(
          _decode(
            envelope.signature,
            'signature',
            expectedBytes: ed.Signature.signatureLength,
          ),
        ),
        message: Uint8List.fromList(envelope.signaturePayload()),
      );
    } catch (_) {
      throw const FormatException('Conversation-key signature is invalid.');
    }

    late final Uint8List plaintext;
    try {
      plaintext = x.SealedBox(x.PrivateKey(_exchangePrivateKey)).decrypt(
        _decodeRange(
          envelope.sealedKey,
          'sealed_key',
          minBytes: 80,
          maxBytes: 4096,
        ),
      );
    } catch (_) {
      throw const FormatException('Conversation-key envelope is invalid.');
    }
    if (plaintext.length != 32) {
      plaintext.fillRange(0, plaintext.length, 0);
      throw const FormatException('Conversation key has an invalid length.');
    }
    return plaintext;
  }

  Map<String, dynamic> toJson() {
    _ensureActive();
    return {
      'signing_seed': _encode(_signingSeed),
      'exchange_private_key': _encode(_exchangePrivateKey),
      'device_name': deviceName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _signingSeed.fillRange(0, _signingSeed.length, 0);
    _exchangePrivateKey.fillRange(0, _exchangePrivateKey.length, 0);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Device identity has been disposed.');
  }
}

Uint8List _decode(Object? value, String field, {required int expectedBytes}) {
  final decoded = _decodeRange(
    value,
    field,
    minBytes: expectedBytes,
    maxBytes: expectedBytes,
  );
  return decoded;
}

Uint8List _decodeRange(
  Object? value,
  String field, {
  required int minBytes,
  required int maxBytes,
}) {
  if (value is! String || value.isEmpty || value.contains('=')) {
    throw FormatException('$field must use unpadded base64url.');
  }
  try {
    final bytes = base64Url.decode(
      value.padRight((value.length + 3) ~/ 4 * 4, '='),
    );
    if (bytes.length < minBytes ||
        bytes.length > maxBytes ||
        _encode(bytes) != value) {
      throw const FormatException();
    }
    return bytes;
  } on FormatException {
    throw FormatException('$field is invalid.');
  }
}

String _encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');

String _groupFingerprint(List<int> bytes) {
  final digits = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return List<String>.generate((digits.length / 4).ceil(), (index) {
    final start = index * 4;
    final end = (start + 4).clamp(0, digits.length);
    return digits.substring(start, end);
  }).join(' ');
}

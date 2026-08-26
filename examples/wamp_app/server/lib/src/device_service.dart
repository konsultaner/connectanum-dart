import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';

class DeviceService {
  const DeviceService({required this.store});

  final AccountStore store;

  Future<DeviceRecord> enroll(
    String username,
    DeviceEnrollment enrollment, {
    DateTime? now,
  }) async {
    enrollment.validate();
    final signingPublicKey = _decodeKey(
      enrollment.signingPublicKey,
      'signing_public_key',
    );
    final exchangePublicKey = _decodeKey(
      enrollment.exchangePublicKey,
      'exchange_public_key',
    );
    final expectedDeviceId = _encode(
      sha256.convert([...signingPublicKey, ...exchangePublicKey]).bytes,
    );
    if (enrollment.deviceId != expectedDeviceId) {
      throw const FormatException(
        'Device identifier does not match its public keys.',
      );
    }

    final signature = _decode(
      enrollment.attestation,
      'attestation',
      expectedBytes: Signature.signatureLength,
    );
    try {
      VerifyKey(signingPublicKey).verify(
        signature: Signature(signature),
        message: Uint8List.fromList(enrollment.attestationPayload(username)),
      );
    } catch (_) {
      throw const FormatException('Device attestation is invalid.');
    }
    return store.enrollDevice(username, enrollment, now: now);
  }

  Future<DeviceDirectory> list(
    String username, {
    bool includeRevoked = false,
  }) async {
    return DeviceDirectory(
      await store.listDevices(username, includeRevoked: includeRevoked),
    );
  }

  Future<DeviceRecord> revoke(
    String username,
    String deviceId, {
    DateTime? now,
  }) {
    _decodeKey(deviceId, 'device_id');
    return store.revokeDevice(username, deviceId, now: now);
  }
}

Uint8List _decodeKey(String value, String field) {
  return _decode(value, field, expectedBytes: 32);
}

Uint8List _decode(String value, String field, {required int expectedBytes}) {
  if (value.isEmpty || value.contains('=')) {
    throw FormatException('$field must use unpadded base64url.');
  }
  try {
    final bytes = base64Url.decode(
      value.padRight((value.length + 3) ~/ 4 * 4, '='),
    );
    if (bytes.length != expectedBytes || _encode(bytes) != value) {
      throw const FormatException();
    }
    return bytes;
  } on FormatException {
    throw FormatException('$field is invalid.');
  }
}

String _encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');

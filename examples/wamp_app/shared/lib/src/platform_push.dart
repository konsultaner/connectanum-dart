import 'dart:convert';

final class PlatformPushSubscriptionRequest {
  PlatformPushSubscriptionRequest({
    required this.deviceId,
    required String provider,
    required this.token,
  }) : provider = provider.trim().toLowerCase() {
    validate();
  }

  static const maxProviderLength = 32;
  static const maxTokenLength = 4096;

  final String deviceId;
  final String provider;
  final String token;

  void validate() {
    _validateDeviceId(deviceId);
    if (provider.isEmpty ||
        provider.length > maxProviderLength ||
        !RegExp(r'^[a-z][a-z0-9._-]*$').hasMatch(provider)) {
      throw const FormatException('Push provider is invalid.');
    }
    if (token.isEmpty || token.length > maxTokenLength) {
      throw const FormatException('Push token is invalid.');
    }
    for (final codeUnit in token.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7e) {
        throw const FormatException('Push token is invalid.');
      }
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {'device_id': deviceId, 'provider': provider, 'token': token};
  }

  factory PlatformPushSubscriptionRequest.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null) {
      throw const FormatException('Push subscription details are required.');
    }
    return PlatformPushSubscriptionRequest(
      deviceId: _readString(value['device_id'], 'device_id'),
      provider: _readString(value['provider'], 'provider'),
      token: _readString(value['token'], 'token'),
    );
  }
}

final class PlatformPushSubscriptionKey {
  PlatformPushSubscriptionKey({
    required this.deviceId,
    required String provider,
  }) : provider = provider.trim().toLowerCase() {
    validate();
  }

  final String deviceId;
  final String provider;

  void validate() {
    _validateDeviceId(deviceId);
    if (provider.isEmpty ||
        provider.length > PlatformPushSubscriptionRequest.maxProviderLength ||
        !RegExp(r'^[a-z][a-z0-9._-]*$').hasMatch(provider)) {
      throw const FormatException('Push provider is invalid.');
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {'device_id': deviceId, 'provider': provider};
  }

  factory PlatformPushSubscriptionKey.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null) {
      throw const FormatException('Push subscription key is required.');
    }
    return PlatformPushSubscriptionKey(
      deviceId: _readString(value['device_id'], 'device_id'),
      provider: _readString(value['provider'], 'provider'),
    );
  }
}

final class PlatformPushSubscriptionReceipt {
  PlatformPushSubscriptionReceipt({
    required this.deviceId,
    required String provider,
    required DateTime registeredAt,
    required DateTime updatedAt,
  }) : provider = provider.trim().toLowerCase(),
       registeredAt = registeredAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    validate();
  }

  final String deviceId;
  final String provider;
  final DateTime registeredAt;
  final DateTime updatedAt;

  void validate() {
    PlatformPushSubscriptionKey(
      deviceId: deviceId,
      provider: provider,
    ).validate();
    if (updatedAt.isBefore(registeredAt)) {
      throw const FormatException('Push update predates registration.');
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'device_id': deviceId,
      'provider': provider,
      'registered_at': registeredAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PlatformPushSubscriptionReceipt.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null) {
      throw const FormatException('Push subscription receipt is required.');
    }
    return PlatformPushSubscriptionReceipt(
      deviceId: _readString(value['device_id'], 'device_id'),
      provider: _readString(value['provider'], 'provider'),
      registeredAt: _readDate(value['registered_at'], 'registered_at'),
      updatedAt: _readDate(value['updated_at'], 'updated_at'),
    );
  }
}

void _validateDeviceId(String value) {
  try {
    final padding = '=' * ((4 - value.length % 4) % 4);
    final decoded = base64Url.decode('$value$padding');
    if (decoded.length != 32 || value.contains('=')) {
      throw const FormatException('Push device identifier is invalid.');
    }
  } on FormatException {
    throw const FormatException('Push device identifier is invalid.');
  }
}

String _readString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

DateTime _readDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be a UTC ISO-8601 string.');
  }
  return parsed;
}

import 'dart:convert';

final class PlatformPushSubscriptionRequest {
  PlatformPushSubscriptionRequest({
    required this.deviceId,
    required String provider,
    required this.token,
    Iterable<String> mutedConversationIds = const [],
  }) : provider = provider.trim().toLowerCase(),
       mutedConversationIds = _normalizeMutedConversationIds(
         mutedConversationIds,
       ) {
    validate();
  }

  static const maxProviderLength = 32;
  static const maxTokenLength = 4096;
  static const maxMutedConversations = 500;
  static const maxConversationIdLength = 200;

  final String deviceId;
  final String provider;
  final String token;
  final List<String> mutedConversationIds;

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
    return {
      'device_id': deviceId,
      'provider': provider,
      'token': token,
      'muted_conversation_ids': mutedConversationIds,
    };
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
      mutedConversationIds: _readMutedConversationIds(
        value['muted_conversation_ids'],
      ),
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

List<String> _readMutedConversationIds(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('muted_conversation_ids must be a list.');
  }
  return value
      .map((item) {
        if (item is! String) {
          throw const FormatException(
            'Muted conversation identifiers must be strings.',
          );
        }
        return item;
      })
      .toList(growable: false);
}

List<String> _normalizeMutedConversationIds(Iterable<String> values) {
  final result = values.toList(growable: false);
  if (result.length > PlatformPushSubscriptionRequest.maxMutedConversations) {
    throw const FormatException('Too many muted conversations are registered.');
  }
  final unique = result.toSet();
  if (unique.length != result.length) {
    throw const FormatException(
      'Muted conversation identifiers must be unique.',
    );
  }
  for (final conversationId in result) {
    if (conversationId.isEmpty ||
        conversationId.length >
            PlatformPushSubscriptionRequest.maxConversationIdLength) {
      throw const FormatException(
        'A muted conversation identifier is invalid.',
      );
    }
  }
  result.sort();
  return List<String>.unmodifiable(result);
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

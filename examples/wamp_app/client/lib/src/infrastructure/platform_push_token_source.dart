import 'dart:async';

import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class PlatformPushToken {
  const PlatformPushToken({required this.provider, required this.token});

  final String provider;
  final String token;

  void validate() {
    if (provider.isEmpty ||
        provider != provider.trim().toLowerCase() ||
        provider.length > PlatformPushSubscriptionRequest.maxProviderLength ||
        !RegExp(r'^[a-z][a-z0-9._-]*$').hasMatch(provider)) {
      throw const FormatException('Push provider is invalid.');
    }
    if (token.isEmpty ||
        token.length > PlatformPushSubscriptionRequest.maxTokenLength) {
      throw const FormatException('Push token is invalid.');
    }
    for (final codeUnit in token.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7e) {
        throw const FormatException('Push token is invalid.');
      }
    }
  }
}

abstract interface class PlatformPushTokenSession {
  Stream<PlatformPushToken> get tokens;

  Future<void> close();
}

abstract interface class PlatformPushTokenSource {
  Future<PlatformPushTokenSession?> open();

  Future<void> dispose();
}

final class PlatformPushTokenSourceException implements Exception {
  const PlatformPushTokenSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class UnavailablePlatformPushTokenSource
    implements PlatformPushTokenSource {
  const UnavailablePlatformPushTokenSource([
    this.message = 'Push is unavailable.',
  ]);

  final String message;

  @override
  Future<PlatformPushTokenSession?> open() =>
      Future.error(PlatformPushTokenSourceException(message));

  @override
  Future<void> dispose() async {}
}

final class DisabledPlatformPushTokenSource implements PlatformPushTokenSource {
  const DisabledPlatformPushTokenSource();

  @override
  Future<PlatformPushTokenSession?> open() async => null;

  @override
  Future<void> dispose() async {}
}

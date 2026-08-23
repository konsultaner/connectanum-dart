import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart';

import '../abstract_transport.dart';

class NativeRawSocketTransport extends AbstractTransport
    implements FileSegmentTransport, DrainableTransport {
  NativeRawSocketTransport(
    String host,
    int port,
    AbstractSerializer serializer,
    int serializerType, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = 24,
    String? libraryPath,
  }) {
    throw UnsupportedError('Native transports require dart:io.');
  }

  factory NativeRawSocketTransport.withJsonSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = 24,
    String? libraryPath,
  }) => throw UnsupportedError('Native transports require dart:io.');

  factory NativeRawSocketTransport.withMsgpackSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = 24,
    String? libraryPath,
  }) => throw UnsupportedError('Native transports require dart:io.');

  factory NativeRawSocketTransport.withCborSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = 24,
    String? libraryPath,
  }) => throw UnsupportedError('Native transports require dart:io.');

  @override
  Completer? get onDisconnect => null;

  @override
  Completer? get onConnectionLost => null;

  @override
  bool get isOpen => false;

  @override
  bool get isReady => false;

  bool get isUpgradedProtocol => false;

  int get headerLength => 4;

  int? get maxMessageLength => 1 << 24;

  @override
  bool get supportsFileSegments => false;

  @override
  TransportFileSource openFileSegmentSource(String path, int expectedLength) {
    throw UnsupportedError('Native transports require dart:io.');
  }

  @override
  void sendFileSegment(
    AbstractMessage message, {
    required TransportFileSource source,
    required int offset,
    required int length,
  }) {
    throw UnsupportedError('Native transports require dart:io.');
  }

  @override
  Future<void> get onReady =>
      Future.error(UnsupportedError('Native transports require dart:io.'));

  @override
  Future<void>? open({Duration? pingInterval}) =>
      Future.error(UnsupportedError('Native transports require dart:io.'));

  @override
  Future<void>? close({error}) =>
      Future.error(UnsupportedError('Native transports require dart:io.'));

  @override
  Stream<AbstractMessage?>? receive() =>
      Stream.error(UnsupportedError('Native transports require dart:io.'));

  @override
  void send(AbstractMessage message) {
    throw UnsupportedError('Native transports require dart:io.');
  }

  @override
  Future<void> drain() => Future<void>.delayed(Duration.zero);
}

class NativeWebSocketTransport extends AbstractTransport
    implements DrainableTransport {
  NativeWebSocketTransport(
    String url,
    AbstractSerializer serializer,
    String serializerType, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) {
    throw UnsupportedError('Native transports require dart:io.');
  }

  factory NativeWebSocketTransport.withJsonSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) => throw UnsupportedError('Native transports require dart:io.');

  factory NativeWebSocketTransport.withMsgpackSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) => throw UnsupportedError('Native transports require dart:io.');

  factory NativeWebSocketTransport.withCborSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) => throw UnsupportedError('Native transports require dart:io.');

  @override
  Completer? get onDisconnect => null;

  @override
  Completer? get onConnectionLost => null;

  @override
  bool get isOpen => false;

  @override
  bool get isReady => false;

  @override
  Future<void> get onReady =>
      Future.error(UnsupportedError('Native transports require dart:io.'));

  @override
  Future<void>? open({Duration? pingInterval}) =>
      Future.error(UnsupportedError('Native transports require dart:io.'));

  @override
  Future<void>? close({error}) =>
      Future.error(UnsupportedError('Native transports require dart:io.'));

  @override
  Stream<AbstractMessage?>? receive() =>
      Stream.error(UnsupportedError('Native transports require dart:io.'));

  @override
  void send(AbstractMessage message) {
    throw UnsupportedError('Native transports require dart:io.');
  }

  @override
  Future<void> drain() => Future<void>.delayed(Duration.zero);
}

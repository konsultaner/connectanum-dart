import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart';

import 'native/e2ee_file_segment.dart';

abstract class AbstractTransport {
  // make it possible to have a connection state in the transport
  Completer? get onDisconnect;
  Completer? get onConnectionLost;
  Stream<AbstractMessage?>? receive();
  Future<void>? open({Duration? pingInterval});
  Future<void>? close({dynamic error});
  Future<void> get onReady;
  bool get isOpen;
  bool get isReady;
  void send(AbstractMessage message);

  /// for internal use only
  /// is called to complete the private underlying [onDisconnect] with a void or an error
  void complete(Completer? onDisconnectCompleter, error) {
    if (onDisconnectCompleter != null && !onDisconnectCompleter.isCompleted) {
      if (error != null) {
        onDisconnectCompleter.complete();
      } else {
        onDisconnectCompleter.complete(error);
      }
    }
  }
}

/// An opened file source retained by a transport for file-backed frame sends.
abstract interface class TransportFileSource {
  void close();
}

/// Optional transport capability for file-backed WAMP message payloads.
abstract interface class FileSegmentTransport {
  bool get supportsFileSegments;

  TransportFileSource openFileSegmentSource(String path, int expectedLength);

  void sendFileSegment(
    AbstractMessage message, {
    required TransportFileSource source,
    required int offset,
    required int length,
  });
}

abstract interface class NativeE2eeFileSegmentTransport
    implements FileSegmentTransport {
  void sendNativeE2eeFileSegment(
    AbstractMessage message, {
    required TransportFileSource source,
    required int offset,
    required int length,
    required NativeE2eeFileSegmentContext e2ee,
  });
}

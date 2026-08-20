import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:crypto/crypto.dart';

import '../protocol/session.dart';

/// Metadata key used by the Connectanum progressive file-transfer contract.
const String wampFileMetadataKey = 'x_connectanum_file';

/// Versioned metadata for a progressive WAMP file transfer.
class WampFileMetadata {
  WampFileMetadata({
    required this.name,
    required this.size,
    required this.chunkSize,
    this.contentType,
    this.sha256Digest,
    Map<String, dynamic>? custom,
  }) : custom = Map<String, dynamic>.unmodifiable(
         custom ?? const <String, dynamic>{},
       ) {
    _validate();
  }

  factory WampFileMetadata.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported file metadata version');
    }
    final custom = json['custom'];
    if (custom != null && custom is! Map) {
      throw const FormatException('File metadata custom must be an object');
    }
    return WampFileMetadata(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? -1,
      chunkSize: json['chunk_size'] as int? ?? -1,
      contentType: json['content_type'] as String?,
      sha256Digest: json['sha256'] as String?,
      custom: custom == null ? null : Map<String, dynamic>.from(custom as Map),
    );
  }

  final String name;
  final int size;
  final int chunkSize;
  final String? contentType;
  final String? sha256Digest;
  final Map<String, dynamic> custom;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': 1,
      'name': name,
      'size': size,
      'chunk_size': chunkSize,
      if (contentType != null) 'content_type': contentType,
      if (sha256Digest != null) 'sha256': sha256Digest!.toLowerCase(),
      if (custom.isNotEmpty) 'custom': custom,
    };
  }

  void _validate() {
    if (name.isEmpty || name.length > 1024 || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', 'must be 1-1024 safe chars');
    }
    if (size < 0) {
      throw RangeError.value(size, 'size', 'must be >= 0');
    }
    if (chunkSize <= 0) {
      throw RangeError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    final type = contentType;
    if (type != null && (type.isEmpty || type.length > 255)) {
      throw ArgumentError.value(
        type,
        'contentType',
        'must be 1-255 chars when set',
      );
    }
    final digest = sha256Digest;
    if (digest != null && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest)) {
      throw ArgumentError.value(
        digest,
        'sha256Digest',
        'must be a 64-character hexadecimal SHA-256 digest',
      );
    }
  }
}

/// Re-openable byte source used by [WampFileSession.setFile].
class WampFileSource {
  WampFileSource({
    required this.name,
    required this.length,
    required this.openRead,
    this.contentType,
    this.sha256Digest,
    this.nativePath,
    Map<String, dynamic>? custom,
  }) : custom = Map<String, dynamic>.unmodifiable(
         custom ?? const <String, dynamic>{},
       );

  factory WampFileSource.bytes(
    Uint8List bytes, {
    required String name,
    String? contentType,
    String? sha256Digest,
    Map<String, dynamic>? custom,
  }) {
    return WampFileSource(
      name: name,
      length: bytes.length,
      openRead: () => Stream<Uint8List>.value(bytes),
      contentType: contentType,
      sha256Digest: sha256Digest,
      custom: custom,
    );
  }

  final String name;
  final int length;
  final Stream<Uint8List> Function() openRead;
  final String? contentType;
  final String? sha256Digest;
  final String? nativePath;
  final Map<String, dynamic> custom;
}

/// Immutable completion information supplied to [WampFileSink.close].
class WampFileReceipt {
  const WampFileReceipt({
    required this.metadata,
    required this.receivedBytes,
    required this.sha256Digest,
  });

  final WampFileMetadata metadata;
  final int receivedBytes;
  final String sha256Digest;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': metadata.name,
      'size': receivedBytes,
      'sha256': sha256Digest,
    };
  }
}

/// Backpressure-aware destination for incoming file chunks.
abstract class WampFileSink {
  FutureOr<void> add(Uint8List chunk);

  FutureOr<Map<String, dynamic>?> close(WampFileReceipt receipt);

  /// May run concurrently with an in-flight [add] to unblock failed transfers.
  FutureOr<void> abort(Object error) {}
}

typedef WampFileSinkFactory =
    FutureOr<WampFileSink> Function(WampFileMetadata metadata);

/// Local validation or source-stream failure while sending a file.
class WampFileTransferException implements Exception {
  const WampFileTransferException(this.message);

  final String message;

  @override
  String toString() => 'WampFileTransferException: $message';
}

/// High-level progressive file delivery for an established WAMP session.
extension WampFileSession on Session {
  Future<Result> setFile(
    String procedure,
    WampFileSource source, {
    int chunkSize = 256 * 1024,
    Duration timeout = const Duration(minutes: 5),
    CallOptions? options,
  }) async {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
    final metadata = WampFileMetadata(
      name: source.name,
      size: source.length,
      chunkSize: chunkSize,
      contentType: source.contentType,
      sha256Digest: source.sha256Digest,
      custom: source.custom,
    );
    final cancel = Completer<String>();
    final call = startProgressiveCall(
      procedure,
      argumentsKeywords: <String, dynamic>{
        wampFileMetadataKey: metadata.toJson(),
      },
      options: _fileCallOptions(options, timeout),
      cancelCompleter: cancel,
      enableFileSegments: source.nativePath != null,
    );
    final finalResult = call.results.firstWhere(
      (result) => !result.isProgressive(),
    );

    var sentBytes = 0;
    Uint8List? pending;
    try {
      final nativePath = source.nativePath;
      if (nativePath != null &&
          source.length > 0 &&
          call.supportsFileSegments) {
        final nativeSource = call.openFileSource(nativePath, source.length);
        try {
          var offset = 0;
          while (offset < source.length) {
            final remaining = source.length - offset;
            final length = remaining < chunkSize ? remaining : chunkSize;
            if (offset + length == source.length) {
              call.finishFileSegment(
                nativeSource,
                offset: offset,
                length: length,
              );
            } else {
              call.sendFileSegment(
                nativeSource,
                offset: offset,
                length: length,
              );
            }
            offset += length;
          }
        } finally {
          nativeSource.close();
        }
        return await finalResult;
      }
      await for (final sourceChunk in source.openRead()) {
        var offset = 0;
        while (offset < sourceChunk.length) {
          final end = (offset + chunkSize).clamp(0, sourceChunk.length);
          final chunk = offset == 0 && end == sourceChunk.length
              ? sourceChunk
              : Uint8List.sublistView(sourceChunk, offset, end);
          sentBytes += chunk.length;
          if (sentBytes > source.length) {
            throw WampFileTransferException(
              'Source emitted more than its declared ${source.length} bytes',
            );
          }
          final previous = pending;
          if (previous != null) {
            call.sendLazyChunk(_fileChunkPayload(previous));
          }
          pending = chunk;
          offset = end;
        }
      }
      if (sentBytes != source.length) {
        throw WampFileTransferException(
          'Source emitted $sentBytes of its declared ${source.length} bytes',
        );
      }
      call.finishLazy(_fileChunkPayload(pending ?? Uint8List(0)));
      return await finalResult;
    } catch (error) {
      if (!cancel.isCompleted) {
        cancel.complete(CancelOptions.modeKillNoWait);
      }
      unawaited(finalResult.then<void>((_) {}, onError: (_, _) {}));
      rethrow;
    }
  }
}

LazyMessagePayload _fileChunkPayload(Uint8List bytes) {
  return LazyMessagePayload.materialized(arguments: <dynamic>[bytes]);
}

CallOptions _fileCallOptions(CallOptions? options, Duration timeout) {
  return CallOptions(
    receiveProgress: options?.receiveProgress,
    timeout: options?.timeout ?? timeout.inMilliseconds,
    discloseMe: options?.discloseMe,
    pptScheme: options?.pptScheme,
    pptSerializer: options?.pptSerializer,
    pptCipher: options?.pptCipher,
    pptKeyId: options?.pptKeyId,
    custom: options?.custom,
  );
}

/// Bounded receiver for the [WampFileSession.setFile] wire contract.
class WampFileReceiver {
  WampFileReceiver._({
    required Session session,
    required WampFileSinkFactory sinkFactory,
    required this.maxConcurrentTransfers,
    required this.maxFileSize,
    required this.maxChunkSize,
    required this.maxBufferedBytes,
    required this.idleTimeout,
  }) : _session = session,
       _sinkFactory = sinkFactory;

  static Future<WampFileReceiver> register(
    Session session,
    String procedure,
    WampFileSinkFactory sinkFactory, {
    RegisterOptions? options,
    int maxConcurrentTransfers = 8,
    int maxFileSize = 16 * 1024 * 1024 * 1024,
    int maxChunkSize = 4 * 1024 * 1024,
    int maxBufferedBytes = 8 * 1024 * 1024,
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    if (maxConcurrentTransfers <= 0 ||
        maxFileSize < 0 ||
        maxChunkSize <= 0 ||
        maxBufferedBytes <= 0 ||
        idleTimeout <= Duration.zero) {
      throw ArgumentError('File receiver limits must be positive');
    }
    final receiver = WampFileReceiver._(
      session: session,
      sinkFactory: sinkFactory,
      maxConcurrentTransfers: maxConcurrentTransfers,
      maxFileSize: maxFileSize,
      maxChunkSize: maxChunkSize,
      maxBufferedBytes: maxBufferedBytes,
      idleTimeout: idleTimeout,
    );
    receiver.registration = await session.registerLazyPayloadHandler(
      procedure,
      receiver._onInvocation,
      options: options,
    );
    return receiver;
  }

  static const String invalidMetadataError =
      'connectanum.error.file.invalid_metadata';
  static const String invalidChunkError =
      'connectanum.error.file.invalid_chunk';
  static const String capacityExceededError =
      'connectanum.error.file.capacity_exceeded';
  static const String checksumMismatchError =
      'connectanum.error.file.checksum_mismatch';
  static const String sinkFailedError = 'connectanum.error.file.sink_failed';
  static const String timeoutError = 'connectanum.error.file.timeout';

  final Session _session;
  final WampFileSinkFactory _sinkFactory;
  final int maxConcurrentTransfers;
  final int maxFileSize;
  final int maxChunkSize;
  final int maxBufferedBytes;
  final Duration idleTimeout;
  final Map<int, _WampFileTransferState> _transfers =
      <int, _WampFileTransferState>{};

  late final Registered registration;
  int _bufferedBytes = 0;
  bool _closed = false;

  int get activeTransfers => _transfers.length;
  int get bufferedBytes => _bufferedBytes;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final state in _transfers.values.toList(growable: false)) {
      _failState(
        state,
        state.lastInvocation,
        sinkFailedError,
        'File receiver closed',
        respond: false,
      );
    }
    await _session.unregister(registration.registrationId);
  }

  Future<void> _onInvocation(LazyInvocationPayload invocation) async {
    if (_closed) {
      _respondError(
        invocation,
        sinkFailedError,
        'File receiver is closed',
      );
      return;
    }
    final state = _transfers[invocation.requestId];
    if (state == null) {
      _acceptHeader(invocation);
      return;
    }
    _acceptChunk(state, invocation);
  }

  void _acceptHeader(LazyInvocationPayload invocation) {
    final decoded = invocation.toPayload();
    final arguments = decoded.arguments;
    final keywords = decoded.argumentsKeywords;
    if (!invocation.progress ||
        invocation.payload.transparentBinaryPayload != null ||
        arguments?.isNotEmpty == true) {
      _respondError(
        invocation,
        invalidMetadataError,
        'The first invocation must contain progressive metadata only',
      );
      return;
    }
    final rawMetadata = keywords?[wampFileMetadataKey];
    if (keywords == null || keywords.length != 1 || rawMetadata is! Map) {
      _respondError(
        invocation,
        invalidMetadataError,
        'Missing file metadata',
      );
      return;
    }

    late final WampFileMetadata metadata;
    try {
      metadata = WampFileMetadata.fromJson(
        Map<String, dynamic>.from(rawMetadata),
      );
    } catch (_) {
      _respondError(
        invocation,
        invalidMetadataError,
        'Malformed file metadata',
      );
      return;
    }
    if (metadata.size > maxFileSize || metadata.chunkSize > maxChunkSize) {
      _respondError(
        invocation,
        capacityExceededError,
        'Declared file or chunk size exceeds receiver limits',
      );
      return;
    }
    if (_transfers.length >= maxConcurrentTransfers) {
      _respondError(
        invocation,
        capacityExceededError,
        'Concurrent file-transfer limit reached',
      );
      return;
    }

    final state = _WampFileTransferState(metadata, invocation);
    _transfers[invocation.requestId] = state;
    _touch(state);
    state.tail =
        Future<WampFileSink>.sync(
              () => _sinkFactory(metadata),
            )
            .then<void>((sink) async {
              if (state.failed) {
                await sink.abort(
                  state.failure ?? StateError('Transfer failed'),
                );
                return;
              }
              state.sink = sink;
            })
            .catchError((Object error, StackTrace stackTrace) {
              _failState(
                state,
                invocation,
                sinkFailedError,
                'File sink initialization failed',
                cause: error,
              );
            });
  }

  void _acceptChunk(
    _WampFileTransferState state,
    LazyInvocationPayload invocation,
  ) {
    if (state.finalizing || state.failed) {
      _failState(
        state,
        invocation,
        invalidChunkError,
        'File transfer already reached a terminal chunk',
      );
      return;
    }
    final decoded = invocation.toPayload();
    final decodedArguments = decoded.arguments;
    final decodedKeywords = decoded.argumentsKeywords;
    final bytes = _singleBinaryArgument(decodedArguments);
    if (bytes == null ||
        invocation.payload.transparentBinaryPayload != null ||
        decodedKeywords?.isNotEmpty == true ||
        (invocation.progress && bytes.isEmpty)) {
      _failState(
        state,
        invocation,
        invalidChunkError,
        'Data invocations must contain binary payload only',
      );
      return;
    }
    if (bytes.length > state.metadata.chunkSize ||
        bytes.length > maxChunkSize ||
        state.acceptedBytes + bytes.length > state.metadata.size) {
      _failState(
        state,
        invocation,
        invalidChunkError,
        'File chunk exceeds declared transfer bounds',
      );
      return;
    }
    if (_bufferedBytes + bytes.length > maxBufferedBytes) {
      _failState(
        state,
        invocation,
        capacityExceededError,
        'Buffered file data exceeds receiver limit',
      );
      return;
    }

    state.lastInvocation = invocation;
    state.acceptedBytes += bytes.length;
    state.queuedBytes += bytes.length;
    _bufferedBytes += bytes.length;
    if (!invocation.progress) {
      state.finalizing = true;
    }
    _touch(state);

    state.tail = state.tail
        .then<void>((_) async {
          if (state.failed) {
            return;
          }
          final sink = state.sink;
          if (sink == null) {
            throw StateError('File sink was not initialized');
          }
          await sink.add(bytes);
          if (state.failed) {
            return;
          }
          state.hashInput.add(bytes);
          state.receivedBytes += bytes.length;
          if (!invocation.progress) {
            await _finishState(state, invocation);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          _failState(
            state,
            invocation,
            sinkFailedError,
            'File sink operation failed',
            cause: error,
          );
        })
        .whenComplete(() {
          state.queuedBytes -= bytes.length;
          _bufferedBytes -= bytes.length;
        });
  }

  Future<void> _finishState(
    _WampFileTransferState state,
    LazyInvocationPayload invocation,
  ) async {
    if (state.receivedBytes != state.metadata.size) {
      _failState(
        state,
        invocation,
        invalidChunkError,
        'Received byte count does not match declared file size',
      );
      return;
    }
    state.closeHash();
    final actualDigest = state.digest.toString();
    final expectedDigest = state.metadata.sha256Digest?.toLowerCase();
    if (expectedDigest != null && expectedDigest != actualDigest) {
      _failState(
        state,
        invocation,
        checksumMismatchError,
        'Received file checksum does not match metadata',
      );
      return;
    }
    final receipt = WampFileReceipt(
      metadata: state.metadata,
      receivedBytes: state.receivedBytes,
      sha256Digest: actualDigest,
    );
    final result = await state.sink!.close(receipt);
    if (state.failed) {
      return;
    }
    state.completed = true;
    state.timer?.cancel();
    if (identical(_transfers[invocation.requestId], state)) {
      _transfers.remove(invocation.requestId);
    }
    if (!invocation.isResponseClosed()) {
      invocation.respondWith(
        argumentsKeywords: <String, dynamic>{
          'file': receipt.toJson(),
          'result': ?result,
        },
        options: _fileYieldOptions(invocation),
      );
    }
  }

  void _touch(_WampFileTransferState state) {
    state.timer?.cancel();
    state.timer = Timer(idleTimeout, () {
      _failState(
        state,
        state.lastInvocation,
        timeoutError,
        'File transfer exceeded its idle timeout',
      );
    });
  }

  void _failState(
    _WampFileTransferState state,
    LazyInvocationPayload? invocation,
    String errorUri,
    String message, {
    Object? cause,
    bool respond = true,
  }) {
    if (state.failed || state.completed) {
      return;
    }
    state.failed = true;
    state.failure = cause ?? WampFileTransferException(message);
    state.timer?.cancel();
    final requestId = state.lastInvocation.requestId;
    if (identical(_transfers[requestId], state)) {
      _transfers.remove(requestId);
    }
    final sink = state.sink;
    if (sink != null && !state.abortStarted) {
      state.abortStarted = true;
      unawaited(
        Future<void>.sync(() => sink.abort(state.failure!)).catchError((_) {}),
      );
    }
    final responder = invocation ?? state.lastInvocation;
    if (respond && !responder.isResponseClosed()) {
      _respondError(responder, errorUri, message);
    }
  }

  void _respondError(
    LazyInvocationPayload invocation,
    String errorUri,
    String message,
  ) {
    if (invocation.isResponseClosed()) {
      return;
    }
    invocation.respondWith(
      isError: true,
      errorUri: errorUri,
      arguments: <dynamic>[message],
    );
  }
}

YieldOptions? _fileYieldOptions(LazyInvocationPayload invocation) {
  if (invocation.pptScheme == null) {
    return null;
  }
  return YieldOptions(
    pptScheme: invocation.pptScheme,
    pptSerializer: invocation.pptSerializer,
    pptCipher: invocation.pptCipher,
    pptKeyId: invocation.pptKeyId,
  );
}

Uint8List? _singleBinaryArgument(List<dynamic>? arguments) {
  if (arguments == null || arguments.length != 1) {
    return null;
  }
  final value = arguments.single;
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  return null;
}

class _WampFileTransferState {
  _WampFileTransferState(this.metadata, this.lastInvocation) {
    hashInput = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) {
        digest = digests.single;
      }),
    );
  }

  final WampFileMetadata metadata;
  late final ByteConversionSink hashInput;
  late Digest digest;
  Future<void> tail = Future<void>.value();
  WampFileSink? sink;
  LazyInvocationPayload lastInvocation;
  Timer? timer;
  Object? failure;
  int acceptedBytes = 0;
  int receivedBytes = 0;
  int queuedBytes = 0;
  bool hashClosed = false;
  bool finalizing = false;
  bool failed = false;
  bool completed = false;
  bool abortStarted = false;

  void closeHash() {
    if (hashClosed) {
      return;
    }
    hashClosed = true;
    hashInput.close();
  }
}

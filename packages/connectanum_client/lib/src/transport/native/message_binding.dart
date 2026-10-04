import 'dart:convert';
import 'dart:core' hide Error;
import 'dart:core' as core show Error;
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' show decodeBase64Bytes;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'message_protocol.dart';

const String _jsonBinaryPrefix = '\u0000';
const String _jsonEscapedBinaryPrefix = '\\u0000';

const _resultDetailKeys = {
  'progress',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};
const _eventDetailKeys = {
  'publisher',
  'trustlevel',
  'topic',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};
const _invocationDetailKeys = {
  'caller',
  'procedure',
  'progress',
  'receive_progress',
  'timeout',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};

class NativeSessionMessage extends AbstractMessageWithPayload {
  NativeSessionMessage({
    required this.serializer,
    required NativeMessageMetadata metadata,
    Uint8List? argsBytes,
    Uint8List? kwargsBytes,
  }) : _metadata = metadata {
    id = metadata.messageCode;
    _applyNativeTransparentPayload(this, serializer, metadata);
    _applyLazyPayload(this, serializer, argsBytes, kwargsBytes);
  }

  /// Keeps only routing metadata until application or wire values are read.
  ///
  /// Lazy application views can consume a typed native E2EE payload before any
  /// ciphertext export. Wire access still exports the original immutable views,
  /// forcing the safe copied decrypt fallback. Consuming decrypt invalidates
  /// wire access that has not already exported storage, including on auth failure.
  NativeSessionMessage.deferred({
    required this.serializer,
    required NativeMessageMetadata metadata,
    required NativeSessionMessage Function() wireMessage,
  }) : _metadata = metadata {
    if (!isNativeTypedE2eeSessionMetadata(metadata)) {
      throw ArgumentError(
        'Deferred native Session requires typed E2EE metadata',
      );
    }
    id = metadata.messageCode;
    _deferredNativePayload = true;
    _wireMessageLoader = wireMessage;
  }

  final NativeMessageSerializer serializer;
  NativeMessageMetadata _metadata;
  NativeMessageMetadata get metadata => _metadata;
  bool _deferredNativePayload = false;
  bool _loadingWire = false;
  bool _restoringWire = false;
  bool _wirePayloadModified = false;
  bool _readingWirePayload = false;
  NativeSessionMessage Function()? _wireMessageLoader;
  ({Object error, StackTrace stack})? _wireFailure;
  LazyMessagePayload? _applicationPayload;

  /// Whether a deferred wrapper's wire values no longer match its native handle.
  bool get hasModifiedNativeWirePayload => _wirePayloadModified;

  void _ensureWirePayload() {
    if (_loadingWire) {
      if (_restoringWire) return;
      throw StateError('Recursive deferred native wire payload access');
    }
    final failure = _wireFailure;
    if (failure != null) {
      core.Error.throwWithStackTrace(failure.error, failure.stack);
    }
    final loader = _wireMessageLoader;
    if (loader == null) return;
    _loadingWire = true;
    try {
      final wire = loader();
      _restoringWire = true;
      _metadata = wire.metadata;
      super.restoreLazyPayload(wire.toLazyPayload());
      _wireMessageLoader = null;
    } catch (error, stack) {
      _wireFailure = (error: error, stack: stack);
      _wireMessageLoader = null;
      rethrow;
    } finally {
      _restoringWire = false;
      _loadingWire = false;
    }
  }

  void _modifyWirePayload() {
    _ensureWirePayload();
    if (!_deferredNativePayload || _loadingWire) return;
    _wirePayloadModified = true;
    super.transparentBinaryPayload = null;
    // A changed ciphertext must never decrypt the original anchored handle.
    super.attachE2eeRuntimeContext(
      e2eeRuntimeContext?.copyWith(payloadAnchor: null),
    );
  }

  @override
  List<dynamic>? get arguments {
    _ensureWirePayload();
    return super.arguments;
  }

  @override
  set arguments(List<dynamic>? value) {
    _modifyWirePayload();
    super.arguments = value;
  }

  @override
  Map<String, dynamic>? get argumentsKeywords {
    _ensureWirePayload();
    return super.argumentsKeywords;
  }

  @override
  set argumentsKeywords(Map<String, dynamic>? value) {
    _modifyWirePayload();
    super.argumentsKeywords = value;
  }

  @override
  Uint8List? get transparentBinaryPayload {
    _ensureWirePayload();
    return super.transparentBinaryPayload;
  }

  @override
  set transparentBinaryPayload(Uint8List? value) {
    _modifyWirePayload();
    super.transparentBinaryPayload = value;
  }

  @override
  Uint8List? get debugEncodedArgumentsBytes {
    _ensureWirePayload();
    return super.debugEncodedArgumentsBytes;
  }

  @override
  Uint8List? get debugEncodedArgumentsKeywordsBytes {
    _ensureWirePayload();
    return super.debugEncodedArgumentsKeywordsBytes;
  }

  @override
  List<dynamic>? get wireArguments {
    _ensureWirePayload();
    return super.wireArguments;
  }

  @override
  Map<String, dynamic>? get wireArgumentsKeywords {
    _ensureWirePayload();
    return super.wireArgumentsKeywords;
  }

  @override
  void attachE2eeProvider(WampE2eeProvider? provider) {
    if (!identical(provider, e2eeProvider)) _applicationPayload = null;
    super.attachE2eeProvider(provider);
  }

  @override
  void attachE2eeRuntimeContext(WampE2eeRuntimeContext? runtimeContext) {
    if (!identical(runtimeContext, e2eeRuntimeContext)) {
      _applicationPayload = null;
    }
    super.attachE2eeRuntimeContext(
      _wirePayloadModified
          ? runtimeContext?.copyWith(payloadAnchor: null)
          : runtimeContext,
    );
  }

  @override
  void setLazyPayload({
    Uint8List? argumentsBytes,
    PayloadListDecoder? argumentsDecoder,
    Uint8List? argumentsKeywordsBytes,
    PayloadMapDecoder? argumentsKeywordsDecoder,
    LazyPayloadEncoding? encoding,
  }) {
    _modifyWirePayload();
    super.setLazyPayload(
      argumentsBytes: argumentsBytes,
      argumentsDecoder: argumentsDecoder,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      argumentsKeywordsDecoder: argumentsKeywordsDecoder,
      encoding: encoding,
    );
  }

  @override
  void restoreLazyPayload(LazyMessagePayload payload) {
    _modifyWirePayload();
    super.restoreLazyPayload(
      _wirePayloadModified && !_loadingWire
          ? payload.withE2eeRuntimeContext(
              payload.e2eeRuntimeContext?.copyWith(payloadAnchor: null),
            )
          : payload,
    );
  }

  @override
  void retainLazyPayload(LazyMessagePayload payload) {
    _modifyWirePayload();
    super.retainLazyPayload(
      _wirePayloadModified && !_loadingWire
          ? payload.withE2eeRuntimeContext(
              payload.e2eeRuntimeContext?.copyWith(payloadAnchor: null),
            )
          : payload,
    );
  }

  @override
  void ensureDecodedPayloadView({
    required String? pptScheme,
    required String? pptSerializer,
    required String? pptCipher,
    required String? pptKeyId,
  }) {
    _ensureWirePayload();
    final wasReadingWire = _readingWirePayload;
    _readingWirePayload = true;
    try {
      super.ensureDecodedPayloadView(
        pptScheme: pptScheme,
        pptSerializer: pptSerializer,
        pptCipher: pptCipher,
        pptKeyId: pptKeyId,
      );
    } finally {
      _readingWirePayload = wasReadingWire;
    }
  }

  @override
  LazyMessagePayload toLazyPayload({Object? anchor}) {
    if (!_deferredNativePayload ||
        _wirePayloadModified ||
        _readingWirePayload) {
      return super.toLazyPayload(anchor: anchor);
    }
    final provider = e2eeProvider;
    final runtimeProvider = switch (provider) {
      WampE2eeRuntimePayloadProvider value => value,
      _ => null,
    };
    final context = e2eeRuntimeContext;
    final (scheme, serializer, cipher, keyId) = _nativeTypedE2eeFields(
      metadata,
    );
    final payload = _applicationPayload ??= LazyMessagePayload.deferred(
      encoding: LazyPayloadEncoding.flatbuffers,
      e2eeProvider: provider,
      e2eeRuntimeContext: context,
      anchor: this,
      loader: () {
        if (!_wirePayloadModified &&
            runtimeProvider != null &&
            runtimeProvider.canUnpackFromRuntimeContext(context)) {
          return decodePayloadView(
            null,
            null,
            pptScheme: scheme,
            pptSerializer: serializer,
            pptCipher: cipher,
            pptKeyId: keyId,
            e2eeProvider: provider,
            runtimeContext: context,
          );
        }
        _ensureWirePayload();
        return decodeLazyPayloadView(
          super.toLazyPayload(),
          pptScheme: scheme,
          pptSerializer: serializer,
          pptCipher: cipher,
          pptKeyId: keyId,
          e2eeProvider: provider,
          runtimeContext: _wirePayloadModified
              ? context?.copyWith(payloadAnchor: null)
              : context,
        );
      },
    );
    return payload.withAnchor(anchor ?? this);
  }

  /// Optional application details decoded only when a lazy handler reads them.
  /// Standard projected WAMP fields remain on the typed payload view.
  late final Map<String, dynamic>? customDetails = metadata.detailsBytes == null
      ? null
      : _lazyDynamicDetailMap(
          serializer,
          metadata.detailsBytes,
          knownKeys: switch (metadata.messageCode) {
            final code when code == MessageTypes.codeResult =>
              _resultDetailKeys,
            final code when code == MessageTypes.codeEvent => _eventDetailKeys,
            final code when code == MessageTypes.codeInvocation =>
              _invocationDetailKeys,
            _ => throw StateError(
              'Custom payload details require RESULT, EVENT or INVOCATION',
            ),
          },
        );

  AbstractMessage materialize() {
    _ensureWirePayload();
    final boundMessage = _bindFromMetadata(
      serializer,
      metadata,
      argsBytes: debugEncodedArgumentsBytes,
      kwargsBytes: debugEncodedArgumentsKeywordsBytes,
    );
    if (boundMessage == null) {
      throw StateError(
        'Native session message ${metadata.messageCode} cannot be materialized',
      );
    }
    if (boundMessage is AbstractMessageWithPayload) {
      boundMessage.attachE2eeProvider(e2eeProvider);
      boundMessage.attachE2eeRuntimeContext(e2eeRuntimeContext);
    }
    final anchor = sessionMessageAnchorFor(this);
    if (anchor != null) {
      attachSessionMessageAnchor(boundMessage, anchor);
    }
    return boundMessage;
  }
}

(String?, String?, String?, String?) _nativeTypedE2eeFields(
  NativeMessageMetadata metadata,
) => metadata.messageCode == MessageTypes.codeResult
    ? (metadata.stringA, metadata.stringB, metadata.stringC, metadata.stringD)
    : (metadata.stringB, metadata.stringC, metadata.stringD, metadata.stringE);

bool isNativeTypedE2eeSessionMetadata(NativeMessageMetadata metadata) {
  if (!metadata.hasFlag(NativeMessageMetadata.flagMetadataBind) ||
      !{
        MessageTypes.codeResult,
        MessageTypes.codeEvent,
        MessageTypes.codeInvocation,
      }.contains(metadata.messageCode)) {
    return false;
  }
  final (scheme, serializer, cipher, _) = _nativeTypedE2eeFields(metadata);
  return scheme == 'wamp' &&
      serializer == 'flatbuffers' &&
      (cipher == 'aes256gcm' || cipher == 'xsalsa20poly1305');
}

AbstractMessage bindMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
  NativeMessageMetadata? metadata,
}) {
  final message = metadata != null
      ? _bindFromMetadata(
          serializer,
          metadata,
          argsBytes: argsBytes,
          kwargsBytes: kwargsBytes,
        )
      : null;
  final boundMessage = message ?? _bindDecodedPayload(serializer, bytes);
  if (message == null && boundMessage is AbstractMessageWithPayload) {
    _applyLazyPayload(boundMessage, serializer, argsBytes, kwargsBytes);
  }
  if (message == null &&
      boundMessage is Abort &&
      (argsBytes != null || kwargsBytes != null)) {
    return Abort(
      boundMessage.reason,
      details: boundMessage.details,
      message: boundMessage.message?.message,
      arguments: argsBytes == null
          ? boundMessage.arguments
          : _decodeOptionalArgumentList(serializer, argsBytes),
      argumentsKeywords: kwargsBytes == null
          ? boundMessage.argumentsKeywords
          : _decodeOptionalKeywordMap(serializer, kwargsBytes),
    );
  }
  return boundMessage;
}

Object bindSessionMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
  NativeMessageMetadata? metadata,
}) {
  if (metadata != null &&
      metadata.hasFlag(NativeMessageMetadata.flagMetadataBind) &&
      _supportsSessionMetadataMessage(metadata.messageCode)) {
    return NativeSessionMessage(
      serializer: serializer,
      metadata: metadata,
      argsBytes: argsBytes,
      kwargsBytes: kwargsBytes,
    );
  }
  return bindMessage(
    serializer,
    bytes,
    argsBytes: argsBytes,
    kwargsBytes: kwargsBytes,
    metadata: metadata,
  );
}

AbstractMessage materializeSessionMessage(Object message) {
  if (message is NativeSessionMessage) {
    return message.materialize();
  }
  return message as AbstractMessage;
}

AbstractMessage _bindDecodedPayload(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  if (serializer == NativeMessageSerializer.flatbuffers) {
    return flatbuffers.Serializer().deserialize(bytes)!;
  }
  final decoded = _decodePayload(serializer, bytes);
  if (decoded is! List) {
    throw ArgumentError('Decoded WAMP message is not an array: $decoded');
  }
  if (decoded.isEmpty) {
    throw ArgumentError('WAMP message cannot be empty');
  }
  return _bindDecoded(decoded.cast<dynamic>());
}

AbstractMessage? _bindFromMetadata(
  NativeMessageSerializer serializer,
  NativeMessageMetadata metadata, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
}) {
  final message = _bindFromMetadataFields(
    serializer,
    metadata,
    argsBytes: argsBytes,
    kwargsBytes: kwargsBytes,
  );
  if (message != null) {
    _applyNativeTransparentPayload(message, serializer, metadata);
  }
  if (message != null &&
      serializer == NativeMessageSerializer.flatbuffers &&
      metadata.messageCode != MessageTypes.codeHeartbeat &&
      metadata.detailsBytes != null) {
    flatbuffers.Serializer().retainMetadata(message, metadata.detailsBytes!);
  }
  return message;
}

void _applyNativeTransparentPayload(
  AbstractMessage message,
  NativeMessageSerializer serializer,
  NativeMessageMetadata metadata,
) {
  final present = metadata.hasFlag(
    NativeMessageMetadata.flagTransparentPayload,
  );
  final bytes = metadata.transparentPayloadBytes;
  if (present != (bytes != null) ||
      (present &&
          (serializer != NativeMessageSerializer.flatbuffers ||
              message is! AbstractMessageWithPayload ||
              !{16, 36, 48, 50, 68, 70, 8}.contains(metadata.messageCode)))) {
    throw ArgumentError('Invalid native transparent payload metadata');
  }
  if (present) {
    (message as AbstractMessageWithPayload).transparentBinaryPayload = bytes;
  }
}

AbstractMessage? _bindFromMetadataFields(
  NativeMessageSerializer serializer,
  NativeMessageMetadata metadata, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
}) {
  if (!metadata.hasFlag(NativeMessageMetadata.flagMetadataBind)) {
    return null;
  }
  final code = metadata.messageCode;
  final directBind = metadata.hasFlag(NativeMessageMetadata.flagDirectBind);
  if (code == MessageTypes.codePublished) {
    return Published(metadata.primaryId, metadata.secondaryId);
  }
  if (code == MessageTypes.codeSubscribed) {
    return Subscribed(metadata.primaryId, metadata.secondaryId);
  }
  if (code == MessageTypes.codeWelcome) {
    return Welcome(
      metadata.primaryId,
      _detailsFromMetadata(
        serializer,
        metadata.detailsBytes,
        realm: directBind ? metadata.stringA : null,
        authId: directBind ? metadata.stringB : null,
        authRole: directBind ? metadata.stringC : null,
        authMethod: directBind ? metadata.stringD : null,
        authProvider: directBind ? metadata.stringE : null,
      ),
    );
  }
  if (code == MessageTypes.codeChallenge) {
    return Challenge(
      metadata.stringA ?? '',
      _challengeExtraFromMetadata(serializer, metadata.detailsBytes),
    );
  }
  if (code == MessageTypes.codeAbort) {
    final details = directBind
        ? _lazyObjectDetailMap(
            serializer,
            metadata.detailsBytes,
            initialValues: <String, Object?>{
              if (metadata.stringB != null) 'message': metadata.stringB,
            },
            knownKeys: const {'message'},
          )
        : _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
              const <String, Object?>{};
    return Abort(
      metadata.stringA ?? '',
      details: details,
      message: details['message'] as String?,
      arguments: _decodeOptionalArgumentList(serializer, argsBytes),
      argumentsKeywords: _decodeOptionalKeywordMap(serializer, kwargsBytes),
    );
  }
  if (code == MessageTypes.codeEvent) {
    final details = directBind
        ? EventDetails(
            publisher:
                metadata.hasFlag(NativeMessageMetadata.flagDetailNumberAPresent)
                ? metadata.detailNumberA
                : null,
            trustlevel:
                metadata.hasFlag(NativeMessageMetadata.flagDetailNumberBPresent)
                ? metadata.detailNumberB
                : null,
            topic: metadata.stringA,
            pptScheme: metadata.stringB,
            pptSerializer: metadata.stringC,
            pptCipher: metadata.stringD,
            pptKeyid: metadata.stringE,
          )
        : _mapEventDetails(
            _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
          );
    if (directBind) {
      _attachLazyCustomFieldsFromDetails(
        details,
        serializer,
        metadata.detailsBytes,
        _eventDetailKeys,
      );
    }
    final message = Event(metadata.primaryId, metadata.secondaryId, details);
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  if (code == MessageTypes.codeHeartbeat) {
    final heartbeat =
        _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
        const <String, dynamic>{};
    return Heartbeat(
      details: Map<String, Object?>.from(
        _asStringKeyMap(heartbeat['details']) ?? const <String, Object?>{},
      ),
      ping: _asInt(heartbeat['ping']),
      incoming: _asInt(heartbeat['incoming']),
      outgoing: _asInt(heartbeat['outgoing']),
    );
  }
  if (code == MessageTypes.codeResult) {
    final details = directBind
        ? ResultDetails(
            progress:
                metadata.hasFlag(NativeMessageMetadata.flagDetailBoolATrue)
                ? true
                : null,
            pptScheme: metadata.stringA,
            pptSerializer: metadata.stringB,
            pptCipher: metadata.stringC,
            pptKeyId: metadata.stringD,
          )
        : _mapResultDetails(
            _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
          );
    if (directBind) {
      _attachLazyCustomFieldsFromDetails(
        details,
        serializer,
        metadata.detailsBytes,
        _resultDetailKeys,
      );
    }
    final message = Result(metadata.primaryId, details);
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  if (code == MessageTypes.codeRegistered) {
    return Registered(metadata.primaryId, metadata.secondaryId);
  }
  if (code == MessageTypes.codeInvocation) {
    final details = directBind
        ? (InvocationDetails(
              metadata.hasFlag(NativeMessageMetadata.flagDetailNumberAPresent)
                  ? metadata.detailNumberA
                  : null,
              metadata.stringA,
              metadata.hasFlag(NativeMessageMetadata.flagDetailBoolATrue)
                  ? true
                  : null,
              metadata.stringB,
              metadata.stringC,
              metadata.stringD,
              metadata.stringE,
            )
            ..progress =
                metadata.hasFlag(NativeMessageMetadata.flagDetailBoolBTrue)
                ? true
                : null
            ..timeout =
                metadata.hasFlag(NativeMessageMetadata.flagDetailNumberBPresent)
                ? metadata.detailNumberB
                : null)
        : _mapInvocationDetails(
            _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
          );
    if (directBind) {
      _attachLazyCustomFieldsFromDetails(
        details,
        serializer,
        metadata.detailsBytes,
        _invocationDetailKeys,
      );
    }
    final message = Invocation(
      metadata.primaryId,
      metadata.secondaryId,
      details,
    );
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  if (code == MessageTypes.codeInterrupt) {
    final options = directBind
        ? _mapCancelOptionsFromMetadata(metadata.stringA)
        : _mapCancelOptions(
            _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
          );
    return Interrupt(
      metadata.primaryId,
      options: _interruptOptionsFromMode(options?.mode),
    );
  }
  if (code == MessageTypes.codeUnregistered) {
    return Unregistered(metadata.primaryId);
  }
  if (code == MessageTypes.codeUnsubscribed) {
    return Unsubscribed(
      metadata.primaryId,
      directBind
          ? UnsubscribedDetails(
              metadata.hasFlag(NativeMessageMetadata.flagDetailNumberAPresent)
                  ? metadata.detailNumberA
                  : null,
              metadata.stringA,
            )
          : _mapUnsubscribedDetails(
              _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
            ),
    );
  }
  if (code == MessageTypes.codeGoodbye) {
    final details = directBind
        ? (metadata.stringB == null
              ? const <String, Object?>{}
              : <String, Object?>{'message': metadata.stringB})
        : _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
              const <String, Object?>{};
    return Goodbye(
      details['message'] == null
          ? null
          : GoodbyeMessage(details['message'] as String?),
      metadata.stringA ?? '',
    );
  }
  if (code == MessageTypes.codeError) {
    final details = directBind
        ? _lazyDynamicDetailMap(
            serializer,
            metadata.detailsBytes,
            initialValues: <String, dynamic>{
              if (metadata.stringB != null) 'message': metadata.stringB,
            },
            knownKeys: const {'message'},
          )
        : _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
              <String, dynamic>{};
    final message = Error(
      metadata.primaryId,
      metadata.secondaryId,
      details,
      metadata.stringA,
    );
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  final unknown = _decodeOptionalMapFragment(serializer, metadata.detailsBytes);
  if (unknown != null && unknown['fields'] is List) {
    return UnknownMessage(
      code,
      fields: _asDynamicList(unknown['fields']),
      requestId: _asInt(unknown['request_id']),
    );
  }
  return null;
}

bool _supportsSessionMetadataMessage(int code) {
  return code == MessageTypes.codeChallenge ||
      code == MessageTypes.codeWelcome ||
      code == MessageTypes.codeAbort ||
      code == MessageTypes.codePublished ||
      code == MessageTypes.codeSubscribed ||
      code == MessageTypes.codeEvent ||
      code == MessageTypes.codeUnsubscribed ||
      code == MessageTypes.codeResult ||
      code == MessageTypes.codeRegistered ||
      code == MessageTypes.codeInvocation ||
      code == MessageTypes.codeInterrupt ||
      code == MessageTypes.codeUnregistered ||
      code == MessageTypes.codeGoodbye ||
      code == MessageTypes.codeError;
}

Object? _decodePayload(NativeMessageSerializer serializer, Uint8List bytes) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return _normalizeJsonBinaryPayload(jsonDecode(utf8.decode(bytes)));
    case NativeMessageSerializer.messagePack:
      return msgpack.deserialize(bytes);
    case NativeMessageSerializer.cbor:
      return cbor.cborDecode(bytes).toObject();
    case NativeMessageSerializer.ubjson:
    case NativeMessageSerializer.flatbuffers:
      throw UnsupportedError(
        'Serializer ${serializer.name} is not supported for inbound messages',
      );
  }
}

Map<String, dynamic>? _decodeOptionalMapFragment(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null) {
    return null;
  }
  if (serializer == NativeMessageSerializer.flatbuffers) {
    return flatbuffers.Serializer().deserializeMetadata(bytes);
  }
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return null;
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError('Expected details map but got $decoded');
}

List<dynamic>? _decodeOptionalArgumentList(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null) {
    return null;
  }
  return _decodeArgumentList(serializer, bytes);
}

Map<String, dynamic>? _decodeOptionalKeywordMap(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null) {
    return null;
  }
  return _decodeKeywordMap(serializer, bytes);
}

void _attachLazyCustomFieldsFromDetails(
  CustomFieldContainer target,
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes,
  Set<String> knownKeys,
) {
  if (detailsBytes == null) {
    return;
  }
  target.setLazyCustomFieldsLoader(
    () => _extractCustomFields(
      _decodeOptionalMapFragment(serializer, detailsBytes) ??
          const <String, dynamic>{},
      knownKeys,
    ),
  );
}

Map<String, dynamic> _lazyDynamicDetailMap(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes, {
  Map<String, dynamic>? initialValues,
  Set<String> knownKeys = const <String>{},
}) {
  return lazyStringKeyMap<dynamic>(
    initialValues: initialValues,
    loader: detailsBytes == null
        ? null
        : () => _extractCustomFields(
            _decodeOptionalMapFragment(serializer, detailsBytes) ??
                const <String, dynamic>{},
            knownKeys,
          ),
  );
}

Map<String, Object?> _lazyObjectDetailMap(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes, {
  Map<String, Object?>? initialValues,
  Set<String> knownKeys = const <String>{},
}) {
  return lazyStringKeyMap<Object?>(
    initialValues: initialValues,
    loader: detailsBytes == null
        ? null
        : () => Map<String, Object?>.from(
            _extractCustomFields(
              _decodeOptionalMapFragment(serializer, detailsBytes) ??
                  const <String, dynamic>{},
              knownKeys,
            ),
          ),
  );
}

AbstractMessage _bindDecoded(List<dynamic> message) {
  final code = message[0] as int;
  if (code == MessageTypes.codeChallenge) {
    return _bindChallenge(message);
  }
  if (code == MessageTypes.codeWelcome) {
    return Welcome(message[1] as int, _mapDetails(_asStringKeyMap(message[2])));
  }
  if (code == MessageTypes.codeAbort) {
    final details = _asStringKeyMap(message.length > 1 ? message[1] : null);
    final reason = message.length > 2 ? message[2] as String : '';
    return Abort(
      reason,
      details: details,
      message: _readOptionalMessageText(message, 1),
      arguments: message.length > 3 ? _asDynamicList(message[3]) : null,
      argumentsKeywords: message.length > 4
          ? _asStringKeyMap(message[4])
          : null,
    );
  }
  if (code == MessageTypes.codeGoodbye) {
    final details = _asStringKeyMap(message.length > 1 ? message[1] : null);
    final reason = message.length > 2 ? message[2] as String : '';
    return Goodbye(
      details != null ? GoodbyeMessage(details['message'] as String?) : null,
      reason,
    );
  }
  if (code == MessageTypes.codeHeartbeat) {
    return Heartbeat(
      details: Map<String, Object?>.from(
        _asStringKeyMap(message.length > 1 ? message[1] : null) ??
            const <String, Object?>{},
      ),
      ping: _asInt(message.length > 2 ? message[2] : null),
      incoming: _asInt(message.length > 3 ? message[3] : null),
      outgoing: _asInt(message.length > 4 ? message[4] : null),
    );
  }
  if (code == MessageTypes.codeError) {
    return _bindError(message);
  }
  if (code == MessageTypes.codePublished) {
    return Published(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeSubscribed) {
    return Subscribed(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeEvent) {
    return Event(
      message[1] as int,
      message[2] as int,
      _mapEventDetails(_asStringKeyMap(message[3])),
    );
  }
  if (code == MessageTypes.codeUnsubscribed) {
    return Unsubscribed(
      message[1] as int,
      _mapUnsubscribedDetails(
        _asStringKeyMap(message.length > 2 ? message[2] : null),
      ),
    );
  }
  if (code == MessageTypes.codeResult) {
    return Result(
      message[1] as int,
      _mapResultDetails(_asStringKeyMap(message[2])),
    );
  }
  if (code == MessageTypes.codeRegistered) {
    return Registered(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeInvocation) {
    return Invocation(
      message[1] as int,
      message[2] as int,
      _mapInvocationDetails(_asStringKeyMap(message[3])),
    );
  }
  if (code == MessageTypes.codeInterrupt) {
    final options = _mapCancelOptions(
      _asStringKeyMap(message.length > 2 ? message[2] : null),
    );
    return Interrupt(
      message[1] as int,
      options: _interruptOptionsFromMode(options?.mode),
    );
  }
  if (code == MessageTypes.codeUnregistered) {
    return Unregistered(message[1] as int);
  }
  return UnknownMessage(
    code,
    fields: message.length > 1 ? message.sublist(1) : const <dynamic>[],
  );
}

Challenge _bindChallenge(List<dynamic> message) {
  final extraMap = _asStringKeyMap(message.length > 2 ? message[2] : null);
  return Challenge(
    message[1] as String,
    Extra.fromMap(extraMap ?? const <String, dynamic>{}),
  );
}

Error _bindError(List<dynamic> message) {
  final requestTypeId = message[1] as int;
  final requestId = message[2] as int;
  final details = _asStringKeyMap(message[3]) ?? <String, dynamic>{};
  final error = message.length > 4 ? message[4] as String? : null;
  return Error(requestTypeId, requestId, details, error);
}

void _applyLazyPayload(
  AbstractMessageWithPayload message,
  NativeMessageSerializer serializer,
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
) {
  if (argsBytes == null && kwargsBytes == null) {
    return;
  }

  message.setLazyPayload(
    argumentsBytes: argsBytes,
    argumentsDecoder: argsBytes == null
        ? null
        : (fragment) => _decodeArgumentList(serializer, fragment),
    argumentsKeywordsBytes: kwargsBytes,
    argumentsKeywordsDecoder: kwargsBytes == null
        ? null
        : (fragment) => _decodeKeywordMap(serializer, fragment),
    encoding: _lazyPayloadEncodingForSerializer(serializer),
  );
}

LazyPayloadEncoding? _lazyPayloadEncodingForSerializer(
  NativeMessageSerializer serializer,
) {
  return switch (serializer) {
    NativeMessageSerializer.json => LazyPayloadEncoding.json,
    NativeMessageSerializer.messagePack => LazyPayloadEncoding.messagePack,
    NativeMessageSerializer.cbor => LazyPayloadEncoding.cbor,
    NativeMessageSerializer.ubjson => null,
    NativeMessageSerializer.flatbuffers => LazyPayloadEncoding.cbor,
  };
}

Details _detailsFromMetadata(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes, {
  String? realm,
  String? authId,
  String? authRole,
  String? authMethod,
  String? authProvider,
}) {
  final details = Details();
  details.realm = realm;
  details.authid = authId;
  details.authrole = authRole;
  details.authmethod = authMethod;
  details.authprovider = authProvider;
  if (detailsBytes != null) {
    details.setLazyFieldsLoader(
      () => Map<String, dynamic>.from(
        _decodeOptionalMapFragment(serializer, detailsBytes) ??
            const <String, dynamic>{},
      ),
    );
  }
  return details;
}

Details _mapDetails(Map<String, dynamic>? map) {
  final details = Details();
  if (map == null) {
    return details;
  }
  details.agent = map['agent'] as String?;
  details.realm = map['realm'] as String?;
  if (map['authmethods'] is List) {
    details.authmethods = List<String>.from(map['authmethods']);
  }
  details.authid = map['authid'] as String?;
  details.authrole = map['authrole'] as String?;
  details.authmethod = map['authmethod'] as String?;
  details.authprovider = map['authprovider'] as String?;
  details.authextra = _asStringKeyMap(map['authextra']);
  details.nonce = map['nonce'] as String?;
  details.challenge = map['challenge'] as String?;
  details.iterations = _asInt(map['iterations']);
  details.keylen = _asInt(map['keylen']);
  details.progress = map['progress'] as bool?;
  details.salt = map['salt'] as String?;
  if (map['topic'] is String) {
    details.topic = Uri.tryParse(map['topic'] as String);
  }
  if (map['procedure'] is String) {
    details.procedure = Uri.tryParse(map['procedure'] as String);
  }
  details.trustlevel = _asInt(map['trustlevel']);
  details.roles = _mapRoles(_asStringKeyMap(map['roles']));
  details.custom.addAll(
    _extractCustomFields(map, const {
      'agent',
      'realm',
      'authmethods',
      'authid',
      'authrole',
      'authmethod',
      'authprovider',
      'authextra',
      'nonce',
      'challenge',
      'iterations',
      'keylen',
      'progress',
      'salt',
      'topic',
      'procedure',
      'trustlevel',
      'roles',
    }),
  );
  return details;
}

Extra _challengeExtraFromMetadata(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes,
) {
  final extra = Extra();
  if (detailsBytes != null) {
    extra.setLazyLoader(
      () => Map<String, dynamic>.from(
        _decodeOptionalMapFragment(serializer, detailsBytes) ??
            const <String, dynamic>{},
      ),
    );
  }
  return extra;
}

EventDetails _mapEventDetails(Map<String, dynamic>? map) {
  final safeMap = map ?? const <String, dynamic>{};
  return EventDetails(
    publisher: _asInt(safeMap['publisher']),
    trustlevel: _asInt(safeMap['trustlevel']),
    topic: safeMap['topic'] as String?,
    pptScheme: safeMap['ppt_scheme'] as String?,
    pptSerializer: safeMap['ppt_serializer'] as String?,
    pptCipher: safeMap['ppt_cipher'] as String?,
    pptKeyid: safeMap['ppt_keyid'] as String?,
    custom: _extractCustomFields(safeMap, const {
      'publisher',
      'trustlevel',
      'topic',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
}

ResultDetails _mapResultDetails(Map<String, dynamic>? map) {
  final safeMap = map ?? const <String, dynamic>{};
  return ResultDetails(
    progress: safeMap['progress'] as bool?,
    pptScheme: safeMap['ppt_scheme'] as String?,
    pptSerializer: safeMap['ppt_serializer'] as String?,
    pptCipher: safeMap['ppt_cipher'] as String?,
    pptKeyId: safeMap['ppt_keyid'] as String?,
    custom: _extractCustomFields(safeMap, const {
      'progress',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
}

InvocationDetails _mapInvocationDetails(Map<String, dynamic>? map) {
  final safeMap = map ?? const <String, dynamic>{};
  return InvocationDetails(
      _asInt(safeMap['caller']),
      safeMap['procedure'] as String?,
      safeMap['receive_progress'] as bool?,
      safeMap['ppt_scheme'] as String?,
      safeMap['ppt_serializer'] as String?,
      safeMap['ppt_cipher'] as String?,
      safeMap['ppt_keyid'] as String?,
      _extractCustomFields(safeMap, const {
        'caller',
        'procedure',
        'progress',
        'receive_progress',
        'timeout',
        'ppt_scheme',
        'ppt_serializer',
        'ppt_cipher',
        'ppt_keyid',
      }),
    )
    ..progress = safeMap['progress'] as bool?
    ..timeout = _asInt(safeMap['timeout']);
}

UnsubscribedDetails? _mapUnsubscribedDetails(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  return UnsubscribedDetails(
    _asInt(map['subscription']),
    map['reason'] as String?,
  );
}

CancelOptions? _mapCancelOptions(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final options = CancelOptions();
  options.mode = map['mode'] as String?;
  return options;
}

CancelOptions? _mapCancelOptionsFromMetadata(String? mode) {
  if (mode == null) {
    return null;
  }
  final options = CancelOptions();
  options.mode = mode;
  return options;
}

InterruptOptions? _interruptOptionsFromMode(String? mode) {
  if (mode == null) {
    return null;
  }
  final options = InterruptOptions();
  options.mode = mode;
  return options;
}

List<dynamic> _decodeArgumentList(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return <dynamic>[];
  }
  if (decoded is List) {
    return List<dynamic>.from(decoded);
  }
  throw ArgumentError('Expected arguments list but got $decoded');
}

Map<String, dynamic> _decodeKeywordMap(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return <String, dynamic>{};
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError('Expected keyword arguments map but got $decoded');
}

Object? _decodeFragment(NativeMessageSerializer serializer, Uint8List bytes) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return _normalizeJsonBinaryPayload(jsonDecode(utf8.decode(bytes)));
    case NativeMessageSerializer.messagePack:
      return msgpack.deserialize(bytes);
    case NativeMessageSerializer.cbor:
      return cbor.cborDecode(bytes).toObject();
    case NativeMessageSerializer.flatbuffers:
      return flatbuffers.Serializer().deserializeApplication(bytes);
    case NativeMessageSerializer.ubjson:
      throw UnsupportedError(
        'Serializer ${serializer.name} is not supported for payload decoding',
      );
  }
}

Object? _normalizeJsonBinaryPayload(Object? value) {
  if (value is String &&
      (value.startsWith(_jsonBinaryPrefix) ||
          value.startsWith(_jsonEscapedBinaryPrefix))) {
    final prefixLength = value.startsWith(_jsonBinaryPrefix)
        ? _jsonBinaryPrefix.length
        : _jsonEscapedBinaryPrefix.length;
    return decodeBase64Bytes(value, prefixLength);
  }
  if (value is List) {
    return value
        .map<Object?>((entry) => _normalizeJsonBinaryPayload(entry))
        .toList(growable: false);
  }
  if (value is Map) {
    return value.map<Object?, Object?>(
      (key, entry) => MapEntry(key, _normalizeJsonBinaryPayload(entry)),
    );
  }
  return value;
}

Roles? _mapRoles(Map<String, dynamic>? rolesMap) {
  if (rolesMap == null) {
    return null;
  }
  final roles = Roles();
  if (rolesMap['publisher'] is Map) {
    roles.publisher = Publisher()
      ..features = _mapPublisherFeatures(
        _asStringKeyMap(rolesMap['publisher']?['features']),
      );
  }
  if (rolesMap['broker'] is Map) {
    roles.broker = Broker()
      ..features = _mapBrokerFeatures(
        _asStringKeyMap(rolesMap['broker']?['features']),
      );
  }
  if (rolesMap['subscriber'] is Map) {
    roles.subscriber = Subscriber()
      ..features = _mapSubscriberFeatures(
        _asStringKeyMap(rolesMap['subscriber']?['features']),
      );
  }
  if (rolesMap['dealer'] is Map) {
    final dealer = Dealer();
    dealer.reflection = rolesMap['dealer']['reflection'] as bool?;
    dealer.features = _mapDealerFeatures(
      _asStringKeyMap(rolesMap['dealer']?['features']),
    );
    roles.dealer = dealer;
  }
  if (rolesMap['callee'] is Map) {
    roles.callee = Callee()
      ..features = _mapCalleeFeatures(
        _asStringKeyMap(rolesMap['callee']?['features']),
      );
  }
  if (rolesMap['caller'] is Map) {
    roles.caller = Caller()
      ..features = _mapCallerFeatures(
        _asStringKeyMap(rolesMap['caller']?['features']),
      );
  }
  return roles;
}

PublisherFeatures? _mapPublisherFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = PublisherFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.subscriberBlackWhiteListing =
      map['subscriber_blackwhite_listing'] ??
      features.subscriberBlackWhiteListing;
  features.publisherExclusion =
      map['publisher_exclusion'] ?? features.publisherExclusion;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

BrokerFeatures? _mapBrokerFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = BrokerFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.publicationTrustLevels =
      map['publication_trustlevels'] ??
      map['publication_trust_levels'] ??
      features.publicationTrustLevels;
  features.patternBasedSubscription =
      map['pattern_based_subscription'] ?? features.patternBasedSubscription;
  features.subscriptionMetaApi =
      map['subscription_meta_api'] ?? features.subscriptionMetaApi;
  features.subscriberBlackWhiteListing =
      map['subscriber_blackwhite_listing'] ??
      features.subscriberBlackWhiteListing;
  features.sessionMetaApi = map['session_meta_api'] ?? features.sessionMetaApi;
  features.publisherExclusion =
      map['publisher_exclusion'] ?? features.publisherExclusion;
  features.eventHistory = map['event_history'] ?? features.eventHistory;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

SubscriberFeatures? _mapSubscriberFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = SubscriberFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.publicationTrustLevels =
      map['publication_trustlevels'] ?? features.publicationTrustLevels;
  features.patternBasedSubscription =
      map['pattern_based_subscription'] ?? features.patternBasedSubscription;
  features.subscriptionRevocation =
      map['subscription_revocation'] ?? features.subscriptionRevocation;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

DealerFeatures? _mapDealerFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = DealerFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTrustLevels =
      map['call_trustlevels'] ?? features.callTrustLevels;
  features.patternBasedRegistration =
      map['pattern_based_registration'] ?? features.patternBasedRegistration;
  features.registrationMetaApi =
      map['registration_meta_api'] ?? features.registrationMetaApi;
  features.sharedRegistration =
      map['shared_registration'] ?? features.sharedRegistration;
  features.sessionMetaApi = map['session_meta_api'] ?? features.sessionMetaApi;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallInvocations =
      map['progressive_call_invocations'] ??
      features.progressiveCallInvocations;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

CalleeFeatures? _mapCalleeFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = CalleeFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTrustlevels =
      map['call_trustlevels'] ?? features.callTrustlevels;
  features.patternBasedRegistration =
      map['pattern_based_registration'] ?? features.patternBasedRegistration;
  features.sharedRegistration =
      map['shared_registration'] ?? features.sharedRegistration;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallInvocations =
      map['progressive_call_invocations'] ??
      features.progressiveCallInvocations;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

CallerFeatures? _mapCallerFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = CallerFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallInvocations =
      map['progressive_call_invocations'] ??
      features.progressiveCallInvocations;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

Map<String, dynamic> _extractCustomFields(
  Map<String, dynamic> map,
  Set<String> knownKeys,
) {
  final custom = <String, dynamic>{};
  for (final entry in map.entries) {
    if (!knownKeys.contains(entry.key)) {
      custom[entry.key] = entry.value;
    }
  }
  return custom;
}

String? _readOptionalMessageText(List<dynamic> message, int index) {
  final value = message.length > index ? message[index] : null;
  if (value is Map) {
    return value['message'] as String?;
  }
  return value as String?;
}

Map<String, dynamic>? _asStringKeyMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  throw ArgumentError('Expected map but received $value');
}

List<dynamic> _asDynamicList(Object? value) {
  if (value == null) {
    return const <dynamic>[];
  }
  if (value is List) {
    return List<dynamic>.from(value);
  }
  throw ArgumentError('Expected list but received $value');
}

int? _asInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

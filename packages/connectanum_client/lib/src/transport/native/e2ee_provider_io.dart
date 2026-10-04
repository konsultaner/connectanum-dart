import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor_serializer;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart'
    as flatbuffers_serializer;

import 'e2ee_file_segment.dart';
import 'native_transports_io.dart';
import 'message_binding.dart';
import 'runtime.dart';

/// Native implementation of the existing version-1 CBOR E2EE profile.
class NativeWampCborXsalsa20Poly1305Provider
    extends _NativeWampE2eeCipherProvider {
  NativeWampCborXsalsa20Poly1305Provider({
    required Map<String, List<int>> keys,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : this._(
         keys: keys,
         defaultKeyId: defaultKeyId,
         keySelectionPolicy: keySelectionPolicy,
         libraryPath: libraryPath,
         runtime: runtime,
         cipher: supportedCipher,
       );

  NativeWampCborXsalsa20Poly1305Provider._({
    required super.keys,
    required super.cipher,
    super.defaultKeyId,
    super.keySelectionPolicy,
    super.libraryPath,
    super.runtime,
  }) : super(
         payloadSerializer: cbor_serializer.Serializer(),
         serializerName: supportedSerializer,
         profileVersion: ConnectanumE2eeProfile.version,
       );

  NativeWampCborXsalsa20Poly1305Provider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
         libraryPath: libraryPath,
         runtime: runtime,
       );

  static const supportedSerializer = ConnectanumE2eeProfile.serializer;
  static const supportedCipher = ConnectanumE2eeProfile.xsalsa20Poly1305;
}

abstract class _NativeWampE2eeCipherProvider
    implements
        DisposableWampE2eeProvider,
        WampE2eePolicyAwareProvider,
        WampE2eeProfileSupport,
        WampE2eeRuntimePayloadProvider,
        WampE2eeNegotiatedKeySelectionProvider,
        NativeE2eeFileSegmentProvider {
  _NativeWampE2eeCipherProvider({
    required Map<String, List<int>> keys,
    required String cipher,
    required AbstractSerializer payloadSerializer,
    required String serializerName,
    required int profileVersion,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : _runtime =
           runtime ?? NativeClientRuntime.instance(libraryPath: libraryPath),
       _defaultKeyId = _resolveDefaultKeyId(keys, defaultKeyId),
       _knownKeyIds = Set.unmodifiable(keys.keys),
       _keySelectionPolicy = keySelectionPolicy,
       _cipher = cipher,
       _serializer = payloadSerializer,
       _serializerName = serializerName,
       _profileVersion = profileVersion {
    final normalizedKeys = _normalizeKeys(keys);
    final keyringHandle = _runtime.createE2eeKeyring();
    var sessionHandle = 0;
    try {
      for (final entry in normalizedKeys.entries) {
        _runtime.addE2eeKey(
          keyringHandle,
          entry.key,
          entry.value,
          makeDefault: _defaultKeyId != null && entry.key == _defaultKeyId,
        );
      }
      sessionHandle = _runtime.createE2eeSession(
        keyringHandle,
        defaultKeyId: _defaultKeyId,
      );
    } catch (_) {
      if (sessionHandle > 0) {
        _runtime.releaseE2eeSession(sessionHandle);
      }
      _runtime.releaseE2eeKeyring(keyringHandle);
      rethrow;
    }
    _keyringHandle = keyringHandle;
    _sessionHandle = sessionHandle;
  }

  final AbstractSerializer _serializer;
  final String _serializerName;
  final int _profileVersion;

  bool get _isTyped =>
      _profileVersion == ConnectanumFlatBuffersE2eeProfile.version;

  final NativeClientRuntime _runtime;
  final Set<String> _knownKeyIds;
  final String? _defaultKeyId;
  final WampE2eeKeySelectionPolicy? _keySelectionPolicy;
  final String _cipher;
  static final _negotiatedKeySelectionPolicy =
      WampE2eeKeySelectionPolicies.negotiated();

  @override
  bool get handlesNegotiatedKeySelection => _isTyped;
  late final int _keyringHandle;
  late final int _sessionHandle;
  bool _released = false;

  @override
  bool supportsE2eeProfile({
    required int version,
    required String scheme,
    required String serializer,
    required String cipher,
  }) {
    return version == _profileVersion &&
        scheme == ConnectanumE2eeProfile.scheme &&
        serializer == _serializerName &&
        cipher == _cipher;
  }

  String? get defaultKeyId => _defaultKeyId;

  @override
  WampE2eeKeySelectionPolicy? get keySelectionPolicy => _keySelectionPolicy;

  @override
  bool canUnpackFromRuntimeContext(
    WampE2eeRuntimeContext? runtimeContext,
  ) =>
      (_isTyped
          ? _runtime.supportsTypedConsumingE2eeMessagePayloadDecrypt
          : _runtime.supportsConsumingE2eeMessagePayloadDecrypt) &&
      nativeIncomingMessageForAnchor(runtimeContext?.payloadAnchor) != null;

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    // Typed preflight precedes key-policy callbacks and metadata defaults.
    _ensureOpen();
    _verifyScheme(options);
    _verifySerializer(options);
    final typedPlaintext = _isTyped
        ? _typedPlaintext(arguments, argumentsKeywords)
        : null;
    final segment = _prepareEncryption(options, runtimeContext: runtimeContext);
    final plaintext =
        typedPlaintext ??
        _serializer.serializePPT(
          PPTPayload(
            arguments: arguments,
            argumentsKeywords: argumentsKeywords,
          ),
        );
    try {
      return <dynamic>[
        _runtime.encryptE2ee(
          segment.sessionHandle,
          plaintext,
          keyId: segment.keyId,
          cipher: segment.cipher,
        ),
      ];
    } on NativeTransportException catch (error) {
      throw _mapNativeException('pack', options, error);
    }
  }

  @override
  bool get supportsNativeE2eeFileSegments => !_isTyped;

  @override
  NativeE2eeFileSegmentContext prepareNativeE2eeFileSegment(
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    if (_isTyped) {
      throw UnsupportedError(
        'Native E2EE file segments require the version-1 CBOR profile',
      );
    }
    return _prepareEncryption(options, runtimeContext: runtimeContext);
  }

  Uint8List _typedPlaintext(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  ) {
    final bytes = _serializer.serializePPT(
      PPTPayload(arguments: arguments, argumentsKeywords: argumentsKeywords),
    );
    final overhead = _cipher == ConnectanumE2eeProfile.aes256Gcm ? 28 : 40;
    if (bytes.length >
        ConnectanumFlatBuffersE2eeProfile.maximumCiphertextBytes - overhead) {
      throw ArgumentError('Typed E2EE ciphertext exceeds the byte limit');
    }
    return bytes;
  }

  NativeE2eeFileSegmentContext _prepareEncryption(
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    _ensureOpen();
    _verifyScheme(options);
    _verifySerializer(options);
    final keyId = _resolveKeyId(
      options,
      operation: 'pack',
      runtimeContext: runtimeContext,
    );
    _ensureOpen();
    _verifyScheme(options);
    _verifySerializer(options);
    _resolveCipher(options, operation: 'pack');
    options.pptScheme ??= 'wamp';
    options.pptSerializer ??= _serializerName;
    options.pptCipher ??= _cipher;
    options.pptKeyId ??= keyId;
    return NativeE2eeFileSegmentContext(
      runtimeIdentity: _runtime,
      sessionHandle: _sessionHandle,
      keyId: keyId,
      cipher: _cipher,
    );
  }

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    _ensureOpen();
    _verifyScheme(options);
    _verifySerializer(options);
    _resolveCipher(options, operation: 'unpack');
    final typedCiphertext = _isTyped && arguments != null
        ? _coerceEncryptedPayload(arguments, options)
        : null;
    final incoming = nativeIncomingMessageForAnchor(
      runtimeContext?.payloadAnchor,
    );
    if (_isTyped && incoming != null) {
      try {
        _runtime.preflightTypedE2eeMessageCiphertext(
          incoming,
          cipher: _cipher,
          minimumLength: _cipher == ConnectanumE2eeProfile.aes256Gcm
              ? ConnectanumE2eeProfile.aes256GcmNonceLength +
                    ConnectanumE2eeProfile.aes256GcmTagLength
              : 40,
          maximumLength:
              ConnectanumFlatBuffersE2eeProfile.maximumCiphertextBytes,
        );
      } on NativeTransportException catch (error) {
        throw _mapNativeException('unpack', options, error);
      }
    }
    final keyId = _resolveKeyId(
      options,
      operation: 'unpack',
      runtimeContext: runtimeContext,
    );
    final anchoredMessage = runtimeContext?.payloadAnchor;
    if (incoming != null &&
        anchoredMessage is NativeSessionMessage &&
        anchoredMessage.hasModifiedNativeWirePayload) {
      throw WampE2eeInvalidPayloadException(
        'unpack',
        options: options,
        reason: 'Native wire payload changed during key selection',
      );
    }
    _ensureOpen();
    _verifyScheme(options);
    _verifySerializer(options);
    _resolveCipher(options, operation: 'unpack');
    try {
      if (incoming != null) {
        final nativePayload = _runtime.decryptE2eeMessageSingleBinaryArgument(
          _sessionHandle,
          incoming,
          keyId: keyId,
          cipher: _cipher,
          plaintextFormat: _isTyped
              ? NativeE2eePlaintextFormat.typedFlatBuffers
              : NativeE2eePlaintextFormat.cborPpt,
        );
        if (nativePayload != null && nativePayload.directBinary) {
          return (
            arguments: <dynamic>[nativePayload.bytes],
            argumentsKeywords: null,
          );
        }
        if (nativePayload != null) {
          final decoded = _decodePlaintext(nativePayload.bytes, options);
          return (
            arguments: decoded.arguments,
            argumentsKeywords: decoded.argumentsKeywords,
          );
        }
      }
      final encryptedBytes =
          typedCiphertext ?? _coerceEncryptedPayload(arguments, options);
      final plaintext = _runtime.decryptE2ee(
        _sessionHandle,
        encryptedBytes,
        keyId: keyId,
        cipher: _cipher,
      );
      final decoded = _decodePlaintext(
        _isTyped ? plaintext.asUnmodifiableView() : plaintext,
        options,
      );
      return (
        arguments: decoded.arguments,
        argumentsKeywords: decoded.argumentsKeywords,
      );
    } on NativeTransportException catch (error) {
      throw _mapNativeException('unpack', options, error);
    }
  }

  PPTPayload _decodePlaintext(Uint8List plaintext, PPTOptions options) {
    final decoded = _serializer.deserializePPT(plaintext);
    if (decoded == null) {
      throw WampE2eeInvalidPayloadException(
        'unpack',
        options: options,
        reason: 'Decrypted payload is not a valid CBOR PPT envelope',
      );
    }
    return decoded;
  }

  @override
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _runtime.releaseE2eeSession(_sessionHandle);
    _runtime.releaseE2eeKeyring(_keyringHandle);
  }

  void _ensureOpen() {
    if (_released) {
      throw StateError('Native WAMP E2EE provider has already been released');
    }
  }

  void _verifyScheme(PPTOptions options) {
    final scheme = options.pptScheme;
    if (scheme != null && scheme != 'wamp') {
      throw ArgumentError.value(
        scheme,
        'pptScheme',
        'WAMP E2EE providers can only be used with ppt_scheme = "wamp"',
      );
    }
  }

  void _verifySerializer(PPTOptions options) {
    final serializer = options.pptSerializer;
    if (serializer != null && serializer != _serializerName) {
      throw ArgumentError.value(
        serializer,
        'pptSerializer',
        _isTyped
            ? 'This E2EE provider requires ppt_serializer = "flatbuffers"'
            : 'WAMP E2EE currently supports only ppt_serializer = "cbor"',
      );
    }
  }

  String _resolveCipher(PPTOptions options, {required String operation}) {
    final cipher = options.pptCipher ?? _cipher;
    if (cipher != _cipher) {
      throw WampE2eeUnsupportedCipherException(operation, options: options);
    }
    return cipher;
  }

  String _resolveKeyId(
    PPTOptions options, {
    required String operation,
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    final policyKeyId = options.pptKeyId == null
        ? _resolvePolicyKeyId(runtimeContext, options)
        : null;
    // Policy receives mutable options. Use and validate their current key ID
    // so emitted metadata and the actual cryptographic key cannot diverge.
    final keyId =
        options.pptKeyId ??
        policyKeyId ??
        (_isTyped && runtimeContext != null
            ? _negotiatedKeySelectionPolicy(runtimeContext, options)
            : null) ??
        _defaultKeyId;
    if (keyId == null) {
      throw WampE2eeKeyNotFoundException(
        operation,
        options: options,
        reason: 'No ppt_keyid was provided and the provider has no default key',
      );
    }
    if (!_knownKeyIds.contains(keyId)) {
      throw WampE2eeKeyNotFoundException(
        operation,
        options: options,
        reason: 'No key is configured for ppt_keyid "$keyId"',
      );
    }
    options.pptKeyId ??= keyId;
    return keyId;
  }

  String? _resolvePolicyKeyId(
    WampE2eeRuntimeContext? runtimeContext,
    PPTOptions options,
  ) {
    if (runtimeContext == null) {
      return null;
    }
    return _keySelectionPolicy?.call(runtimeContext, options);
  }

  Uint8List _coerceEncryptedPayload(
    List<dynamic>? arguments,
    PPTOptions options,
  ) {
    if (arguments == null || arguments.length != 1) {
      throw WampE2eeInvalidPayloadException(
        'unpack',
        options: options,
        reason: 'WAMP E2EE payloads must be a single binary argument',
      );
    }
    final value = arguments.single;
    if (_isTyped &&
        value is List &&
        value.length >
            ConnectanumFlatBuffersE2eeProfile.maximumCiphertextBytes) {
      throw WampE2eeInvalidPayloadException(
        'unpack',
        options: options,
        reason: 'Typed E2EE ciphertext exceeds the byte limit',
      );
    }
    if (_isTyped && value is List && value is! Uint8List) {
      final bytes = Uint8List(value.length);
      for (var index = 0; index < bytes.length; index++) {
        final byte = value[index];
        if (byte is! int || byte < 0 || byte > 255) {
          throw WampE2eeInvalidPayloadException(
            'unpack',
            options: options,
            reason: 'WAMP E2EE payload bytes must be integers from 0 to 255',
          );
        }
        bytes[index] = byte;
      }
      return bytes;
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    if (value is List) {
      return Uint8List.fromList(value.cast<int>());
    }
    throw WampE2eeInvalidPayloadException(
      'unpack',
      options: options,
      reason: 'WAMP E2EE payload must be a byte sequence',
    );
  }

  WampE2eeException _mapNativeException(
    String operation,
    PPTOptions options,
    NativeTransportException error,
  ) {
    return switch (error.code) {
      NativeTransportErrorCode.keyNotFound => WampE2eeKeyNotFoundException(
        operation,
        options: options,
      ),
      NativeTransportErrorCode.decryptionFailed => WampE2eeDecryptionException(
        operation,
        options: options,
        cause: error,
      ),
      _ => WampE2eeInvalidPayloadException(
        operation,
        options: options,
        reason: error.message,
      ),
    };
  }

  static Map<String, Uint8List> _normalizeKeys(Map<String, List<int>> keys) {
    if (keys.isEmpty) {
      throw ArgumentError.value(
        keys,
        'keys',
        'At least one E2EE key must be configured',
      );
    }
    final normalized = <String, Uint8List>{};
    for (final entry in keys.entries) {
      final keyId = entry.key;
      if (keyId.isEmpty) {
        throw ArgumentError.value(
          keyId,
          'keys',
          'E2EE key ids must not be empty',
        );
      }
      final bytes = Uint8List.fromList(entry.value);
      if (bytes.length != 32) {
        throw ArgumentError.value(
          entry.value,
          'keys',
          'E2EE key "$keyId" must be 32 bytes long',
        );
      }
      normalized[keyId] = bytes;
    }
    return normalized;
  }

  static String? _resolveDefaultKeyId(
    Map<String, List<int>> keys,
    String? defaultKeyId,
  ) {
    if (defaultKeyId != null) {
      if (!keys.containsKey(defaultKeyId)) {
        throw ArgumentError.value(
          defaultKeyId,
          'defaultKeyId',
          'Default E2EE key id must exist in the configured key set',
        );
      }
      return defaultKeyId;
    }
    return keys.length == 1 ? keys.keys.single : null;
  }
}

/// Native implementation of Connectanum's version-2 typed FlatBuffers profile.
///
/// Plaintext is one application byte span. Encryption still transforms bytes;
/// the consuming receive path retains a read-only native plaintext owner.
class NativeWampFlatBuffersXsalsa20Poly1305Provider
    extends _NativeWampE2eeCipherProvider {
  NativeWampFlatBuffersXsalsa20Poly1305Provider({
    required Map<String, List<int>> keys,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : this._(
         keys: keys,
         defaultKeyId: defaultKeyId,
         keySelectionPolicy: keySelectionPolicy,
         libraryPath: libraryPath,
         runtime: runtime,
         cipher: supportedCipher,
       );

  NativeWampFlatBuffersXsalsa20Poly1305Provider._({
    required super.keys,
    required super.cipher,
    super.defaultKeyId,
    super.keySelectionPolicy,
    super.libraryPath,
    super.runtime,
  }) : super(
         payloadSerializer: flatbuffers_serializer.Serializer(),
         serializerName: supportedSerializer,
         profileVersion: ConnectanumFlatBuffersE2eeProfile.version,
       );

  NativeWampFlatBuffersXsalsa20Poly1305Provider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
         libraryPath: libraryPath,
         runtime: runtime,
       );

  static const supportedSerializer =
      ConnectanumFlatBuffersE2eeProfile.serializer;
  static const supportedCipher = ConnectanumE2eeProfile.xsalsa20Poly1305;
}

class NativeWampFlatBuffersAes256GcmProvider
    extends NativeWampFlatBuffersXsalsa20Poly1305Provider {
  NativeWampFlatBuffersAes256GcmProvider({
    required super.keys,
    super.defaultKeyId,
    super.keySelectionPolicy,
    super.libraryPath,
    super.runtime,
  }) : super._(cipher: supportedCipher);

  NativeWampFlatBuffersAes256GcmProvider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
         libraryPath: libraryPath,
         runtime: runtime,
       );

  static const supportedSerializer =
      ConnectanumFlatBuffersE2eeProfile.serializer;
  static const supportedCipher = ConnectanumE2eeProfile.aes256Gcm;
}

class NativeWampCborAes256GcmProvider
    extends NativeWampCborXsalsa20Poly1305Provider {
  NativeWampCborAes256GcmProvider({
    required super.keys,
    super.defaultKeyId,
    super.keySelectionPolicy,
    super.libraryPath,
    super.runtime,
  }) : super._(cipher: supportedCipher);

  NativeWampCborAes256GcmProvider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
    NativeClientRuntime? runtime,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
         libraryPath: libraryPath,
         runtime: runtime,
       );

  static const supportedSerializer = ConnectanumE2eeProfile.serializer;
  static const supportedCipher = ConnectanumE2eeProfile.aes256Gcm;
}

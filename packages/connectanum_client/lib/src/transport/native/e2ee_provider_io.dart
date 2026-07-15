import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor_serializer;
import 'package:connectanum_core/connectanum_core.dart';

import 'runtime.dart';

class NativeWampCborXsalsa20Poly1305Provider
    implements
        DisposableWampE2eeProvider,
        WampE2eePolicyAwareProvider,
        WampE2eeProfileSupport {
  NativeWampCborXsalsa20Poly1305Provider({
    required Map<String, List<int>> keys,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    NativeClientRuntime? runtime,
  }) : this._(
         keys: keys,
         defaultKeyId: defaultKeyId,
         keySelectionPolicy: keySelectionPolicy,
         runtime: runtime,
         cipher: supportedCipher,
       );

  NativeWampCborXsalsa20Poly1305Provider._({
    required Map<String, List<int>> keys,
    required String cipher,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    NativeClientRuntime? runtime,
  }) : _runtime = runtime ?? NativeClientRuntime.instance(),
       _defaultKeyId = _resolveDefaultKeyId(keys, defaultKeyId),
       _knownKeyIds = Set.unmodifiable(keys.keys),
       _keySelectionPolicy = keySelectionPolicy,
       _cipher = cipher {
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

  NativeWampCborXsalsa20Poly1305Provider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    NativeClientRuntime? runtime,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
         runtime: runtime,
       );

  static const supportedSerializer = ConnectanumE2eeProfile.serializer;
  static const supportedCipher = ConnectanumE2eeProfile.xsalsa20Poly1305;

  static final cbor_serializer.Serializer _serializer =
      cbor_serializer.Serializer();

  final NativeClientRuntime _runtime;
  final Set<String> _knownKeyIds;
  final String? _defaultKeyId;
  final WampE2eeKeySelectionPolicy? _keySelectionPolicy;
  final String _cipher;
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
    return version == ConnectanumE2eeProfile.version &&
        scheme == ConnectanumE2eeProfile.scheme &&
        serializer == ConnectanumE2eeProfile.serializer &&
        cipher == _cipher;
  }

  String? get defaultKeyId => _defaultKeyId;

  @override
  WampE2eeKeySelectionPolicy? get keySelectionPolicy => _keySelectionPolicy;

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
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
    _resolveCipher(options, operation: 'pack');

    options.pptScheme ??= 'wamp';
    options.pptSerializer ??= supportedSerializer;
    options.pptCipher ??= _cipher;
    options.pptKeyId ??= keyId;

    final plaintext = Uint8List.fromList(
      _serializer.serializePPT(
        PPTPayload(arguments: arguments, argumentsKeywords: argumentsKeywords),
      ),
    );
    try {
      return <dynamic>[
        _runtime.encryptE2ee(
          _sessionHandle,
          plaintext,
          keyId: options.pptKeyId,
          cipher: _cipher,
        ),
      ];
    } on NativeTransportException catch (error) {
      throw _mapNativeException('pack', options, error);
    }
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
    final keyId = _resolveKeyId(
      options,
      operation: 'unpack',
      runtimeContext: runtimeContext,
    );
    final encryptedBytes = _coerceEncryptedPayload(arguments, options);
    try {
      final plaintext = _runtime.decryptE2ee(
        _sessionHandle,
        encryptedBytes,
        keyId: keyId,
        cipher: _cipher,
      );
      final decoded = _serializer.deserializePPT(plaintext);
      if (decoded == null) {
        throw WampE2eeInvalidPayloadException(
          'unpack',
          options: options,
          reason: 'Decrypted payload is not a valid CBOR PPT envelope',
        );
      }
      return (
        arguments: decoded.arguments,
        argumentsKeywords: decoded.argumentsKeywords,
      );
    } on NativeTransportException catch (error) {
      throw _mapNativeException('unpack', options, error);
    }
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
    if (serializer != null && serializer != supportedSerializer) {
      throw ArgumentError.value(
        serializer,
        'pptSerializer',
        'WAMP E2EE currently supports only ppt_serializer = "cbor"',
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
    final keyId =
        options.pptKeyId ??
        _resolvePolicyKeyId(runtimeContext, options) ??
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

class NativeWampCborAes256GcmProvider
    extends NativeWampCborXsalsa20Poly1305Provider {
  NativeWampCborAes256GcmProvider({
    required super.keys,
    super.defaultKeyId,
    super.keySelectionPolicy,
    super.runtime,
  }) : super._(cipher: supportedCipher);

  NativeWampCborAes256GcmProvider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    NativeClientRuntime? runtime,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
         runtime: runtime,
       );

  static const supportedSerializer = ConnectanumE2eeProfile.serializer;
  static const supportedCipher = ConnectanumE2eeProfile.aes256Gcm;
}

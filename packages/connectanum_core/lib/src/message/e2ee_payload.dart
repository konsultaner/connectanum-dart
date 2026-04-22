import 'dart:typed_data';

import 'package:pinenacl/api.dart' show EncryptedMessage;
import 'package:pinenacl/x25519.dart' show SecretBox;

import 'abstract_ppt_options.dart';
import '../message/ppt_payload.dart';
import '../serializer/cbor/serializer.dart' as cbor_serializer;

typedef E2EEPayloadView = ({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
});

enum WampE2eeDirection { outbound, inbound }

enum WampE2eeMessageType {
  call,
  publish,
  yield,
  event,
  result,
  invocation,
  error,
}

class WampE2eePartyContext {
  const WampE2eePartyContext({
    this.sessionId,
    this.authId,
    this.authRole,
    this.authMethod,
    this.authProvider,
    this.authExtra,
    this.trustLevel,
    this.details,
  });

  factory WampE2eePartyContext.fromDetails({
    int? sessionId,
    int? trustLevel,
    Map<String, dynamic>? details,
  }) {
    if (sessionId == null &&
        trustLevel == null &&
        (details == null || details.isEmpty)) {
      return const WampE2eePartyContext();
    }
    final copiedDetails = details == null || details.isEmpty
        ? null
        : Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(details));
    return WampE2eePartyContext(
      sessionId: sessionId,
      authId: copiedDetails?['authid'] as String?,
      authRole: copiedDetails?['authrole'] as String?,
      authMethod: copiedDetails?['authmethod'] as String?,
      authProvider: copiedDetails?['authprovider'] as String?,
      authExtra: _coerceStringDynamicMap(copiedDetails?['authextra']),
      trustLevel: trustLevel,
      details: copiedDetails,
    );
  }

  final int? sessionId;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final Map<String, dynamic>? authExtra;
  final int? trustLevel;
  final Map<String, dynamic>? details;

  bool get isEmpty =>
      sessionId == null &&
      authId == null &&
      authRole == null &&
      authMethod == null &&
      authProvider == null &&
      authExtra == null &&
      trustLevel == null &&
      details == null;

  WampE2eePartyContext copyWith({
    Object? sessionId = _unsetContextValue,
    Object? authId = _unsetContextValue,
    Object? authRole = _unsetContextValue,
    Object? authMethod = _unsetContextValue,
    Object? authProvider = _unsetContextValue,
    Object? authExtra = _unsetContextValue,
    Object? trustLevel = _unsetContextValue,
    Object? details = _unsetContextValue,
  }) {
    return WampE2eePartyContext(
      sessionId: identical(sessionId, _unsetContextValue)
          ? this.sessionId
          : sessionId as int?,
      authId: identical(authId, _unsetContextValue)
          ? this.authId
          : authId as String?,
      authRole: identical(authRole, _unsetContextValue)
          ? this.authRole
          : authRole as String?,
      authMethod: identical(authMethod, _unsetContextValue)
          ? this.authMethod
          : authMethod as String?,
      authProvider: identical(authProvider, _unsetContextValue)
          ? this.authProvider
          : authProvider as String?,
      authExtra: identical(authExtra, _unsetContextValue)
          ? this.authExtra
          : authExtra as Map<String, dynamic>?,
      trustLevel: identical(trustLevel, _unsetContextValue)
          ? this.trustLevel
          : trustLevel as int?,
      details: identical(details, _unsetContextValue)
          ? this.details
          : details as Map<String, dynamic>?,
    );
  }
}

class WampE2eeRuntimeContext {
  const WampE2eeRuntimeContext({
    required this.direction,
    required this.messageType,
    this.realm,
    this.uri,
    this.local,
    this.peer,
    this.negotiated,
  });

  final WampE2eeDirection direction;
  final WampE2eeMessageType messageType;
  final String? realm;
  final String? uri;
  final WampE2eePartyContext? local;
  final WampE2eePartyContext? peer;
  final Map<String, dynamic>? negotiated;

  WampE2eeRuntimeContext copyWith({
    WampE2eeDirection? direction,
    WampE2eeMessageType? messageType,
    Object? realm = _unsetContextValue,
    Object? uri = _unsetContextValue,
    Object? local = _unsetContextValue,
    Object? peer = _unsetContextValue,
    Object? negotiated = _unsetContextValue,
  }) {
    return WampE2eeRuntimeContext(
      direction: direction ?? this.direction,
      messageType: messageType ?? this.messageType,
      realm: identical(realm, _unsetContextValue)
          ? this.realm
          : realm as String?,
      uri: identical(uri, _unsetContextValue) ? this.uri : uri as String?,
      local: identical(local, _unsetContextValue)
          ? this.local
          : local as WampE2eePartyContext?,
      peer: identical(peer, _unsetContextValue)
          ? this.peer
          : peer as WampE2eePartyContext?,
      negotiated: identical(negotiated, _unsetContextValue)
          ? this.negotiated
          : negotiated as Map<String, dynamic>?,
    );
  }
}

typedef WampE2eeKeySelectionPolicy =
    String? Function(WampE2eeRuntimeContext runtimeContext, PPTOptions options);

abstract class WampE2eeProvider {
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  });

  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  });
}

abstract class DisposableWampE2eeProvider implements WampE2eeProvider {
  void release();
}

abstract class WampE2eeException implements Exception {
  WampE2eeException(
    this.operation, {
    required this.options,
    this.reason,
    this.cause,
  });

  final String operation;
  final PPTOptions options;
  final String? reason;
  final Object? cause;

  @override
  String toString() {
    final fields = <String>[
      'operation: $operation',
      ..._formatE2eeOptions(options),
      if (reason != null) 'reason: $reason',
      if (cause != null) 'cause: $cause',
    ];
    return '$runtimeType(${fields.join(', ')})';
  }
}

class WampE2eeProviderUnavailableException extends WampE2eeException {
  WampE2eeProviderUnavailableException(
    super.operation, {
    required super.options,
  }) : super(reason: 'No WAMP E2EE provider is attached');
}

class WampE2eeUnsupportedCipherException extends WampE2eeException {
  WampE2eeUnsupportedCipherException(super.operation, {required super.options})
    : super(reason: 'Only xsalsa20poly1305 is supported for WAMP E2EE');
}

class WampE2eeKeyNotFoundException extends WampE2eeException {
  WampE2eeKeyNotFoundException(
    super.operation, {
    required super.options,
    super.reason,
  });
}

class WampE2eeInvalidPayloadException extends WampE2eeException {
  WampE2eeInvalidPayloadException(
    super.operation, {
    required super.options,
    super.reason,
  });
}

class WampE2eeDecryptionException extends WampE2eeException {
  WampE2eeDecryptionException(
    super.operation, {
    required super.options,
    super.cause,
  }) : super(
         reason:
             'The encrypted payload could not be authenticated or decrypted',
       );
}

class WampCborXsalsa20Poly1305Provider implements WampE2eeProvider {
  WampCborXsalsa20Poly1305Provider({
    required Map<String, List<int>> keys,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
  }) : _keys = Map.unmodifiable(_normalizeKeys(keys)),
       _defaultKeyId = _resolveDefaultKeyId(keys, defaultKeyId),
       _keySelectionPolicy = keySelectionPolicy;

  WampCborXsalsa20Poly1305Provider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
  }) : this(
         keys: {keyId: key},
         defaultKeyId: keyId,
         keySelectionPolicy: keySelectionPolicy,
       );

  static const supportedSerializer = 'cbor';
  static const supportedCipher = 'xsalsa20poly1305';

  static final cbor_serializer.Serializer _serializer =
      cbor_serializer.Serializer();

  final Map<String, Uint8List> _keys;
  final String? _defaultKeyId;
  final WampE2eeKeySelectionPolicy? _keySelectionPolicy;

  String? get defaultKeyId => _defaultKeyId;

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
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
    options.pptCipher ??= supportedCipher;
    options.pptKeyId ??= keyId;

    final plaintext = Uint8List.fromList(
      _serializer.serializePPT(
        PPTPayload(arguments: arguments, argumentsKeywords: argumentsKeywords),
      ),
    );
    final encrypted = SecretBox(_keys[keyId]!).encrypt(plaintext);
    return <dynamic>[Uint8List.fromList(encrypted)];
  }

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    _verifyScheme(options);
    _verifySerializer(options);
    _resolveCipher(options, operation: 'unpack');
    final keyId = _resolveKeyId(
      options,
      operation: 'unpack',
      runtimeContext: runtimeContext,
    );
    final encryptedBytes = _coerceEncryptedPayload(arguments, options);

    final decoded = _decryptPayload(encryptedBytes, options, _keys[keyId]!);
    return (
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
    );
  }

  PPTPayload _decryptPayload(
    Uint8List encryptedBytes,
    PPTOptions options,
    Uint8List key,
  ) {
    final plaintext = (() {
      try {
        return SecretBox(
          key,
        ).decrypt(EncryptedMessage.fromList(encryptedBytes));
      } catch (error) {
        throw WampE2eeDecryptionException(
          'unpack',
          options: options,
          cause: error,
        );
      }
    })();

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
    final cipher = options.pptCipher ?? supportedCipher;
    if (cipher != supportedCipher) {
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
    if (!_keys.containsKey(keyId)) {
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
      if (bytes.length != SecretBox.keyLength) {
        throw ArgumentError.value(
          entry.value,
          'keys',
          'E2EE key "$keyId" must be ${SecretBox.keyLength} bytes long',
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

class E2EEPayload extends PPTPayload {
  String? uri;

  E2EEPayload({this.uri, arguments, argumentsKeywords}) {
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  /// Packs E2EE Payload and returns 1-item array for WAMP message arguments
  static List<dynamic> packE2EEPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeProvider? provider,
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    final resolvedProvider = provider;
    if (resolvedProvider == null) {
      throw WampE2eeProviderUnavailableException('pack', options: options);
    }
    return resolvedProvider.packPayload(
      arguments,
      argumentsKeywords,
      options,
      runtimeContext: runtimeContext,
    );
  }

  static E2EEPayload unpackE2EEPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeProvider? provider,
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    final resolvedProvider = provider;
    if (resolvedProvider == null) {
      throw WampE2eeProviderUnavailableException('unpack', options: options);
    }
    final decoded = resolvedProvider.unpackPayload(
      arguments,
      options,
      runtimeContext: runtimeContext,
    );
    return E2EEPayload(
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
    );
  }
}

List<String> _formatE2eeOptions(PPTOptions options) {
  return <String>[
    "pptScheme=${options.pptScheme ?? 'null'}",
    "pptSerializer=${options.pptSerializer ?? 'null'}",
    "pptCipher=${options.pptCipher ?? 'null'}",
    "pptKeyId=${options.pptKeyId ?? 'null'}",
  ];
}

const Object _unsetContextValue = Object();

Map<String, dynamic>? _coerceStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(value);
  }
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, entryValue) => MapEntry(key.toString(), entryValue)),
    );
  }
  return null;
}

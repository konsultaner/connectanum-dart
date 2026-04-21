import 'dart:typed_data';

import 'abstract_message.dart';
import 'abstract_ppt_options.dart';
import 'e2ee_payload.dart';
import 'ppt_payload.dart';

typedef PayloadListDecoder = List<dynamic> Function(Uint8List bytes);
typedef PayloadMapDecoder = Map<String, dynamic> Function(Uint8List bytes);
typedef MaterializedPayloadView = ({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
});
typedef PackedPayloadDecoder =
    MaterializedPayloadView Function(Uint8List bytes);

enum LazyPayloadEncoding { json, messagePack, cbor }

class LazyMessagePayload {
  LazyMessagePayload._({
    this.transparentBinaryPayload,
    this.encoding,
    this.pptDecoded = false,
    this.e2eeProvider,
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    PayloadListDecoder? argumentsDecoder,
    PayloadMapDecoder? argumentsKeywordsDecoder,
    Uint8List? packedPayloadBytes,
    PackedPayloadDecoder? packedPayloadDecoder,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    this.anchor,
  }) : _argumentsBytes = argumentsBytes,
       _argumentsKeywordsBytes = argumentsKeywordsBytes,
       _argumentsDecoder = argumentsDecoder,
       _argumentsKeywordsDecoder = argumentsKeywordsDecoder,
       _packedPayloadBytes = packedPayloadBytes,
       _packedPayloadDecoder = packedPayloadDecoder,
       _arguments = arguments,
       _argumentsKeywords = argumentsKeywords;

  factory LazyMessagePayload.encoded({
    Uint8List? transparentBinaryPayload,
    LazyPayloadEncoding? encoding,
    WampE2eeProvider? e2eeProvider,
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    PayloadListDecoder? argumentsDecoder,
    PayloadMapDecoder? argumentsKeywordsDecoder,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    Object? anchor,
  }) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      e2eeProvider: e2eeProvider,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      argumentsDecoder: argumentsDecoder,
      argumentsKeywordsDecoder: argumentsKeywordsDecoder,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      packedPayloadBytes: null,
      packedPayloadDecoder: null,
      anchor: anchor,
    );
  }

  factory LazyMessagePayload.packed({
    Uint8List? transparentBinaryPayload,
    required LazyPayloadEncoding? encoding,
    required Uint8List packedPayloadBytes,
    required PackedPayloadDecoder packedPayloadDecoder,
    bool pptDecoded = true,
    WampE2eeProvider? e2eeProvider,
    Object? anchor,
  }) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      e2eeProvider: e2eeProvider,
      packedPayloadBytes: packedPayloadBytes,
      packedPayloadDecoder: packedPayloadDecoder,
      pptDecoded: pptDecoded,
      anchor: anchor,
    );
  }

  factory LazyMessagePayload.materialized({
    Uint8List? transparentBinaryPayload,
    LazyPayloadEncoding? encoding,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    bool pptDecoded = false,
    WampE2eeProvider? e2eeProvider,
    Object? anchor,
  }) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      e2eeProvider: e2eeProvider,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      pptDecoded: pptDecoded,
      anchor: anchor,
    );
  }

  final Uint8List? transparentBinaryPayload;
  final LazyPayloadEncoding? encoding;
  final bool pptDecoded;
  final WampE2eeProvider? e2eeProvider;
  final Object? anchor;

  Uint8List? _argumentsBytes;
  Uint8List? _argumentsKeywordsBytes;
  PayloadListDecoder? _argumentsDecoder;
  PayloadMapDecoder? _argumentsKeywordsDecoder;
  Uint8List? _packedPayloadBytes;
  PackedPayloadDecoder? _packedPayloadDecoder;
  List<dynamic>? _arguments;
  Map<String, dynamic>? _argumentsKeywords;

  bool get hasEncodedArguments => _argumentsBytes != null;

  bool get hasEncodedArgumentsKeywords => _argumentsKeywordsBytes != null;

  Uint8List? get argumentsBytes => _argumentsBytes;

  Uint8List? get argumentsKeywordsBytes => _argumentsKeywordsBytes;

  bool get hasPackedPayloadBytes => _packedPayloadBytes != null;

  Uint8List? get packedPayloadBytes => _packedPayloadBytes;

  List<dynamic>? get arguments {
    _decodePackedPayloadIfNeeded();
    if (_arguments == null &&
        _argumentsBytes != null &&
        _argumentsDecoder != null) {
      _arguments = _argumentsDecoder!(_argumentsBytes!);
    }
    return _arguments;
  }

  Map<String, dynamic>? get argumentsKeywords {
    _decodePackedPayloadIfNeeded();
    if (_argumentsKeywords == null &&
        _argumentsKeywordsBytes != null &&
        _argumentsKeywordsDecoder != null) {
      _argumentsKeywords = _argumentsKeywordsDecoder!(_argumentsKeywordsBytes!);
    }
    return _argumentsKeywords;
  }

  LazyMessagePayload toOwned() {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload == null
          ? null
          : Uint8List.fromList(transparentBinaryPayload!),
      encoding: encoding,
      pptDecoded: pptDecoded,
      e2eeProvider: e2eeProvider,
      argumentsBytes: _argumentsBytes == null
          ? null
          : Uint8List.fromList(_argumentsBytes!),
      argumentsKeywordsBytes: _argumentsKeywordsBytes == null
          ? null
          : Uint8List.fromList(_argumentsKeywordsBytes!),
      argumentsDecoder: _argumentsDecoder,
      argumentsKeywordsDecoder: _argumentsKeywordsDecoder,
      packedPayloadBytes: _packedPayloadBytes == null
          ? null
          : Uint8List.fromList(_packedPayloadBytes!),
      packedPayloadDecoder: _packedPayloadDecoder,
      arguments: _arguments == null ? null : List<dynamic>.from(_arguments!),
      argumentsKeywords: _argumentsKeywords == null
          ? null
          : Map<String, dynamic>.from(_argumentsKeywords!),
    );
  }

  void _decodePackedPayloadIfNeeded() {
    if (_packedPayloadBytes == null || _packedPayloadDecoder == null) {
      return;
    }
    if (_arguments != null || _argumentsKeywords != null) {
      return;
    }
    final decoded = _packedPayloadDecoder!(_packedPayloadBytes!);
    _arguments = decoded.arguments;
    _argumentsKeywords = decoded.argumentsKeywords;
  }

  LazyMessagePayload withAnchor(Object? anchor) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      pptDecoded: pptDecoded,
      e2eeProvider: e2eeProvider,
      argumentsBytes: _argumentsBytes,
      argumentsKeywordsBytes: _argumentsKeywordsBytes,
      argumentsDecoder: _argumentsDecoder,
      argumentsKeywordsDecoder: _argumentsKeywordsDecoder,
      packedPayloadBytes: _packedPayloadBytes,
      packedPayloadDecoder: _packedPayloadDecoder,
      arguments: _arguments,
      argumentsKeywords: _argumentsKeywords,
      anchor: anchor,
    );
  }

  LazyMessagePayload withE2eeProvider(WampE2eeProvider? provider) {
    if (provider == e2eeProvider) {
      return this;
    }
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      pptDecoded: pptDecoded,
      e2eeProvider: provider,
      argumentsBytes: _argumentsBytes,
      argumentsKeywordsBytes: _argumentsKeywordsBytes,
      argumentsDecoder: _argumentsDecoder,
      argumentsKeywordsDecoder: _argumentsKeywordsDecoder,
      packedPayloadBytes: _packedPayloadBytes,
      packedPayloadDecoder: _packedPayloadDecoder,
      arguments: _arguments,
      argumentsKeywords: _argumentsKeywords,
      anchor: anchor,
    );
  }
}

MaterializedPayloadView decodePayloadView(
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords, {
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  WampE2eeProvider? e2eeProvider,
}) {
  if (pptScheme == null) {
    return (arguments: arguments, argumentsKeywords: argumentsKeywords);
  }

  final options = _InlinePptOptions(
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
  );
  if (pptScheme == 'wamp') {
    final e2eePayload = E2EEPayload.unpackE2EEPayload(
      arguments,
      options,
      provider: e2eeProvider,
    );
    return (
      arguments: e2eePayload.arguments,
      argumentsKeywords: e2eePayload.argumentsKeywords,
    );
  }
  final pptPayload = PPTPayload.unpackPPTPayload(arguments, options);
  return (
    arguments: pptPayload.arguments,
    argumentsKeywords: pptPayload.argumentsKeywords,
  );
}

MaterializedPayloadView decodeLazyPayloadView(
  LazyMessagePayload payload, {
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  WampE2eeProvider? e2eeProvider,
}) {
  if (payload.pptDecoded) {
    return (
      arguments: payload.arguments,
      argumentsKeywords: payload.argumentsKeywords,
    );
  }
  return decodePayloadView(
    payload.arguments,
    payload.argumentsKeywords,
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
    e2eeProvider: e2eeProvider ?? payload.e2eeProvider,
  );
}

LazyMessagePayload unwrapLazyPayloadView(
  LazyMessagePayload payload, {
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  WampE2eeProvider? e2eeProvider,
}) {
  final resolvedE2eeProvider = e2eeProvider ?? payload.e2eeProvider;
  if (pptScheme == null ||
      payload.pptDecoded ||
      payload.packedPayloadBytes != null) {
    return payload.withE2eeProvider(resolvedE2eeProvider);
  }
  final outerArguments = payload.arguments;
  final outerArgumentsKeywords = payload.argumentsKeywords;
  if (outerArguments == null || outerArguments.isEmpty) {
    return LazyMessagePayload.materialized(
      transparentBinaryPayload: payload.transparentBinaryPayload,
      encoding: payload.encoding,
      arguments: const <dynamic>[],
      argumentsKeywords: const <String, dynamic>{},
      pptDecoded: true,
      e2eeProvider: resolvedE2eeProvider,
      anchor: payload.anchor,
    );
  }
  final packedPayloadBytes = _extractWrappedPayloadBytes(
    outerArguments,
    outerArgumentsKeywords,
  );
  if (packedPayloadBytes != null) {
    return LazyMessagePayload.packed(
      transparentBinaryPayload: payload.transparentBinaryPayload,
      encoding: _lazyEncodingFromPptSerializer(pptSerializer),
      packedPayloadBytes: packedPayloadBytes,
      packedPayloadDecoder: (bytes) {
        final decoded = decodePayloadView(
          <dynamic>[bytes],
          null,
          pptScheme: pptScheme,
          pptSerializer: pptSerializer,
          pptCipher: pptCipher,
          pptKeyId: pptKeyId,
          e2eeProvider: resolvedE2eeProvider,
        );
        return (
          arguments: decoded.arguments,
          argumentsKeywords: decoded.argumentsKeywords,
        );
      },
      e2eeProvider: resolvedE2eeProvider,
      anchor: payload.anchor,
    );
  }
  final decoded = decodeLazyPayloadView(
    payload,
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
    e2eeProvider: resolvedE2eeProvider,
  );
  return LazyMessagePayload.materialized(
    transparentBinaryPayload: payload.transparentBinaryPayload,
    encoding: payload.encoding,
    arguments: decoded.arguments,
    argumentsKeywords: decoded.argumentsKeywords,
    pptDecoded: true,
    e2eeProvider: resolvedE2eeProvider,
    anchor: payload.anchor,
  );
}

LazyPayloadEncoding? _lazyEncodingFromPptSerializer(String? serializer) {
  return switch (serializer) {
    'json' => LazyPayloadEncoding.json,
    'msgpack' => LazyPayloadEncoding.messagePack,
    'cbor' => LazyPayloadEncoding.cbor,
    _ => null,
  };
}

Uint8List _coercePptBinaryPayload(Object? value) {
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  if (value is List) {
    return Uint8List.fromList(value.cast<int>());
  }
  throw ArgumentError.value(
    value,
    'value',
    'PPT payload must be a byte sequence',
  );
}

Uint8List? _extractWrappedPayloadBytes(
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
) {
  if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
    return null;
  }
  if (arguments == null || arguments.length != 1) {
    return null;
  }
  final first = arguments.first;
  if (!_isBinaryPayloadValue(first)) {
    return null;
  }
  return _coercePptBinaryPayload(first);
}

class _InlinePptOptions extends PPTOptions {
  _InlinePptOptions({
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
  }) {
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
  }

  @override
  bool verify() => true;
}

/// CALL,EVENT,RESULT,ERROR,PUBLISH,INVOCATION,YIELD may have a transparent payload
abstract class AbstractMessageWithPayload extends AbstractMessage {
  Uint8List? transparentBinaryPayload;

  List<dynamic>? _arguments;
  Map<String, dynamic>? _argumentsKeywords;

  Uint8List? _encodedArguments;
  Uint8List? _encodedArgumentsKeywords;
  PayloadListDecoder? _argumentsDecoder;
  PayloadMapDecoder? _argumentsKeywordsDecoder;
  LazyPayloadEncoding? _lazyPayloadEncoding;
  bool _pptPayloadDecoded = false;
  LazyMessagePayload? _retainedLazyPayload;
  WampE2eeProvider? _e2eeProvider;

  AbstractMessageWithPayload({
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  List<dynamic>? get arguments {
    if (_arguments == null &&
        _encodedArguments != null &&
        _argumentsDecoder != null) {
      _arguments = _argumentsDecoder!(_encodedArguments!);
    }
    return _arguments;
  }

  set arguments(List<dynamic>? value) {
    _arguments = value;
    _encodedArguments = null;
    _argumentsDecoder = null;
    _pptPayloadDecoded = false;
    _retainedLazyPayload = null;
  }

  Map<String, dynamic>? get argumentsKeywords {
    if (_argumentsKeywords == null &&
        _encodedArgumentsKeywords != null &&
        _argumentsKeywordsDecoder != null) {
      _argumentsKeywords = _argumentsKeywordsDecoder!(
        _encodedArgumentsKeywords!,
      );
    }
    return _argumentsKeywords;
  }

  set argumentsKeywords(Map<String, dynamic>? value) {
    _argumentsKeywords = value;
    _encodedArgumentsKeywords = null;
    _argumentsKeywordsDecoder = null;
    _pptPayloadDecoded = false;
    _retainedLazyPayload = null;
  }

  bool get hasLazyArguments => _encodedArguments != null;

  bool get hasLazyArgumentsKeywords => _encodedArgumentsKeywords != null;

  Uint8List? get debugEncodedArgumentsBytes => _encodedArguments;

  Uint8List? get debugEncodedArgumentsKeywordsBytes =>
      _encodedArgumentsKeywords;

  LazyPayloadEncoding? get lazyPayloadEncoding => _lazyPayloadEncoding;

  bool get hasDecodedPptPayload => _pptPayloadDecoded;

  WampE2eeProvider? get e2eeProvider =>
      _retainedLazyPayload?.e2eeProvider ?? _e2eeProvider;

  void attachE2eeProvider(WampE2eeProvider? provider) {
    _e2eeProvider = provider;
    final retainedLazyPayload = _retainedLazyPayload;
    if (retainedLazyPayload != null) {
      _retainedLazyPayload = retainedLazyPayload
          .withE2eeProvider(provider)
          .withAnchor(this);
    }
  }

  void markPptPayloadDecoded() {
    _pptPayloadDecoded = true;
  }

  LazyMessagePayload toLazyPayload({Object? anchor}) {
    final retainedLazyPayload = _retainedLazyPayload;
    if (retainedLazyPayload != null) {
      return retainedLazyPayload.withAnchor(anchor ?? this);
    }
    if (_pptPayloadDecoded) {
      return LazyMessagePayload.materialized(
        transparentBinaryPayload: transparentBinaryPayload,
        encoding: _lazyPayloadEncoding,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        pptDecoded: true,
        e2eeProvider: e2eeProvider,
        anchor: anchor ?? this,
      );
    }
    if ((_encodedArguments != null && _argumentsDecoder != null) ||
        (_encodedArgumentsKeywords != null &&
            _argumentsKeywordsDecoder != null)) {
      return LazyMessagePayload.encoded(
        transparentBinaryPayload: transparentBinaryPayload,
        encoding: _lazyPayloadEncoding,
        argumentsBytes: _encodedArguments,
        argumentsKeywordsBytes: _encodedArgumentsKeywords,
        argumentsDecoder: _argumentsDecoder,
        argumentsKeywordsDecoder: _argumentsKeywordsDecoder,
        arguments: _encodedArguments == null ? _arguments : null,
        argumentsKeywords: _encodedArgumentsKeywords == null
            ? _argumentsKeywords
            : null,
        e2eeProvider: e2eeProvider,
        anchor: anchor ?? this,
      );
    }
    return LazyMessagePayload.materialized(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: _lazyPayloadEncoding,
      arguments: _arguments,
      argumentsKeywords: _argumentsKeywords,
      e2eeProvider: e2eeProvider,
      anchor: anchor ?? this,
    );
  }

  /// Sets encoded payload slices that can be lazily decoded on demand.
  void setLazyPayload({
    Uint8List? argumentsBytes,
    PayloadListDecoder? argumentsDecoder,
    Uint8List? argumentsKeywordsBytes,
    PayloadMapDecoder? argumentsKeywordsDecoder,
    LazyPayloadEncoding? encoding,
  }) {
    _lazyPayloadEncoding = encoding;
    _pptPayloadDecoded = false;
    _retainedLazyPayload = null;
    if (argumentsBytes != null && argumentsDecoder != null) {
      _encodedArguments = argumentsBytes;
      _argumentsDecoder = argumentsDecoder;
      _arguments = null;
    }
    if (argumentsKeywordsBytes != null && argumentsKeywordsDecoder != null) {
      _encodedArgumentsKeywords = argumentsKeywordsBytes;
      _argumentsKeywordsDecoder = argumentsKeywordsDecoder;
      _argumentsKeywords = null;
    }
  }

  void retainLazyPayload(LazyMessagePayload payload) {
    final provider = payload.e2eeProvider ?? _e2eeProvider;
    _e2eeProvider = provider;
    _retainedLazyPayload = payload.withE2eeProvider(provider).withAnchor(this);
    _lazyPayloadEncoding ??= payload.encoding;
  }

  /// Rehydrates a materialized message from a shared lazy payload view without
  /// forcing an eager decode. Packed PPT payloads are restored as outer
  /// arguments so decode-on-access still works for classic getters.
  void restoreLazyPayload(LazyMessagePayload payload) {
    final provider = payload.e2eeProvider ?? _e2eeProvider;
    transparentBinaryPayload = payload.transparentBinaryPayload;
    _lazyPayloadEncoding = payload.encoding;
    if (payload.packedPayloadBytes != null) {
      arguments = <dynamic>[payload.packedPayloadBytes!];
      argumentsKeywords = null;
      attachE2eeProvider(provider);
      retainLazyPayload(payload.withE2eeProvider(provider));
      return;
    }
    setLazyPayload(
      argumentsBytes: payload.argumentsBytes,
      argumentsDecoder: payload.argumentsBytes == null
          ? null
          : (_) => payload.arguments ?? const <dynamic>[],
      argumentsKeywordsBytes: payload.argumentsKeywordsBytes,
      argumentsKeywordsDecoder: payload.argumentsKeywordsBytes == null
          ? null
          : (_) => payload.argumentsKeywords ?? const <String, dynamic>{},
      encoding: payload.encoding,
    );
    if (!payload.hasEncodedArguments) {
      arguments = payload.arguments;
    }
    if (!payload.hasEncodedArgumentsKeywords) {
      argumentsKeywords = payload.argumentsKeywords;
    }
    if (payload.pptDecoded) {
      markPptPayloadDecoded();
    }
    attachE2eeProvider(provider);
    retainLazyPayload(payload.withE2eeProvider(provider));
  }

  /// Unpacks PPT/E2EE payloads in place only when a caller actually touches the
  /// materialized payload getters. The original lazy bytes are retained so the
  /// message can still be forwarded without forcing a re-encode.
  void ensureDecodedPayloadView({
    required String? pptScheme,
    required String? pptSerializer,
    required String? pptCipher,
    required String? pptKeyId,
  }) {
    if (pptScheme == null || _pptPayloadDecoded) {
      return;
    }
    final retainedPayload = toLazyPayload(anchor: this);
    final rawArguments = _arguments ?? _decodeArgumentsBytes();
    final rawArgumentsKeywords =
        _argumentsKeywords ?? _decodeArgumentsKeywordsBytes();
    if (!_payloadLooksPackedForPpt(
      rawArguments,
      rawArgumentsKeywords,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
    )) {
      retainLazyPayload(retainedPayload);
      _pptPayloadDecoded = true;
      return;
    }
    final decoded = decodePayloadView(
      rawArguments,
      rawArgumentsKeywords,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
      e2eeProvider: e2eeProvider,
    );
    _arguments = decoded.arguments;
    _argumentsKeywords = decoded.argumentsKeywords;
    retainLazyPayload(retainedPayload);
    _pptPayloadDecoded = true;
  }

  List<dynamic>? _decodeArgumentsBytes() {
    if (_encodedArguments == null || _argumentsDecoder == null) {
      return null;
    }
    _arguments = _argumentsDecoder!(_encodedArguments!);
    return _arguments;
  }

  Map<String, dynamic>? _decodeArgumentsKeywordsBytes() {
    if (_encodedArgumentsKeywords == null ||
        _argumentsKeywordsDecoder == null) {
      return null;
    }
    _argumentsKeywords = _argumentsKeywordsDecoder!(_encodedArgumentsKeywords!);
    return _argumentsKeywords;
  }

  /// Transfers the message payload to another message
  void copyPayloadTo(AbstractMessageWithPayload message) {
    message.attachE2eeProvider(e2eeProvider);
    message.transparentBinaryPayload = transparentBinaryPayload;

    if ((_encodedArguments != null && _argumentsDecoder != null) ||
        (_encodedArgumentsKeywords != null &&
            _argumentsKeywordsDecoder != null)) {
      message.setLazyPayload(
        argumentsBytes: _encodedArguments == null
            ? null
            : Uint8List.fromList(_encodedArguments!),
        argumentsDecoder: _argumentsDecoder,
        argumentsKeywordsBytes: _encodedArgumentsKeywords == null
            ? null
            : Uint8List.fromList(_encodedArgumentsKeywords!),
        argumentsKeywordsDecoder: _argumentsKeywordsDecoder,
        encoding: _lazyPayloadEncoding,
      );
      if (_encodedArguments == null) {
        message.arguments = _arguments == null
            ? null
            : List<dynamic>.from(_arguments!);
      }
      if (_encodedArgumentsKeywords == null) {
        message.argumentsKeywords = _argumentsKeywords == null
            ? null
            : Map<String, dynamic>.from(_argumentsKeywords!);
      }
      message._pptPayloadDecoded = _pptPayloadDecoded;
    } else {
      message._lazyPayloadEncoding = _lazyPayloadEncoding;
      message.arguments = _arguments == null
          ? null
          : List<dynamic>.from(_arguments!);
      message.argumentsKeywords = _argumentsKeywords == null
          ? null
          : Map<String, dynamic>.from(_argumentsKeywords!);
      message._pptPayloadDecoded = _pptPayloadDecoded;
    }
    final retainedLazyPayload = _retainedLazyPayload;
    if (retainedLazyPayload != null) {
      message.retainLazyPayload(retainedLazyPayload.toOwned());
    }
  }
}

bool _payloadLooksPackedForPpt(
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords, {
  required String? pptScheme,
  required String? pptSerializer,
}) {
  if (pptScheme == null) {
    return false;
  }
  if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
    return false;
  }
  if (arguments == null || arguments.isEmpty) {
    return false;
  }
  final first = arguments.first;
  if (pptScheme == 'wamp') {
    return _isBinaryPayloadValue(first);
  }
  if (pptSerializer == null ||
      (pptSerializer != 'json' &&
          pptSerializer != 'msgpack' &&
          pptSerializer != 'cbor')) {
    return arguments.length == 1 && first is Map;
  }
  return _isBinaryPayloadValue(first);
}

bool _isBinaryPayloadValue(Object? value) {
  return value is Uint8List || value is List<int>;
}

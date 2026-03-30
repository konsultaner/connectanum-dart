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
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    PayloadListDecoder? argumentsDecoder,
    PayloadMapDecoder? argumentsKeywordsDecoder,
    Object? anchor,
  }) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      argumentsDecoder: argumentsDecoder,
      argumentsKeywordsDecoder: argumentsKeywordsDecoder,
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
    Object? anchor,
  }) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
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
    Object? anchor,
  }) {
    return LazyMessagePayload._(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: encoding,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      pptDecoded: pptDecoded,
      anchor: anchor,
    );
  }

  final Uint8List? transparentBinaryPayload;
  final LazyPayloadEncoding? encoding;
  final bool pptDecoded;
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
    final e2eePayload = E2EEPayload.unpackE2EEPayload(arguments, options);
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
  );
}

LazyMessagePayload unwrapLazyPayloadView(
  LazyMessagePayload payload, {
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
}) {
  if (pptScheme == null || payload.pptDecoded) {
    return payload;
  }
  if (pptScheme == 'wamp') {
    final decoded = decodeLazyPayloadView(
      payload,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
    );
    return LazyMessagePayload.materialized(
      transparentBinaryPayload: payload.transparentBinaryPayload,
      encoding: payload.encoding,
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
      pptDecoded: true,
      anchor: payload.anchor,
    );
  }
  final outerArguments = payload.arguments;
  if (outerArguments == null || outerArguments.isEmpty) {
    return LazyMessagePayload.materialized(
      transparentBinaryPayload: payload.transparentBinaryPayload,
      encoding: payload.encoding,
      arguments: const <dynamic>[],
      argumentsKeywords: const <String, dynamic>{},
      pptDecoded: true,
      anchor: payload.anchor,
    );
  }
  final binPayload = _coercePptBinaryPayload(outerArguments.first);
  return LazyMessagePayload.packed(
    transparentBinaryPayload: payload.transparentBinaryPayload,
    encoding: _lazyEncodingFromPptSerializer(pptSerializer),
    packedPayloadBytes: binPayload,
    packedPayloadDecoder: (bytes) {
      final options = _InlinePptOptions(
        pptScheme: pptScheme,
        pptSerializer: pptSerializer,
        pptCipher: pptCipher,
        pptKeyId: pptKeyId,
      );
      final decoded = PPTPayload.unpackPPTPayload([bytes], options);
      return (
        arguments: decoded.arguments,
        argumentsKeywords: decoded.argumentsKeywords,
      );
    },
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
        anchor: anchor ?? this,
      );
    }
    return LazyMessagePayload.materialized(
      transparentBinaryPayload: transparentBinaryPayload,
      encoding: _lazyPayloadEncoding,
      arguments: _arguments,
      argumentsKeywords: _argumentsKeywords,
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
    _retainedLazyPayload = payload.withAnchor(this);
    _lazyPayloadEncoding ??= payload.encoding;
  }

  /// Transfers the message payload to another message
  void copyPayloadTo(AbstractMessageWithPayload message) {
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

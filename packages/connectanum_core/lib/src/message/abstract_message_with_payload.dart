import 'dart:typed_data';

import 'abstract_message.dart';

typedef PayloadListDecoder = List<dynamic> Function(Uint8List bytes);
typedef PayloadMapDecoder = Map<String, dynamic> Function(Uint8List bytes);

/// CALL,EVENT,RESULT,ERROR,PUBLISH,INVOCATION,YIELD may have a transparent payload
abstract class AbstractMessageWithPayload extends AbstractMessage {
  Uint8List? transparentBinaryPayload;

  List<dynamic>? _arguments;
  Map<String, dynamic>? _argumentsKeywords;

  Uint8List? _encodedArguments;
  Uint8List? _encodedArgumentsKeywords;
  PayloadListDecoder? _argumentsDecoder;
  PayloadMapDecoder? _argumentsKeywordsDecoder;

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
      _encodedArguments = null;
      _argumentsDecoder = null;
    }
    return _arguments;
  }

  set arguments(List<dynamic>? value) {
    _arguments = value;
    _encodedArguments = null;
    _argumentsDecoder = null;
  }

  Map<String, dynamic>? get argumentsKeywords {
    if (_argumentsKeywords == null &&
        _encodedArgumentsKeywords != null &&
        _argumentsKeywordsDecoder != null) {
      _argumentsKeywords = _argumentsKeywordsDecoder!(
        _encodedArgumentsKeywords!,
      );
      _encodedArgumentsKeywords = null;
      _argumentsKeywordsDecoder = null;
    }
    return _argumentsKeywords;
  }

  set argumentsKeywords(Map<String, dynamic>? value) {
    _argumentsKeywords = value;
    _encodedArgumentsKeywords = null;
    _argumentsKeywordsDecoder = null;
  }

  bool get hasLazyArguments => _encodedArguments != null;

  bool get hasLazyArgumentsKeywords => _encodedArgumentsKeywords != null;

  Uint8List? get debugEncodedArgumentsBytes => _encodedArguments;

  Uint8List? get debugEncodedArgumentsKeywordsBytes =>
      _encodedArgumentsKeywords;

  /// Sets encoded payload slices that can be lazily decoded on demand.
  void setLazyPayload({
    Uint8List? argumentsBytes,
    PayloadListDecoder? argumentsDecoder,
    Uint8List? argumentsKeywordsBytes,
    PayloadMapDecoder? argumentsKeywordsDecoder,
  }) {
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
      );
    } else {
      message.arguments = _arguments == null
          ? null
          : List<dynamic>.from(_arguments!);
      message.argumentsKeywords = _argumentsKeywords == null
          ? null
          : Map<String, dynamic>.from(_argumentsKeywords!);
    }
  }
}

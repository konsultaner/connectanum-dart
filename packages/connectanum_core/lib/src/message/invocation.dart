import 'dart:collection';
import 'dart:typed_data';

import 'e2ee_payload.dart';
import 'ppt_payload.dart';
import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'custom_fields.dart';
import 'message_types.dart';
import 'uri_pattern.dart';
import 'error.dart';
import 'yield.dart';

typedef InvocationPayloadResponder =
    void Function({
      LazyMessagePayload? lazyPayload,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords,
      bool isError,
      String? errorUri,
      YieldOptions? options,
    });

class LazyInvocationPayload {
  LazyInvocationPayload({
    required this.requestId,
    required this.registrationId,
    required this.receiveProgress,
    required this.respondWith,
    required this.isResponseClosed,
    required this.payload,
    this.caller,
    this.procedure,
    this.pptScheme,
    this.pptSerializer,
    this.pptCipher,
    this.pptKeyId,
    this.customDetails,
  });

  final int requestId;
  final int registrationId;
  final int? caller;
  final String? procedure;
  final bool receiveProgress;
  final String? pptScheme;
  final String? pptSerializer;
  final String? pptCipher;
  final String? pptKeyId;
  final Map<String, dynamic>? customDetails;
  final InvocationPayloadResponder respondWith;
  final bool Function() isResponseClosed;
  final LazyMessagePayload payload;

  List<dynamic>? get arguments => payload.arguments;

  Map<String, dynamic>? get argumentsKeywords => payload.argumentsKeywords;

  Uint8List? get argumentsBytes => payload.argumentsBytes;

  Uint8List? get argumentsKeywordsBytes => payload.argumentsKeywordsBytes;

  Uint8List? get packedPayloadBytes => payload.packedPayloadBytes;

  InvocationPayload toPayload() {
    final decoded = payload.pptDecoded
        ? (
            arguments: payload.arguments,
            argumentsKeywords: payload.argumentsKeywords,
          )
        : decodeLazyPayloadView(
            payload,
            pptScheme: pptScheme,
            pptSerializer: pptSerializer,
            pptCipher: pptCipher,
            pptKeyId: pptKeyId,
          );
    return (
      requestId: requestId,
      registrationId: registrationId,
      caller: caller,
      procedure: procedure,
      receiveProgress: receiveProgress,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
      customDetails: customDetails,
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
      respondWith: respondWith,
      isResponseClosed: isResponseClosed,
    );
  }
}

typedef InvocationPayload = ({
  int requestId,
  int registrationId,
  int? caller,
  String? procedure,
  bool receiveProgress,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  Map<String, dynamic>? customDetails,
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
  InvocationPayloadResponder respondWith,
  bool Function() isResponseClosed,
});

class Invocation extends AbstractMessageWithPayload {
  int requestId;
  int registrationId;
  InvocationDetails details;
  void Function(AbstractMessageWithPayload invocationResultMessage)?
  _onResponse;
  bool _responseClosed = false;

  bool get responseClosed => _responseClosed;

  void respondWith({
    LazyMessagePayload? lazyPayload,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    bool isError = false,
    String? errorUri,
    YieldOptions? options,
  }) {
    if (isError) {
      if (options != null) {
        assert(options.progress == false);
      }
      assert(UriPattern.match(errorUri!));
      final error = Error(
        MessageTypes.codeInvocation,
        requestId,
        HashMap(),
        errorUri,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
      _emitResponse(error);
    } else {
      var invokeArguments = arguments;
      var invokeArgumentsKeywords = argumentsKeywords;

      if (options?.pptScheme == 'wamp') {
        // It's E2EE payload
        invokeArguments = E2EEPayload.packE2EEPayload(
          arguments,
          argumentsKeywords,
          options!,
        );
        invokeArgumentsKeywords = null;
      } else if (options?.pptScheme != null) {
        // It's some variation of PPT
        invokeArguments = PPTPayload.packPPTPayload(
          arguments,
          argumentsKeywords,
          options!,
        );
        invokeArgumentsKeywords = null;
      }

      final yield = Yield(
        requestId,
        options: options,
        arguments: invokeArguments,
        argumentsKeywords: invokeArgumentsKeywords,
      );
      if (lazyPayload != null) {
        if (options?.pptScheme != null && options?.pptScheme != 'wamp') {
          if (lazyPayload.packedPayloadBytes != null &&
              _matchesPackedPayloadEncoding(lazyPayload, options)) {
            yield.arguments = [lazyPayload.packedPayloadBytes!];
            yield.argumentsKeywords = null;
          } else {
            yield.arguments = invokeArguments;
            yield.argumentsKeywords = invokeArgumentsKeywords;
          }
        } else if (options?.pptScheme == null) {
          yield.setLazyPayload(
            argumentsBytes: lazyPayload.argumentsBytes,
            argumentsDecoder: lazyPayload.argumentsBytes == null
                ? null
                : (_) => lazyPayload.arguments ?? const <dynamic>[],
            argumentsKeywordsBytes: lazyPayload.argumentsKeywordsBytes,
            argumentsKeywordsDecoder: lazyPayload.argumentsKeywordsBytes == null
                ? null
                : (_) =>
                      lazyPayload.argumentsKeywords ??
                      const <String, dynamic>{},
            encoding: lazyPayload.encoding,
          );
          if (!lazyPayload.hasEncodedArguments) {
            yield.arguments = lazyPayload.arguments;
          }
          if (!lazyPayload.hasEncodedArgumentsKeywords) {
            yield.argumentsKeywords = lazyPayload.argumentsKeywords;
          }
        }
      }
      _emitResponse(yield);
    }
  }

  Invocation(
    this.requestId,
    this.registrationId,
    this.details, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    id = MessageTypes.codeInvocation;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  bool isProgressive() {
    return details.receiveProgress ?? false;
  }

  void onResponse(
    void Function(AbstractMessageWithPayload invocationResultMessage) onData,
  ) {
    _onResponse = onData;
  }

  void _emitResponse(AbstractMessageWithPayload response) {
    if (_responseClosed) {
      throw StateError('Invocation response handler already completed');
    }
    final onResponse = _onResponse;
    if (onResponse == null) {
      throw StateError('Invocation response handler not attached');
    }
    onResponse(response);
    if (response is Error) {
      _responseClosed = true;
      return;
    }
    if (response is Yield && response.options?.progress == true) {
      return;
    }
    _responseClosed = true;
  }

  InvocationPayload toPayload() {
    final decoded = hasDecodedPptPayload
        ? (arguments: arguments, argumentsKeywords: argumentsKeywords)
        : decodePayloadView(
            arguments,
            argumentsKeywords,
            pptScheme: details.pptScheme,
            pptSerializer: details.pptSerializer,
            pptCipher: details.pptCipher,
            pptKeyId: details.pptKeyId,
          );
    return (
      requestId: requestId,
      registrationId: registrationId,
      caller: details.caller,
      procedure: details.procedure,
      receiveProgress: details.receiveProgress ?? false,
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
      customDetails: details.custom.isEmpty ? null : details.custom,
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
      respondWith:
          ({
            LazyMessagePayload? lazyPayload,
            List<dynamic>? arguments,
            Map<String, dynamic>? argumentsKeywords,
            bool isError = false,
            String? errorUri,
            YieldOptions? options,
          }) {
            respondWith(
              lazyPayload: lazyPayload,
              arguments: arguments,
              argumentsKeywords: argumentsKeywords,
              isError: isError,
              errorUri: errorUri,
              options: options,
            );
          },
      isResponseClosed: () => responseClosed,
    );
  }

  LazyInvocationPayload toLazyInvocationPayload({Object? anchor}) {
    return LazyInvocationPayload(
      requestId: requestId,
      registrationId: registrationId,
      caller: details.caller,
      procedure: details.procedure,
      receiveProgress: details.receiveProgress ?? false,
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
      customDetails: details.custom.isEmpty ? null : details.custom,
      respondWith:
          ({
            LazyMessagePayload? lazyPayload,
            List<dynamic>? arguments,
            Map<String, dynamic>? argumentsKeywords,
            bool isError = false,
            String? errorUri,
            YieldOptions? options,
          }) {
            respondWith(
              lazyPayload: lazyPayload,
              arguments: arguments,
              argumentsKeywords: argumentsKeywords,
              isError: isError,
              errorUri: errorUri,
              options: options,
            );
          },
      isResponseClosed: () => responseClosed,
      payload: unwrapLazyPayloadView(
        super.toLazyPayload(anchor: anchor ?? this),
        pptScheme: details.pptScheme,
        pptSerializer: details.pptSerializer,
        pptCipher: details.pptCipher,
        pptKeyId: details.pptKeyId,
      ),
    );
  }
}

bool _matchesPackedPayloadEncoding(
  LazyMessagePayload payload,
  YieldOptions? options,
) {
  return switch ((payload.encoding, options?.pptSerializer)) {
    (LazyPayloadEncoding.json, 'json') => true,
    (LazyPayloadEncoding.messagePack, 'msgpack') => true,
    (LazyPayloadEncoding.cbor, 'cbor') => true,
    _ => false,
  };
}

class InvocationDetails extends PPTOptions with CustomFieldContainer {
  // caller_identification == true
  int? caller;

  // pattern_based_registration == true
  String? procedure;

  // pattern_based_registration == true
  bool? receiveProgress;

  InvocationDetails(
    this.caller,
    this.procedure,
    this.receiveProgress, [
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
    Map<String, dynamic>? custom,
  ]) {
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
    if (custom != null) {
      this.custom.addAll(custom);
    }
  }

  @override
  bool verify() {
    return verifyPPT();
  }
}

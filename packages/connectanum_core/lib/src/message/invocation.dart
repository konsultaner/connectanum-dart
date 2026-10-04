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
    this.progress = false,
    this.timeout,
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
  final bool progress;
  final int? timeout;
  final bool receiveProgress;
  final String? pptScheme;
  final String? pptSerializer;
  final String? pptCipher;
  final String? pptKeyId;
  final Map<String, dynamic>? customDetails;
  final InvocationPayloadResponder respondWith;
  final bool Function() isResponseClosed;
  final LazyMessagePayload payload;

  late final MaterializedPayloadView _decodedPayload = payload.pptDecoded
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

  List<dynamic>? get arguments => _decodedPayload.arguments;

  Map<String, dynamic>? get argumentsKeywords =>
      _decodedPayload.argumentsKeywords;

  Uint8List? get argumentsBytes => payload.argumentsBytes;

  Uint8List? get argumentsKeywordsBytes => payload.argumentsKeywordsBytes;

  Uint8List? get packedPayloadBytes => payload.packedPayloadBytes;

  InvocationPayload toPayload() {
    return (
      requestId: requestId,
      registrationId: registrationId,
      caller: caller,
      procedure: procedure,
      progress: progress,
      timeout: timeout,
      receiveProgress: receiveProgress,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
      customDetails: customDetails,
      arguments: _decodedPayload.arguments,
      argumentsKeywords: _decodedPayload.argumentsKeywords,
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
  bool progress,
  int? timeout,
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
  bool _responseAbandoned = false;

  bool get responseClosed => _responseClosed;

  /// Closes this response handler without sending a WAMP message.
  ///
  /// Session adapters use this when the connection can no longer deliver a
  /// reply. Closing is idempotent and cannot be undone by a failed dispatch or
  /// by attaching another response callback.
  void closeResponse() {
    _responseAbandoned = true;
    _responseClosed = true;
    _onResponse = null;
  }

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
    }
    var invokeArguments = arguments;
    var invokeArgumentsKeywords = argumentsKeywords;
    Uint8List? packedPayload;
    final runtimeContext = _responseRuntimeContext(
      isError ? WampE2eeMessageType.error : WampE2eeMessageType.yield,
    );

    if (options?.pptScheme != null && options?.pptScheme != 'wamp') {
      packedPayload = lazyPayload == null
          ? null
          : _packMatchingLazyPayload(lazyPayload, options!);
    }

    if (options?.pptScheme == 'wamp') {
      // An encoding match proves neither ciphertext provenance nor key/cipher
      // affinity. The outbound provider must apply its context and key policy.
      invokeArguments = E2EEPayload.packE2EEPayload(
        lazyPayload?.arguments ?? arguments,
        lazyPayload?.argumentsKeywords ?? argumentsKeywords,
        options!,
        provider: lazyPayload?.e2eeProvider ?? e2eeProvider,
        runtimeContext: runtimeContext,
      );
      invokeArgumentsKeywords = null;
    } else if (options?.pptScheme != null) {
      invokeArguments = packedPayload == null
          ? PPTPayload.packPPTPayload(
              lazyPayload?.arguments ?? arguments,
              lazyPayload?.argumentsKeywords ?? argumentsKeywords,
              options!,
            )
          : <dynamic>[packedPayload];
      invokeArgumentsKeywords = null;
    }

    final AbstractMessageWithPayload response = isError
        ? Error(
            MessageTypes.codeInvocation,
            requestId,
            <String, dynamic>{
              if (options?.pptScheme != null) 'ppt_scheme': options!.pptScheme,
              if (options?.pptSerializer != null)
                'ppt_serializer': options!.pptSerializer,
              if (options?.pptCipher != null) 'ppt_cipher': options!.pptCipher,
              if (options?.pptKeyId != null) 'ppt_keyid': options!.pptKeyId,
              ...?options?.custom,
            },
            errorUri,
            arguments: invokeArguments,
            argumentsKeywords: invokeArgumentsKeywords,
          )
        : Yield(
            requestId,
            options: options,
            arguments: invokeArguments,
            argumentsKeywords: invokeArgumentsKeywords,
          );
    response.attachE2eeProvider(lazyPayload?.e2eeProvider ?? e2eeProvider);
    response.attachE2eeRuntimeContext(runtimeContext);
    if (lazyPayload != null && options?.pptScheme == null) {
      if (lazyPayload.hasPackedPayloadBytes) {
        // Without PPT metadata the reply contains application values, not the
        // packed wire wrapper. Encoded dynamic fragments can still be reused.
        response.arguments = lazyPayload.arguments ?? arguments;
        response.argumentsKeywords =
            lazyPayload.argumentsKeywords ?? argumentsKeywords;
      } else {
        response.restoreLazyPayload(lazyPayload);
        if (!lazyPayload.hasEncodedArguments && lazyPayload.arguments == null) {
          response.arguments = arguments;
        }
        if (!lazyPayload.hasEncodedArgumentsKeywords &&
            lazyPayload.argumentsKeywords == null) {
          response.argumentsKeywords = argumentsKeywords;
        }
      }
    }
    if (lazyPayload != null && options?.pptScheme != 'wamp') {
      // Keep the source lease with the actual outbound wire view. Packing a
      // reply can reuse spans even when its argument wrapper is different.
      response.retainLazyPayload(response.toLazyPayload(anchor: lazyPayload));
    }
    _emitResponse(response);
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

  @override
  List<dynamic>? get arguments {
    ensureDecodedPayloadView(
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
    );
    return super.arguments;
  }

  @override
  Map<String, dynamic>? get argumentsKeywords {
    ensureDecodedPayloadView(
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
    );
    return super.argumentsKeywords;
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
    if (response is Yield && response.options?.progress == true) {
      onResponse(response);
      return;
    }
    // Block terminal reentry, but preserve retryability if dispatch is rejected.
    _responseClosed = true;
    try {
      onResponse(response);
    } catch (_) {
      _responseClosed = _responseAbandoned;
      rethrow;
    }
  }

  WampE2eeRuntimeContext? _responseRuntimeContext(
    WampE2eeMessageType messageType,
  ) {
    final runtimeContext = e2eeRuntimeContext;
    if (runtimeContext == null) {
      return null;
    }
    return runtimeContext.copyWith(
      direction: WampE2eeDirection.outbound,
      messageType: messageType,
      uri: details.procedure ?? runtimeContext.uri,
    );
  }

  InvocationPayload toPayload() {
    ensureDecodedPayloadView(
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
      progress: details.progress ?? false,
      timeout: details.timeout,
      receiveProgress: details.receiveProgress ?? false,
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
      customDetails: details.custom.isEmpty ? null : details.custom,
      arguments: super.arguments,
      argumentsKeywords: super.argumentsKeywords,
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
      progress: details.progress ?? false,
      timeout: details.timeout,
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
  return _matchesPayloadEncoding(payload.encoding, options?.pptSerializer);
}

bool _matchesPayloadEncoding(
  LazyPayloadEncoding? encoding,
  String? serializer,
) {
  return switch ((encoding, serializer)) {
    (LazyPayloadEncoding.json, 'json') => true,
    (LazyPayloadEncoding.messagePack, 'msgpack') => true,
    (LazyPayloadEncoding.cbor, 'cbor') => true,
    (LazyPayloadEncoding.flatbuffers, 'flatbuffers') => true,
    _ => false,
  };
}

Uint8List? _packMatchingLazyPayload(
  LazyMessagePayload payload,
  YieldOptions options,
) {
  if (payload.packedPayloadBytes != null &&
      _matchesPackedPayloadEncoding(payload, options)) {
    return payload.packedPayloadBytes;
  }
  if (!_matchesPayloadEncoding(payload.encoding, options.pptSerializer)) {
    return null;
  }
  return PPTPayload.packSerializedPayload(
    options.pptSerializer,
    argumentsBytes: payload.argumentsBytes,
    argumentsKeywordsBytes: payload.argumentsKeywordsBytes,
    arguments: payload.argumentsBytes == null ? payload.arguments : null,
    argumentsKeywords: payload.argumentsKeywordsBytes == null
        ? payload.argumentsKeywords
        : null,
  );
}

class InvocationDetails extends PPTOptions with CustomFieldContainer {
  // progressive_call_invocations == true
  bool? progress;

  // caller_identification == true
  int? caller;

  // pattern_based_registration == true
  String? procedure;

  // pattern_based_registration == true
  bool? receiveProgress;

  // call_timeout == true with REGISTER.Options.forward_timeout
  int? timeout;

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
    if (timeout != null && timeout! < 0) {
      throw RangeError.value(timeout!, 'timeout', 'timeout must be >= 0');
    }
    return verifyPPT();
  }
}

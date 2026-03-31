import 'dart:typed_data';

import 'abstract_ppt_options.dart';
import 'custom_fields.dart';
import 'message_types.dart';
import 'abstract_message_with_payload.dart';

class LazyResultPayload {
  LazyResultPayload({
    required this.callRequestId,
    required this.progress,
    required this.payload,
    this.pptScheme,
    this.pptSerializer,
    this.pptCipher,
    this.pptKeyId,
    this.customDetails,
  });

  final int callRequestId;
  final bool progress;
  final String? pptScheme;
  final String? pptSerializer;
  final String? pptCipher;
  final String? pptKeyId;
  final Map<String, dynamic>? customDetails;
  final LazyMessagePayload payload;

  List<dynamic>? get arguments => payload.arguments;

  Map<String, dynamic>? get argumentsKeywords => payload.argumentsKeywords;

  Uint8List? get argumentsBytes => payload.argumentsBytes;

  Uint8List? get argumentsKeywordsBytes => payload.argumentsKeywordsBytes;

  Uint8List? get packedPayloadBytes => payload.packedPayloadBytes;

  ResultPayload toPayload() {
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
      callRequestId: callRequestId,
      progress: progress,
      pptScheme: pptScheme,
      pptSerializer: pptSerializer,
      pptCipher: pptCipher,
      pptKeyId: pptKeyId,
      customDetails: customDetails,
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
    );
  }
}

typedef ResultPayload = ({
  int callRequestId,
  bool progress,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  Map<String, dynamic>? customDetails,
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
});

class Result extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int callRequestId;

  /// The ID of the publication of the published event.
  ResultDetails details;

  Result(
    this.callRequestId,
    this.details, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    id = MessageTypes.codeResult;
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
    return details.progress != null && details.progress!;
  }

  ResultPayload toPayload() {
    ensureDecodedPayloadView(
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
    );
    return (
      callRequestId: callRequestId,
      progress: isProgressive(),
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
      customDetails: details.custom.isEmpty ? null : details.custom,
      arguments: super.arguments,
      argumentsKeywords: super.argumentsKeywords,
    );
  }

  LazyResultPayload toLazyResultPayload({Object? anchor}) {
    return LazyResultPayload(
      callRequestId: callRequestId,
      progress: isProgressive(),
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
      customDetails: details.custom.isEmpty ? null : details.custom,
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

Result resultFromLazyPayload(LazyResultPayload payload) {
  final result = Result(
    payload.callRequestId,
    ResultDetails(
      progress: payload.progress,
      pptScheme: payload.pptScheme,
      pptSerializer: payload.pptSerializer,
      pptCipher: payload.pptCipher,
      pptKeyId: payload.pptKeyId,
      custom: payload.customDetails,
    ),
  );
  result.restoreLazyPayload(payload.payload);
  return result;
}

class ResultDetails extends PPTOptions with CustomFieldContainer {
  // progressive_call_results == true
  bool? progress;

  ResultDetails({
    bool? progress,
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
    Map<String, dynamic>? custom,
  }) {
    this.progress = progress ?? false;
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

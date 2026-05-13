import 'dart:typed_data';

import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'custom_fields.dart';
import 'message_types.dart';

class LazyEventPayload {
  LazyEventPayload({
    required this.subscriptionId,
    required this.publicationId,
    required this.payload,
    this.publisher,
    this.trustlevel,
    this.topic,
    this.pptScheme,
    this.pptSerializer,
    this.pptCipher,
    this.pptKeyId,
    this.customDetails,
  });

  final int subscriptionId;
  final int publicationId;
  final int? publisher;
  final int? trustlevel;
  final String? topic;
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

  EventPayload toPayload() {
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
      subscriptionId: subscriptionId,
      publicationId: publicationId,
      publisher: publisher,
      trustlevel: trustlevel,
      topic: topic,
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

typedef EventPayload = ({
  int subscriptionId,
  int publicationId,
  int? publisher,
  int? trustlevel,
  String? topic,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
  Map<String, dynamic>? customDetails,
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
});

class Event extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int subscriptionId;

  /// The ID of the publication of the published event.
  int publicationId;
  EventDetails details;

  Event(
    this.subscriptionId,
    this.publicationId,
    this.details, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    id = MessageTypes.codeEvent;
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

  EventPayload toPayload() {
    ensureDecodedPayloadView(
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
    );
    return (
      subscriptionId: subscriptionId,
      publicationId: publicationId,
      publisher: details.publisher,
      trustlevel: details.trustlevel,
      topic: details.topic,
      pptScheme: details.pptScheme,
      pptSerializer: details.pptSerializer,
      pptCipher: details.pptCipher,
      pptKeyId: details.pptKeyId,
      customDetails: details.custom.isEmpty ? null : details.custom,
      arguments: super.arguments,
      argumentsKeywords: super.argumentsKeywords,
    );
  }

  LazyEventPayload toLazyEventPayload({Object? anchor}) {
    return LazyEventPayload(
      subscriptionId: subscriptionId,
      publicationId: publicationId,
      publisher: details.publisher,
      trustlevel: details.trustlevel,
      topic: details.topic,
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

Event eventFromPayload(EventPayload payload) {
  return Event(
    payload.subscriptionId,
    payload.publicationId,
    EventDetails(
      publisher: payload.publisher,
      trustlevel: payload.trustlevel,
      topic: payload.topic,
      pptScheme: payload.pptScheme,
      pptSerializer: payload.pptSerializer,
      pptCipher: payload.pptCipher,
      pptKeyid: payload.pptKeyId,
      custom: payload.customDetails,
    ),
    arguments: payload.arguments == null
        ? null
        : List<dynamic>.from(payload.arguments!),
    argumentsKeywords: payload.argumentsKeywords == null
        ? null
        : Map<String, dynamic>.from(payload.argumentsKeywords!),
  );
}

/// Options used influence the event behavior
class EventDetails extends PPTOptions with CustomFieldContainer {
  // publisher_identification == true
  int? publisher;

  // publication_trustlevels == true
  int? trustlevel;

  // for pattern-matching
  String? topic;

  EventDetails({
    this.publisher,
    this.trustlevel,
    this.topic,
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyid,
    Map<String, dynamic>? custom,
  }) {
    // ignore: unnecessary_this
    this.pptScheme = pptScheme;
    // ignore: unnecessary_this
    this.pptSerializer = pptSerializer;
    // ignore: unnecessary_this
    this.pptCipher = pptCipher;
    // ignore: unnecessary_this
    this.pptKeyId = pptKeyid;
    if (custom != null) {
      this.custom.addAll(custom);
    }
  }

  @override
  bool verify() {
    return verifyPPT();
  }
}

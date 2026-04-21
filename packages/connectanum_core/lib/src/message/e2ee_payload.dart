import 'abstract_ppt_options.dart';
import '../message/ppt_payload.dart';

typedef E2EEPayloadView = ({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
});

abstract class WampE2eeProvider {
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options,
  );

  E2EEPayloadView unpackPayload(List<dynamic>? arguments, PPTOptions options);
}

class WampE2eeProviderUnavailableException implements Exception {
  WampE2eeProviderUnavailableException(this.operation, {required this.options});

  final String operation;
  final PPTOptions options;

  @override
  String toString() {
    final fields = <String>[
      "pptScheme=${options.pptScheme ?? 'null'}",
      "pptSerializer=${options.pptSerializer ?? 'null'}",
      "pptCipher=${options.pptCipher ?? 'null'}",
      "pptKeyId=${options.pptKeyId ?? 'null'}",
    ];
    return 'WampE2eeProviderUnavailableException('
        'operation: $operation, ${fields.join(', ')})';
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
  }) {
    final resolvedProvider = provider;
    if (resolvedProvider == null) {
      throw WampE2eeProviderUnavailableException('pack', options: options);
    }
    return resolvedProvider.packPayload(arguments, argumentsKeywords, options);
  }

  static E2EEPayload unpackE2EEPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeProvider? provider,
  }) {
    final resolvedProvider = provider;
    if (resolvedProvider == null) {
      throw WampE2eeProviderUnavailableException('unpack', options: options);
    }
    final decoded = resolvedProvider.unpackPayload(arguments, options);
    return E2EEPayload(
      arguments: decoded.arguments,
      argumentsKeywords: decoded.argumentsKeywords,
    );
  }
}

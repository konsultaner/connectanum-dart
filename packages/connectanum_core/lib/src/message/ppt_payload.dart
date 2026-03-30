import 'dart:typed_data';

import '../message/abstract_ppt_options.dart';
import '../serializer/abstract_serializer.dart';
import '../serializer/cbor/serializer.dart' as cbor_serializer;
import '../serializer/json/serializer.dart' as json_serializer;
import '../serializer/msgpack/serializer.dart' as msgpack_serializer;

class PPTPayload {
  static final AbstractSerializer _jsonSerializer =
      json_serializer.Serializer();
  static final AbstractSerializer _cborSerializer =
      cbor_serializer.Serializer();
  static final AbstractSerializer _msgpackSerializer =
      msgpack_serializer.Serializer();

  List<dynamic>? arguments;
  Map<String, dynamic>? argumentsKeywords;

  PPTPayload({this.arguments, this.argumentsKeywords});

  /// Packs PPT Payload and returns 1-item array for WAMP message arguments
  static List<dynamic> packPPTPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options,
  ) {
    final serializer = _serializerForName(options.pptSerializer);
    if (serializer != null) {
      return [
        serializer.serializePPT(
          PPTPayload(
            arguments: arguments,
            argumentsKeywords: argumentsKeywords,
          ),
        ),
      ];
    } else {
      return [
        {'args': arguments, 'kwargs': argumentsKeywords},
      ];
    }
  }

  static Uint8List? packSerializedPayload(
    String? serializerName, {
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    final serializer = _serializerForName(serializerName);
    if (serializer == null) {
      return null;
    }
    return serializer.serializePPTFragments(
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
    );
  }

  static PPTPayload unpackPPTPayload(
    List<dynamic>? arguments,
    PPTOptions details,
  ) {
    if (arguments == null) {
      return PPTPayload();
    }

    final serializer = _serializerForName(details.pptSerializer);
    if (serializer != null) {
      return serializer.deserializePPT(_coerceBinaryPayload(arguments[0])) ??
          PPTPayload();
    } else {
      return PPTPayload(
        arguments: arguments[0]['args'],
        argumentsKeywords: arguments[0]['kwargs'],
      );
    }
  }

  static AbstractSerializer? _serializerForName(String? serializerName) {
    return switch (serializerName) {
      'json' => _jsonSerializer,
      'cbor' => _cborSerializer,
      'msgpack' => _msgpackSerializer,
      _ => null,
    };
  }

  static Uint8List _coerceBinaryPayload(Object? value) {
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
}

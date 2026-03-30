import 'dart:async';

enum NativeMessageSerializer {
  json(1),
  messagePack(2),
  cbor(3),
  ubjson(4),
  flatbuffers(5);

  const NativeMessageSerializer(this.id);

  final int id;

  static NativeMessageSerializer fromId(int id) {
    for (final serializer in values) {
      if (serializer.id == id) {
        return serializer;
      }
    }
    throw StateError('Unsupported native serializer id $id');
  }
}

class NativeMessageMetadata {
  const NativeMessageMetadata({
    required this.messageCode,
    required this.primaryId,
    required this.secondaryId,
    required this.detailNumberA,
    required this.detailNumberB,
    required this.flags,
    this.stringA,
    this.stringB,
    this.stringC,
    this.stringD,
    this.stringE,
  });

  static const flagDirectBind = 1 << 0;
  static const flagDetailNumberAPresent = 1 << 1;
  static const flagDetailNumberBPresent = 1 << 2;
  static const flagDetailBoolATrue = 1 << 3;

  final int messageCode;
  final int primaryId;
  final int secondaryId;
  final int detailNumberA;
  final int detailNumberB;
  final int flags;
  final String? stringA;
  final String? stringB;
  final String? stringC;
  final String? stringD;
  final String? stringE;

  bool hasFlag(int flag) => (flags & flag) != 0;
}

abstract interface class SessionOptimizedTransport {
  Stream<Object?> receiveSessionMessages();
}

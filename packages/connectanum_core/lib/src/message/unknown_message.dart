import 'abstract_message.dart';

class UnknownMessage extends AbstractMessage {
  UnknownMessage(int messageCode, {List<dynamic>? fields, int? requestId})
    : fields = List<dynamic>.from(fields ?? const []),
      requestId =
          requestId ??
          ((fields != null && fields.isNotEmpty && fields.first is int)
              ? fields.first as int
              : null) {
    id = messageCode;
  }

  final List<dynamic> fields;
  final int? requestId;
}

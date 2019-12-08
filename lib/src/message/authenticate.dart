import 'abstract_message.dart';

class Authenticate extends AbstractMessage {
    String signature;
    Map<String, Object> extra;
}

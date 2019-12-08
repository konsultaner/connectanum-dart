import 'abstract_message.dart';

class Abort extends AbstractMessage {
    Message message;
    Uri reason;
}

class Message {
    String message;
}
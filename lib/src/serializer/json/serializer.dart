import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/call.dart';
import 'package:connectanum_dart/src/message/error.dart';
import 'package:connectanum_dart/src/message/event.dart';
import 'package:connectanum_dart/src/message/goodbye.dart';
import 'package:connectanum_dart/src/message/hello.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/publish.dart';
import 'package:connectanum_dart/src/message/register.dart';
import 'package:connectanum_dart/src/message/invocation.dart';
import 'package:connectanum_dart/src/message/subscribe.dart';
import 'package:connectanum_dart/src/message/unregister.dart';
import 'package:connectanum_dart/src/message/unsubscribe.dart';

import '../abstract_serializer.dart';

class Serializer extends AbstractSerializer<String> {

  @override
  AbstractMessage deserialize(String message) {
    return null;
  }

  @override
  String serialize(AbstractMessage message) {
    if (message is Hello) {
      return "[${MessageTypes.CODE_HELLO},${message.realm},${message.details}]"; //TODO
    }
    if (message is Authenticate) {
      return "[${MessageTypes.CODE_AUTHENTICATE},${message.signature},{}]";
    }
    if (message is Register) {
        return "[${MessageTypes.CODE_REGISTER},${message.requestId},${message.procedure},${message.options}]";//TODO
    }
    if (message is Unregister) {
        return "[${MessageTypes.CODE_REGISTER},${message.requestId},${message.registrationId}]";
    }
    if (message is Call) {
        return "[${MessageTypes.CODE_CALL},${message.requestId},${message.options},${message.procedure}${_serializePayload(message)}]";
    }
    if (message is Invocation) {
        return "[${MessageTypes.CODE_INVOCATION},${message.requestId},${message.registrationId},${message.details}${_serializePayload(message)}]";//todo
    }
    if (message is Publish) {
        return "[${MessageTypes.CODE_PUBLISH},${message.requestId},${message.options},${message.topic}${_serializePayload(message)}]";
    }
    if (message is Event) {
        return "[${MessageTypes.CODE_EVENT},${message.subscriptionId},${message.publicationId}${_serializePayload(message)}]";
    }
    if (message is Subscribe) {
        return "[${MessageTypes.CODE_SUBSCRIBE},${message.requestId},${message.options},${message.topic}]";//todo
    }
    if (message is Unsubscribe) {
        return "[${MessageTypes.CODE_UNSUBSCRIBE},${message.requestId},${message.subscriptionId}]";
    }
    if (message is Error) {
        return "[${MessageTypes.CODE_GOODBYE},${message.requestTypeId},${message.requestId},${message.details}${_serializePayload(message)}]";// TODO
    }
    if (message is Goodbye) {
        return "[${MessageTypes.CODE_GOODBYE},${message.message != null ? "{\"message\":\"${message.message.message ?? ""}\"" : "{}"},${message.reason}]";
    }
    return null;
  }

  String _serializePayload(AbstractMessageWithPayload message) {
    //TODO
    if (message.argumentsKeywords != null) {
      return ",${message.arguments ?? "[]"},${message.argumentsKeywords}";
    } else if (message.arguments != null) {
      return ",${message.arguments}";
    } else {
      return "";
    }
  }

}
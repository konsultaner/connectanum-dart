import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/call.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/error.dart';
import 'package:connectanum_dart/src/message/event.dart';
import 'package:connectanum_dart/src/message/goodbye.dart';
import 'package:connectanum_dart/src/message/hello.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/publish.dart';
import 'package:connectanum_dart/src/message/published.dart';
import 'package:connectanum_dart/src/message/register.dart';
import 'package:connectanum_dart/src/message/invocation.dart';
import 'package:connectanum_dart/src/message/registered.dart';
import 'package:connectanum_dart/src/message/result.dart';
import 'package:connectanum_dart/src/message/subscribe.dart';
import 'package:connectanum_dart/src/message/unregister.dart';
import 'package:connectanum_dart/src/message/unregistered.dart';
import 'package:connectanum_dart/src/message/unsubscribe.dart';
import 'package:connectanum_dart/src/message/details.dart';
import 'package:connectanum_dart/src/message/unsubscribed.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:connectanum_dart/src/message/yield.dart';

import 'dart:convert';

import '../abstract_serializer.dart';

class Serializer extends AbstractSerializer<String> {

  @override
  AbstractMessage deserialize(String jsonMessage) {
    Object message = json.decode(jsonMessage);
    if (message is List) {
      int messageId = message[0];
      if (messageId == MessageTypes.CODE_CHALLENGE) {
        return Challenge(message[1], new Extra(
          challenge: message[2]["challenge"],
          salt: message[2]["salt"],
          keylen: message[2]["keylen"],
          iterations: message[2]["iterations"],
          memory: message[2]["memory"],
          parallel: message[2]["parallel"],
          version_num: message[2]["version_num"],
          version_str: message[2]["version_str"],
          nonce: message[2]["nonce"]
        ));
      }
      if (messageId == MessageTypes.CODE_WELCOME) {
        return new Welcome(message[1], new Details()); // TODO
      }
      if (messageId == MessageTypes.CODE_REGISTERED) {
        return new Registered(message[1], message[2]);
      }
      if (messageId == MessageTypes.CODE_UNREGISTERED) {
        return new Unregistered(message[1]);
      }
      if (messageId == MessageTypes.CODE_INVOCATION) {
        return _addPayload(new Invocation(message[1], message[2], new InvocationDetails(
            message[3]["caller"], message[3]["procedure"], message[3]["receive_progress"]
        )),message,4);
      }
      if (messageId == MessageTypes.CODE_RESULT) {
        return _addPayload(new Result(message[1], new ResultDetails(
            message[2]["progress"]
        )),message,3);
      }
      if (messageId == MessageTypes.CODE_PUBLISHED) {
        return new Published(message[1],message[2]);
      }
      if (messageId == MessageTypes.CODE_UNSUBSCRIBED) {
        return new Unsubscribed(message[1]);
      }
      if (messageId == MessageTypes.CODE_EVENT) {
        return _addPayload(new Event(message[1], message[2], new EventDetails(
            message[4]["publisher"], message[4]["trustlevel"], message[4]["topic"],
        )),message,5);
      }
    }
  }

  AbstractMessageWithPayload _addPayload(AbstractMessageWithPayload message, List<Object> messageData, argumentsOffset) {
    if (messageData.length >= argumentsOffset + 1) {
      message.arguments = messageData[argumentsOffset];
    }
    if (messageData.length >= argumentsOffset + 2) {
      message.argumentsKeywords = messageData[argumentsOffset+1];
    }
    return message;
  }

  @override
  String serialize(AbstractMessage message) {
    if (message is Hello) {
      return "[${MessageTypes.CODE_HELLO},${message.realm},${_serializeDetails(message.details)}]";
    }
    if (message is Authenticate) {
      return "[${MessageTypes.CODE_AUTHENTICATE},${message.signature},{}]";
    }
    if (message is Register) {
        return "[${MessageTypes.CODE_REGISTER},${message.requestId},${message.procedure},${_serializeRegisterOptions(message.options)}]";
    }
    if (message is Unregister) {
        return "[${MessageTypes.CODE_REGISTER},${message.requestId},${message.registrationId}]";
    }
    if (message is Call) {
        return "[${MessageTypes.CODE_CALL},${message.requestId},${message.options},${message.procedure}${_serializePayload(message)}]";
    }
    if (message is Yield) {
        return "[${MessageTypes.CODE_YIELD},${message.invocationRequestId},${_serializeYieldOptions(message.options)}${_serializePayload(message)}]";
    }
    if (message is Publish) {
        return "[${MessageTypes.CODE_PUBLISH},${message.requestId},${message.options},${message.topic}${_serializePayload(message)}]";
    }
    if (message is Event) {
        return "[${MessageTypes.CODE_EVENT},${message.subscriptionId},${message.publicationId}${_serializePayload(message)}]";
    }
    if (message is Subscribe) {
        return "[${MessageTypes.CODE_SUBSCRIBE},${message.requestId},${_serializeSubscribeOptions(message.options)},${message.topic}]";
    }
    if (message is Unsubscribe) {
        return "[${MessageTypes.CODE_UNSUBSCRIBE},${message.requestId},${message.subscriptionId}]";
    }
    if (message is Error) {
        return "[${MessageTypes.CODE_GOODBYE},${message.requestTypeId},${message.requestId},${json.encode(message.details)}${_serializePayload(message)}]";
    }
    if (message is Goodbye) {
        return "[${MessageTypes.CODE_GOODBYE},${message.message != null ? "{\"message\":\"${message.message.message ?? ""}\"" : "{}"},${message.reason}]";
    }
    return null;
  }

  String _serializeDetails(Details details) {
    if(details.roles != null) {
      List<String> rolesJson = [];
      if (details.roles.caller != null && details.roles.caller.features != null) {
        List<String> callerFeatures = [];
        callerFeatures.add('"call_canceling":${details.roles.caller.features.call_canceling ? "true" : "false"}');
        callerFeatures.add('"call_timeout":${details.roles.caller.features.call_timeout ? "true" : "false"}');
        callerFeatures.add('"caller_identification":${details.roles.caller.features.caller_identification ? "true" : "false"}');
        callerFeatures.add('"payload_transparency":${details.roles.caller.features.payload_transparency ? "true" : "false"}');
        callerFeatures.add('"progressive_call_results":${details.roles.caller.features.progressive_call_results ? "true" : "false"}');
        rolesJson.add('"caller":{"features":{${callerFeatures.join(",")}}');
      }
      if (details.roles.callee != null && details.roles.callee.features != null) {
        List<String> calleeFeatures = [];
        calleeFeatures.add('"caller_identification":${details.roles.callee.features.caller_identification ? "true" : "false"}');
        calleeFeatures.add('"call_trustlevels":${details.roles.callee.features.call_trustlevels ? "true" : "false"}');
        calleeFeatures.add('"pattern_based_registration":${details.roles.callee.features.pattern_based_registration ? "true" : "false"}');
        calleeFeatures.add('"shared_registration":${details.roles.callee.features.shared_registration ? "true" : "false"}');
        calleeFeatures.add('"call_timeout":${details.roles.callee.features.call_timeout ? "true" : "false"}');
        calleeFeatures.add('"call_canceling":${details.roles.callee.features.call_canceling ? "true" : "false"}');
        calleeFeatures.add('"progressive_call_results":${details.roles.callee.features.progressive_call_results ? "true" : "false"}');
        calleeFeatures.add('"payload_transparency":${details.roles.callee.features.payload_transparency ? "true" : "false"}');
        rolesJson.add('"callee":{"features":{${calleeFeatures.join(",")}}');
      }
      if (details.roles.subscriber != null && details.roles.subscriber.features != null) {
        List<String> subscriberFeatures = [];
        subscriberFeatures.add('"call_timeout":${details.roles.subscriber.features.call_timeout ? "true" : "false"}');
        subscriberFeatures.add('"call_canceling":${details.roles.subscriber.features.call_canceling ? "true" : "false"}');
        subscriberFeatures.add('"progressive_call_results":${details.roles.subscriber.features.progressive_call_results ? "true" : "false"}');
        subscriberFeatures.add('"payload_transparency":${details.roles.subscriber.features.payload_transparency ? "true" : "false"}');
        rolesJson.add('"subscriber":{"features":{${subscriberFeatures.join(",")}}');
      }
      if (details.roles.publisher != null && details.roles.publisher.features != null) {
        List<String> publisherFeatures = [];
        publisherFeatures.add('"publisher_identification":${details.roles.publisher.features.publisher_identification ? "true" : "false"}');
        publisherFeatures.add('"subscriber_blackwhite_listing":${details.roles.publisher.features.subscriber_blackwhite_listing ? "true" : "false"}');
        publisherFeatures.add('"publisher_exclusion":${details.roles.publisher.features.publisher_exclusion ? "true" : "false"}');
        publisherFeatures.add('"payload_transparency":${details.roles.publisher.features.payload_transparency ? "true" : "false"}');
        rolesJson.add('"publisher":{"features":{${publisherFeatures.join(",")}}');
      }
      return "{${rolesJson.join(",")}";
    } else {
      return "{}";
    }
  }

  String _serializeSubscribeOptions(SubscribeOptions options) {
    List<String> jsonOptions = [];
    if(options.match != null) {
      jsonOptions.add('"match":"${options.match}"');
    }
    if(options.meta_topic != null) {
      jsonOptions.add('"meta_topic":"${options.meta_topic}"');
    }

    return "{" + jsonOptions.join(",") + "}";
  }

  String _serializeRegisterOptions(RegisterOptions options) {
    List<String> jsonOptions = [];
    if(options.match != null) {
      jsonOptions.add('"match":"${options.match}"');
    }
    if(options.disclose_caller != null) {
      jsonOptions.add('"disclose_caller":${options.disclose_caller ? "true" : "false"}');
    }
    if(options.invoke != null) {
      jsonOptions.add('"invoke":"${options.invoke}"');
    }

    return "{" + jsonOptions.join(",") + "}";
  }

  String _serializeYieldOptions(YieldOptions options) {
    List<String> jsonDetails = [];
    if(options.progress != null) {
      jsonDetails.add('"progress":${options.progress ? "true" : "false"}');
    }
    return "{" + jsonDetails.join(",") + "}";
  }

  String _serializePayload(AbstractMessageWithPayload message) {
    if (message.argumentsKeywords != null) {
      return ",${json.encode(message.arguments ?? [])},${json.encode(message.argumentsKeywords)}";
    } else if (message.arguments != null) {
      return ",${json.encode(message.arguments)}";
    } else {
      return "";
    }
  }

}
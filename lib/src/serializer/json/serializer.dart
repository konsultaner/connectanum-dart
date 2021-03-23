import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../../../src/message/abstract_message.dart';
import '../../../src/message/abort.dart';
import '../../../src/message/abstract_message_with_payload.dart';
import '../../../src/message/authenticate.dart';
import '../../../src/message/call.dart';
import '../../../src/message/challenge.dart';
import '../../../src/message/error.dart';
import '../../../src/message/event.dart';
import '../../../src/message/goodbye.dart';
import '../../../src/message/hello.dart';
import '../../../src/message/message_types.dart';
import '../../../src/message/publish.dart';
import '../../../src/message/published.dart';
import '../../../src/message/register.dart';
import '../../../src/message/invocation.dart';
import '../../../src/message/registered.dart';
import '../../../src/message/result.dart';
import '../../../src/message/subscribe.dart';
import '../../../src/message/subscribed.dart';
import '../../../src/message/unregister.dart';
import '../../../src/message/unregistered.dart';
import '../../../src/message/unsubscribe.dart';
import '../../../src/message/details.dart';
import '../../../src/message/unsubscribed.dart';
import '../../../src/message/welcome.dart';
import '../../../src/message/yield.dart';

import 'dart:convert';

import '../abstract_serializer.dart';

/// This is a seralizer for JSON messages. It is used to initialize an [AbstractTransport]
/// object.
class Serializer extends AbstractSerializer {
  static final RegExp _binaryPrefix = RegExp('\x00');
  static final Logger _logger = Logger('Serializer');

  /// Converts a uint8 JSON message into a WAMP message object
  @override
  AbstractMessage deserialize(Uint8List jsonMessage) {
    return deserializeFromString(Utf8Decoder().convert(jsonMessage));
  }

  /// Converts a string JSON message into a WAMP message object
  AbstractMessage deserializeFromString(String jsonMessage) {
    Object message = json.decode(jsonMessage);
    if (message is List) {
      int messageId = message[0];
      if (messageId == MessageTypes.CODE_CHALLENGE) {
        return Challenge(
            message[1],
            Extra(
                challenge: message[2]['challenge'],
                salt: message[2]['salt'],
                keylen: message[2]['keylen'],
                iterations: message[2]['iterations'],
                memory: message[2]['memory'],
                kdf: message[2]['kdf'],
                nonce: message[2]['nonce']));
      }
      if (messageId == MessageTypes.CODE_WELCOME) {
        final details = Details();
        details.realm = message[2]['realm'] ?? '';
        details.authid = message[2]['authid'] ?? '';
        details.authprovider = message[2]['authprovider'] ?? '';
        details.authmethod = message[2]['authmethod'] ?? '';
        details.authrole = message[2]['authrole'] ?? '';
        details.authextra = message[2]['authextra'] ?? <String, String>{};
        if (message[2]['roles'] != null) {
          details.roles = Roles();
          if (message[2]['roles']['dealer'] != null) {
            details.roles.dealer = Dealer();
            if (message[2]['roles']['broker']['features'] != null) {
              details.roles.dealer.features = DealerFeatures();
              details.roles.dealer.features.caller_identification = message[2]
                          ['roles']['dealer']['features']
                      ['caller_identification'] ??
                  false;
              details.roles.dealer.features.call_trustlevels = message[2]
                      ['roles']['dealer']['features']['call_trustlevels'] ??
                  false;
              details.roles.dealer.features.pattern_based_registration =
                  message[2]['roles']['dealer']['features']
                          ['pattern_based_registration'] ??
                      false;
              details.roles.dealer.features.registration_meta_api = message[2]
                          ['roles']['dealer']['features']
                      ['registration_meta_api'] ??
                  false;
              details.roles.dealer.features.shared_registration = message[2]
                      ['roles']['dealer']['features']['shared_registration'] ??
                  false;
              details.roles.dealer.features.session_meta_api = message[2]
                      ['roles']['dealer']['features']['session_meta_api'] ??
                  false;
              details.roles.dealer.features.call_timeout = message[2]['roles']
                      ['dealer']['features']['call_timeout'] ??
                  false;
              details.roles.dealer.features.call_canceling = message[2]['roles']
                      ['dealer']['features']['call_canceling'] ??
                  false;
              details.roles.dealer.features.progressive_call_results =
                  // ignore: prefer_single_quotes
                  message[2]['roles']['dealer']['features']
                          ['progressive_call_results'] ??
                      false;
              details.roles.dealer.features.payload_transparency = message[2]
                      ['roles']['dealer']['features']['payload_transparency'] ??
                  false;
            }
          }
          if (message[2]['roles']['broker'] != null) {
            details.roles.broker = Broker();
            if (message[2]['roles']['broker']['features'] != null) {
              details.roles.broker.features = BrokerFeatures();
              details.roles.broker.features.publisher_identification =
                  message[2]['roles']['broker']['features']
                          ['publisher_identification'] ??
                      false;
              details.roles.broker.features.publication_trustlevels = message[2]
                          ['roles']['broker']['features']
                      ['publication_trustlevels'] ??
                  false;
              details.roles.broker.features.pattern_based_subscription =
                  message[2]['roles']['broker']['features']
                          ['pattern_based_subscription'] ??
                      false;
              details.roles.broker.features.subscription_meta_api = message[2]
                          ['roles']['broker']['features']
                      ['subscription_meta_api'] ??
                  false;
              details.roles.broker.features.subscriber_blackwhite_listing =
                  message[2]['roles']['broker']['features']
                          ['subscriber_blackwhite_listing'] ??
                      false;
              details.roles.broker.features.session_meta_api = message[2]
                      ['roles']['broker']['features']['session_meta_api'] ??
                  false;
              details.roles.broker.features.publisher_exclusion = message[2]
                      ['roles']['broker']['features']['publisher_exclusion'] ??
                  false;
              details.roles.broker.features.event_history = message[2]['roles']
                      ['broker']['features']['event_history'] ??
                  false;
              details.roles.broker.features.payload_transparency = message[2]
                      ['roles']['broker']['features']['payload_transparency'] ??
                  false;
            }
          }
        }
        return Welcome(message[1], details);
      }
      if (messageId == MessageTypes.CODE_REGISTERED) {
        return Registered(message[1], message[2]);
      }
      if (messageId == MessageTypes.CODE_UNREGISTERED) {
        return Unregistered(message[1]);
      }
      if (messageId == MessageTypes.CODE_INVOCATION) {
        return _addPayload(
            Invocation(
                message[1],
                message[2],
                InvocationDetails(message[3]['caller'], message[3]['procedure'],
                    message[3]['receive_progress'])),
            message,
            4);
      }
      if (messageId == MessageTypes.CODE_RESULT) {
        return _addPayload(
            Result(message[1], ResultDetails(message[2]['progress'])),
            message,
            3);
      }
      if (messageId == MessageTypes.CODE_PUBLISHED) {
        return Published(message[1], message[2]);
      }
      if (messageId == MessageTypes.CODE_SUBSCRIBED) {
        return Subscribed(message[1], message[2]);
      }
      if (messageId == MessageTypes.CODE_UNSUBSCRIBED) {
        return Unsubscribed(
            message[1],
            message.length == 2
                ? null
                : UnsubscribedDetails(
                    message[2]['subscription'], message[2]['reason']));
      }
      if (messageId == MessageTypes.CODE_EVENT) {
        return _addPayload(
            Event(
                message[1],
                message[2],
                EventDetails(
                    publisher: message[3]['publisher'],
                    trustlevel: message[3]['trustlevel'],
                    topic: message[3]['topic'])),
            message,
            4);
      }
      if (messageId == MessageTypes.CODE_ERROR) {
        return _addPayload(
            Error(message[1], message[2], message[3], message[4]), message, 5);
      }
      if (messageId == MessageTypes.CODE_ABORT) {
        return Abort(message[2],
            message: message[1] == null ? null : message[1]['message']);
      }
      if (messageId == MessageTypes.CODE_GOODBYE) {
        return Goodbye(
            message[1] == null ? null : GoodbyeMessage(message[1]['message']),
            message[2]);
      }
    }
    _logger.shout('Could not deserialize the message: ' + jsonMessage);
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(AbstractMessageWithPayload message,
      List<Object> messageData, argumentsOffset) {
    if (messageData.length == argumentsOffset + 1 &&
        messageData[argumentsOffset] is String) {
      if ((messageData[argumentsOffset] as String).startsWith(_binaryPrefix)) {
        message.transparentBinaryPayload =
            _convertStringToUint8List(messageData[argumentsOffset]);
      }
    } else {
      if (messageData.length >= argumentsOffset + 1) {
        message.arguments = messageData[argumentsOffset];
      }
      if (messageData.length >= argumentsOffset + 2) {
        message.argumentsKeywords = messageData[argumentsOffset + 1];
      }
      _convertMessagePayloadBinaryJsonStringToUint8List(message);
    }
    return message;
  }

  void _convertMessagePayloadBinaryJsonStringToUint8List(
      AbstractMessageWithPayload message) {
    if (message.arguments != null && message.arguments.isNotEmpty) {
      _convertListEntriesBinaryJsonStringToUint8List(message.arguments);
    }

    if (message.argumentsKeywords != null &&
        message.argumentsKeywords.isNotEmpty) {
      _convertMapEntriesBinaryJsonStringToUint8List(message.argumentsKeywords);
    }
  }

  void _convertMapEntriesBinaryJsonStringToUint8List(Map payload) {
    for (var element in payload.entries) {
      if (element.value is Map) {
        _convertMapEntriesBinaryJsonStringToUint8List(element.value);
      }
      if (element.value is List) {
        _convertListEntriesBinaryJsonStringToUint8List(element.value);
      }
      if (element.value is String && element.value.startsWith(_binaryPrefix)) {
        payload[element.key] = _convertStringToUint8List(element.value);
      }
    }
  }

  void _convertListEntriesBinaryJsonStringToUint8List(List payload) {
    for (var i = 0; i < payload.length; i++) {
      if (payload[i] is Map) {
        _convertMapEntriesBinaryJsonStringToUint8List(payload[i]);
      }
      if (payload[i] is List) {
        _convertListEntriesBinaryJsonStringToUint8List(payload[i]);
      }
      if (payload[i] is String && payload[i].startsWith(_binaryPrefix)) {
        payload[i] = _convertStringToUint8List(payload[i]);
      }
    }
  }

  Uint8List _convertStringToUint8List(String binaryJsonString) {
    return base64.decode(binaryJsonString.substring(1));
  }

  /// Converts a WAMP message object into a uint8 json message
  @override
  Uint8List serialize(AbstractMessage message) {
    return Utf8Encoder().convert(serializeToString(message));
  }

  /// Converts a WAMP message object into a string json message
  String serializeToString(AbstractMessage message) {
    if (message is Hello) {
      return '[${MessageTypes.CODE_HELLO},${message.realm == null ? 'null' : '"' + message.realm + '"'},${_serializeDetails(message.details)}]';
    }
    if (message is Authenticate) {
      return '[${MessageTypes.CODE_AUTHENTICATE},"${message.signature ?? ""}",${message.extra == null ? '{}' : json.encode(message.extra)}]';
    }
    if (message is Register) {
      return '[${MessageTypes.CODE_REGISTER},${message.requestId},${_serializeRegisterOptions(message.options)},"${message.procedure}"]';
    }
    if (message is Unregister) {
      return '[${MessageTypes.CODE_UNREGISTER},${message.requestId},${message.registrationId}]';
    }
    if (message is Call) {
      return '[${MessageTypes.CODE_CALL},${message.requestId},${_serializeCallOptions(message.options)},"${message.procedure}"${_serializePayload(message)}]';
    }
    if (message is Yield) {
      return '[${MessageTypes.CODE_YIELD},${message.invocationRequestId},${_serializeYieldOptions(message.options)}${_serializePayload(message)}]';
    }
    if (message is Invocation) {
      // for serializer unit test only
      return '[${MessageTypes.CODE_INVOCATION},${message.requestId},${message.registrationId},{}${_serializePayload(message)}]';
    }
    if (message is Publish) {
      return '[${MessageTypes.CODE_PUBLISH},${message.requestId},${_serializePublish(message.options)},"${message.topic}"${_serializePayload(message)}]';
    }
    if (message is Event) {
      return '[${MessageTypes.CODE_EVENT},${message.subscriptionId},${message.publicationId}${_serializePayload(message)}]';
    }
    if (message is Subscribe) {
      return '[${MessageTypes.CODE_SUBSCRIBE},${message.requestId},${_serializeSubscribeOptions(message.options)},"${message.topic}"]';
    }
    if (message is Unsubscribe) {
      return '[${MessageTypes.CODE_UNSUBSCRIBE},${message.requestId},${message.subscriptionId}]';
    }
    if (message is Error) {
      return '[${MessageTypes.CODE_ERROR},${message.requestTypeId},${message.requestId},${json.encode(message.details)},"${message.error}"${_serializePayload(message)}]';
    }
    if (message is Abort) {
      return '[${MessageTypes.CODE_ABORT},${message.message != null ? '{"message":"${message.message.message ?? ""}"}' : "{}"},"${message.reason}"]';
    }
    if (message is Goodbye) {
      return '[${MessageTypes.CODE_GOODBYE},${message.message != null ? '{"message":"${message.message.message ?? ""}"}' : "{}"},"${message.reason}"]';
    }

    _logger.shout(
        'Could not serialize the message of type: ' + message.toString());
    throw Exception(''); // TODO think of something helpful here...
  }

  String _serializeDetails(Details details) {
    if (details.roles != null) {
      var rolesJson = [];
      if (details.roles.caller != null &&
          details.roles.caller.features != null) {
        var callerFeatures = [];
        callerFeatures.add(
            '"call_canceling":${details.roles.caller.features.call_canceling ? "true" : "false"}');
        callerFeatures.add(
            '"call_timeout":${details.roles.caller.features.call_timeout ? "true" : "false"}');
        callerFeatures.add(
            '"caller_identification":${details.roles.caller.features.caller_identification ? "true" : "false"}');
        callerFeatures.add(
            '"payload_transparency":${details.roles.caller.features.payload_transparency ? "true" : "false"}');
        callerFeatures.add(
            '"progressive_call_results":${details.roles.caller.features.progressive_call_results ? "true" : "false"}');
        rolesJson.add('"caller":{"features":{${callerFeatures.join(",")}}}');
      }
      if (details.roles.callee != null &&
          details.roles.callee.features != null) {
        var calleeFeatures = [];
        calleeFeatures.add(
            '"caller_identification":${details.roles.callee.features.caller_identification ? "true" : "false"}');
        calleeFeatures.add(
            '"call_trustlevels":${details.roles.callee.features.call_trustlevels ? "true" : "false"}');
        calleeFeatures.add(
            '"pattern_based_registration":${details.roles.callee.features.pattern_based_registration ? "true" : "false"}');
        calleeFeatures.add(
            '"shared_registration":${details.roles.callee.features.shared_registration ? "true" : "false"}');
        calleeFeatures.add(
            '"call_timeout":${details.roles.callee.features.call_timeout ? "true" : "false"}');
        calleeFeatures.add(
            '"call_canceling":${details.roles.callee.features.call_canceling ? "true" : "false"}');
        calleeFeatures.add(
            '"progressive_call_results":${details.roles.callee.features.progressive_call_results ? "true" : "false"}');
        calleeFeatures.add(
            '"payload_transparency":${details.roles.callee.features.payload_transparency ? "true" : "false"}');
        rolesJson.add('"callee":{"features":{${calleeFeatures.join(",")}}}');
      }
      if (details.roles.subscriber != null &&
          details.roles.subscriber.features != null) {
        var subscriberFeatures = [];
        subscriberFeatures.add(
            '"call_timeout":${details.roles.subscriber.features.call_timeout ? "true" : "false"}');
        subscriberFeatures.add(
            '"call_canceling":${details.roles.subscriber.features.call_canceling ? "true" : "false"}');
        subscriberFeatures.add(
            '"progressive_call_results":${details.roles.subscriber.features.progressive_call_results ? "true" : "false"}');
        subscriberFeatures.add(
            '"payload_transparency":${details.roles.subscriber.features.payload_transparency ? "true" : "false"}');
        subscriberFeatures.add(
            '"subscription_revocation":${details.roles.subscriber.features.subscription_revocation ? "true" : "false"}');
        rolesJson
            .add('"subscriber":{"features":{${subscriberFeatures.join(",")}}}');
      }
      if (details.roles.publisher != null &&
          details.roles.publisher.features != null) {
        var publisherFeatures = [];
        publisherFeatures.add(
            '"publisher_identification":${details.roles.publisher.features.publisher_identification ? "true" : "false"}');
        publisherFeatures.add(
            '"subscriber_blackwhite_listing":${details.roles.publisher.features.subscriber_blackwhite_listing ? "true" : "false"}');
        publisherFeatures.add(
            '"publisher_exclusion":${details.roles.publisher.features.publisher_exclusion ? "true" : "false"}');
        publisherFeatures.add(
            '"payload_transparency":${details.roles.publisher.features.payload_transparency ? "true" : "false"}');
        rolesJson
            .add('"publisher":{"features":{${publisherFeatures.join(",")}}}');
      }
      var detailsParts = ['"roles":{${rolesJson.join(",")}}'];
      if (details.authid != null) {
        detailsParts.add('"authid":"${details.authid}"');
      }
      if (details.authmethods != null && details.authmethods.isNotEmpty) {
        detailsParts
            .add('"authmethods":["${details.authmethods.join('","')}"]');
      }
      if (details.authextra != null) {
        detailsParts.add('"authextra":${json.encode(details.authextra)}');
      }
      return '{${detailsParts.join(",")}}';
    } else {
      return '{}';
    }
  }

  String _serializeSubscribeOptions(SubscribeOptions options) {
    var jsonOptions = [];
    if (options != null) {
      if (options.get_retained != null) {
        jsonOptions
            .add('"get_retained":${options.get_retained ? "true" : "false"}');
      }
      if (options.match != null) {
        jsonOptions.add('"match":"${options.match}"');
      }
      if (options.meta_topic != null) {
        jsonOptions.add('"meta_topic":"${options.meta_topic}"');
      }
      options
          .getCustomValues<String>(SubscribeOptions.CUSTOM_SERIALIZER_JSON)
          .forEach((key, value) {
        jsonOptions.add('"${key}":${value}');
      });
    }

    return '{' + jsonOptions.join(',') + '}';
  }

  String _serializeRegisterOptions(RegisterOptions options) {
    var jsonOptions = [];
    if (options != null) {
      if (options.match != null) {
        jsonOptions.add('"match":"${options.match}"');
      }
      if (options.disclose_caller != null) {
        jsonOptions.add(
            '"disclose_caller":${options.disclose_caller ? 'true' : 'false'}');
      }
      if (options.invoke != null) {
        jsonOptions.add('"invoke":"${options.invoke}"');
      }
    }

    return '{' + jsonOptions.join(',') + '}';
  }

  String _serializeCallOptions(CallOptions options) {
    var jsonOptions = [];
    if (options != null) {
      if (options.receive_progress != null) {
        jsonOptions.add(
            '"receive_progress":${options.receive_progress ? "true" : "false"}');
      }
      if (options.disclose_me != null) {
        jsonOptions
            .add('"disclose_me":${options.disclose_me ? "true" : "false"}');
      }
      if (options.timeout != null) {
        jsonOptions.add('"timeout":${options.timeout}');
      }
    }

    return '{' + jsonOptions.join(',') + '}';
  }

  String _serializeYieldOptions(YieldOptions options) {
    var jsonDetails = [];
    if (options != null) {
      if (options.progress != null) {
        jsonDetails.add('"progress":${options.progress ? "true" : "false"}');
      }
    }
    return '{' + jsonDetails.join(',') + '}';
  }

  String _serializePublish(PublishOptions options) {
    var jsonDetails = [];
    if (options != null) {
      if (options.retain != null) {
        jsonDetails.add('"retain":${options.retain ? "true" : "false"}');
      }
      if (options.disclose_me != null) {
        jsonDetails
            .add('"disclose_me":${options.disclose_me ? "true" : "false"}');
      }
      if (options.acknowledge != null) {
        jsonDetails
            .add('"acknowledge":${options.acknowledge ? "true" : "false"}');
      }
      if (options.exclude_me != null) {
        jsonDetails
            .add('"exclude_me":${options.exclude_me ? "true" : "false"}');
      }
      if (options.exclude != null) {
        jsonDetails.add('"exclude":[${options.exclude.join(",")}]');
      }
      if (options.exclude_authid != null) {
        jsonDetails
            .add('"exclude_authid":["${options.exclude_authid.join('","')}"]');
      }
      if (options.exclude_authrole != null) {
        jsonDetails.add(
            '"exclude_authrole":["${options.exclude_authrole.join('","')}"]');
      }
      if (options.eligible != null) {
        jsonDetails.add('"eligible":[${options.eligible.join(",")}]');
      }
      if (options.eligible_authid != null) {
        jsonDetails.add(
            '"eligible_authid":["${options.eligible_authid.join('","')}"]');
      }
      if (options.eligible_authrole != null) {
        jsonDetails.add(
            '"eligible_authrole":["${options.eligible_authrole.join('","')}"]');
      }
    }
    return '{' + jsonDetails.join(',') + '}';
  }

  String _serializePayload(AbstractMessageWithPayload message) {
    if (message != null) {
      _convertMessagePayloadUint8ListToBinaryJsonString(message);
      if (message.transparentBinaryPayload != null) {
        return ',${json.encode(_convertUint8ListToString(message.transparentBinaryPayload))}';
      } else {
        if (message.argumentsKeywords != null) {
          return ',${json.encode(message.arguments ?? [])},${json.encode(message.argumentsKeywords)}';
        } else if (message.arguments != null) {
          return ',${json.encode(message.arguments)}';
        }
      }
    }
    return '';
  }

  void _convertMessagePayloadUint8ListToBinaryJsonString(
      AbstractMessageWithPayload message) {
    if (message.arguments != null && message.arguments.isNotEmpty) {
      _convertListEntriesUint8ListToBinaryJsonString(message.arguments);
    }

    if (message.argumentsKeywords != null &&
        message.argumentsKeywords.isNotEmpty) {
      _convertMapEntriesUint8ListToBinaryJsonString(message.argumentsKeywords);
    }
  }

  void _convertMapEntriesUint8ListToBinaryJsonString(Map payload) {
    for (var element in payload.entries) {
      if (element.value is Map) {
        _convertMapEntriesUint8ListToBinaryJsonString(element.value);
      }
      if (element.value is List) {
        _convertListEntriesUint8ListToBinaryJsonString(element.value);
      }
      if (element.value is Uint8List) {
        payload[element.key] = _convertUint8ListToString(element.value);
      }
    }
  }

  void _convertListEntriesUint8ListToBinaryJsonString(List payload) {
    for (var i = 0; i < payload.length; i++) {
      if (payload[i] is Map) {
        _convertMapEntriesUint8ListToBinaryJsonString(payload[i]);
      }
      if (payload[i] is List) {
        _convertListEntriesUint8ListToBinaryJsonString(payload[i]);
      }
      if (payload[i] is Uint8List) {
        payload[i] = _convertUint8ListToString(payload[i]);
      }
    }
  }

  String _convertUint8ListToString(Uint8List binary) {
    return '\x00' + base64.encode(binary);
  }
}

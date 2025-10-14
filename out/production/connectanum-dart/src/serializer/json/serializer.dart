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

import '../../message/ppt_payload.dart';
import '../abstract_serializer.dart';

/// This is a serializer for JSON messages. It is used to initialize an [AbstractTransport]
/// object.
class Serializer extends AbstractSerializer {
  static final String _binaryPrefix = '\\u0000';
  static final Logger _logger = Logger('Connectanum.Serializer');

  /// Converts a uint8 JSON message into a WAMP message object
  @override
  AbstractMessage? deserialize(Uint8List? jsonMessage) {
    return deserializeFromString(Utf8Decoder().convert(jsonMessage!));
  }

  /// Converts a string JSON message into a WAMP message object
  AbstractMessage? deserializeFromString(String jsonMessage) {
    Object? message = json.decode(jsonMessage);
    if (message is List) {
      int messageId = message[0];
      if (messageId == MessageTypes.codeChallenge) {
        return Challenge(
            message[1],
            Extra(
                challenge: message[2]['challenge'],
                salt: message[2]['salt'],
                keyLen: message[2]['keylen'],
                iterations: message[2]['iterations'],
                memory: message[2]['memory'],
                kdf: message[2]['kdf'],
                nonce: message[2]['nonce']));
      }
      if (messageId == MessageTypes.codeWelcome) {
        final details = Details();
        details.realm = message[2]['realm'] ?? '';
        details.authid = message[2]['authid'] ?? '';
        details.authprovider = message[2]['authprovider'] ?? '';
        details.authmethod = message[2]['authmethod'] ?? '';
        details.authrole = message[2]['authrole'] ?? '';
        if (message[2]['authextra'] != null) {
          (message[2]['authextra'] as Map).forEach((key, value) {
            details.authextra ??= <String, dynamic>{};
            details.authextra![key] = value;
          });
        }
        if (message[2]['roles'] != null) {
          details.roles = Roles();
          if (message[2]['roles']['dealer'] != null) {
            details.roles!.dealer = Dealer();
            if (message[2]['roles']['dealer']['features'] != null) {
              details.roles!.dealer!.features = DealerFeatures();
              details.roles!.dealer!.features!.callerIdentification = message[2]
                          ['roles']['dealer']['features']
                      ['caller_identification'] ??
                  false;
              details.roles!.dealer!.features!.callTrustLevels = message[2]
                      ['roles']['dealer']['features']['call_trustlevels'] ??
                  false;
              details.roles!.dealer!.features!.patternBasedRegistration =
                  message[2]['roles']['dealer']['features']
                          ['pattern_based_registration'] ??
                      false;
              details.roles!.dealer!.features!.registrationMetaApi = message[2]
                          ['roles']['dealer']['features']
                      ['registration_meta_api'] ??
                  false;
              details.roles!.dealer!.features!.sharedRegistration = message[2]
                      ['roles']['dealer']['features']['shared_registration'] ??
                  false;
              details.roles!.dealer!.features!.sessionMetaApi = message[2]
                      ['roles']['dealer']['features']['session_meta_api'] ??
                  false;
              details.roles!.dealer!.features!.callTimeout = message[2]['roles']
                      ['dealer']['features']['call_timeout'] ??
                  false;
              details.roles!.dealer!.features!.callCanceling = message[2]
                      ['roles']['dealer']['features']['call_canceling'] ??
                  false;
              details.roles!.dealer!.features!.progressiveCallResults =
                  // ignore: prefer_single_quotes
                  message[2]['roles']['dealer']['features']
                          ['progressive_call_results'] ??
                      false;
              details.roles!.dealer!.features!.payloadPassThruMode = message[2]
                          ['roles']['dealer']['features']
                      ['payload_passthru_mode'] ??
                  false;
            }
          }
          if (message[2]['roles']['broker'] != null) {
            details.roles!.broker = Broker();
            if (message[2]['roles']['broker']['features'] != null) {
              details.roles!.broker!.features = BrokerFeatures();
              details.roles!.broker!.features!.publisherIdentification =
                  message[2]['roles']['broker']['features']
                          ['publisher_identification'] ??
                      false;
              details.roles!.broker!.features!.publicationTrustLevels =
                  message[2]['roles']['broker']['features']
                          ['publication_trustlevels'] ??
                      false;
              details.roles!.broker!.features!.patternBasedSubscription =
                  message[2]['roles']['broker']['features']
                          ['pattern_based_subscription'] ??
                      false;
              details.roles!.broker!.features!.subscriptionMetaApi = message[2]
                          ['roles']['broker']['features']
                      ['subscription_meta_api'] ??
                  false;
              details.roles!.broker!.features!.subscriberBlackWhiteListing =
                  message[2]['roles']['broker']['features']
                          ['subscriber_blackwhite_listing'] ??
                      false;
              details.roles!.broker!.features!.sessionMetaApi = message[2]
                      ['roles']['broker']['features']['session_meta_api'] ??
                  false;
              details.roles!.broker!.features!.publisherExclusion = message[2]
                      ['roles']['broker']['features']['publisher_exclusion'] ??
                  false;
              details.roles!.broker!.features!.eventHistory = message[2]
                      ['roles']['broker']['features']['event_history'] ??
                  false;
              details.roles!.broker!.features!.payloadPassThruMode = message[2]
                          ['roles']['broker']['features']
                      ['payload_passthru_mode'] ??
                  false;
            }
          }
        }
        return Welcome(message[1], details);
      }
      if (messageId == MessageTypes.codeRegistered) {
        return Registered(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnregistered) {
        return Unregistered(message[1]);
      }
      if (messageId == MessageTypes.codeInvocation) {
        return _addPayload(
            Invocation(
                message[1],
                message[2],
                InvocationDetails(message[3]['caller'], message[3]['procedure'],
                    message[3]['receive_progress'])),
            message,
            4);
      }
      if (messageId == MessageTypes.codeResult) {
        return _addPayload(
            Result(
                message[1],
                ResultDetails(
                    progress: message[2]['progress'],
                    pptScheme: message[2]['ppt_scheme'],
                    pptSerializer: message[2]['ppt_serializer'],
                    pptCipher: message[2]['ppt_cipher'],
                    pptKeyId: message[2]['ppt_keyid'])),
            message,
            3);
      }
      if (messageId == MessageTypes.codePublished) {
        return Published(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeSubscribed) {
        return Subscribed(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnsubscribed) {
        return Unsubscribed(
            message[1],
            message.length == 2
                ? null
                : UnsubscribedDetails(
                    message[2]['subscription'], message[2]['reason']));
      }
      if (messageId == MessageTypes.codeEvent) {
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
      if (messageId == MessageTypes.codeError) {
        return _addPayload(
            Error(message[1], message[2], message[3], message[4]), message, 5);
      }
      if (messageId == MessageTypes.codeAbort) {
        return Abort(message[2],
            message: message[1] == null ? null : message[1]['message']);
      }
      if (messageId == MessageTypes.codeGoodbye) {
        return Goodbye(
            message[1] == null ? null : GoodbyeMessage(message[1]['message']),
            message[2]);
      }
    }
    _logger.shout('Could not deserialize the message: $jsonMessage');
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(AbstractMessageWithPayload message,
      List<dynamic> messageData, argumentsOffset) {
    if (messageData.length == argumentsOffset + 1 &&
        messageData[argumentsOffset] is String) {
      if ((messageData[argumentsOffset] as String).startsWith(_binaryPrefix)) {
        message.transparentBinaryPayload = _convertStringToUint8List(
            (messageData[argumentsOffset] as String)
                .substring(_binaryPrefix.length - 1));
      }
    } else {
      if (messageData.length >= argumentsOffset + 1) {
        message.arguments = messageData[argumentsOffset] as List<dynamic>?;
      }
      if (messageData.length >= argumentsOffset + 2) {
        message.argumentsKeywords =
            messageData[argumentsOffset + 1] as Map<String, dynamic>?;
      }
      _convertMessagePayloadBinaryJsonStringToUint8List(message);
    }
    return message;
  }

  void _convertMessagePayloadBinaryJsonStringToUint8List(
      AbstractMessageWithPayload message) {
    if (message.arguments != null && message.arguments!.isNotEmpty) {
      _convertListEntriesBinaryJsonStringToUint8List(message.arguments!);
    }

    if (message.argumentsKeywords != null &&
        message.argumentsKeywords!.isNotEmpty) {
      _convertMapEntriesBinaryJsonStringToUint8List(message.argumentsKeywords!);
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
        payload[element.key] = _convertStringToUint8List(
            (element.value as String).substring(_binaryPrefix.length - 1));
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
        payload[i] = _convertStringToUint8List(
            (payload[i] as String).substring(_binaryPrefix.length - 1));
      }
    }
  }

  Uint8List _convertStringToUint8List(String binaryJsonString) {
    return base64.decode(binaryJsonString.substring(1));
  }

  /// Converts a WAMP message object into a uint8 json message
  @override
  String serialize(AbstractMessage message) {
    return serializeToString(message);
  }

  /// Converts a WAMP message object into a string json message
  String serializeToString(AbstractMessage message) {
    if (message is Hello) {
      return '[${MessageTypes.codeHello},${message.realm == null ? 'null' : '"${message.realm!}"'},${_serializeDetails(message.details)}]';
    }
    if (message is Authenticate) {
      return '[${MessageTypes.codeAuthenticate},"${message.signature ?? ""}",${message.extra == null ? '{}' : json.encode(message.extra)}]';
    }
    if (message is Register) {
      return '[${MessageTypes.codeRegister},${message.requestId},${_serializeRegisterOptions(message.options)},"${message.procedure}"]';
    }
    if (message is Unregister) {
      return '[${MessageTypes.codeUnregister},${message.requestId},${message.registrationId}]';
    }
    if (message is Call) {
      return '[${MessageTypes.codeCall},${message.requestId},${_serializeCallOptions(message.options)},"${message.procedure}"${_serializePayload(message)}]';
    }
    if (message is Yield) {
      return '[${MessageTypes.codeYield},${message.invocationRequestId},${_serializeYieldOptions(message.options)}${_serializePayload(message)}]';
    }
    if (message is Invocation) {
      // for serializer unit test only
      return '[${MessageTypes.codeInvocation},${message.requestId},${message.registrationId},{}${_serializePayload(message)}]';
    }
    if (message is Publish) {
      return '[${MessageTypes.codePublish},${message.requestId},${_serializePublish(message.options)},"${message.topic}"${_serializePayload(message)}]';
    }
    if (message is Event) {
      return '[${MessageTypes.codeEvent},${message.subscriptionId},${message.publicationId}${_serializePayload(message)}]';
    }
    if (message is Subscribe) {
      return '[${MessageTypes.codeSubscribe},${message.requestId},${_serializeSubscribeOptions(message.options)},"${message.topic}"]';
    }
    if (message is Unsubscribe) {
      return '[${MessageTypes.codeUnsubscribe},${message.requestId},${message.subscriptionId}]';
    }
    if (message is Error) {
      return '[${MessageTypes.codeError},${message.requestTypeId},${message.requestId},${json.encode(message.details)},"${message.error}"${_serializePayload(message)}]';
    }
    if (message is Abort) {
      return '[${MessageTypes.codeAbort},${message.message != null ? '{"message":"${message.message!.message}"}' : "{}"},"${message.reason}"]';
    }
    if (message is Goodbye) {
      return '[${MessageTypes.codeGoodbye},${message.message != null ? '{"message":"${message.message!.message ?? ""}"}' : "{}"},"${message.reason}"]';
    }

    _logger.shout('Could not serialize the message of type: $message');
    throw Exception(''); // TODO think of something helpful here...
  }

  String _serializeDetails(Details details) {
    if (details.roles != null) {
      var rolesJson = [];
      if (details.roles?.caller?.features != null) {
        var callerFeatures = [];
        callerFeatures.add(
            '"call_canceling":${details.roles!.caller!.features!.callCanceling ? "true" : "false"}');
        callerFeatures.add(
            '"call_timeout":${details.roles!.caller!.features!.callTimeout ? "true" : "false"}');
        callerFeatures.add(
            '"caller_identification":${details.roles!.caller!.features!.callerIdentification ? "true" : "false"}');
        callerFeatures.add(
            '"payload_passthru_mode":${details.roles!.caller!.features!.payloadPassThruMode ? "true" : "false"}');
        callerFeatures.add(
            '"progressive_call_results":${details.roles!.caller!.features!.progressiveCallResults ? "true" : "false"}');
        rolesJson.add('"caller":{"features":{${callerFeatures.join(",")}}}');
      }
      if (details.roles?.callee?.features != null) {
        var calleeFeatures = [];
        calleeFeatures.add(
            '"caller_identification":${details.roles!.callee!.features!.callerIdentification ? "true" : "false"}');
        calleeFeatures.add(
            '"call_trustlevels":${details.roles!.callee!.features!.callTrustlevels ? "true" : "false"}');
        calleeFeatures.add(
            '"pattern_based_registration":${details.roles!.callee!.features!.patternBasedRegistration ? "true" : "false"}');
        calleeFeatures.add(
            '"shared_registration":${details.roles!.callee!.features!.sharedRegistration ? "true" : "false"}');
        calleeFeatures.add(
            '"call_timeout":${details.roles!.callee!.features!.callTimeout ? "true" : "false"}');
        calleeFeatures.add(
            '"call_canceling":${details.roles!.callee!.features!.callCanceling ? "true" : "false"}');
        calleeFeatures.add(
            '"progressive_call_results":${details.roles!.callee!.features!.progressiveCallResults ? "true" : "false"}');
        calleeFeatures.add(
            '"payload_passthru_mode":${details.roles!.callee!.features!.payloadPassThruMode ? "true" : "false"}');
        rolesJson.add('"callee":{"features":{${calleeFeatures.join(",")}}}');
      }
      if (details.roles?.subscriber?.features != null) {
        var subscriberFeatures = [];
        subscriberFeatures.add(
            '"call_timeout":${details.roles!.subscriber!.features!.callTimeout ? "true" : "false"}');
        subscriberFeatures.add(
            '"call_canceling":${details.roles!.subscriber!.features!.callCanceling ? "true" : "false"}');
        subscriberFeatures.add(
            '"progressive_call_results":${details.roles!.subscriber!.features!.progressiveCallResults ? "true" : "false"}');
        subscriberFeatures.add(
            '"payload_passthru_mode":${details.roles!.subscriber!.features!.payloadPassThruMode ? "true" : "false"}');
        subscriberFeatures.add(
            '"subscription_revocation":${details.roles!.subscriber!.features!.subscriptionRevocation ? "true" : "false"}');
        rolesJson
            .add('"subscriber":{"features":{${subscriberFeatures.join(",")}}}');
      }
      if (details.roles?.publisher?.features != null) {
        var publisherFeatures = [];
        publisherFeatures.add(
            '"publisher_identification":${details.roles!.publisher!.features!.publisherIdentification ? "true" : "false"}');
        publisherFeatures.add(
            '"subscriber_blackwhite_listing":${details.roles!.publisher!.features!.subscriberBlackWhiteListing ? "true" : "false"}');
        publisherFeatures.add(
            '"publisher_exclusion":${details.roles!.publisher!.features!.publisherExclusion ? "true" : "false"}');
        publisherFeatures.add(
            '"payload_passthru_mode":${details.roles!.publisher!.features!.payloadPassThruMode ? "true" : "false"}');
        rolesJson
            .add('"publisher":{"features":{${publisherFeatures.join(",")}}}');
      }
      var detailsParts = ['"roles":{${rolesJson.join(",")}}'];
      if (details.authid != null) {
        detailsParts.add('"authid":"${details.authid}"');
      }
      if (details.authmethods != null && details.authmethods!.isNotEmpty) {
        detailsParts
            .add('"authmethods":["${details.authmethods!.join('","')}"]');
      }
      if (details.authextra != null) {
        detailsParts.add('"authextra":${json.encode(details.authextra)}');
      }
      return '{${detailsParts.join(",")}}';
    } else {
      return '{}';
    }
  }

  String _serializeSubscribeOptions(SubscribeOptions? options) {
    var jsonOptions = [];
    if (options != null) {
      if (options.getRetained != null) {
        jsonOptions
            .add('"get_retained":${options.getRetained! ? "true" : "false"}');
      }
      if (options.match != null) {
        jsonOptions.add('"match":"${options.match}"');
      }
      if (options.metaTopic != null) {
        jsonOptions.add('"meta_topic":"${options.metaTopic}"');
      }
      options
          .getCustomValues<String>(SubscribeOptions.customSerializerJson)
          .forEach((key, value) {
        jsonOptions.add('"$key":$value');
      });
    }

    return '{${jsonOptions.join(',')}}';
  }

  String _serializeRegisterOptions(RegisterOptions? options) {
    var jsonOptions = [];
    if (options != null) {
      if (options.match != null) {
        jsonOptions.add('"match":"${options.match}"');
      }
      if (options.discloseCaller != null) {
        jsonOptions.add(
            '"disclose_caller":${options.discloseCaller! ? 'true' : 'false'}');
      }
      if (options.invoke != null) {
        jsonOptions.add('"invoke":"${options.invoke}"');
      }
    }

    return '{${jsonOptions.join(',')}}';
  }

  String _serializeCallOptions(CallOptions? options) {
    var jsonOptions = [];
    if (options != null) {
      if (options.receiveProgress != null) {
        jsonOptions.add(
            '"receive_progress":${options.receiveProgress! ? "true" : "false"}');
      }
      if (options.discloseMe != null) {
        jsonOptions
            .add('"disclose_me":${options.discloseMe! ? "true" : "false"}');
      }
      if (options.timeout != null) {
        jsonOptions.add('"timeout":${options.timeout}');
      }
    }

    return '{${jsonOptions.join(',')}}';
  }

  String _serializeYieldOptions(YieldOptions? options) {
    var jsonDetails = [];
    if (options != null) {
      jsonDetails.add('"progress":${options.progress ? "true" : "false"}');
    }
    return '{${jsonDetails.join(',')}}';
  }

  String _serializePublish(PublishOptions? options) {
    var jsonDetails = [];
    if (options != null) {
      if (options.retain != null) {
        jsonDetails.add('"retain":${options.retain! ? "true" : "false"}');
      }
      if (options.discloseMe != null) {
        jsonDetails
            .add('"disclose_me":${options.discloseMe! ? "true" : "false"}');
      }
      if (options.acknowledge != null) {
        jsonDetails
            .add('"acknowledge":${options.acknowledge! ? "true" : "false"}');
      }
      if (options.excludeMe != null) {
        jsonDetails
            .add('"exclude_me":${options.excludeMe! ? "true" : "false"}');
      }
      if (options.exclude != null) {
        jsonDetails.add('"exclude":[${options.exclude!.join(",")}]');
      }
      if (options.excludeAuthId != null) {
        jsonDetails
            .add('"exclude_authid":["${options.excludeAuthId!.join('","')}"]');
      }
      if (options.excludeAuthRole != null) {
        jsonDetails.add(
            '"exclude_authrole":["${options.excludeAuthRole!.join('","')}"]');
      }
      if (options.eligible != null) {
        jsonDetails.add('"eligible":[${options.eligible!.join(",")}]');
      }
      if (options.eligibleAuthId != null) {
        jsonDetails.add(
            '"eligible_authid":["${options.eligibleAuthId!.join('","')}"]');
      }
      if (options.eligibleAuthRole != null) {
        jsonDetails.add(
            '"eligible_authrole":["${options.eligibleAuthRole!.join('","')}"]');
      }
    }
    return '{${jsonDetails.join(',')}}';
  }

  String _serializePayload(AbstractMessageWithPayload message) {
    _convertMessagePayloadUint8ListToBinaryJsonString(message);
    if (message.transparentBinaryPayload != null) {
      return ',${json.encode(_convertUint8ListToString(message.transparentBinaryPayload!))}';
    } else {
      if (message.argumentsKeywords != null) {
        return ',${json.encode(message.arguments ?? [])},${json.encode(message.argumentsKeywords)}';
      } else if (message.arguments != null) {
        return ',${json.encode(message.arguments)}';
      }
    }
    return '';
  }

  void _convertMessagePayloadUint8ListToBinaryJsonString(
      AbstractMessageWithPayload message) {
    if (message.arguments != null && message.arguments!.isNotEmpty) {
      _convertListEntriesUint8ListToBinaryJsonString(message.arguments!);
    }

    if (message.argumentsKeywords != null &&
        message.argumentsKeywords!.isNotEmpty) {
      _convertMapEntriesUint8ListToBinaryJsonString(message.argumentsKeywords!);
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
    return '\\u0000${base64.encode(binary)}';
  }

  /// Converts a uint8 JSON message into a PPT Payload Object
  @override
  PPTPayload? deserializePPT(Uint8List binPayload) {
    var messageStr = Utf8Decoder().convert(binPayload);
    Object? decodedObject = json.decode(messageStr);

    if (decodedObject is Map) {
      return PPTPayload(
          arguments: decodedObject['args'],
          argumentsKeywords: decodedObject['kwargs']);
    }

    _logger.shout('Could not deserialize the message: $messageStr');
    // TODO respond with an error
    return null;
  }

  /// Converts a PPT Payload Object into a uint8 array
  @override
  Uint8List serializePPT(PPTPayload pptPayload) {
    var pptMap = {
      'arguments': pptPayload.arguments,
      'argumentsKeywords': pptPayload.argumentsKeywords
    };
    _convertMapEntriesUint8ListToBinaryJsonString(pptMap);
    var str =
        '{"args": ${json.encode(pptMap['arguments'])}, "kwargs": ${json.encode(pptMap['argumentsKeywords'])}}';
    return Utf8Encoder().convert(str);
  }
}

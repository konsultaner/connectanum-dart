import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;

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

import '../../message/ppt_payload.dart';
import '../abstract_serializer.dart';

/// This is a seralizer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Serializer');

  /// Converts a uint8 msgpack message into a WAMP message object
  @override
  AbstractMessage? deserialize(Uint8List? msgPack) {
    Object? message = msgpack_dart.deserialize(msgPack!);
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
              details.roles!.dealer!.features!.callerIdentification =
                  message[2]['roles']['dealer']['features']
                          ['caller_identification'] ??
                      false;
              details.roles!.dealer!.features!.callTrustLevels = message[2]
                      ['roles']['dealer']['features']['call_trustlevels'] ??
                  false;
              details.roles!.dealer!.features!.patternBasedRegistration =
                  message[2]['roles']['dealer']['features']
                          ['pattern_based_registration'] ??
                      false;
              details.roles!.dealer!.features!.registrationMetaApi =
                  message[2]['roles']['dealer']['features']
                          ['registration_meta_api'] ??
                      false;
              details.roles!.dealer!.features!.sharedRegistration = message[2]
                      ['roles']['dealer']['features']['shared_registration'] ??
                  false;
              details.roles!.dealer!.features!.sessionMetaApi = message[2]
                      ['roles']['dealer']['features']['session_meta_api'] ??
                  false;
              details.roles!.dealer!.features!.callTimeout = message[2]
                      ['roles']['dealer']['features']['call_timeout'] ??
                  false;
              details.roles!.dealer!.features!.callCanceling = message[2]
                      ['roles']['dealer']['features']['call_canceling'] ??
                  false;
              details.roles!.dealer!.features!.progressiveCallResults =
                  message[2]['roles']['dealer']['features']
                          ['progressive_call_results'] ??
                      false;
              details.roles!.dealer!.features!.payloadPassThruMode =
                  message[2]['roles']['dealer']['features']
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
              details.roles!.broker!.features!.subscriptionMetaApi =
                  message[2]['roles']['broker']['features']
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
              details.roles!.broker!.features!.payloadPassThruMode =
                  message[2]['roles']['broker']['features']
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
            Error(message[1], message[2], Map<String, Object>.from(message[3]),
                message[4]),
            message,
            5);
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
    _logger.shout('Could not deserialize the message: $msgPack');
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(AbstractMessageWithPayload message,
      List<dynamic> messageData, argumentsOffset) {
    if (messageData.length >= argumentsOffset + 1) {
      message.arguments = messageData[argumentsOffset] as List<dynamic>?;
    }
    if (messageData.length >= argumentsOffset + 2) {
      message.argumentsKeywords =
          Map.castFrom<dynamic, dynamic, String, Object>(
              messageData[argumentsOffset + 1] as Map<dynamic, dynamic>);
    }
    return message;
  }

  /// Converts a WAMP message object into a uint8 msgpack message
  @override
  Uint8List serialize(AbstractMessage message) {
    if (message is Hello) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.codeHello) +
          msgpack_dart.serialize(message.realm) +
          _serializeDetails(message.details)!);
    }
    if (message is Authenticate) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.codeAuthenticate) +
          msgpack_dart.serialize(message.signature ?? '') +
          msgpack_dart.serialize(message.extra ?? '{}'));
    }
    if (message is Register) {
      return Uint8List.fromList([148] +
          msgpack_dart.serialize(MessageTypes.codeRegister) +
          msgpack_dart.serialize(message.requestId) +
          _serializeRegisterOptions(message.options) +
          msgpack_dart.serialize(message.procedure));
    }
    if (message is Unregister) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.codeUnregister) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.registrationId));
    }
    if (message is Call) {
      var res = [148] +
          msgpack_dart.serialize(MessageTypes.codeCall) +
          msgpack_dart.serialize(message.requestId) +
          _serializeCallOptions(message.options) +
          msgpack_dart.serialize(message.procedure);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Yield) {
      var res = [147] +
          msgpack_dart.serialize(MessageTypes.codeYield) +
          msgpack_dart.serialize(message.invocationRequestId) +
          _serializeYieldOptions(message.options);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Invocation) {
      // for serializer unit test only
      var res = [148] +
          msgpack_dart.serialize(MessageTypes.codeInvocation) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.registrationId) +
          msgpack_dart.serialize({});
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Publish) {
      var res = [148] +
          msgpack_dart.serialize(MessageTypes.codePublish) +
          msgpack_dart.serialize(message.requestId) +
          _serializePublish(message.options) +
          msgpack_dart.serialize(message.topic);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Event) {
      var res = [147] +
          msgpack_dart.serialize(MessageTypes.codeEvent) +
          msgpack_dart.serialize(message.subscriptionId) +
          msgpack_dart.serialize(message.publicationId);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Subscribe) {
      return Uint8List.fromList([148] +
          msgpack_dart.serialize(MessageTypes.codeSubscribe) +
          msgpack_dart.serialize(message.requestId) +
          _serializeSubscribeOptions(message.options) +
          msgpack_dart.serialize(message.topic));
    }
    if (message is Unsubscribe) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.codeUnsubscribe) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.subscriptionId));
    }
    if (message is Error) {
      var res = [149] +
          msgpack_dart.serialize(MessageTypes.codeError) +
          msgpack_dart.serialize(message.requestTypeId) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.details) +
          msgpack_dart.serialize(message.error);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Abort) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.codeAbort) +
          msgpack_dart.serialize(message.message != null
              ? {'message': message.message!.message}
              : {}) +
          msgpack_dart.serialize(message.reason));
    }
    if (message is Goodbye) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.codeGoodbye) +
          msgpack_dart.serialize(message.message != null
              ? {'message': message.message!.message ?? ""}
              : {}) +
          msgpack_dart.serialize(message.reason));
    }

    _logger.shout(
        'Could not serialize the message of type: $message');
    throw Exception('Message type not known!');
  }

  Uint8List? _serializeDetails(Details details) {
    if (details.roles != null) {
      var roles = {};
      if (details.roles!.caller != null &&
          details.roles!.caller!.features != null) {
        var callerFeatures = {};
        callerFeatures.addEntries([
          MapEntry('call_canceling',
              details.roles!.caller!.features!.callCanceling),
          MapEntry(
              'call_timeout', details.roles!.caller!.features!.callTimeout),
          MapEntry('caller_identification',
              details.roles!.caller!.features!.callerIdentification),
          MapEntry('payload_passthru_mode',
              details.roles!.caller!.features!.payloadPassThruMode),
          MapEntry('progressive_call_results',
              details.roles!.caller!.features!.progressiveCallResults)
        ]);
        roles.addEntries([
          MapEntry('caller', {'features': callerFeatures})
        ]);
      }
      if (details.roles!.callee != null &&
          details.roles!.callee!.features != null) {
        var calleeFeatures = {};
        calleeFeatures.addEntries([
          MapEntry('caller_identification',
              details.roles!.callee!.features!.callerIdentification),
          MapEntry('call_trustlevels',
              details.roles!.callee!.features!.callTrustlevels),
          MapEntry('pattern_based_registration',
              details.roles!.callee!.features!.patternBasedRegistration),
          MapEntry('shared_registration',
              details.roles!.callee!.features!.sharedRegistration),
          MapEntry('call_canceling',
              details.roles!.callee!.features!.callCanceling),
          MapEntry(
              'call_timeout', details.roles!.callee!.features!.callTimeout),
          MapEntry('caller_identification',
              details.roles!.callee!.features!.callerIdentification),
          MapEntry('payload_passthru_mode',
              details.roles!.callee!.features!.payloadPassThruMode),
          MapEntry('progressive_call_results',
              details.roles!.callee!.features!.progressiveCallResults)
        ]);
        roles.addEntries([
          MapEntry('callee', {'features': calleeFeatures})
        ]);
      }
      if (details.roles!.subscriber != null &&
          details.roles!.subscriber!.features != null) {
        var subscriberFeatures = {};
        subscriberFeatures.addEntries([
          MapEntry('call_canceling',
              details.roles!.subscriber!.features!.callCanceling),
          MapEntry('call_timeout',
              details.roles!.subscriber!.features!.callTimeout),
          MapEntry('payload_passthru_mode',
              details.roles!.subscriber!.features!.payloadPassThruMode),
          MapEntry('progressive_call_results',
              details.roles!.subscriber!.features!.progressiveCallResults),
          MapEntry('subscription_revocation',
              details.roles!.subscriber!.features!.subscriptionRevocation)
        ]);
        roles.addEntries([
          MapEntry('subscriber', {'features': subscriberFeatures})
        ]);
      }
      if (details.roles!.publisher != null &&
          details.roles!.publisher!.features != null) {
        var publisherFeatures = {};
        publisherFeatures.addEntries([
          MapEntry('publisher_identification',
              details.roles!.publisher!.features!.publisherIdentification),
          MapEntry(
              'subscriber_blackwhite_listing',
              details
                  .roles!.publisher!.features!.subscriberBlackWhiteListing),
          MapEntry('publisher_exclusion',
              details.roles!.publisher!.features!.publisherExclusion),
          MapEntry('payload_passthru_mode',
              details.roles!.publisher!.features!.payloadPassThruMode)
        ]);
        roles.addEntries([
          MapEntry('publisher', {'features': publisherFeatures})
        ]);
      }
      var detailsParts = <String, dynamic>{};
      detailsParts['roles'] = roles;
      if (details.authid != null) {
        detailsParts['authid'] = details.authid;
      }
      if (details.authmethods != null && details.authmethods!.isNotEmpty) {
        detailsParts['authmethods'] = details.authmethods;
      }
      if (details.authextra != null) {
        detailsParts['authextra'] = details.authextra;
      }
      return msgpack_dart.serialize(detailsParts);
    } else {
      return null;
    }
  }

  Uint8List _serializeSubscribeOptions(SubscribeOptions? options) {
    var subscriptionOptions = {};
    if (options != null) {
      if (options.getRetained != null) {
        subscriptionOptions['get_retained'] = options.getRetained;
      }
      if (options.match != null) {
        subscriptionOptions['match'] = options.match;
      }
      if (options.metaTopic != null) {
        subscriptionOptions['meta_topic'] = options.metaTopic;
      }
      options
          .getCustomValues<dynamic>(SubscribeOptions.customSerializerJson)
          .forEach((key, value) {
        subscriptionOptions[key] = value;
      });
    }

    return msgpack_dart.serialize(subscriptionOptions);
  }

  Uint8List _serializeRegisterOptions(RegisterOptions? options) {
    var registerOptions = {};
    if (options != null) {
      if (options.match != null) {
        registerOptions.addEntries([MapEntry('match', options.match)]);
      }
      if (options.discloseCaller != null) {
        registerOptions
            .addEntries([MapEntry('disclose_caller', options.discloseCaller)]);
      }
      if (options.invoke != null) {
        registerOptions.addEntries([MapEntry('invoke', options.invoke)]);
      }
    }

    return msgpack_dart.serialize(registerOptions);
  }

  Uint8List _serializeCallOptions(CallOptions? options) {
    var callOptions = {};
    if (options != null) {
      if (options.receiveProgress != null) {
        callOptions.addEntries(
            [MapEntry('receive_progress', options.receiveProgress)]);
      }
      if (options.discloseMe != null) {
        callOptions.addEntries([MapEntry('disclose_me', options.discloseMe)]);
      }
      if (options.timeout != null) {
        callOptions.addEntries([MapEntry('timeout', options.timeout)]);
      }
    }

    return msgpack_dart.serialize(callOptions);
  }

  Uint8List _serializeYieldOptions(YieldOptions? options) {
    var yieldOptions = {};
    if (options != null) {
      yieldOptions.addEntries([MapEntry('progress', options.progress)]);
    }
    return msgpack_dart.serialize(yieldOptions);
  }

  Uint8List _serializePublish(PublishOptions? options) {
    var publishDetails = {};
    if (options != null) {
      publishDetails.addEntries([
        if (options.retain != null) MapEntry('retain', options.retain),
        if (options.discloseMe != null)
          MapEntry('disclose_me', options.discloseMe),
        if (options.acknowledge != null)
          MapEntry('acknowledge', options.acknowledge),
        if (options.excludeMe != null)
          MapEntry('exclude_me', options.excludeMe),
        if (options.exclude != null) MapEntry('exclude', options.exclude),
        if (options.excludeAuthId != null)
          MapEntry('exclude_authid', options.excludeAuthId),
        if (options.excludeAuthRole != null)
          MapEntry('exclude_auth_role', options.excludeAuthRole),
        if (options.eligible != null) MapEntry('eligible', options.eligible),
        if (options.eligibleAuthRole != null)
          MapEntry('eligible_authrole', options.eligibleAuthRole),
        if (options.eligibleAuthId != null)
          MapEntry('eligible_authid', options.eligibleAuthId)
      ]);
    }
    return msgpack_dart.serialize(publishDetails);
  }

  /// returns bytes to add to header and serialized payload bytes
  SerializedPayload<int, Uint8List> _serializePayload(
      AbstractMessageWithPayload message) {
    if (message.argumentsKeywords != null) {
      return SerializedPayload(
          2,
          Uint8List.fromList(msgpack_dart.serialize(message.arguments ?? []) +
              msgpack_dart.serialize(message.argumentsKeywords)));
    } else if (message.arguments != null) {
      return SerializedPayload(1, msgpack_dart.serialize(message.arguments));
    }
    return SerializedPayload(0, msgpack_dart.serialize(''));
  }

  /// Converts a uint8 data into a PPT Payload Object
  @override
  PPTPayload? deserializePPT(Uint8List binPayload) {
    List<dynamic>? arguments;
    Map<String, dynamic>? argumentsKeywords;

    Object? decodedObject = msgpack_dart.deserialize(binPayload);

    if (decodedObject is Map) {
      if (decodedObject['args'] != null && decodedObject['args'] is List) {
        arguments = decodedObject['args'] as List<dynamic>?;
      }

      if (decodedObject['kwargs'] != null && decodedObject['kwargs'] is Map) {
        argumentsKeywords = Map.castFrom<dynamic, dynamic, String, Object>(
            decodedObject['kwargs'] as Map<dynamic, dynamic>);
      }

      return PPTPayload(
          arguments: arguments, argumentsKeywords: argumentsKeywords);
    }

    _logger
        .shout('Could not deserialize the message: $binPayload');
    // TODO respond with an error
    return null;
  }

  /// Converts a PPT Payload Object into a uint8 array
  @override
  Uint8List serializePPT(PPTPayload pptPayload) {
    var pptMap = {
      'args': pptPayload.arguments,
      'kwargs': pptPayload.argumentsKeywords
    };
    return msgpack_dart.serialize(pptMap);
  }
}

/// this is a little helper class for payload
/// serialization and type "safety"
class SerializedPayload<int, Uint8List> {
  final int payloadType;
  final Uint8List payload;

  SerializedPayload(
    this.payloadType,
    this.payload,
  );
}

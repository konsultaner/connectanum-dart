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

import '../../message/message_types.dart';
import '../abstract_serializer.dart';

/// This is a seralizer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Serializer');

  /// Converts a uint8 msgpack message into a WAMP message object
  @override
  AbstractMessage deserialize(Uint8List msgPack) {
    Object message = msgpack_dart.deserialize(msgPack);
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
            Error(message[1], message[2], Map<String, Object>.from(message[3]),
                message[4]),
            message,
            5);
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
    _logger.shout('Could not deserialize the message: ' + msgPack.toString());
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(AbstractMessageWithPayload message,
      List<Object> messageData, argumentsOffset) {
    if (messageData.length >= argumentsOffset + 1) {
      message.arguments = messageData[argumentsOffset];
    }
    if (messageData.length >= argumentsOffset + 2) {
      message.argumentsKeywords =
          Map.castFrom<dynamic, dynamic, String, Object>(
              messageData[argumentsOffset + 1]);
    }
    return message;
  }

  /// Converts a WAMP message object into a uint8 msgpack message
  @override
  Uint8List serialize(AbstractMessage message) {
    if (message is Hello) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.CODE_HELLO) +
          msgpack_dart.serialize(message.realm) +
          _serializeDetails(message.details));
    }
    if (message is Authenticate) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.CODE_AUTHENTICATE) +
          msgpack_dart.serialize(message.signature ?? '') +
          msgpack_dart.serialize(message.extra ?? '{}'));
    }
    if (message is Register) {
      return Uint8List.fromList([148] +
          msgpack_dart.serialize(MessageTypes.CODE_REGISTER) +
          msgpack_dart.serialize(message.requestId) +
          _serializeRegisterOptions(message.options) +
          msgpack_dart.serialize(message.procedure));
    }
    if (message is Unregister) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.CODE_UNREGISTER) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.registrationId));
    }
    if (message is Call) {
      var res = [148] +
          msgpack_dart.serialize(MessageTypes.CODE_CALL) +
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
          msgpack_dart.serialize(MessageTypes.CODE_YIELD) +
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
          msgpack_dart.serialize(MessageTypes.CODE_INVOCATION) +
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
          msgpack_dart.serialize(MessageTypes.CODE_PUBLISH) +
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
          msgpack_dart.serialize(MessageTypes.CODE_EVENT) +
          msgpack_dart.serialize(message.subscriptionId) +
          msgpack_dart.serialize(message.publicationId);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Subscribe) {
      return Uint8List.fromList([148] +
          msgpack_dart.serialize(MessageTypes.CODE_SUBSCRIBE) +
          msgpack_dart.serialize(message.requestId) +
          _serializeSubscribeOptions(message.options) +
          msgpack_dart.serialize(message.topic));
    }
    if (message is Unsubscribe) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.CODE_UNSUBSCRIBE) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.subscriptionId));
    }
    if (message is Error) {
      var res = [149] +
          msgpack_dart.serialize(MessageTypes.CODE_ERROR) +
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
          msgpack_dart.serialize(MessageTypes.CODE_ABORT) +
          msgpack_dart.serialize(message.message != null
              ? {'message': '${message.message.message ?? ""}'}
              : {}) +
          msgpack_dart.serialize(message.reason));
    }
    if (message is Goodbye) {
      return Uint8List.fromList([147] +
          msgpack_dart.serialize(MessageTypes.CODE_GOODBYE) +
          msgpack_dart.serialize(message.message != null
              ? {'message': '${message.message.message ?? ""}'}
              : {}) +
          msgpack_dart.serialize(message.reason));
    }

    _logger.shout(
        'Could not serialize the message of type: ' + message.toString());
    throw Exception('Message type not known!');
  }

  Uint8List _serializeDetails(Details details) {
    if (details.roles != null) {
      var roles = {};
      if (details.roles.caller != null &&
          details.roles.caller.features != null) {
        var callerFeatures = {};
        callerFeatures.addEntries([
          MapEntry(
              'call_canceling', details.roles.caller.features.call_canceling),
          MapEntry('call_timeout', details.roles.caller.features.call_timeout),
          MapEntry('caller_identification',
              details.roles.caller.features.caller_identification),
          MapEntry('payload_transparency',
              details.roles.caller.features.payload_transparency),
          MapEntry('progressive_call_results',
              details.roles.caller.features.progressive_call_results)
        ]);
        roles.addEntries([
          MapEntry('caller', {'features': callerFeatures})
        ]);
      }
      if (details.roles.callee != null &&
          details.roles.callee.features != null) {
        var calleeFeatures = {};
        calleeFeatures.addEntries([
          MapEntry('caller_identification',
              details.roles.callee.features.caller_identification),
          MapEntry('call_trustlevel',
              details.roles.callee.features.call_trustlevels),
          MapEntry('pattern_based_registration',
              details.roles.callee.features.pattern_based_registration),
          MapEntry('shared_registration',
              details.roles.callee.features.shared_registration),
          MapEntry(
              'call_canceling', details.roles.callee.features.call_canceling),
          MapEntry('call_timeout', details.roles.callee.features.call_timeout),
          MapEntry('caller_identification',
              details.roles.callee.features.caller_identification),
          MapEntry('payload_transparency',
              details.roles.callee.features.payload_transparency),
          MapEntry('progressive_call_results',
              details.roles.callee.features.progressive_call_results)
        ]);
        roles.addEntries([
          MapEntry('callee', {'features': calleeFeatures})
        ]);
      }
      if (details.roles.subscriber != null &&
          details.roles.subscriber.features != null) {
        var subscriberFeatures = {};
        subscriberFeatures.addEntries([
          MapEntry('call_canceling',
              details.roles.subscriber.features.call_canceling),
          MapEntry(
              'call_timeout', details.roles.subscriber.features.call_timeout),
          MapEntry('payload_transparency',
              details.roles.subscriber.features.payload_transparency),
          MapEntry('progressive_call_results',
              details.roles.subscriber.features.progressive_call_results),
          MapEntry('subscription_revocation',
              details.roles.subscriber.features.subscription_revocation)
        ]);
        roles.addEntries([
          MapEntry('subscriber', {'features': subscriberFeatures})
        ]);
      }
      if (details.roles.publisher != null &&
          details.roles.publisher.features != null) {
        var publisherFeatures = {};
        publisherFeatures.addEntries([
          MapEntry('publisher_identification',
              details.roles.publisher.features.publisher_identification),
          MapEntry('subscriber_blackwhite_listing',
              details.roles.publisher.features.subscriber_blackwhite_listing),
          MapEntry('publisher_exclusion',
              details.roles.publisher.features.publisher_exclusion),
          MapEntry('payload_transparency',
              details.roles.publisher.features.payload_transparency)
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
      if (details.authmethods != null && details.authmethods.isNotEmpty) {
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

  Uint8List _serializeSubscribeOptions(SubscribeOptions options) {
    var subscriptionOptions = {};
    if (options != null) {
      if (options.get_retained != null) {
        subscriptionOptions['get_retained'] = options.get_retained;
      }
      if (options.match != null) {
        subscriptionOptions['match'] = options.match;
      }
      if (options.meta_topic != null) {
        subscriptionOptions['meta_topic'] = options.meta_topic;
      }
      options
          .getCustomValues<dynamic>(SubscribeOptions.CUSTOM_SERIALIZER_JSON)
          .forEach((key, value) {
        subscriptionOptions[key] = value;
      });
    }

    return msgpack_dart.serialize(subscriptionOptions);
  }

  Uint8List _serializeRegisterOptions(RegisterOptions options) {
    var registerOptions = {};
    if (options != null) {
      if (options.match != null) {
        registerOptions.addEntries([MapEntry('match', options.match)]);
      }
      if (options.disclose_caller != null) {
        registerOptions
            .addEntries([MapEntry('disclose_caller', options.disclose_caller)]);
      }
      if (options.invoke != null) {
        registerOptions.addEntries([MapEntry('invoke', options.invoke)]);
      }
    }

    return msgpack_dart.serialize(registerOptions);
  }

  Uint8List _serializeCallOptions(CallOptions options) {
    var callOptions = {};
    if (options != null) {
      if (options.receive_progress != null) {
        callOptions.addEntries(
            [MapEntry('receive_progress', options.receive_progress)]);
      }
      if (options.disclose_me != null) {
        callOptions.addEntries([MapEntry('disclose_me', options.disclose_me)]);
      }
      if (options.timeout != null) {
        callOptions.addEntries([MapEntry('timeout', options.timeout)]);
      }
    }

    return msgpack_dart.serialize(callOptions);
  }

  Uint8List _serializeYieldOptions(YieldOptions options) {
    var yieldOptions = {};
    if (options != null) {
      if (options.progress != null) {
        yieldOptions.addEntries([MapEntry('progress', options.progress)]);
      }
    }
    return msgpack_dart.serialize(yieldOptions);
  }

  Uint8List _serializePublish(PublishOptions options) {
    var publishDetails = {};
    if (options != null) {
      publishDetails.addEntries([
        if (options.retain != null) MapEntry('retain', options.retain),
        if (options.disclose_me != null)
          MapEntry('disclose_me', options.disclose_me),
        if (options.acknowledge != null)
          MapEntry('acknowledge', options.acknowledge),
        if (options.exclude_me != null)
          MapEntry('exclude_me', options.exclude_me),
        if (options.exclude != null) MapEntry('exclude', options.exclude),
        if (options.exclude_authid != null)
          MapEntry('exclude_authid', options.exclude_authid),
        if (options.exclude_authrole != null)
          MapEntry('exclude_auth_role', options.exclude_authrole),
        if (options.eligible != null) MapEntry('eligible', options.eligible),
        if (options.eligible_authrole != null)
          MapEntry('eligible_authrole', options.eligible_authrole),
        if (options.eligible_authid != null)
          MapEntry('eligible_authid', options.eligible_authid)
      ]);
    }
    return msgpack_dart.serialize(publishDetails);
  }

  /// returns bytes to add to header and serialized payload bytes
  SerializedPayload<int, Uint8List> _serializePayload(
      AbstractMessageWithPayload message) {
    if (message != null) {
      if (message.argumentsKeywords != null) {
        return SerializedPayload(
            2,
            Uint8List.fromList(msgpack_dart.serialize(message.arguments ?? []) +
                msgpack_dart.serialize(message.argumentsKeywords)));
      } else if (message.arguments != null) {
        return SerializedPayload(1, msgpack_dart.serialize(message.arguments));
      }
    }
    return SerializedPayload(0, msgpack_dart.serialize(''));
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

import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/src/message/abstract_message_with_payload.dart';
import 'package:connectanum/src/message/authenticate.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/message/yield.dart';
import 'package:logging/logging.dart';

/// This is a seralizer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Serializer');

  @override
  AbstractMessage? deserialize(Uint8List? message) {
    if (message is List) {
      final decodedMessage = cbor.decode(message!.toList());
      if (decodedMessage is CborList) {
        final cborMessageId = decodedMessage[0];
        if (cborMessageId is CborInt) {
          final messageId = cborMessageId.toInt();
          if (messageId == MessageTypes.CODE_ABORT && decodedMessage.length == 3) {
            return Abort((decodedMessage[2] as CborString).toString(),
                message: decodedMessage[1] is CborMap && (decodedMessage[1] as CborMap)[CborString('message')] != null ? ((decodedMessage[1] as CborMap)[CborString('message')] as CborString).toString() : null);
          }
          if (messageId == MessageTypes.CODE_CHALLENGE && decodedMessage.length == 3) {
            return Challenge(
                (decodedMessage[1] as CborString).toString(),
                Extra(
                    challenge: (decodedMessage[2] as CborMap)[CborString('challenge')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('challenge')] as CborString).toString(),
                    salt: (decodedMessage[2] as CborMap)[CborString('salt')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('salt')] as CborString).toString(),
                    keylen: (decodedMessage[2] as CborMap)[CborString('keylen')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('keylen')] as CborInt).toInt(),
                    iterations: (decodedMessage[2] as CborMap)[CborString('iterations')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('iterations')] as CborInt).toInt(),
                    memory: (decodedMessage[2] as CborMap)[CborString('memory')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('memory')] as CborInt).toInt(),
                    kdf: (decodedMessage[2] as CborMap)[CborString('kdf')] == null ? null :((decodedMessage[2] as CborMap)[CborString('kdf')] as CborString).toString(),
                    nonce: (decodedMessage[2] as CborMap)[CborString('nonce')] == null ? null :((decodedMessage[2] as CborMap)[CborString('nonce')] as CborString).toString()));
          }
          if (messageId == MessageTypes.CODE_WELCOME && decodedMessage.length == 3) {
            final details = Details();
            details.realm = (((decodedMessage[2] as CborMap)[CborString('realm')] ?? CborString('')) as CborString).toString();
            details.authid = (((decodedMessage[2] as CborMap)[CborString('authid')] ?? CborString('')) as CborString).toString();
            details.authprovider = (((decodedMessage[2] as CborMap)[CborString('authprovider')] ?? CborString('')) as CborString).toString();
            details.authmethod = (((decodedMessage[2] as CborMap)[CborString('authmethod')] ?? CborString('')) as CborString).toString();
            details.authrole = (((decodedMessage[2] as CborMap)[CborString('authrole')] ?? CborString('')) as CborString).toString();
            if ((decodedMessage[2] as CborMap)[CborString('authextra')] != null) {
              ((decodedMessage[2] as CborMap)[CborString('authextra')] as CborMap).forEach((key, value) {
                details.authextra ??= <String, dynamic>{};
                if (value is CborString) {
                  details.authextra![(key as CborString).toString()] = value.toString();
                }
                if (value is CborInt) {
                  details.authextra![(key as CborString).toString()] = value.toInt();
                }
                if (value is CborFloat) {
                  details.authextra![(key as CborString).toString()] = value.value;
                }
                if (value is CborBool) {
                  details.authextra![(key as CborString).toString()] = value.value;
                }
                if (value is CborBase64) {
                  details.authextra![(key as CborString).toString()] = value.toString();
                }
              });
            }
            if ((decodedMessage[2] as CborMap)[CborString('roles')] != null) {
              details.roles = Roles();
              if (((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] != null) {
                details.roles!.dealer = Dealer();
                if ((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] != null) {
                  details.roles!.dealer!.features = DealerFeatures();
                  details.roles!.dealer!.features!.caller_identification =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('caller_identification')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.call_trustlevels =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('call_trustlevels')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.pattern_based_registration =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('pattern_based_registration')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.registration_meta_api =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('registration_meta_api')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.shared_registration =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('shared_registration')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.session_meta_api =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('session_meta_api')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.call_timeout =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('call_timeout')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.call_canceling =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('call_canceling')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.progressive_call_results =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('progressive_call_results')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.dealer!.features!.payload_transparency =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('dealer')] as CborMap)[CborString('features')] as CborMap)[CborString('payload_transparency')] ?? CborBool(false)) as CborBool).value;
                }
              }
              if (((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] != null) {
                details.roles!.broker = Broker();
                if ((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] != null) {
                  details.roles!.broker!.features = BrokerFeatures();
                  details.roles!.broker!.features!.publisher_identification =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('publisher_identification')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.publication_trustlevels =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('publication_trustlevels')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.pattern_based_subscription =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('pattern_based_subscription')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.subscription_meta_api =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('subscription_meta_api')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.subscriber_blackwhite_listing =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('subscriber_blackwhite_listing')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.session_meta_api =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('session_meta_api')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.publisher_exclusion =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('publisher_exclusion')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.event_history =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('event_history')] ?? CborBool(false)) as CborBool).value;
                  details.roles!.broker!.features!.payload_transparency =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')] as CborMap)[CborString('broker')] as CborMap)[CborString('features')] as CborMap)[CborString('payload_transparency')] ?? CborBool(false)) as CborBool).value;
                }
              }
            }
            return Welcome((decodedMessage[1] as CborInt).toInt(), details);
          }
          if (messageId == MessageTypes.CODE_REGISTERED && decodedMessage.length == 3) {
            return Registered((decodedMessage[1] as CborInt).toInt(), (decodedMessage[2] as CborInt).toInt());
          }
          if (messageId == MessageTypes.CODE_UNREGISTERED && decodedMessage.length == 2) {
            return Unregistered((decodedMessage[1] as CborInt).toInt());
          }
          if (messageId == MessageTypes.CODE_INVOCATION && decodedMessage.length > 3) {
            return _addPayload(
                Invocation(
                    (decodedMessage[1] as CborInt).toInt(),
                    (decodedMessage[2] as CborInt).toInt(),
                    InvocationDetails(
                        (decodedMessage[3] as CborMap)[CborString('caller')] == null ? null : ((decodedMessage[3] as CborMap)[CborString('caller')] as CborInt).toInt(),
                        (decodedMessage[3] as CborMap)[CborString('procedure')] == null ? null : ((decodedMessage[3] as CborMap)[CborString('procedure')] as CborString).toString(),
                        (decodedMessage[3] as CborMap)[CborString('receive_progress')] == null ? null : ((decodedMessage[3] as CborMap)[CborString('receive_progress')] as CborBool).value,
                    )
                ),
                decodedMessage,
                4
            );
          }
          if (messageId == MessageTypes.CODE_RESULT && decodedMessage.length > 2) {
            return _addPayload(
                Result(
                    (decodedMessage[1] as CborInt).toInt(),
                    ResultDetails(
                        (decodedMessage[2] as CborMap)[CborString('progress')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('progress')] as CborBool).value
                    )
                ),
                decodedMessage,
                3);
          }
          if (messageId == MessageTypes.CODE_PUBLISHED && decodedMessage.length == 3) {
            return Published((decodedMessage[1] as CborInt).toInt(), (decodedMessage[2] as CborInt).toInt());
          }
          if (messageId == MessageTypes.CODE_SUBSCRIBED && decodedMessage.length == 3) {
            return Subscribed((decodedMessage[1] as CborInt).toInt(), (decodedMessage[2] as CborInt).toInt());
          }
          if (messageId == MessageTypes.CODE_UNSUBSCRIBED && decodedMessage.length > 1) {
            return Unsubscribed(
                (decodedMessage[1] as CborInt).toInt(),
                decodedMessage.length == 2 ? null : UnsubscribedDetails(
                    (decodedMessage[2] as CborMap)[CborString('subscription')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('subscription')] as CborInt).toInt(),
                    (decodedMessage[2] as CborMap)[CborString('reason')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('reason')] as CborString).toString()
                )
            );
          }
          if (messageId == MessageTypes.CODE_EVENT && decodedMessage.length > 3) {
            return _addPayload(
                Event(
                    (decodedMessage[1] as CborInt).toInt(),
                    (decodedMessage[2] as CborInt).toInt(),
                    EventDetails(
                        publisher: (decodedMessage[3] as CborMap)[CborString('publisher')] == null ? null : ((decodedMessage[3] as CborMap)[CborString('publisher')] as CborInt).toInt(),
                        trustlevel: (decodedMessage[3] as CborMap)[CborString('trustlevel')] == null ? null : ((decodedMessage[3] as CborMap)[CborString('trustlevel')] as CborInt).toInt(),
                        topic: (decodedMessage[3] as CborMap)[CborString('topic')] == null ? null : ((decodedMessage[3] as CborMap)[CborString('topic')] as CborString).toString())),
                decodedMessage,
                4);
          }
          if (messageId == MessageTypes.CODE_ERROR && decodedMessage.length > 4) {
            return _addPayload(
                Error(
                    (decodedMessage[1] as CborInt).toInt(),
                    (decodedMessage[2] as CborInt).toInt(),
                    Map<String, Object>.from((decodedMessage[3] as CborMap).toObject() as Map),
                    (decodedMessage[4] as CborString).toString()
                ),
                decodedMessage,
                5);
          }
          if (messageId == MessageTypes.CODE_GOODBYE) {
            return Goodbye(
                decodedMessage.length == 1 ? null : GoodbyeMessage((decodedMessage[1] as CborMap)[CborString('message')] == null ? null : ((decodedMessage[1] as CborMap)[CborString('message')] as CborString).toString()),
                (decodedMessage[2] as CborString).toString());
          }
        }
      }
      return null;
    }
    _logger.shout('Could not deserialize the message: ' + message.toString());
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(AbstractMessageWithPayload message,
      List<dynamic> messageData, argumentsOffset) {
    if (messageData.length >= argumentsOffset + 1) {
      if (messageData[argumentsOffset] is CborList) {
        message.arguments = (messageData[argumentsOffset] as CborList).toObject() as List<dynamic>;
      }
    }
    if (messageData.length >= argumentsOffset + 2) {
      if (messageData[argumentsOffset + 1] is CborMap) {
        message.argumentsKeywords = Map.castFrom<dynamic, dynamic, String, dynamic>(
            (messageData[argumentsOffset + 1] as CborMap).toObject() as Map<dynamic, dynamic>);
      }
    }
    return message;
  }

  @override
  Uint8List serialize(AbstractMessage message) {
    if (message is Hello) {
      return Uint8List.fromList(cbor.encode(CborValue([
        MessageTypes.CODE_HELLO,
        message.realm,
        _serializeDetails(message.details)!
      ])));
    }
    if (message is Authenticate) {
      return Uint8List.fromList(cbor.encode(CborValue([
        MessageTypes.CODE_AUTHENTICATE,
        message.signature ?? '',
        message.extra ?? {}
      ])));
    }
    if (message is Register) {
      return Uint8List.fromList(cbor.encode(CborValue([
        MessageTypes.CODE_REGISTER,
        message.requestId,
        _serializeRegisterOptions(message.options),
        message.procedure
      ])));
    }
    if (message is Unregister) {
      return Uint8List.fromList(cbor.encode(CborValue([
        MessageTypes.CODE_UNREGISTER,
        message.requestId,
        message.registrationId
      ])));
    }
    if (message is Call) {
      var structuredMessage = [
        MessageTypes.CODE_CALL,
        message.requestId,
        _serializeCallOptions(message.options),
        message.procedure,
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Yield) {
      var structuredMessage = [
        MessageTypes.CODE_YIELD,
        message.invocationRequestId,
        _serializeYieldOptions(message.options)
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Invocation) {
      // for serializer unit test only
      var structuredMessage = [
        MessageTypes.CODE_INVOCATION,
        message.requestId,
        message.registrationId,
        {}
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Publish) {
      var structuredMessage = [
        MessageTypes.CODE_PUBLISH,
        message.requestId,
        _serializePublish(message.options),
        message.topic
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Event) {
      var structuredMessage = [
        MessageTypes.CODE_EVENT,
        message.subscriptionId,
        message.publicationId
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Subscribe) {
      var structuredMessage = [
        MessageTypes.CODE_SUBSCRIBE,
        message.requestId,
        _serializeSubscribeOptions(message.options),
        message.topic
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Unsubscribe) {
      var structuredMessage = [
        MessageTypes.CODE_UNSUBSCRIBE,
        message.requestId,
        message.subscriptionId
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Error) {
      var structuredMessage = [
        MessageTypes.CODE_ERROR,
        message.requestTypeId,
        message.requestId,
        message.details,
        message.error
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Abort) {
      var structuredMessage = [
        MessageTypes.CODE_ABORT,
        message.message != null ? {'message':message.message!.message} : {},
        message.reason
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Goodbye) {
      var structuredMessage = [
        MessageTypes.CODE_GOODBYE,
        message.message != null ? {'message':message.message!.message ?? ''} : {},
        message.reason
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }

    _logger.shout(
        'Could not serialize the message of type: ' + message.toString());
    throw Exception(''); // TODO think of something helpful here...
  }

  dynamic _firstPayload(AbstractMessageWithPayload message) {
    return message.transparentBinaryPayload ?? message.arguments ?? (message.argumentsKeywords != null ? [] : null);
  }

  dynamic _secondPayload(AbstractMessageWithPayload message) {
    if (message.transparentBinaryPayload == null && message.argumentsKeywords != null) {
      return message.argumentsKeywords;
    }
    return null;
  }

  void _appendPayloadToList(List structuredMessage, AbstractMessageWithPayload message){
    var firstPayload = _firstPayload(message);
    if (firstPayload != null) {
      structuredMessage.add(firstPayload);
      var secondPayload = _secondPayload(message);
      if (secondPayload != null) {
        structuredMessage.add(secondPayload);
      }
    }
  }

  Map? _serializeDetails(Details details) {
    if (details.roles != null) {
      var roles = {};
      if (details.roles!.caller != null &&
          details.roles!.caller!.features != null) {
        var callerFeatures = {};
        callerFeatures.addEntries([
          MapEntry('call_canceling', details.roles!.caller!.features!.call_canceling),
          MapEntry('call_timeout', details.roles!.caller!.features!.call_timeout),
          MapEntry('caller_identification', details.roles!.caller!.features!.caller_identification),
          MapEntry('payload_transparency', details.roles!.caller!.features!.payload_transparency),
          MapEntry('progressive_call_results', details.roles!.caller!.features!.progressive_call_results)
        ]);
        roles.addEntries([
          MapEntry('caller', {'features': callerFeatures})
        ]);
      }
      if (details.roles!.callee != null &&
          details.roles!.callee!.features != null) {
        var calleeFeatures = {};
        calleeFeatures.addEntries([
          MapEntry('caller_identification', details.roles!.callee!.features!.caller_identification),
          MapEntry('call_trustlevels', details.roles!.callee!.features!.call_trustlevels),
          MapEntry('pattern_based_registration', details.roles!.callee!.features!.pattern_based_registration),
          MapEntry('shared_registration', details.roles!.callee!.features!.shared_registration),
          MapEntry('call_timeout', details.roles!.callee!.features!.call_timeout),
          MapEntry('call_canceling', details.roles!.callee!.features!.call_canceling),
          MapEntry('progressive_call_results', details.roles!.callee!.features!.progressive_call_results),
          MapEntry('payload_transparency', details.roles!.callee!.features!.payload_transparency),
        ]);
        roles.addEntries([
          MapEntry('callee', {'features': calleeFeatures})
        ]);
      }
      if (details.roles!.subscriber != null &&
          details.roles!.subscriber!.features != null) {
        var subscriberFeatures = {};
        subscriberFeatures.addEntries([
          MapEntry('call_timeout', details.roles!.subscriber!.features!.call_timeout),
          MapEntry('call_canceling', details.roles!.subscriber!.features!.call_canceling),
          MapEntry('progressive_call_results', details.roles!.subscriber!.features!.progressive_call_results),
          MapEntry('payload_transparency', details.roles!.subscriber!.features!.payload_transparency),
          MapEntry('subscription_revocation', details.roles!.subscriber!.features!.subscription_revocation)
        ]);
        roles.addEntries([
          MapEntry('subscriber', {'features': subscriberFeatures})
        ]);
      }
      if (details.roles!.publisher != null &&
          details.roles!.publisher!.features != null) {
        var publisherFeatures = {};
        publisherFeatures.addEntries([
          MapEntry('publisher_identification', details.roles!.publisher!.features!.publisher_identification),
          MapEntry('subscriber_blackwhite_listing', details.roles!.publisher!.features!.subscriber_blackwhite_listing),
          MapEntry('publisher_exclusion', details.roles!.publisher!.features!.publisher_exclusion),
          MapEntry('payload_transparency', details.roles!.publisher!.features!.payload_transparency)
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
      return detailsParts;
    } else {
      return null;
    }
  }

  Map _serializeRegisterOptions(RegisterOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.match != null) {
        optionMap.addEntries([MapEntry('match', options.match)]);
      }
      if (options.disclose_caller != null) {
        optionMap
            .addEntries([MapEntry('disclose_caller', options.disclose_caller)]);
      }
      if (options.invoke != null) {
        optionMap.addEntries([MapEntry('invoke', options.invoke)]);
      }
    }

    return optionMap;
  }

  Map _serializeCallOptions(CallOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.receive_progress != null) {
        optionMap.addEntries([MapEntry('receive_progress', options.receive_progress!)]);
      }
      if (options.disclose_me != null) {
        optionMap.addEntries([MapEntry('disclose_me', options.disclose_me!)]);
      }
      if (options.timeout != null) {
        optionMap.addEntries([MapEntry('timeout', options.timeout!)]);
      }
    }
    return optionMap;
  }

  Map _serializeYieldOptions(YieldOptions? options) {
    var optionsMap = {};
    if (options != null) {
      optionsMap.addEntries([MapEntry('progress', options.progress)]);
    }
    return optionsMap;
  }

  Map _serializePublish(PublishOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.retain != null) {
        optionMap.addEntries([MapEntry('retain', options.retain)]);
      }
      if (options.disclose_me != null) {
        optionMap.addEntries([MapEntry('retain', options.disclose_me)]);
      }
      if (options.acknowledge != null) {
        optionMap.addEntries([MapEntry('acknowledge', options.acknowledge)]);
      }
      if (options.exclude_me != null) {
        optionMap.addEntries([MapEntry('exclude_me', options.exclude_me)]);
      }
      if (options.exclude != null) {
        optionMap.addEntries([MapEntry('exclude', options.exclude)]);
      }
      if (options.exclude_authid != null) {
        optionMap.addEntries([MapEntry('exclude_authid', options.exclude_authid)]);
      }
      if (options.exclude_authrole != null) {
        optionMap.addEntries([MapEntry('exclude_authrole', options.exclude_authrole)]);
      }
      if (options.eligible != null) {
        optionMap.addEntries([MapEntry('eligible', options.eligible)]);
      }
      if (options.eligible_authid != null) {
        optionMap.addEntries([MapEntry('eligible_authid', options.eligible_authid)]);
      }
      if (options.eligible_authrole != null) {
        optionMap.addEntries([MapEntry('eligible_authrole', options.eligible_authrole)]);
      }
    }
    return optionMap;
  }

  Map _serializeSubscribeOptions(SubscribeOptions? options) {
    var jsonOptions = {};
    if (options != null) {
      if (options.get_retained != null) {
        jsonOptions.addEntries([MapEntry('get_retained', options.get_retained)]);
      }
      if (options.match != null) {
        jsonOptions.addEntries([MapEntry('match', options.match)]);
      }
      if (options.meta_topic != null) {
        jsonOptions.addEntries([MapEntry('meta_topic', options.meta_topic)]);
      }
      options
          .getCustomValues<dynamic>(SubscribeOptions.CUSTOM_SERIALIZER_CBOR)
          .forEach((key, value) {
        jsonOptions.addEntries([MapEntry(key,value)]);
      });
    }

    return jsonOptions;
  }
}
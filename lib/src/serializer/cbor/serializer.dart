import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/src/message/abstract_message_with_payload.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
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
    return Uint8List(0);
  }

}
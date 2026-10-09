import 'package:connectanum_core/connectanum_core.dart';

/// Plain WAMP dictionaries shared by the FlatBuffers field projection.
/// Only metadata is encoded as CBOR; no complete message is round-tripped.
class WampDictionaryCodec {
  static Map<String, dynamic> serializeDetails(Details details) {
    final detailsParts = <String, dynamic>{};
    if (details.roles != null) {
      var roles = {};
      if (details.roles!.caller != null) {
        final callerFeatures = details.roles!.caller!.features;
        if (callerFeatures != null) {
          var callerFeaturesMap = {};
          callerFeaturesMap.addEntries([
            MapEntry('call_canceling', callerFeatures.callCanceling),
            MapEntry('call_timeout', callerFeatures.callTimeout),
            MapEntry(
              'caller_identification',
              callerFeatures.callerIdentification,
            ),
            MapEntry(
              'payload_passthru_mode',
              callerFeatures.payloadPassThruMode,
            ),
            MapEntry(
              'progressive_call_invocations',
              callerFeatures.progressiveCallInvocations,
            ),
            MapEntry(
              'progressive_call_results',
              callerFeatures.progressiveCallResults,
            ),
          ]);
          roles.addEntries([
            MapEntry('caller', {'features': callerFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('caller', {})]);
        }
      }
      if (details.roles!.callee != null) {
        final calleeFeatures = details.roles!.callee!.features;
        if (calleeFeatures != null) {
          var calleeFeaturesMap = {};
          calleeFeaturesMap.addEntries([
            MapEntry(
              'caller_identification',
              calleeFeatures.callerIdentification,
            ),
            MapEntry('call_trustlevels', calleeFeatures.callTrustlevels),
            MapEntry(
              'pattern_based_registration',
              calleeFeatures.patternBasedRegistration,
            ),
            MapEntry('shared_registration', calleeFeatures.sharedRegistration),
            MapEntry('call_timeout', calleeFeatures.callTimeout),
            MapEntry('call_canceling', calleeFeatures.callCanceling),
            MapEntry(
              'progressive_call_invocations',
              calleeFeatures.progressiveCallInvocations,
            ),
            MapEntry(
              'progressive_call_results',
              calleeFeatures.progressiveCallResults,
            ),
            MapEntry(
              'payload_passthru_mode',
              calleeFeatures.payloadPassThruMode,
            ),
          ]);
          roles.addEntries([
            MapEntry('callee', {'features': calleeFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('callee', {})]);
        }
      }
      if (details.roles!.subscriber != null) {
        final subscriberFeatures = details.roles!.subscriber!.features;
        if (subscriberFeatures != null) {
          var subscriberFeaturesMap = {};
          subscriberFeaturesMap.addEntries([
            MapEntry(
              'publisher_identification',
              subscriberFeatures.publisherIdentification,
            ),
            MapEntry(
              'publication_trustlevels',
              subscriberFeatures.publicationTrustLevels,
            ),
            MapEntry(
              'pattern_based_subscription',
              subscriberFeatures.patternBasedSubscription,
            ),
            MapEntry(
              'payload_passthru_mode',
              subscriberFeatures.payloadPassThruMode,
            ),
            MapEntry(
              'subscription_revocation',
              subscriberFeatures.subscriptionRevocation,
            ),
            MapEntry('call_timeout', subscriberFeatures.callTimeout),
            MapEntry('call_canceling', subscriberFeatures.callCanceling),
            MapEntry(
              'progressive_call_results',
              subscriberFeatures.progressiveCallResults,
            ),
          ]);
          roles.addEntries([
            MapEntry('subscriber', {'features': subscriberFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('subscriber', {})]);
        }
      }
      if (details.roles!.publisher != null) {
        final publisherFeatures = details.roles!.publisher!.features;
        if (publisherFeatures != null) {
          var publisherFeaturesMap = {};
          publisherFeaturesMap.addEntries([
            MapEntry(
              'publisher_identification',
              publisherFeatures.publisherIdentification,
            ),
            MapEntry(
              'subscriber_blackwhite_listing',
              publisherFeatures.subscriberBlackWhiteListing,
            ),
            MapEntry(
              'publisher_exclusion',
              publisherFeatures.publisherExclusion,
            ),
            MapEntry(
              'payload_passthru_mode',
              publisherFeatures.payloadPassThruMode,
            ),
          ]);
          roles.addEntries([
            MapEntry('publisher', {'features': publisherFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('publisher', {})]);
        }
      }
      if (details.roles!.broker != null) {
        final brokerFeatures = details.roles!.broker!.features;
        final brokerMap = <String, dynamic>{};
        if (brokerFeatures != null) {
          brokerMap['features'] = {
            'publisher_identification': brokerFeatures.publisherIdentification,
            'publication_trustlevels': brokerFeatures.publicationTrustLevels,
            'pattern_based_subscription':
                brokerFeatures.patternBasedSubscription,
            'subscription_meta_api': brokerFeatures.subscriptionMetaApi,
            'subscriber_blackwhite_listing':
                brokerFeatures.subscriberBlackWhiteListing,
            'session_meta_api': brokerFeatures.sessionMetaApi,
            'publisher_exclusion': brokerFeatures.publisherExclusion,
            'event_history': brokerFeatures.eventHistory,
            'payload_passthru_mode': brokerFeatures.payloadPassThruMode,
          };
        }
        if (details.roles!.broker!.reflection != null) {
          brokerMap['reflection'] = details.roles!.broker!.reflection;
        }
        roles.addEntries([MapEntry('broker', brokerMap)]);
      }
      if (details.roles!.dealer != null) {
        final dealerFeatures = details.roles!.dealer!.features;
        final dealerMap = <String, dynamic>{};
        if (dealerFeatures != null) {
          dealerMap['features'] = {
            'caller_identification': dealerFeatures.callerIdentification,
            'call_trustlevels': dealerFeatures.callTrustLevels,
            'pattern_based_registration':
                dealerFeatures.patternBasedRegistration,
            'registration_meta_api': dealerFeatures.registrationMetaApi,
            'shared_registration': dealerFeatures.sharedRegistration,
            'session_meta_api': dealerFeatures.sessionMetaApi,
            'call_timeout': dealerFeatures.callTimeout,
            'call_canceling': dealerFeatures.callCanceling,
            'progressive_call_invocations':
                dealerFeatures.progressiveCallInvocations,
            'progressive_call_results': dealerFeatures.progressiveCallResults,
            'payload_passthru_mode': dealerFeatures.payloadPassThruMode,
          };
        }
        if (details.roles!.dealer!.reflection != null) {
          dealerMap['reflection'] = details.roles!.dealer!.reflection;
        }
        roles.addEntries([MapEntry('dealer', dealerMap)]);
      }
      detailsParts['roles'] = roles;
    }
    if (details.realm != null) {
      detailsParts['realm'] = details.realm;
    }
    if (details.authid != null) {
      detailsParts['authid'] = details.authid;
    }
    if (details.authmethod != null) {
      detailsParts['authmethod'] = details.authmethod;
    }
    if (details.authprovider != null) {
      detailsParts['authprovider'] = details.authprovider;
    }
    if (details.authrole != null) {
      detailsParts['authrole'] = details.authrole;
    }
    if (details.authmethods != null) {
      detailsParts['authmethods'] = details.authmethods;
    }
    if (details.authextra != null) {
      detailsParts['authextra'] = details.authextra;
    }
    if (details.custom.isNotEmpty) {
      details.custom.forEach((key, value) {
        detailsParts.putIfAbsent(key, () => value);
      });
    }
    if (details.agent != null) detailsParts['agent'] = details.agent;
    if (details.nonce != null) detailsParts['nonce'] = details.nonce;
    if (details.challenge != null) {
      detailsParts['challenge'] = details.challenge;
    }
    if (details.iterations != null) {
      detailsParts['iterations'] = details.iterations;
    }
    if (details.keylen != null) detailsParts['keylen'] = details.keylen;
    if (details.progress != null) detailsParts['progress'] = details.progress;
    if (details.salt != null) detailsParts['salt'] = details.salt;
    if (details.topic != null) detailsParts['topic'] = details.topic.toString();
    if (details.procedure != null) {
      detailsParts['procedure'] = details.procedure.toString();
    }
    if (details.trustlevel != null) {
      detailsParts['trustlevel'] = details.trustlevel;
    }
    return detailsParts;
  }

  static Map serializeRegisterOptions(RegisterOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.match != null) {
        optionMap.addEntries([MapEntry('match', options.match)]);
      }
      if (options.discloseCaller != null) {
        optionMap.addEntries([
          MapEntry('disclose_caller', options.discloseCaller),
        ]);
      }
      if (options.invoke != null) {
        optionMap.addEntries([MapEntry('invoke', options.invoke)]);
      }
      if (options.forwardTimeout != null) {
        optionMap.addEntries([
          MapEntry('forward_timeout', options.forwardTimeout),
        ]);
      }
      if (options.custom.isNotEmpty) {
        optionMap.addAll(options.custom);
      }
    }

    return optionMap;
  }

  static Map serializeCallOptions(CallOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.progress != null) {
        optionMap.addEntries([MapEntry('progress', options.progress!)]);
      }
      if (options.receiveProgress != null) {
        optionMap.addEntries([
          MapEntry('receive_progress', options.receiveProgress!),
        ]);
      }
      if (options.discloseMe != null) {
        optionMap.addEntries([MapEntry('disclose_me', options.discloseMe!)]);
      }
      if (options.timeout != null) {
        optionMap.addEntries([MapEntry('timeout', options.timeout!)]);
      }
      if (options.pptScheme != null) {
        optionMap.addEntries([MapEntry('ppt_scheme', options.pptScheme!)]);
      }
      if (options.pptSerializer != null) {
        optionMap.addEntries([
          MapEntry('ppt_serializer', options.pptSerializer!),
        ]);
      }
      if (options.pptCipher != null) {
        optionMap.addEntries([MapEntry('ppt_cipher', options.pptCipher!)]);
      }
      if (options.pptKeyId != null) {
        optionMap.addEntries([MapEntry('ppt_keyid', options.pptKeyId!)]);
      }
      if (options.custom.isNotEmpty) {
        optionMap.addAll(options.custom);
      }
    }
    return optionMap;
  }

  static Map serializeYieldOptions(YieldOptions? options) {
    var optionsMap = {};
    if (options != null) {
      optionsMap.addEntries([MapEntry('progress', options.progress)]);
      if (options.pptScheme != null) {
        optionsMap.addEntries([MapEntry('ppt_scheme', options.pptScheme!)]);
      }
      if (options.pptSerializer != null) {
        optionsMap.addEntries([
          MapEntry('ppt_serializer', options.pptSerializer!),
        ]);
      }
      if (options.pptCipher != null) {
        optionsMap.addEntries([MapEntry('ppt_cipher', options.pptCipher!)]);
      }
      if (options.pptKeyId != null) {
        optionsMap.addEntries([MapEntry('ppt_keyid', options.pptKeyId!)]);
      }
      if (options.custom.isNotEmpty) {
        optionsMap.addAll(options.custom);
      }
    }
    return optionsMap;
  }

  static Map serializePublish(PublishOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.retain != null) {
        optionMap.addEntries([MapEntry('retain', options.retain)]);
      }
      if (options.discloseMe != null) {
        optionMap.addEntries([MapEntry('disclose_me', options.discloseMe)]);
      }
      if (options.acknowledge != null) {
        optionMap.addEntries([MapEntry('acknowledge', options.acknowledge)]);
      }
      if (options.excludeMe != null) {
        optionMap.addEntries([MapEntry('exclude_me', options.excludeMe)]);
      }
      if (options.exclude != null) {
        optionMap.addEntries([MapEntry('exclude', options.exclude)]);
      }
      if (options.excludeAuthId != null) {
        optionMap.addEntries([
          MapEntry('exclude_authid', options.excludeAuthId),
        ]);
      }
      if (options.excludeAuthRole != null) {
        optionMap.addEntries([
          MapEntry('exclude_authrole', options.excludeAuthRole),
        ]);
      }
      if (options.eligible != null) {
        optionMap.addEntries([MapEntry('eligible', options.eligible)]);
      }
      if (options.eligibleAuthId != null) {
        optionMap.addEntries([
          MapEntry('eligible_authid', options.eligibleAuthId),
        ]);
      }
      if (options.eligibleAuthRole != null) {
        optionMap.addEntries([
          MapEntry('eligible_authrole', options.eligibleAuthRole),
        ]);
      }
      if (options.pptScheme != null) {
        optionMap.addEntries([MapEntry('ppt_scheme', options.pptScheme)]);
      }
      if (options.pptSerializer != null) {
        optionMap.addEntries([
          MapEntry('ppt_serializer', options.pptSerializer),
        ]);
      }
      if (options.pptCipher != null) {
        optionMap.addEntries([MapEntry('ppt_cipher', options.pptCipher)]);
      }
      if (options.pptKeyId != null) {
        optionMap.addEntries([MapEntry('ppt_keyid', options.pptKeyId)]);
      }
      if (options.custom.isNotEmpty) {
        optionMap.addAll(options.custom);
      }
    }
    return optionMap;
  }

  static Map<String, dynamic> serializeEventDetails(EventDetails details) {
    final map = <String, dynamic>{};
    if (details.publisher != null) {
      map['publisher'] = details.publisher;
    }
    if (details.topic != null) {
      map['topic'] = details.topic;
    }
    if (details.trustlevel != null) {
      map['trustlevel'] = details.trustlevel;
    }
    if (details.pptScheme != null) {
      map['ppt_scheme'] = details.pptScheme;
    }
    if (details.pptSerializer != null) {
      map['ppt_serializer'] = details.pptSerializer;
    }
    if (details.pptCipher != null) {
      map['ppt_cipher'] = details.pptCipher;
    }
    if (details.pptKeyId != null) {
      map['ppt_keyid'] = details.pptKeyId;
    }
    if (details.custom.isNotEmpty) {
      map.addAll(details.custom);
    }
    return map;
  }

  static Map<String, dynamic> serializeInvocationDetails(
    InvocationDetails details,
  ) {
    final map = <String, dynamic>{};
    if (details.caller != null) {
      map['caller'] = details.caller;
    }
    if (details.procedure != null) {
      map['procedure'] = details.procedure;
    }
    if (details.progress != null) {
      map['progress'] = details.progress;
    }
    if (details.receiveProgress != null) {
      map['receive_progress'] = details.receiveProgress;
    }
    if (details.timeout != null) {
      map['timeout'] = details.timeout;
    }
    if (details.pptScheme != null) {
      map['ppt_scheme'] = details.pptScheme;
    }
    if (details.pptSerializer != null) {
      map['ppt_serializer'] = details.pptSerializer;
    }
    if (details.pptCipher != null) {
      map['ppt_cipher'] = details.pptCipher;
    }
    if (details.pptKeyId != null) {
      map['ppt_keyid'] = details.pptKeyId;
    }
    if (details.custom.isNotEmpty) {
      map.addAll(details.custom);
    }
    return map;
  }

  static Map serializeSubscribeOptions(SubscribeOptions? options) {
    var jsonOptions = {};
    if (options != null) {
      if (options.getRetained != null) {
        jsonOptions.addEntries([MapEntry('get_retained', options.getRetained)]);
      }
      if (options.match != null) {
        jsonOptions.addEntries([MapEntry('match', options.match)]);
      }
      if (options.metaTopic != null) {
        jsonOptions.addEntries([MapEntry('meta_topic', options.metaTopic)]);
      }
      if (options.custom.isNotEmpty) {
        jsonOptions.addAll(options.custom);
      }
      options
          .getCustomValues<dynamic>(SubscribeOptions.customSerializerCbor)
          .forEach((key, value) {
            jsonOptions.addEntries([MapEntry(key, value)]);
          });
    }

    return jsonOptions;
  }
}

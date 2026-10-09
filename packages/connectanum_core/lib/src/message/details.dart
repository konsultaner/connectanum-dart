import 'field_assignments.dart';
import 'custom_fields.dart';

class Details {
  final Map<String, dynamic> custom = LazyStringKeyMap<dynamic>();

  String? _agent;
  String? _realm;
  List<String>? _authmethods;
  String? _authid;
  String? _authrole;
  String? _authmethod;
  String? _authprovider;
  Map<String, dynamic>? _authextra;
  String? _nonce;
  String? _challenge;
  int? _iterations;
  int? _keylen;
  bool? _progress;
  String? _salt;
  Uri? _topic;
  Uri? _procedure;
  int? _trustlevel;
  Roles? _roles;

  Map<String, dynamic> Function()? _lazyFieldsLoader;

  String? get agent {
    if (_agent == null) {
      _ensureLazyFieldsLoaded();
    }
    return _agent;
  }

  set agent(String? value) => _agent = value;

  String? get realm {
    if (_realm == null) {
      _ensureLazyFieldsLoaded();
    }
    return _realm;
  }

  set realm(String? value) => _realm = value;

  List<String>? get authmethods {
    if (_authmethods == null) {
      _ensureLazyFieldsLoaded();
    }
    return _authmethods;
  }

  set authmethods(List<String>? value) => _authmethods = value;

  String? get authid {
    if (_authid == null) {
      _ensureLazyFieldsLoaded();
    }
    return _authid;
  }

  set authid(String? value) => _authid = value;

  String? get authrole {
    if (_authrole == null) {
      _ensureLazyFieldsLoaded();
    }
    return _authrole;
  }

  set authrole(String? value) => _authrole = value;

  String? get authmethod {
    if (_authmethod == null) {
      _ensureLazyFieldsLoaded();
    }
    return _authmethod;
  }

  set authmethod(String? value) => _authmethod = value;

  String? get authprovider {
    if (_authprovider == null) {
      _ensureLazyFieldsLoaded();
    }
    return _authprovider;
  }

  set authprovider(String? value) => _authprovider = value;

  Map<String, dynamic>? get authextra {
    if (_authextra == null) {
      _ensureLazyFieldsLoaded();
    }
    return _authextra;
  }

  set authextra(Map<String, dynamic>? value) => _authextra = value;

  String? get nonce {
    if (_nonce == null) {
      _ensureLazyFieldsLoaded();
    }
    return _nonce;
  }

  set nonce(String? value) => _nonce = value;

  String? get challenge {
    if (_challenge == null) {
      _ensureLazyFieldsLoaded();
    }
    return _challenge;
  }

  set challenge(String? value) => _challenge = value;

  int? get iterations {
    if (_iterations == null) {
      _ensureLazyFieldsLoaded();
    }
    return _iterations;
  }

  set iterations(int? value) => _iterations = value;

  int? get keylen {
    if (_keylen == null) {
      _ensureLazyFieldsLoaded();
    }
    return _keylen;
  }

  set keylen(int? value) => _keylen = value;

  bool? get progress {
    if (_progress == null) {
      _ensureLazyFieldsLoaded();
    }
    return _progress;
  }

  set progress(bool? value) => _progress = value;

  String? get salt {
    if (_salt == null) {
      _ensureLazyFieldsLoaded();
    }
    return _salt;
  }

  set salt(String? value) => _salt = value;

  Uri? get topic {
    if (_topic == null) {
      _ensureLazyFieldsLoaded();
    }
    return _topic;
  }

  set topic(Uri? value) => _topic = value;

  Uri? get procedure {
    if (_procedure == null) {
      _ensureLazyFieldsLoaded();
    }
    return _procedure;
  }

  set procedure(Uri? value) => _procedure = value;

  int? get trustlevel {
    if (_trustlevel == null) {
      _ensureLazyFieldsLoaded();
    }
    return _trustlevel;
  }

  set trustlevel(int? value) => _trustlevel = value;

  Roles? get roles {
    if (_roles == null) {
      _ensureLazyFieldsLoaded();
    }
    return _roles;
  }

  set roles(Roles? value) => _roles = value;

  void setLazyFieldsLoader(Map<String, dynamic> Function() loader) {
    final previousLoader = _lazyFieldsLoader;
    if (previousLoader == null) {
      _lazyFieldsLoader = loader;
    } else {
      _lazyFieldsLoader = () {
        final merged = <String, dynamic>{}
          ..addAll(previousLoader())
          ..addAll(loader());
        return merged;
      };
    }
    attachLazyStringKeyMapLoader(custom, () {
      _ensureLazyFieldsLoaded();
      return const <String, dynamic>{};
    });
  }

  void setLazyCustomFieldsLoader(Map<String, dynamic> Function() loader) {
    attachLazyStringKeyMapLoader(custom, loader);
  }

  void setLazyAuthExtraLoader(Map<String, dynamic> Function() loader) {
    _authextra ??= LazyStringKeyMap<dynamic>();
    attachLazyStringKeyMapLoader(_authextra!, loader);
  }

  void _ensureLazyFieldsLoaded() {
    final loader = _lazyFieldsLoader;
    if (loader == null) {
      return;
    }
    _lazyFieldsLoader = null;
    _mergeStructuredFields(loader());
  }

  void _mergeStructuredFields(Map<String, dynamic> map) {
    _agent ??= map['agent'] as String?;
    _realm ??= map['realm'] as String?;

    if (_authmethods == null && map['authmethods'] is List) {
      _authmethods = List<String>.from(map['authmethods'] as List);
    }

    _authid ??= map['authid'] as String?;
    _authrole ??= map['authrole'] as String?;
    _authmethod ??= map['authmethod'] as String?;
    _authprovider ??= map['authprovider'] as String?;
    _nonce ??= map['nonce'] as String?;
    _challenge ??= map['challenge'] as String?;
    _iterations ??= _asInt(map['iterations']);
    _keylen ??= _asInt(map['keylen']);
    _progress ??= map['progress'] as bool?;
    _salt ??= map['salt'] as String?;

    if (_topic == null && map['topic'] is String) {
      _topic = Uri.tryParse(map['topic'] as String);
    }
    if (_procedure == null && map['procedure'] is String) {
      _procedure = Uri.tryParse(map['procedure'] as String);
    }
    _trustlevel ??= _asInt(map['trustlevel']);

    final authExtraMap = _asStringKeyMap(map['authextra']);
    if (authExtraMap != null && authExtraMap.isNotEmpty) {
      _authextra ??= <String, dynamic>{};
      for (final entry in authExtraMap.entries) {
        _authextra!.putIfAbsent(entry.key, () => entry.value);
      }
    }

    final rolesMap = _asStringKeyMap(map['roles']);
    _roles ??= _mapRoles(rolesMap);

    final customFields = _extractCustomFields(map, const {
      'agent',
      'realm',
      'authmethods',
      'authid',
      'authrole',
      'authmethod',
      'authprovider',
      'authextra',
      'nonce',
      'challenge',
      'iterations',
      'keylen',
      'progress',
      'salt',
      'topic',
      'procedure',
      'trustlevel',
      'roles',
    });
    for (final entry in customFields.entries) {
      custom.putIfAbsent(entry.key, () => entry.value);
    }
  }

  static Details forHello() {
    final details = Details();
    final roles = Roles();

    final caller = Caller()
      ..features = (CallerFeatures()
        ..callerIdentification = true
        ..callTimeout = true
        ..callCanceling = true
        ..progressiveCallInvocations = true
        ..progressiveCallResults = true
        ..payloadPassThruMode = true);
    final callee = Callee()
      ..features = (CalleeFeatures()
        ..callerIdentification = true
        ..patternBasedRegistration = true
        ..sharedRegistration = true
        ..callTimeout = true
        ..callCanceling = true
        ..progressiveCallInvocations = true
        ..progressiveCallResults = true
        ..payloadPassThruMode = true);
    final publisher = Publisher()
      ..features = (PublisherFeatures()
        ..publisherIdentification = true
        ..subscriberBlackWhiteListing = true
        ..publisherExclusion = true
        ..payloadPassThruMode = true);
    final subscriber = Subscriber()
      ..features = (SubscriberFeatures()
        ..publisherIdentification = true
        ..publicationTrustLevels = true
        ..patternBasedSubscription = true
        ..subscriptionRevocation = true
        ..payloadPassThruMode = true);

    roles.caller = caller;
    roles.callee = callee;
    roles.publisher = publisher;
    roles.subscriber = subscriber;
    details.roles = roles;

    return details;
  }

  static Details forWelcome({
    String? realm,
    String? authId,
    String? authMethod,
    String? authProvider,
    String? authRole,
    Map<String, dynamic>? authExtra,
  }) {
    final details = Details();

    details.realm = realm;
    details.authid = authId;
    details.authmethod = authMethod;
    details.authprovider = authProvider;
    details.authrole = authRole;
    details.authextra = authExtra;

    final roles = Roles();
    final dealer = Dealer()
      ..features = (DealerFeatures()
        ..callerIdentification = true
        ..patternBasedRegistration = true
        ..sharedRegistration = true
        ..registrationMetaApi = true
        ..callTimeout = true
        ..callCanceling = true
        ..progressiveCallInvocations = true
        ..progressiveCallResults = true
        ..payloadPassThruMode = true);
    final broker = Broker()
      ..features = (BrokerFeatures()
        ..publisherIdentification = true
        ..patternBasedSubscription = true
        ..subscriptionMetaApi = true
        ..subscriberBlackWhiteListing = true
        ..publisherExclusion = true
        ..payloadPassThruMode = true);

    roles.dealer = dealer;
    roles.broker = broker;
    details.roles = roles;

    return details;
  }
}

Map<String, dynamic>? _asStringKeyMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, entryValue) => MapEntry(key.toString(), entryValue));
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}

Map<String, dynamic> _extractCustomFields(
  Map<String, dynamic> map,
  Set<String> knownKeys,
) {
  final custom = <String, dynamic>{};
  for (final entry in map.entries) {
    if (knownKeys.contains(entry.key)) {
      continue;
    }
    custom[entry.key] = entry.value;
  }
  return custom;
}

Roles? _mapRoles(Map<String, dynamic>? rolesMap) {
  if (rolesMap == null) {
    return null;
  }
  final roles = Roles();
  if (rolesMap['publisher'] is Map) {
    roles.publisher = Publisher()
      ..features = _mapPublisherFeatures(
        _asStringKeyMap((rolesMap['publisher'] as Map)['features']),
      );
  }
  if (rolesMap['broker'] is Map) {
    final broker = Broker();
    broker.reflection = (rolesMap['broker'] as Map)['reflection'] as bool?;
    broker.features = _mapBrokerFeatures(
      _asStringKeyMap((rolesMap['broker'] as Map)['features']),
    );
    roles.broker = broker;
  }
  if (rolesMap['subscriber'] is Map) {
    roles.subscriber = Subscriber()
      ..features = _mapSubscriberFeatures(
        _asStringKeyMap((rolesMap['subscriber'] as Map)['features']),
      );
  }
  if (rolesMap['dealer'] is Map) {
    final dealer = Dealer();
    dealer.reflection = (rolesMap['dealer'] as Map)['reflection'] as bool?;
    dealer.features = _mapDealerFeatures(
      _asStringKeyMap((rolesMap['dealer'] as Map)['features']),
    );
    roles.dealer = dealer;
  }
  if (rolesMap['callee'] is Map) {
    roles.callee = Callee()
      ..features = _mapCalleeFeatures(
        _asStringKeyMap((rolesMap['callee'] as Map)['features']),
      );
  }
  if (rolesMap['caller'] is Map) {
    roles.caller = Caller()
      ..features = _mapCallerFeatures(
        _asStringKeyMap((rolesMap['caller'] as Map)['features']),
      );
  }
  return roles;
}

PublisherFeatures? _mapPublisherFeatures(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final features = PublisherFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.subscriberBlackWhiteListing =
      map['subscriber_blackwhite_listing'] ??
      features.subscriberBlackWhiteListing;
  features.publisherExclusion =
      map['publisher_exclusion'] ?? features.publisherExclusion;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

BrokerFeatures? _mapBrokerFeatures(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final features = BrokerFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.publicationTrustLevels =
      map['publication_trustlevels'] ??
      map['publication_trust_levels'] ??
      features.publicationTrustLevels;
  features.patternBasedSubscription =
      map['pattern_based_subscription'] ?? features.patternBasedSubscription;
  features.subscriptionMetaApi =
      map['subscription_meta_api'] ?? features.subscriptionMetaApi;
  features.subscriberBlackWhiteListing =
      map['subscriber_blackwhite_listing'] ??
      features.subscriberBlackWhiteListing;
  features.sessionMetaApi = map['session_meta_api'] ?? features.sessionMetaApi;
  features.publisherExclusion =
      map['publisher_exclusion'] ?? features.publisherExclusion;
  features.eventHistory = map['event_history'] ?? features.eventHistory;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

SubscriberFeatures? _mapSubscriberFeatures(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final features = SubscriberFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.publicationTrustLevels =
      map['publication_trustlevels'] ?? features.publicationTrustLevels;
  features.patternBasedSubscription =
      map['pattern_based_subscription'] ?? features.patternBasedSubscription;
  features.subscriptionRevocation =
      map['subscription_revocation'] ?? features.subscriptionRevocation;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  return features;
}

DealerFeatures? _mapDealerFeatures(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final features = DealerFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTrustLevels =
      map['call_trustlevels'] ?? features.callTrustLevels;
  features.patternBasedRegistration =
      map['pattern_based_registration'] ?? features.patternBasedRegistration;
  features.registrationMetaApi =
      map['registration_meta_api'] ?? features.registrationMetaApi;
  features.sharedRegistration =
      map['shared_registration'] ?? features.sharedRegistration;
  features.sessionMetaApi = map['session_meta_api'] ?? features.sessionMetaApi;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallInvocations =
      map['progressive_call_invocations'] ??
      features.progressiveCallInvocations;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

CalleeFeatures? _mapCalleeFeatures(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final features = CalleeFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTrustlevels =
      map['call_trustlevels'] ?? features.callTrustlevels;
  features.patternBasedRegistration =
      map['pattern_based_registration'] ?? features.patternBasedRegistration;
  features.sharedRegistration =
      map['shared_registration'] ?? features.sharedRegistration;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallInvocations =
      map['progressive_call_invocations'] ??
      features.progressiveCallInvocations;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

CallerFeatures? _mapCallerFeatures(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  final features = CallerFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallInvocations =
      map['progressive_call_invocations'] ??
      features.progressiveCallInvocations;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

class Roles {
  Publisher? publisher;
  Broker? broker;
  Subscriber? subscriber;
  Dealer? dealer;
  Callee? callee;
  Caller? caller;
}

class Publisher {
  PublisherFeatures? features;
}

class PublisherFeatures {
  bool _publisherIdentification = false;
  bool get publisherIdentification => _publisherIdentification;
  set publisherIdentification(bool value) {
    _publisherIdentification = value;
    recordWampFieldAssignment(this, 'publisher_identification');
  }

  bool _subscriberBlackWhiteListing = false;
  bool get subscriberBlackWhiteListing => _subscriberBlackWhiteListing;
  set subscriberBlackWhiteListing(bool value) {
    _subscriberBlackWhiteListing = value;
    recordWampFieldAssignment(this, 'subscriber_blackwhite_listing');
  }

  bool _publisherExclusion = false;
  bool get publisherExclusion => _publisherExclusion;
  set publisherExclusion(bool value) {
    _publisherExclusion = value;
    recordWampFieldAssignment(this, 'publisher_exclusion');
  }

  bool _payloadPassThruMode = false;
  bool get payloadPassThruMode => _payloadPassThruMode;
  set payloadPassThruMode(bool value) {
    _payloadPassThruMode = value;
    recordWampFieldAssignment(this, 'payload_passthru_mode');
  }
}

class Broker {
  bool? reflection;
  BrokerFeatures? features;
}

/// Broker feature flags advertised in WAMP `WELCOME.Details`.
class BrokerFeatures {
  /// Whether events may disclose the publisher session ID.
  bool _publisherIdentification = false;
  bool get publisherIdentification => _publisherIdentification;
  set publisherIdentification(bool value) {
    _publisherIdentification = value;
    recordWampFieldAssignment(this, 'publisher_identification');
  }

  /// Whether events may include a router-assigned publication trust level.
  bool _publicationTrustLevels = false;
  bool get publicationTrustLevels => _publicationTrustLevels;
  set publicationTrustLevels(bool value) {
    _publicationTrustLevels = value;
    recordWampFieldAssignment(this, 'publication_trustlevels');
  }

  /// Whether the broker supports prefix and wildcard subscriptions.
  bool _patternBasedSubscription = false;
  bool get patternBasedSubscription => _patternBasedSubscription;
  set patternBasedSubscription(bool value) {
    _patternBasedSubscription = value;
    recordWampFieldAssignment(this, 'pattern_based_subscription');
  }

  /// Whether the broker exposes the WAMP subscription meta API.
  bool _subscriptionMetaApi = false;
  bool get subscriptionMetaApi => _subscriptionMetaApi;
  set subscriptionMetaApi(bool value) {
    _subscriptionMetaApi = value;
    recordWampFieldAssignment(this, 'subscription_meta_api');
  }

  /// Whether publishers may include or exclude specific subscribers.
  bool _subscriberBlackWhiteListing = false;
  bool get subscriberBlackWhiteListing => _subscriberBlackWhiteListing;
  set subscriberBlackWhiteListing(bool value) {
    _subscriberBlackWhiteListing = value;
    recordWampFieldAssignment(this, 'subscriber_blackwhite_listing');
  }

  /// Whether the broker exposes the WAMP session meta API.
  bool _sessionMetaApi = false;
  bool get sessionMetaApi => _sessionMetaApi;
  set sessionMetaApi(bool value) {
    _sessionMetaApi = value;
    recordWampFieldAssignment(this, 'session_meta_api');
  }

  /// Whether publishers may control delivery to their own session.
  bool _publisherExclusion = false;
  bool get publisherExclusion => _publisherExclusion;
  set publisherExclusion(bool value) {
    _publisherExclusion = value;
    recordWampFieldAssignment(this, 'publisher_exclusion');
  }

  /// Whether the broker supports event-history retrieval.
  bool _eventHistory = false;
  bool get eventHistory => _eventHistory;
  set eventHistory(bool value) {
    _eventHistory = value;
    recordWampFieldAssignment(this, 'event_history');
  }

  /// Whether the broker supports WAMP Payload Passthru Mode.
  bool _payloadPassThruMode = false;
  bool get payloadPassThruMode => _payloadPassThruMode;
  set payloadPassThruMode(bool value) {
    _payloadPassThruMode = value;
    recordWampFieldAssignment(this, 'payload_passthru_mode');
  }
}

class Subscriber {
  SubscriberFeatures? features;
}

class SubscriberFeatures {
  bool _publisherIdentification = false;
  bool get publisherIdentification => _publisherIdentification;
  set publisherIdentification(bool value) {
    _publisherIdentification = value;
    recordWampFieldAssignment(this, 'publisher_identification');
  }

  bool _publicationTrustLevels = false;
  bool get publicationTrustLevels => _publicationTrustLevels;
  set publicationTrustLevels(bool value) {
    _publicationTrustLevels = value;
    recordWampFieldAssignment(this, 'publication_trustlevels');
  }

  bool _patternBasedSubscription = false;
  bool get patternBasedSubscription => _patternBasedSubscription;
  set patternBasedSubscription(bool value) {
    _patternBasedSubscription = value;
    recordWampFieldAssignment(this, 'pattern_based_subscription');
  }

  bool _subscriptionRevocation = false;
  bool get subscriptionRevocation => _subscriptionRevocation;
  set subscriptionRevocation(bool value) {
    _subscriptionRevocation = value;
    recordWampFieldAssignment(this, 'subscription_revocation');
  }

  bool _payloadPassThruMode = false;
  bool get payloadPassThruMode => _payloadPassThruMode;
  set payloadPassThruMode(bool value) {
    _payloadPassThruMode = value;
    recordWampFieldAssignment(this, 'payload_passthru_mode');
  }

  @Deprecated(
    'RPC timeout support belongs to CallerFeatures and CalleeFeatures.',
  )
  bool _callTimeout = false;
  bool get callTimeout => _callTimeout;
  set callTimeout(bool value) {
    _callTimeout = value;
    recordWampFieldAssignment(this, 'call_timeout');
  }

  @Deprecated(
    'RPC cancellation support belongs to CallerFeatures and CalleeFeatures.',
  )
  bool _callCanceling = false;
  bool get callCanceling => _callCanceling;
  set callCanceling(bool value) {
    _callCanceling = value;
    recordWampFieldAssignment(this, 'call_canceling');
  }

  @Deprecated(
    'Progressive RPC results belong to CallerFeatures and CalleeFeatures.',
  )
  bool _progressiveCallResults = false;
  bool get progressiveCallResults => _progressiveCallResults;
  set progressiveCallResults(bool value) {
    _progressiveCallResults = value;
    recordWampFieldAssignment(this, 'progressive_call_results');
  }
}

class Dealer {
  bool? reflection;
  DealerFeatures? features;
}

class DealerFeatures {
  bool _callerIdentification = false;
  bool get callerIdentification => _callerIdentification;
  set callerIdentification(bool value) {
    _callerIdentification = value;
    recordWampFieldAssignment(this, 'caller_identification');
  }

  bool _callTrustLevels = false;
  bool get callTrustLevels => _callTrustLevels;
  set callTrustLevels(bool value) {
    _callTrustLevels = value;
    recordWampFieldAssignment(this, 'call_trustlevels');
  }

  bool _patternBasedRegistration = false;
  bool get patternBasedRegistration => _patternBasedRegistration;
  set patternBasedRegistration(bool value) {
    _patternBasedRegistration = value;
    recordWampFieldAssignment(this, 'pattern_based_registration');
  }

  bool _registrationMetaApi = false;
  bool get registrationMetaApi => _registrationMetaApi;
  set registrationMetaApi(bool value) {
    _registrationMetaApi = value;
    recordWampFieldAssignment(this, 'registration_meta_api');
  }

  bool _sharedRegistration = false;
  bool get sharedRegistration => _sharedRegistration;
  set sharedRegistration(bool value) {
    _sharedRegistration = value;
    recordWampFieldAssignment(this, 'shared_registration');
  }

  bool _sessionMetaApi = false;
  bool get sessionMetaApi => _sessionMetaApi;
  set sessionMetaApi(bool value) {
    _sessionMetaApi = value;
    recordWampFieldAssignment(this, 'session_meta_api');
  }

  bool _callTimeout = false;
  bool get callTimeout => _callTimeout;
  set callTimeout(bool value) {
    _callTimeout = value;
    recordWampFieldAssignment(this, 'call_timeout');
  }

  bool _callCanceling = false;
  bool get callCanceling => _callCanceling;
  set callCanceling(bool value) {
    _callCanceling = value;
    recordWampFieldAssignment(this, 'call_canceling');
  }

  bool _progressiveCallInvocations = false;
  bool get progressiveCallInvocations => _progressiveCallInvocations;
  set progressiveCallInvocations(bool value) {
    _progressiveCallInvocations = value;
    recordWampFieldAssignment(this, 'progressive_call_invocations');
  }

  bool _progressiveCallResults = false;
  bool get progressiveCallResults => _progressiveCallResults;
  set progressiveCallResults(bool value) {
    _progressiveCallResults = value;
    recordWampFieldAssignment(this, 'progressive_call_results');
  }

  bool _payloadPassThruMode = false;
  bool get payloadPassThruMode => _payloadPassThruMode;
  set payloadPassThruMode(bool value) {
    _payloadPassThruMode = value;
    recordWampFieldAssignment(this, 'payload_passthru_mode');
  }
}

class Callee {
  CalleeFeatures? features;
}

class CalleeFeatures {
  bool _callerIdentification = false;
  bool get callerIdentification => _callerIdentification;
  set callerIdentification(bool value) {
    _callerIdentification = value;
    recordWampFieldAssignment(this, 'caller_identification');
  }

  bool _callTrustlevels = false;
  bool get callTrustlevels => _callTrustlevels;
  set callTrustlevels(bool value) {
    _callTrustlevels = value;
    recordWampFieldAssignment(this, 'call_trustlevels');
  }

  bool _patternBasedRegistration = false;
  bool get patternBasedRegistration => _patternBasedRegistration;
  set patternBasedRegistration(bool value) {
    _patternBasedRegistration = value;
    recordWampFieldAssignment(this, 'pattern_based_registration');
  }

  bool _sharedRegistration = false;
  bool get sharedRegistration => _sharedRegistration;
  set sharedRegistration(bool value) {
    _sharedRegistration = value;
    recordWampFieldAssignment(this, 'shared_registration');
  }

  bool _callTimeout = false;
  bool get callTimeout => _callTimeout;
  set callTimeout(bool value) {
    _callTimeout = value;
    recordWampFieldAssignment(this, 'call_timeout');
  }

  bool _callCanceling = false;
  bool get callCanceling => _callCanceling;
  set callCanceling(bool value) {
    _callCanceling = value;
    recordWampFieldAssignment(this, 'call_canceling');
  }

  bool _progressiveCallInvocations = false;
  bool get progressiveCallInvocations => _progressiveCallInvocations;
  set progressiveCallInvocations(bool value) {
    _progressiveCallInvocations = value;
    recordWampFieldAssignment(this, 'progressive_call_invocations');
  }

  bool _progressiveCallResults = false;
  bool get progressiveCallResults => _progressiveCallResults;
  set progressiveCallResults(bool value) {
    _progressiveCallResults = value;
    recordWampFieldAssignment(this, 'progressive_call_results');
  }

  bool _payloadPassThruMode = false;
  bool get payloadPassThruMode => _payloadPassThruMode;
  set payloadPassThruMode(bool value) {
    _payloadPassThruMode = value;
    recordWampFieldAssignment(this, 'payload_passthru_mode');
  }
}

class Caller {
  CallerFeatures? features;
}

class CallerFeatures {
  bool _callerIdentification = false;
  bool get callerIdentification => _callerIdentification;
  set callerIdentification(bool value) {
    _callerIdentification = value;
    recordWampFieldAssignment(this, 'caller_identification');
  }

  bool _callTimeout = false;
  bool get callTimeout => _callTimeout;
  set callTimeout(bool value) {
    _callTimeout = value;
    recordWampFieldAssignment(this, 'call_timeout');
  }

  bool _callCanceling = false;
  bool get callCanceling => _callCanceling;
  set callCanceling(bool value) {
    _callCanceling = value;
    recordWampFieldAssignment(this, 'call_canceling');
  }

  bool _progressiveCallInvocations = false;
  bool get progressiveCallInvocations => _progressiveCallInvocations;
  set progressiveCallInvocations(bool value) {
    _progressiveCallInvocations = value;
    recordWampFieldAssignment(this, 'progressive_call_invocations');
  }

  bool _progressiveCallResults = false;
  bool get progressiveCallResults => _progressiveCallResults;
  set progressiveCallResults(bool value) {
    _progressiveCallResults = value;
    recordWampFieldAssignment(this, 'progressive_call_results');
  }

  bool _payloadPassThruMode = false;
  bool get payloadPassThruMode => _payloadPassThruMode;
  set payloadPassThruMode(bool value) {
    _payloadPassThruMode = value;
    recordWampFieldAssignment(this, 'payload_passthru_mode');
  }
}

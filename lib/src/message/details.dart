/// Container for additional details sent with WAMP messages.
class Details {
  String? agent;
  String? realm;
  List<String>? authmethods;
  String? authid;
  String? authrole;
  String? authmethod;
  String? authprovider;
  Map<String, dynamic>? authextra;
  String? nonce;
  String? challenge;
  int? iterations;
  int? keylen;
  bool? progress;
  String? salt;
  Uri? topic;
  Uri? procedure;
  int? trustlevel;
  Roles? roles;

  /// Create a [Details] object prefilled for HELLO messages with all default
  /// role information present.
  static Details forHello() {
    final details = Details();
    var roles = Roles();
    var caller = Caller();
    caller.features = CallerFeatures();

    var callee = Callee();
    callee.features = CalleeFeatures();

    var publisher = Publisher();
    publisher.features = PublisherFeatures();

    var subscriber = Subscriber();
    subscriber.features = SubscriberFeatures();

    roles.caller = caller;
    roles.callee = callee;
    roles.publisher = publisher;
    roles.subscriber = subscriber;

    details.roles = roles;

    return details;
  }

  /// Create a [Details] object prefilled for WELCOME messages.
  /// Various authentication information may be supplied via the optional
  /// parameters.
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

    var roles = Roles();

    var dealer = Dealer();
    dealer.features = DealerFeatures();

    var broker = Broker();
    broker.features = BrokerFeatures();

    roles.dealer = dealer;
    roles.broker = broker;

    details.roles = roles;

    return details;
  }
}

/// Holds feature descriptions for the various WAMP roles.
class Roles {
  Publisher? publisher;
  Broker? broker;
  Subscriber? subscriber;
  Dealer? dealer;
  Callee? callee;
  Caller? caller;
}

/// Features supported by the publisher role.
class Publisher {
  PublisherFeatures? features;
}

/// Capabilities a router advertises for its publisher role.
class PublisherFeatures {
  bool publisherIdentification = true;
  bool subscriberBlackWhiteListing = true;
  bool publisherExclusion = true;
  bool payloadPassThruMode = true;
}

/// Features supported by the broker role.
class Broker {
  bool? reflection;
  BrokerFeatures? features;
}

/// Capabilities a router advertises for its broker role.
class BrokerFeatures {
  bool publisherIdentification = false;
  bool publicationTrustLevels = false;
  bool patternBasedSubscription = false;
  bool subscriptionMetaApi = false;
  bool subscriberBlackWhiteListing = false;
  bool sessionMetaApi = false;
  bool publisherExclusion = false;
  bool eventHistory = false;
  bool payloadPassThruMode = false;
}

/// Features supported by the subscriber role.
class Subscriber {
  SubscriberFeatures? features;
}

/// Capabilities a router advertises for its subscriber role.
class SubscriberFeatures {
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = false;
  bool subscriptionRevocation = true;
  bool payloadPassThruMode = true;
}

/// Features supported by the dealer role.
class Dealer {
  bool? reflection;
  DealerFeatures? features;
}

/// Capabilities a router advertises for its dealer role.
class DealerFeatures {
  bool callerIdentification = false;
  bool callTrustLevels = false;
  bool patternBasedRegistration = false;
  bool registrationMetaApi = false;
  bool sharedRegistration = false;
  bool sessionMetaApi = false;
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = false;
  bool payloadPassThruMode = false;
}

/// Features supported by the callee role.
class Callee {
  CalleeFeatures? features;
}

/// Capabilities a router advertises for its callee role.
class CalleeFeatures {
  bool callerIdentification = true;
  bool callTrustlevels = false;
  bool patternBasedRegistration = false;
  bool sharedRegistration = false;
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = true;
  bool payloadPassThruMode = true;
}

/// Features supported by the caller role.
class Caller {
  CallerFeatures? features;
}

/// Capabilities a router advertises for its caller role.
class CallerFeatures {
  bool callerIdentification = true;
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = true;
  bool payloadPassThruMode = true;
}

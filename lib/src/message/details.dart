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
  bool publisherIdentification = true;
  bool subscriberBlackWhiteListing = true;
  bool publisherExclusion = true;
  bool payloadTransparency = true;
}

class Broker {
  bool? reflection;
  BrokerFeatures? features;
}

class BrokerFeatures {
  bool publisherIdentification = false;
  bool publicationTrustLevels = false;
  bool patternBasedSubscription = false;
  bool subscriptionMetaApi = false;
  bool subscriberBlackWhiteListing = false;
  bool sessionMetaApi = false;
  bool publisherExclusion = false;
  bool eventHistory = false;
  bool payloadTransparency = false;
}

class Subscriber {
  SubscriberFeatures? features;
}

class SubscriberFeatures {
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = false;
  bool payloadTransparency = true;
  bool subscriptionRevocation = true;
}

class Dealer {
  bool? reflection;
  DealerFeatures? features;
}

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
  bool payloadTransparency = false;
}

class Callee {
  CalleeFeatures? features;
}

class CalleeFeatures {
  bool callerIdentification = true;
  bool callTrustlevels = false;
  bool patternBasedRegistration = false;
  bool sharedRegistration = false;
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = true;
  bool payloadTransparency = true;
}

class Caller {
  CallerFeatures? features;
}

class CallerFeatures {
  bool callerIdentification = true;
  bool callTimeout = false;
  bool callCanceling = false;
  bool progressiveCallResults = true;
  bool payloadTransparency = true;
}

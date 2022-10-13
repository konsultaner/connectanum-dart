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
  bool publisher_identification = true;
  bool subscriber_blackwhite_listing = true;
  bool publisher_exclusion = true;
  bool payload_passthru_mode = true;
}

class Broker {
  bool? reflection;
  BrokerFeatures? features;
}

class BrokerFeatures {
  bool publisher_identification = false;
  bool publication_trustlevels = false;
  bool pattern_based_subscription = false;
  bool subscription_meta_api = false;
  bool subscriber_blackwhite_listing = false;
  bool session_meta_api = false;
  bool publisher_exclusion = false;
  bool event_history = false;
  bool payload_passthru_mode = false;
}

class Subscriber {
  SubscriberFeatures? features;
}

class SubscriberFeatures {
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = false;
  bool payload_passthru_mode = true;
  bool subscription_revocation = true;
}

class Dealer {
  bool? reflection;
  DealerFeatures? features;
}

class DealerFeatures {
  bool caller_identification = false;
  bool call_trustlevels = false;
  bool pattern_based_registration = false;
  bool registration_meta_api = false;
  bool shared_registration = false;
  bool session_meta_api = false;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = false;
  bool payload_passthru_mode = false;
}

class Callee {
  CalleeFeatures? features;
}

class CalleeFeatures {
  bool caller_identification = true;
  bool call_trustlevels = false;
  bool pattern_based_registration = false;
  bool shared_registration = false;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_passthru_mode = true;
}

class Caller {
  CallerFeatures? features;
}

class CallerFeatures {
  bool caller_identification = true;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_passthru_mode = true;
}

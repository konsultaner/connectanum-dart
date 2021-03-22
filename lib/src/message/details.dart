class Details {
  String agent;
  String realm;
  List<String> authmethods;
  String authid;
  String authrole;
  String authmethod;
  String authprovider;
  Map<String, String> authextra;
  String nonce;
  String challenge;
  int iterations;
  int keylen;
  bool progress;
  String salt;
  Uri topic;
  Uri procedure;
  int trustlevel;
  Roles roles;

  static Details forHello() {
    final details = Details();
    details.roles = Roles();

    details.roles.caller = Caller();
    details.roles.caller.features = CallerFeatures();

    details.roles.callee = Callee();
    details.roles.callee.features = CalleeFeatures();

    details.roles.publisher = Publisher();
    details.roles.publisher.features = PublisherFeatures();

    details.roles.subscriber = Subscriber();
    details.roles.subscriber.features = SubscriberFeatures();

    return details;
  }

  static Details forWelcome({
    String realm,
    String authId,
    String authMethod,
    String authProvider,
    String authRole,
    Map<String, String> authExtra,
  }) {
    final details = Details();

    details.realm = realm;
    details.authid = authId;
    details.authmethod = authMethod;
    details.authprovider = authProvider;
    details.authrole = authRole;
    details.authextra = authExtra;

    details.roles = Roles();

    details.roles.dealer = Dealer();
    details.roles.dealer.features = DealerFeatures();

    details.roles.broker = Broker();
    details.roles.broker.features = BrokerFeatures();

    return details;
  }
}

class Roles {
  Publisher publisher;
  Broker broker;
  Subscriber subscriber;
  Dealer dealer;
  Callee callee;
  Caller caller;
}

class Publisher {
  PublisherFeatures features;
}

class PublisherFeatures {
  bool publisher_identification = true;
  bool subscriber_blackwhite_listing = true;
  bool publisher_exclusion = true;
  bool payload_transparency = true;
}

class Broker {
  bool reflection;
  BrokerFeatures features;
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
  bool payload_transparency = false;
}

class Subscriber {
  SubscriberFeatures features;
}

class SubscriberFeatures {
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = false;
  bool payload_transparency = true;
  bool subscription_revocation = true;
}

class Dealer {
  bool reflection;
  DealerFeatures features;
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
  bool payload_transparency = false;
}

class Callee {
  CalleeFeatures features;
}

class CalleeFeatures {
  bool caller_identification = true;
  bool call_trustlevels = false;
  bool pattern_based_registration = false;
  bool shared_registration = false;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_transparency = true;
}

class Caller {
  CallerFeatures features;
}

class CallerFeatures {
  bool caller_identification = true;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_transparency = true;
}

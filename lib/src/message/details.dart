class Details {
  String agent;
  List<String> authmethods;
  String authid;
  String authrole;
  String authmethod;
  String authprovider;
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

  static forHello() {
    final details = new Details();
    details.roles = new Roles();

    details.roles.caller = new Caller();
    details.roles.caller.features = new CallerFeatures();

    details.roles.callee = new Callee();
    details.roles.callee.features = new CalleeFeatures();

    details.roles.publisher = new Publisher();
    details.roles.publisher.features = new PublisherFeatures();

    details.roles.subscriber = new Subscriber();
    details.roles.subscriber.features = new SubscriberFeatures();

    return details;
  }

  static forWelcome({
    String authId,
    String authMethod,
    String authProvider,
    String authRole,
  }) {
    final details = new Details();
    details.authid = authId;
    details.authmethod = authMethod;
    details.authprovider = authProvider;
    details.authrole = authRole;

    details.roles = new Roles();

    details.roles.dealer = new Dealer();
    details.roles.dealer.features = new DealerFeatures();

    details.roles.broker = new Broker();
    details.roles.broker.features = new BrokerFeatures();

    return details;
  }
}

class Roles{
  Publisher publisher;
  Broker broker;
  Subscriber subscriber;
  Dealer dealer;
  Callee callee;
  Caller caller;
}

class Publisher{
  PublisherFeatures features;
}
class PublisherFeatures{
  bool publisher_identification = true;
  bool subscriber_blackwhite_listing = true;
  bool publisher_exclusion = true;
  bool payload_transparency = true;
}

class Broker{
  bool reflection;
  BrokerFeatures features;
}

class BrokerFeatures{
  bool publisher_identification = true;
  bool publication_trustlevels = false;
  bool pattern_based_subscription = true;
  bool subscription_meta_api = true;
  bool subscriber_blackwhite_listing = true;
  bool session_meta_api = true;
  bool publisher_exclusion = true;
  bool event_history = false;
  bool payload_transparency = true;
}

class Subscriber{
  SubscriberFeatures features;
}

class SubscriberFeatures{
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = false;
  bool payload_transparency = true;
}

class Dealer{
  bool reflection;
  DealerFeatures features;
}

class DealerFeatures{
  bool caller_identification = true;
  bool call_trustlevels = false;
  bool pattern_based_registration = true;
  bool registration_meta_api = true;
  bool shared_registration = true;
  bool session_meta_api = true;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_transparency = true;
}

class Callee{
  CalleeFeatures features;
}

class CalleeFeatures{
  bool caller_identification = true;
  bool call_trustlevels = false;
  bool pattern_based_registration = false;
  bool shared_registration = false;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_transparency = true;
}

class Caller{
  CallerFeatures features;
}

class CallerFeatures{
  bool caller_identification = true;
  bool call_timeout = false;
  bool call_canceling = false;
  bool progressive_call_results = true;
  bool payload_transparency = true;
}

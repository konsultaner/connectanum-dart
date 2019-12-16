import 'abstract_message.dart';

class Cancel extends AbstractMessage {
  int id;
  int requestId;
  Options options;
}

class Options {
  static final String MODE_SKIP = "skip";
  static final String MODE_KILL = "kill";
  static final String MODE_KILL_NO_WAIT = "killnowait";

  String mode;
}

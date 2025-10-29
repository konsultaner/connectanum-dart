/// Numeric codes used for the various WAMP messages.
class MessageTypes {
  static final int codeHello = 1;
  static final int codeWelcome = 2;
  static final int codeAbort = 3;
  static final int codeChallenge = 4;
  static final int codeAuthenticate = 5;
  static final int codeGoodbye = 6;

  static final int codeError = 8;

  static final int codePublish = 16;
  static final int codePublished = 17;

  static final int codeSubscribe = 32;
  static final int codeSubscribed = 33;
  static final int codeUnsubscribe = 34;
  static final int codeUnsubscribed = 35;
  static final int codeEvent = 36;

  static final int codeCall = 48;
  static final int codeCancel = 49;
  static final int codeResult = 50;

  static final int codeRegister = 64;
  static final int codeRegistered = 65;
  static final int codeUnregister = 66;
  static final int codeUnregistered = 67;
  static final int codeInvocation = 68;
  static final int codeInterrupt = 69;
  static final int codeYield = 70;
}

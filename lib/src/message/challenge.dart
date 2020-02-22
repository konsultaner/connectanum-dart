import 'abstract_message.dart';
import 'message_types.dart';

class Challenge extends AbstractMessage {
  String authMethod;
  Extra extra;

  Challenge(this.authMethod, this.extra) {
    this.id = MessageTypes.CODE_CHALLENGE;
  }
}

/**
 * Challenge values to check the authentication validity
 */
class Extra {
  String challenge;
  String salt;
  int keylen;
  int iterations;
  int memory;
  int parallel;
  int version_num;
  String version_str;
  String nonce;

  Extra(
      {this.challenge,
      this.salt,
      this.keylen,
      this.iterations,
      this.memory,
      this.parallel,
      this.version_num,
      this.version_str,
      this.nonce});
}

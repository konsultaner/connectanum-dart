import 'abstract_message.dart';

class Challenge extends AbstractMessage {
    String authMethod;
    Extra extra;
}

/**
 * Challenge values to check the authentication validity
 */
class Extra{
    String challenge;
    String salt;
    int keylen;
    int iterations;
    int memory;
    int parallel;
    int version_num;
    String version_str;
    String nonce;
}

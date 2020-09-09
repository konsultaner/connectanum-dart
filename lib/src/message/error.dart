import 'abstract_message_with_payload.dart';
import 'message_types.dart';

/// The WAMP Error massage
class Error extends AbstractMessageWithPayload {
  static final String ERROR_INVOCATION_CANCELED =
      'wamp.error.invocation_canceled';

  // INTERACTION ERRORS
  static final String ERROR_INVALID_URI = 'wamp.error.invalid_uri';
  static final String INVALID_MESSAGE_ID = 'wamp.error.invalid_message_id';
  static final String WRONG_MESSAGE_STRUCTURE =
      'wamp.error.wrong_message_structure';
  static final String NO_SUCH_PROCEDURE = 'wamp.error.no_such_procedure';
  static final String PROCEDURE_ALREADY_EXISTS =
      'wamp.error.procedure_already_exists';
  static final String NO_SUCH_REGISTRATION = 'wamp.error.no_such_registration';
  static final String NO_SUCH_SUBSCRIPTION = 'wamp.error.no_such_subscription';
  static final String INVALID_ARGUMENT = 'wamp.error.invalid_argument';
  static final String NOT_CONNECTED = 'wamp.error.not_connected';
  static final String UNKNOWN = 'wamp.error.unknown';

  // AUTHORIZATION ERRORS
  static final String NOT_AUTHORIZED = 'wamp.error.not_authorized';
  static final String AUTHORIZATION_FAILED = 'wamp.error.authorization_failed';
  static final String NO_SUCH_REALM = 'wamp.error.no_such_realm';
  static final String NO_SUCH_ROLE = 'wamp.error.no_such_role';
  static final String NO_SUCH_TOPIC = 'wamp.error.no_such_topic';
  static final String NO_SUCH_SESSION = 'wamp.error.no_such_session';
  static final String PROTOCOL_VIOLATION = 'wamp.error.protocol_violation';

  static final String HIDDEN_ERROR_MESSAGE = 'unknown';

  int requestTypeId;
  int requestId;
  Map<String, Object> details;
  String error;

  Error(this.requestTypeId, this.requestId, this.details, this.error,
      {List<Object> arguments, Map<String, Object> argumentsKeywords}) {
    id = MessageTypes.CODE_ERROR;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

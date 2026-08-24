abstract final class WampAppProtocol {
  static const registrationRealm = 'com.wampapp.registration';
  static const appRealm = 'com.wampapp';
  static const scramAuthMethod = 'wamp-scram';

  static const accountRegister = 'com.wampapp.account.register';

  static const errorInvalidRegistration =
      'com.wampapp.error.invalid_registration';
  static const errorUsernameTaken = 'com.wampapp.error.username_taken';
  static const errorRegistrationUnavailable =
      'com.wampapp.error.registration_unavailable';

  static const serviceAuthId = 'wampapp.service';
  static const anonymousRole = 'anonymous';
  static const memberRole = 'member';
  static const serviceRole = 'service';
}

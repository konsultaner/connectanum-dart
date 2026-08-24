abstract final class WampAppProtocol {
  static const registrationRealm = 'com.wampapp.registration';
  static const appRealm = 'com.wampapp';
  static const scramAuthMethod = 'wamp-scram';

  static const accountRegister = 'com.wampapp.account.register';
  static const deviceEnroll = 'com.wampapp.device.enroll';
  static const deviceList = 'com.wampapp.device.list';
  static const deviceRevoke = 'com.wampapp.device.revoke';

  static const errorInvalidRegistration =
      'com.wampapp.error.invalid_registration';
  static const errorUsernameTaken = 'com.wampapp.error.username_taken';
  static const errorRegistrationUnavailable =
      'com.wampapp.error.registration_unavailable';
  static const errorInvalidDevice = 'com.wampapp.error.invalid_device';
  static const errorDeviceConflict = 'com.wampapp.error.device_conflict';
  static const errorDeviceNotFound = 'com.wampapp.error.device_not_found';
  static const errorDeviceRevoked = 'com.wampapp.error.device_revoked';
  static const errorDeviceUnavailable = 'com.wampapp.error.device_unavailable';
  static const errorNotAuthorized = 'com.wampapp.error.not_authorized';

  static const serviceAuthId = 'wampapp.service';
  static const anonymousRole = 'anonymous';
  static const memberRole = 'member';
  static const serviceRole = 'service';
}

abstract final class WampAppProtocol {
  static const registrationRealm = 'com.wampapp.registration';
  static const appRealm = 'com.wampapp';
  static const scramAuthMethod = 'wamp-scram';

  static const accountRegister = 'com.wampapp.account.register';
  static const deviceEnroll = 'com.wampapp.device.enroll';
  static const deviceList = 'com.wampapp.device.list';
  static const deviceLookup = 'com.wampapp.device.lookup';
  static const deviceRevoke = 'com.wampapp.device.revoke';
  static const messageSend = 'com.wampapp.message.send';
  static const messageSync = 'com.wampapp.message.sync';
  static const messageReceipt = 'com.wampapp.message.receipt';
  static const messageConsume = 'com.wampapp.message.consume';
  static const mailboxChanged = 'com.wampapp.mailbox.changed';
  static const attachmentChunkPut = 'com.wampapp.attachment.chunk.put';
  static const attachmentUploadStatus = 'com.wampapp.attachment.upload.status';
  static const attachmentChunkGet = 'com.wampapp.attachment.chunk.get';

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
  static const errorInvalidMessage = 'com.wampapp.error.invalid_message';
  static const errorMessageConflict = 'com.wampapp.error.message_conflict';
  static const errorMessageNotFound = 'com.wampapp.error.message_not_found';
  static const errorMessageConsumed = 'com.wampapp.error.message_consumed';
  static const errorMessageUnavailable =
      'com.wampapp.error.message_unavailable';
  static const errorInvalidAttachment = 'com.wampapp.error.invalid_attachment';
  static const errorAttachmentConflict =
      'com.wampapp.error.attachment_conflict';
  static const errorAttachmentNotFound =
      'com.wampapp.error.attachment_not_found';
  static const errorAttachmentIncomplete =
      'com.wampapp.error.attachment_incomplete';
  static const errorAttachmentUnavailable =
      'com.wampapp.error.attachment_unavailable';
  static const errorNotAuthorized = 'com.wampapp.error.not_authorized';

  static const serviceAuthId = 'wampapp.service';
  static const anonymousRole = 'anonymous';
  static const memberRole = 'member';
  static const serviceRole = 'service';
}

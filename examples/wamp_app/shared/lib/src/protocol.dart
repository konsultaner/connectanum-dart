abstract final class WampAppProtocol {
  static const registrationRealm = 'com.wampapp.registration';
  static const appRealm = 'com.wampapp';
  static const scramAuthMethod = 'wamp-scram';

  static const accountRegister = 'com.wampapp.account.register';
  static const profileGet = 'com.wampapp.profile.get';
  static const profileUpdate = 'com.wampapp.profile.update';
  static const deviceEnroll = 'com.wampapp.device.enroll';
  static const deviceList = 'com.wampapp.device.list';
  static const deviceLookup = 'com.wampapp.device.lookup';
  static const deviceRevoke = 'com.wampapp.device.revoke';
  static const messageSend = 'com.wampapp.message.send';
  static const messageSync = 'com.wampapp.message.sync';
  static const messageReceipt = 'com.wampapp.message.receipt';
  static const messageConsume = 'com.wampapp.message.consume';
  static const mailboxChanged = 'com.wampapp.mailbox.changed';
  static const pushRegister = 'com.wampapp.push.register';
  static const pushUnregister = 'com.wampapp.push.unregister';
  static const attachmentChunkPut = 'com.wampapp.attachment.chunk.put';
  static const attachmentUploadStatus = 'com.wampapp.attachment.upload.status';
  static const attachmentChunkGet = 'com.wampapp.attachment.chunk.get';
  static const backupUploadBegin = 'com.wampapp.backup.upload.begin';
  static const backupChunkPut = 'com.wampapp.backup.chunk.put';
  static const backupUploadCommit = 'com.wampapp.backup.upload.commit';
  static const backupMetadataGet = 'com.wampapp.backup.metadata.get';
  static const backupChunkGet = 'com.wampapp.backup.chunk.get';
  static const backupDelete = 'com.wampapp.backup.delete';

  static const errorInvalidRegistration =
      'com.wampapp.error.invalid_registration';
  static const errorUsernameTaken = 'com.wampapp.error.username_taken';
  static const errorRegistrationUnavailable =
      'com.wampapp.error.registration_unavailable';
  static const errorInvalidProfile = 'com.wampapp.error.invalid_profile';
  static const errorProfileConflict = 'com.wampapp.error.profile_conflict';
  static const errorProfileNotFound = 'com.wampapp.error.profile_not_found';
  static const errorProfileUnavailable =
      'com.wampapp.error.profile_unavailable';
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
  static const errorInvalidPushSubscription =
      'com.wampapp.error.invalid_push_subscription';
  static const errorPushSubscriptionUnavailable =
      'com.wampapp.error.push_subscription_unavailable';
  static const errorInvalidAttachment = 'com.wampapp.error.invalid_attachment';
  static const errorAttachmentConflict =
      'com.wampapp.error.attachment_conflict';
  static const errorAttachmentNotFound =
      'com.wampapp.error.attachment_not_found';
  static const errorAttachmentIncomplete =
      'com.wampapp.error.attachment_incomplete';
  static const errorAttachmentQuotaExceeded =
      'com.wampapp.error.attachment_quota_exceeded';
  static const errorAttachmentUnavailable =
      'com.wampapp.error.attachment_unavailable';
  static const errorInvalidBackup = 'com.wampapp.error.invalid_backup';
  static const errorBackupConflict = 'com.wampapp.error.backup_conflict';
  static const errorBackupNotFound = 'com.wampapp.error.backup_not_found';
  static const errorBackupIncomplete = 'com.wampapp.error.backup_incomplete';
  static const errorBackupQuotaExceeded =
      'com.wampapp.error.backup_quota_exceeded';
  static const errorBackupUnavailable = 'com.wampapp.error.backup_unavailable';
  static const errorNotAuthorized = 'com.wampapp.error.not_authorized';

  static const serviceAuthId = 'wampapp.service';
  static const anonymousRole = 'anonymous';
  static const memberRole = 'member';
  static const serviceRole = 'service';
}

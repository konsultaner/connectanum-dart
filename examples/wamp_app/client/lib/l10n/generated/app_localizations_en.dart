// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'WampApp';

  @override
  String get chats => 'Chats';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get privacy => 'Privacy';

  @override
  String get appearance => 'Appearance';

  @override
  String get dataAndStorage => 'Data and storage';

  @override
  String get advanced => 'Advanced';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get contacts => 'Contacts';

  @override
  String get contactsSubtitle => 'Manage names saved on this device';

  @override
  String get staySignedIn => 'Stay signed in with biometrics';

  @override
  String get staySignedInSubtitle =>
      'Unlock your saved sign-in with Face ID, Touch ID, or your device biometrics';

  @override
  String get biometricsUnavailable =>
      'Biometric sign-in is not available on this device.';

  @override
  String get biometricPasswordPrompt =>
      'Confirm your account password to enable biometric sign-in.';

  @override
  String get signInWithBiometrics => 'Sign in with biometrics';

  @override
  String get pushNotifications => 'Push notifications';

  @override
  String get pushNotificationsSubtitle =>
      'Receive new-message notifications when WampApp is not open';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'Use device setting';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get accentColor => 'App color';

  @override
  String get accentColorSubtitle =>
      'Choose the primary color used throughout WampApp';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentCoral => 'Coral';

  @override
  String get accentAmber => 'Amber';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Use device language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'German';

  @override
  String get languageSpanish => 'Spanish';

  @override
  String get languageFrench => 'French';

  @override
  String get languageItalian => 'Italian';

  @override
  String get languagePortuguese => 'Portuguese';

  @override
  String get backup => 'Backup';

  @override
  String get backupSubtitle => 'Export or restore your encrypted backup';

  @override
  String get serverBackup => 'Server backup';

  @override
  String get serverBackupSubtitle =>
      'Store a recovery-phrase encrypted backup on this server';

  @override
  String get mcpAccess => 'App and agent access';

  @override
  String get mcpAccessSubtitle => 'Control access to your public profile';

  @override
  String get technicalInformation => 'Technical information';

  @override
  String get technicalInformationSubtitle =>
      'Connection, encryption, device, and endpoint details';

  @override
  String get signOut => 'Sign out';

  @override
  String get technicalIntro =>
      'These details help with support and integration. Your chats, passwords, keys, and tokens are never shown here.';

  @override
  String get connection => 'Connection';

  @override
  String get connected => 'Connected';

  @override
  String get server => 'Server';

  @override
  String get websocketEndpoint => 'WebSocket endpoint';

  @override
  String get applicationRealm => 'Application realm';

  @override
  String get username => 'Username';

  @override
  String get device => 'Device';

  @override
  String get deviceId => 'Device ID';

  @override
  String get safetyNumber => 'Safety number';

  @override
  String get encryption => 'Encryption';

  @override
  String get encryptionSummary =>
      'End-to-end encrypted messages and attachments; device keys stay in the encrypted local vault.';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get enable => 'Enable';

  @override
  String get disable => 'Disable';

  @override
  String get save => 'Save';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get createAccount => 'Create account';

  @override
  String get signIn => 'Sign in';

  @override
  String get serverAddress => 'Server address';

  @override
  String get advancedServerSettings => 'Advanced server settings';

  @override
  String get advancedServerSettingsSubtitle =>
      'Change the server address only when your provider tells you to';

  @override
  String get displayName => 'Display name';

  @override
  String get createAndConnect => 'Create and connect';

  @override
  String get connectSecurely => 'Sign in securely';

  @override
  String get restoreEncryptedBackup => 'Restore encrypted backup';

  @override
  String get restoreBackupFromServer => 'Restore backup from server';

  @override
  String get checkingServer => 'Checking service availability…';

  @override
  String get serverReady => 'Service is ready.';

  @override
  String get serverUnavailable =>
      'Service unavailable. Check the address and try again.';

  @override
  String get retry => 'Retry';

  @override
  String get introHeadline => 'Private conversations that feel effortless.';

  @override
  String get introBody =>
      'Message, call, and share with the people who matter. Your conversations stay end-to-end encrypted across your devices.';

  @override
  String get privateByDesign => 'Private by design';

  @override
  String get realTimeMessaging => 'Real-time messaging';

  @override
  String get yourOwnAccount => 'Your own account';

  @override
  String get backupRestoreBoundary =>
      'Both restore paths recover this account\'s device identity, chats, settings, and attachment keys. The server copy is end-to-end encrypted. Cached media bytes are not included and must be downloaded again.';

  @override
  String get contactPrivacyBoundary =>
      'Only the selected display name and the WampApp username you enter are saved in this encrypted device vault. Phone numbers, email addresses, contact IDs, and address-book files are never uploaded or retained.';

  @override
  String get importContacts => 'Import contacts';

  @override
  String get addByUsername => 'Add by username';

  @override
  String get importedDisplayName => 'Imported display name';

  @override
  String get nameOnDevice => 'Name on this device';

  @override
  String get wampAppUsername => 'WampApp username';

  @override
  String get contactVerifyHelper =>
      'Verified with the connected server before saving.';

  @override
  String get contactRenameHelper =>
      'The canonical account cannot be changed while renaming.';

  @override
  String get verifyAndSave => 'Verify and save';

  @override
  String get saveLocalName => 'Save local name';

  @override
  String get noContactsSaved => 'No contacts saved on this device.';

  @override
  String localContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count local contacts',
      one: '1 local contact',
    );
    return '$_temp0';
  }

  @override
  String get renameLocalContact => 'Rename local contact';

  @override
  String get removeLocalContact => 'Remove local contact';

  @override
  String get contactReadFailed => 'The selected contact could not be read.';

  @override
  String get encryptDeviceBackup => 'Encrypt device backup';

  @override
  String get restoreBackup => 'Restore backup';

  @override
  String get backupCreateHelp =>
      'This phrase is the only way to decrypt the export. It is not stored or sent to the server.';

  @override
  String get backupRestoreHelp =>
      'Enter the recovery phrase used when this device backup was created.';

  @override
  String get recoveryPhrase => 'Recovery phrase';

  @override
  String get confirmRecoveryPhrase => 'Confirm recovery phrase';

  @override
  String get passphraseLength => 'Use 16 to 1024 UTF-8 bytes.';

  @override
  String get passphraseMismatch => 'The recovery phrases do not match.';

  @override
  String get createBackup => 'Create backup';

  @override
  String get chooseBackup => 'Choose backup';

  @override
  String get unknown => 'unknown';

  @override
  String get incomingEncryptedVideoCall => 'Incoming encrypted video call';

  @override
  String get incomingEncryptedVoiceCall => 'Incoming encrypted voice call';

  @override
  String get decline => 'Decline';

  @override
  String get accept => 'Accept';

  @override
  String get unmute => 'Unmute';

  @override
  String get mute => 'Mute';

  @override
  String get cameraOff => 'Camera off';

  @override
  String get cameraOn => 'Camera on';

  @override
  String get earpiece => 'Earpiece';

  @override
  String get speaker => 'Speaker';

  @override
  String get endCall => 'End';

  @override
  String get answeredOtherDevice => 'Answered on another device';

  @override
  String get callUnavailable => 'Call unavailable';

  @override
  String get callEnded => 'Call ended';

  @override
  String get backToChats => 'Back to chats';

  @override
  String get callingSecurely => 'Calling securely…';

  @override
  String get connectingMedia => 'Connecting media…';

  @override
  String get encryptedSignaling => 'End-to-end encrypted signaling';

  @override
  String get endingCall => 'Ending call…';

  @override
  String get emojiAndStickers => 'Emoji & stickers';

  @override
  String get closeExpressions => 'Close emoji and stickers';

  @override
  String get searchExpressions => 'Search expressions';

  @override
  String get emoji => 'Emoji';

  @override
  String get stickers => 'Stickers';

  @override
  String stickerLabel(String label) {
    return '$label sticker';
  }

  @override
  String get noMatchingExpressions => 'No matching expressions';

  @override
  String get saveCopy => 'Save copy';

  @override
  String get viewOnceMessage => 'View-once message';

  @override
  String get viewOnceOpenFailed =>
      'This view-once attachment could not be opened.';

  @override
  String get profileUpdated => 'Profile updated.';

  @override
  String get profileUpdateFailed => 'Profile update failed.';

  @override
  String get allow => 'Allow';

  @override
  String get allowMcpProfileTitle => 'Allow public-profile access?';

  @override
  String get mcpProfileConsentBoundary =>
      'An authenticated app or agent will be able to read your username, display name, status, and profile revision. Chats, messages, attachments, backups, devices, calls, encryption keys, and your avatar remain unavailable. You can revoke access immediately.';

  @override
  String get mcpConsentUpdateFailed =>
      'Could not update public-profile access.';

  @override
  String get mcpConnectionLoadFailed =>
      'Could not load app and agent connection information.';

  @override
  String get connectAiService => 'Connect an AI service';

  @override
  String get mcpConnectionHelp =>
      'Use the endpoint below with a client that supports Streamable HTTP or direct JSON. The client authenticates as this WampApp account using a WAMP-SCRAM access grant.';

  @override
  String get mcpEndpoint => 'MCP endpoint';

  @override
  String get authenticationEndpoint => 'Authentication endpoint';

  @override
  String get mcpEndpointCopied => 'MCP endpoint copied.';

  @override
  String get authEndpointCopied => 'Authentication endpoint copied.';

  @override
  String mcpAccount(String username) {
    return 'Account: @$username';
  }

  @override
  String mcpRealm(String realm) {
    return 'Realm: $realm';
  }

  @override
  String get mcpAuthentication => 'Authentication: WAMP-SCRAM access grant';

  @override
  String get mcpCatalog =>
      'Catalogs: tools, resources, and prompts · Transports: Streamable HTTP and direct JSON';

  @override
  String get allowPublicProfileAccess => 'Allow public-profile access';

  @override
  String get accessEnabled => 'Enabled. Revocation takes effect immediately.';

  @override
  String get accessDisabledByDefault => 'Disabled by default.';

  @override
  String visibleFields(String fields) {
    return 'Visible fields: $fields.';
  }

  @override
  String get mcpDataBoundary =>
      'Chats, messages, attachments, backups, devices, calls, encryption keys, and avatars remain unavailable. WampApp never displays or copies your password, access token, or refresh token.';

  @override
  String get enterRecipientFirst => 'Enter a recipient username first.';

  @override
  String get profileLoadFailed => 'Could not load that profile.';

  @override
  String get publicProfile => 'Public profile';

  @override
  String get noStatusSet => 'No status set';

  @override
  String get encryptedDeviceBackupSaved => 'Encrypted device backup saved.';

  @override
  String get backupCancelled => 'Backup was cancelled.';

  @override
  String get encryptedServerBackupSaved =>
      'Encrypted backup stored on this server.';

  @override
  String get cloudBackupCancelled => 'Server backup was cancelled.';

  @override
  String get encryptedBackup => 'Encrypted backup';

  @override
  String get saveBackupFile => 'Save backup file';

  @override
  String get saveBackupFileSubtitle => 'Keep an encrypted archive yourself.';

  @override
  String get backupToServer => 'Back up to this server';

  @override
  String get backupToServerSubtitle =>
      'The server stores only the encrypted archive.';

  @override
  String get newEncryptedGroup => 'New encrypted group';

  @override
  String get groupName => 'Group name';

  @override
  String get memberUsernames => 'Member usernames';

  @override
  String get separateUsernames => 'Separate usernames with commas';

  @override
  String get createGroup => 'Create group';

  @override
  String get editPublicProfile => 'Edit public profile';

  @override
  String get chooseImage => 'Choose image';

  @override
  String get remove => 'Remove';

  @override
  String get status => 'Status';

  @override
  String get available => 'Available';

  @override
  String get profileVisibilityBoundary =>
      'Your profile is visible to authenticated WampApp members. Message contents and device keys are never included.';

  @override
  String copyLabel(String label) {
    return 'Copy $label';
  }

  @override
  String get online => 'Online';

  @override
  String get encryptedMessages => 'Encrypted messages';

  @override
  String get groupCallsUnavailable => 'Group calls are not available yet';

  @override
  String get startEncryptedVoiceCall => 'Start encrypted voice call';

  @override
  String get startEncryptedVideoCall => 'Start encrypted video call';

  @override
  String get unmuteChat => 'Unmute this chat';

  @override
  String get muteChat => 'Mute this chat';

  @override
  String chatAppearance(String appearance) {
    return 'Chat appearance: $appearance';
  }

  @override
  String get syncMessages => 'Sync messages';

  @override
  String localSearchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Local search · $count results',
      one: 'Local search · 1 result',
    );
    return '$_temp0';
  }

  @override
  String get searchLocalMessages =>
      'Search local messages · stays on this device';

  @override
  String get clearMessageSearch => 'Clear message search';

  @override
  String get direct => 'Direct';

  @override
  String get newGroup => 'New group';

  @override
  String get all => 'All';

  @override
  String get unreadReceived => 'Unread received';

  @override
  String get readReceived => 'Read received';

  @override
  String get startDirectChat => 'Start a direct chat';

  @override
  String get directChat => 'Direct chat';

  @override
  String get closeDirectChat => 'Close direct chat';

  @override
  String get verifyEncryptionIdentity => 'Verify encryption identity';

  @override
  String get viewPublicProfile => 'View public profile';

  @override
  String get groupUnavailable => 'Group unavailable';

  @override
  String get noSearchMessages =>
      'No local messages match this search and filter.';

  @override
  String get noMessages =>
      'No messages yet. Choose a registered account and send the first end-to-end encrypted message.';

  @override
  String get noUnreadMessages =>
      'No unread received messages in this conversation.';

  @override
  String get noReadMessages =>
      'No read received messages in this conversation.';

  @override
  String get viewOnce => 'View once';

  @override
  String get keepChatMessages => 'Keep chat messages';

  @override
  String get deleteAfterOneHour => 'Delete after 1 hour';

  @override
  String get deleteAfterOneDay => 'Delete after 1 day';

  @override
  String get deleteAfterSevenDays => 'Delete after 7 days';

  @override
  String get autoDeleteEnabled => 'Auto-delete enabled';

  @override
  String get appearanceStandard => 'Standard';

  @override
  String get appearanceOcean => 'Ocean';

  @override
  String get appearanceSunset => 'Sunset';

  @override
  String recordingDuration(String duration) {
    return 'Recording $duration';
  }

  @override
  String get cancelVoiceNote => 'Cancel voice note';

  @override
  String get finishVoiceNote => 'Finish voice note';

  @override
  String get openConversationToReply => 'Open a conversation to reply';

  @override
  String get messageGroup => 'Message the group';

  @override
  String get message => 'Message';

  @override
  String get chooseExpression => 'Choose emoji or encrypted sticker';

  @override
  String get attachEncryptedFiles => 'Attach encrypted files';

  @override
  String get sendEncryptedMessage => 'Send encrypted message';

  @override
  String get recordEncryptedVoiceNote => 'Record encrypted voice note';

  @override
  String get sending => 'Sending…';

  @override
  String get sentSyncing => 'Sent · syncing';

  @override
  String get notSent => 'Not sent';

  @override
  String get rejected => 'Rejected';

  @override
  String get messageConflict => 'Message conflict';

  @override
  String get opened => 'Opened';

  @override
  String get readByEveryone => 'Read by everyone';

  @override
  String get read => 'Read';

  @override
  String get deliveredToEveryone => 'Delivered to everyone';

  @override
  String get delivered => 'Delivered';

  @override
  String get sent => 'Sent';

  @override
  String get tapToOpenMarkRead => 'Tap to open · mark read';

  @override
  String get tapToViewOnce => 'Tap to view once';

  @override
  String get discard => 'Discard';

  @override
  String get encrypted => 'encrypted';

  @override
  String get fileDecrypted =>
      'The file was authenticated and decrypted on this device.';

  @override
  String get pauseVoiceNote => 'Pause voice note';

  @override
  String get playVoiceNote => 'Play voice note';

  @override
  String get voiceNoteDecrypted => 'authenticated and decrypted on this device';

  @override
  String get confirmSafetyNumber => 'Confirm safety number';

  @override
  String get compareSafetyNumber =>
      'Only continue after comparing this number with your contact through another trusted channel.';

  @override
  String get numbersMatch => 'Numbers match';

  @override
  String get encryptionIdentity => 'Encryption identity';

  @override
  String encryptionIdentityFor(String username) {
    return 'Encryption identity · @$username';
  }

  @override
  String get trustComparisonHelp =>
      'Compare each active device safety number through another trusted channel. Verification detects later identity changes but does not replace that first comparison.';

  @override
  String get verified => 'Verified';

  @override
  String get verifyDevice => 'Verify device';

  @override
  String get refresh => 'Refresh';

  @override
  String get trustLoadFailed =>
      'Could not load or verify this encryption identity.';

  @override
  String get trustUnverified =>
      'Not verified yet. Messages can be sent, but compare every active device before relying on this identity.';

  @override
  String get trustVerified => 'Every active device is verified.';

  @override
  String get trustChanged =>
      'Encryption identity changed. Sending is blocked until every active device is reviewed and verified.';

  @override
  String get chatMuted => 'Chat muted on this account.';

  @override
  String get chatUnmuted => 'Chat unmuted on this account.';

  @override
  String get chatPreferenceSaveFailed => 'Could not save the chat preference.';

  @override
  String chatAppearanceSaved(String appearance) {
    return '$appearance chat appearance saved on this account.';
  }

  @override
  String get chatAppearanceSaveFailed => 'Could not save the chat appearance.';

  @override
  String get disappearingMessagesDisabled =>
      'Disappearing messages disabled for this chat.';

  @override
  String disappearingMessagesEnabled(String retention) {
    return 'New messages in this chat will $retention.';
  }

  @override
  String get openConversationBeforeSending =>
      'Open a conversation or enter a recipient before sending.';

  @override
  String get attachmentLimit => 'A message can contain up to 8 attachments.';

  @override
  String get attachmentSizeLimit =>
      'Each attachment must be 64 MiB or smaller.';

  @override
  String get attachmentReadFailed => 'The selected files could not be opened.';

  @override
  String get stickerTooLarge =>
      'The rendered sticker exceeds the attachment limits.';

  @override
  String get stickerRenderFailed => 'The sticker could not be rendered.';

  @override
  String get microphoneStartFailed =>
      'The microphone could not start recording.';

  @override
  String get voiceRecordingFailed => 'The voice-note recording failed.';
}

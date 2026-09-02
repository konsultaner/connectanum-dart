import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'WampApp'**
  String get appTitle;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @dataAndStorage.
  ///
  /// In en, this message translates to:
  /// **'Data and storage'**
  String get dataAndStorage;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @contactsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage names saved on this device'**
  String get contactsSubtitle;

  /// No description provided for @staySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Stay signed in with biometrics'**
  String get staySignedIn;

  /// No description provided for @staySignedInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock your saved sign-in with Face ID, Touch ID, or your device biometrics'**
  String get staySignedInSubtitle;

  /// No description provided for @biometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric sign-in is not available on this device.'**
  String get biometricsUnavailable;

  /// No description provided for @biometricPasswordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Confirm your account password to enable biometric sign-in.'**
  String get biometricPasswordPrompt;

  /// No description provided for @signInWithBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Sign in with biometrics'**
  String get signInWithBiometrics;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushNotifications;

  /// No description provided for @pushNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive new-message notifications when WampApp is not open'**
  String get pushNotificationsSubtitle;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Use device setting'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Use device language'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFrench;

  /// No description provided for @languageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get languageItalian;

  /// No description provided for @languagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get languagePortuguese;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @backupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export or restore your encrypted backup'**
  String get backupSubtitle;

  /// No description provided for @serverBackup.
  ///
  /// In en, this message translates to:
  /// **'Server backup'**
  String get serverBackup;

  /// No description provided for @serverBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Store a recovery-phrase encrypted backup on this server'**
  String get serverBackupSubtitle;

  /// No description provided for @mcpAccess.
  ///
  /// In en, this message translates to:
  /// **'App and agent access'**
  String get mcpAccess;

  /// No description provided for @mcpAccessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Control access to your public profile'**
  String get mcpAccessSubtitle;

  /// No description provided for @technicalInformation.
  ///
  /// In en, this message translates to:
  /// **'Technical information'**
  String get technicalInformation;

  /// No description provided for @technicalInformationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connection, encryption, device, and endpoint details'**
  String get technicalInformationSubtitle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @technicalIntro.
  ///
  /// In en, this message translates to:
  /// **'These details help with support and integration. Your chats, passwords, keys, and tokens are never shown here.'**
  String get technicalIntro;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @websocketEndpoint.
  ///
  /// In en, this message translates to:
  /// **'WebSocket endpoint'**
  String get websocketEndpoint;

  /// No description provided for @applicationRealm.
  ///
  /// In en, this message translates to:
  /// **'Application realm'**
  String get applicationRealm;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get device;

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceId;

  /// No description provided for @safetyNumber.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyNumber;

  /// No description provided for @encryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryption;

  /// No description provided for @encryptionSummary.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted messages and attachments; device keys stay in the encrypted local vault.'**
  String get encryptionSummary;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @createAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Create and connect'**
  String get createAndConnect;

  /// No description provided for @connectSecurely.
  ///
  /// In en, this message translates to:
  /// **'Sign in securely'**
  String get connectSecurely;

  /// No description provided for @restoreEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore encrypted backup'**
  String get restoreEncryptedBackup;

  /// No description provided for @restoreBackupFromServer.
  ///
  /// In en, this message translates to:
  /// **'Restore backup from server'**
  String get restoreBackupFromServer;

  /// No description provided for @checkingServer.
  ///
  /// In en, this message translates to:
  /// **'Checking service availability…'**
  String get checkingServer;

  /// No description provided for @serverReady.
  ///
  /// In en, this message translates to:
  /// **'Service is ready.'**
  String get serverReady;

  /// No description provided for @serverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Service unavailable. Check the address and try again.'**
  String get serverUnavailable;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @introHeadline.
  ///
  /// In en, this message translates to:
  /// **'Private conversations that feel effortless.'**
  String get introHeadline;

  /// No description provided for @introBody.
  ///
  /// In en, this message translates to:
  /// **'Message, call, and share with the people who matter. Your conversations stay end-to-end encrypted across your devices.'**
  String get introBody;

  /// No description provided for @privateByDesign.
  ///
  /// In en, this message translates to:
  /// **'Private by design'**
  String get privateByDesign;

  /// No description provided for @realTimeMessaging.
  ///
  /// In en, this message translates to:
  /// **'Real-time messaging'**
  String get realTimeMessaging;

  /// No description provided for @yourOwnAccount.
  ///
  /// In en, this message translates to:
  /// **'Your own account'**
  String get yourOwnAccount;

  /// No description provided for @backupRestoreBoundary.
  ///
  /// In en, this message translates to:
  /// **'Both restore paths recover this account\'s device identity, chats, settings, and attachment keys. The server copy is end-to-end encrypted. Cached media bytes are not included and must be downloaded again.'**
  String get backupRestoreBoundary;

  /// No description provided for @contactPrivacyBoundary.
  ///
  /// In en, this message translates to:
  /// **'Only the selected display name and the WampApp username you enter are saved in this encrypted device vault. Phone numbers, email addresses, contact IDs, and address-book files are never uploaded or retained.'**
  String get contactPrivacyBoundary;

  /// No description provided for @importContacts.
  ///
  /// In en, this message translates to:
  /// **'Import contacts'**
  String get importContacts;

  /// No description provided for @addByUsername.
  ///
  /// In en, this message translates to:
  /// **'Add by username'**
  String get addByUsername;

  /// No description provided for @importedDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Imported display name'**
  String get importedDisplayName;

  /// No description provided for @nameOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Name on this device'**
  String get nameOnDevice;

  /// No description provided for @wampAppUsername.
  ///
  /// In en, this message translates to:
  /// **'WampApp username'**
  String get wampAppUsername;

  /// No description provided for @contactVerifyHelper.
  ///
  /// In en, this message translates to:
  /// **'Verified with the connected server before saving.'**
  String get contactVerifyHelper;

  /// No description provided for @contactRenameHelper.
  ///
  /// In en, this message translates to:
  /// **'The canonical account cannot be changed while renaming.'**
  String get contactRenameHelper;

  /// No description provided for @verifyAndSave.
  ///
  /// In en, this message translates to:
  /// **'Verify and save'**
  String get verifyAndSave;

  /// No description provided for @saveLocalName.
  ///
  /// In en, this message translates to:
  /// **'Save local name'**
  String get saveLocalName;

  /// No description provided for @noContactsSaved.
  ///
  /// In en, this message translates to:
  /// **'No contacts saved on this device.'**
  String get noContactsSaved;

  /// No description provided for @localContacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 local contact} other{{count} local contacts}}'**
  String localContacts(int count);

  /// No description provided for @renameLocalContact.
  ///
  /// In en, this message translates to:
  /// **'Rename local contact'**
  String get renameLocalContact;

  /// No description provided for @removeLocalContact.
  ///
  /// In en, this message translates to:
  /// **'Remove local contact'**
  String get removeLocalContact;

  /// No description provided for @contactReadFailed.
  ///
  /// In en, this message translates to:
  /// **'The selected contact could not be read.'**
  String get contactReadFailed;

  /// No description provided for @encryptDeviceBackup.
  ///
  /// In en, this message translates to:
  /// **'Encrypt device backup'**
  String get encryptDeviceBackup;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackup;

  /// No description provided for @backupCreateHelp.
  ///
  /// In en, this message translates to:
  /// **'This phrase is the only way to decrypt the export. It is not stored or sent to the server.'**
  String get backupCreateHelp;

  /// No description provided for @backupRestoreHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery phrase used when this device backup was created.'**
  String get backupRestoreHelp;

  /// No description provided for @recoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get recoveryPhrase;

  /// No description provided for @confirmRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Confirm recovery phrase'**
  String get confirmRecoveryPhrase;

  /// No description provided for @passphraseLength.
  ///
  /// In en, this message translates to:
  /// **'Use 16 to 1024 UTF-8 bytes.'**
  String get passphraseLength;

  /// No description provided for @passphraseMismatch.
  ///
  /// In en, this message translates to:
  /// **'The recovery phrases do not match.'**
  String get passphraseMismatch;

  /// No description provided for @createBackup.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get createBackup;

  /// No description provided for @chooseBackup.
  ///
  /// In en, this message translates to:
  /// **'Choose backup'**
  String get chooseBackup;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get unknown;

  /// No description provided for @incomingEncryptedVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming encrypted video call'**
  String get incomingEncryptedVideoCall;

  /// No description provided for @incomingEncryptedVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming encrypted voice call'**
  String get incomingEncryptedVoiceCall;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @cameraOff.
  ///
  /// In en, this message translates to:
  /// **'Camera off'**
  String get cameraOff;

  /// No description provided for @cameraOn.
  ///
  /// In en, this message translates to:
  /// **'Camera on'**
  String get cameraOn;

  /// No description provided for @earpiece.
  ///
  /// In en, this message translates to:
  /// **'Earpiece'**
  String get earpiece;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @endCall.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get endCall;

  /// No description provided for @answeredOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'Answered on another device'**
  String get answeredOtherDevice;

  /// No description provided for @callUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Call unavailable'**
  String get callUnavailable;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @backToChats.
  ///
  /// In en, this message translates to:
  /// **'Back to chats'**
  String get backToChats;

  /// No description provided for @callingSecurely.
  ///
  /// In en, this message translates to:
  /// **'Calling securely…'**
  String get callingSecurely;

  /// No description provided for @connectingMedia.
  ///
  /// In en, this message translates to:
  /// **'Connecting media…'**
  String get connectingMedia;

  /// No description provided for @encryptedSignaling.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted signaling'**
  String get encryptedSignaling;

  /// No description provided for @endingCall.
  ///
  /// In en, this message translates to:
  /// **'Ending call…'**
  String get endingCall;

  /// No description provided for @emojiAndStickers.
  ///
  /// In en, this message translates to:
  /// **'Emoji & stickers'**
  String get emojiAndStickers;

  /// No description provided for @closeExpressions.
  ///
  /// In en, this message translates to:
  /// **'Close emoji and stickers'**
  String get closeExpressions;

  /// No description provided for @searchExpressions.
  ///
  /// In en, this message translates to:
  /// **'Search expressions'**
  String get searchExpressions;

  /// No description provided for @emoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emoji;

  /// No description provided for @stickers.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get stickers;

  /// No description provided for @stickerLabel.
  ///
  /// In en, this message translates to:
  /// **'{label} sticker'**
  String stickerLabel(String label);

  /// No description provided for @noMatchingExpressions.
  ///
  /// In en, this message translates to:
  /// **'No matching expressions'**
  String get noMatchingExpressions;

  /// No description provided for @saveCopy.
  ///
  /// In en, this message translates to:
  /// **'Save copy'**
  String get saveCopy;

  /// No description provided for @viewOnceMessage.
  ///
  /// In en, this message translates to:
  /// **'View-once message'**
  String get viewOnceMessage;

  /// No description provided for @viewOnceOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'This view-once attachment could not be opened.'**
  String get viewOnceOpenFailed;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated.'**
  String get profileUpdated;

  /// No description provided for @profileUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Profile update failed.'**
  String get profileUpdateFailed;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @allowMcpProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow public-profile access?'**
  String get allowMcpProfileTitle;

  /// No description provided for @mcpProfileConsentBoundary.
  ///
  /// In en, this message translates to:
  /// **'An authenticated app or agent will be able to read your username, display name, status, and profile revision. Chats, messages, attachments, backups, devices, calls, encryption keys, and your avatar remain unavailable. You can revoke access immediately.'**
  String get mcpProfileConsentBoundary;

  /// No description provided for @mcpConsentUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update public-profile access.'**
  String get mcpConsentUpdateFailed;

  /// No description provided for @mcpConnectionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load app and agent connection information.'**
  String get mcpConnectionLoadFailed;

  /// No description provided for @connectAiService.
  ///
  /// In en, this message translates to:
  /// **'Connect an AI service'**
  String get connectAiService;

  /// No description provided for @mcpConnectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Use the endpoint below with a client that supports Streamable HTTP or direct JSON. The client authenticates as this WampApp account using a WAMP-SCRAM access grant.'**
  String get mcpConnectionHelp;

  /// No description provided for @mcpEndpoint.
  ///
  /// In en, this message translates to:
  /// **'MCP endpoint'**
  String get mcpEndpoint;

  /// No description provided for @authenticationEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Authentication endpoint'**
  String get authenticationEndpoint;

  /// No description provided for @mcpEndpointCopied.
  ///
  /// In en, this message translates to:
  /// **'MCP endpoint copied.'**
  String get mcpEndpointCopied;

  /// No description provided for @authEndpointCopied.
  ///
  /// In en, this message translates to:
  /// **'Authentication endpoint copied.'**
  String get authEndpointCopied;

  /// No description provided for @mcpAccount.
  ///
  /// In en, this message translates to:
  /// **'Account: @{username}'**
  String mcpAccount(String username);

  /// No description provided for @mcpRealm.
  ///
  /// In en, this message translates to:
  /// **'Realm: {realm}'**
  String mcpRealm(String realm);

  /// No description provided for @mcpAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication: WAMP-SCRAM access grant'**
  String get mcpAuthentication;

  /// No description provided for @mcpCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalogs: tools, resources, and prompts · Transports: Streamable HTTP and direct JSON'**
  String get mcpCatalog;

  /// No description provided for @allowPublicProfileAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow public-profile access'**
  String get allowPublicProfileAccess;

  /// No description provided for @accessEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled. Revocation takes effect immediately.'**
  String get accessEnabled;

  /// No description provided for @accessDisabledByDefault.
  ///
  /// In en, this message translates to:
  /// **'Disabled by default.'**
  String get accessDisabledByDefault;

  /// No description provided for @visibleFields.
  ///
  /// In en, this message translates to:
  /// **'Visible fields: {fields}.'**
  String visibleFields(String fields);

  /// No description provided for @mcpDataBoundary.
  ///
  /// In en, this message translates to:
  /// **'Chats, messages, attachments, backups, devices, calls, encryption keys, and avatars remain unavailable. WampApp never displays or copies your password, access token, or refresh token.'**
  String get mcpDataBoundary;

  /// No description provided for @enterRecipientFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter a recipient username first.'**
  String get enterRecipientFirst;

  /// No description provided for @profileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load that profile.'**
  String get profileLoadFailed;

  /// No description provided for @publicProfile.
  ///
  /// In en, this message translates to:
  /// **'Public profile'**
  String get publicProfile;

  /// No description provided for @noStatusSet.
  ///
  /// In en, this message translates to:
  /// **'No status set'**
  String get noStatusSet;

  /// No description provided for @encryptedDeviceBackupSaved.
  ///
  /// In en, this message translates to:
  /// **'Encrypted device backup saved.'**
  String get encryptedDeviceBackupSaved;

  /// No description provided for @backupCancelled.
  ///
  /// In en, this message translates to:
  /// **'Backup was cancelled.'**
  String get backupCancelled;

  /// No description provided for @encryptedServerBackupSaved.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup stored on this server.'**
  String get encryptedServerBackupSaved;

  /// No description provided for @cloudBackupCancelled.
  ///
  /// In en, this message translates to:
  /// **'Server backup was cancelled.'**
  String get cloudBackupCancelled;

  /// No description provided for @encryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup'**
  String get encryptedBackup;

  /// No description provided for @saveBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Save backup file'**
  String get saveBackupFile;

  /// No description provided for @saveBackupFileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep an encrypted archive yourself.'**
  String get saveBackupFileSubtitle;

  /// No description provided for @backupToServer.
  ///
  /// In en, this message translates to:
  /// **'Back up to this server'**
  String get backupToServer;

  /// No description provided for @backupToServerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The server stores only the encrypted archive.'**
  String get backupToServerSubtitle;

  /// No description provided for @newEncryptedGroup.
  ///
  /// In en, this message translates to:
  /// **'New encrypted group'**
  String get newEncryptedGroup;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @memberUsernames.
  ///
  /// In en, this message translates to:
  /// **'Member usernames'**
  String get memberUsernames;

  /// No description provided for @separateUsernames.
  ///
  /// In en, this message translates to:
  /// **'Separate usernames with commas'**
  String get separateUsernames;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @editPublicProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit public profile'**
  String get editPublicProfile;

  /// No description provided for @chooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get chooseImage;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @profileVisibilityBoundary.
  ///
  /// In en, this message translates to:
  /// **'Your profile is visible to authenticated WampApp members. Message contents and device keys are never included.'**
  String get profileVisibilityBoundary;

  /// No description provided for @copyLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String copyLabel(String label);

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @encryptedMessages.
  ///
  /// In en, this message translates to:
  /// **'Encrypted messages'**
  String get encryptedMessages;

  /// No description provided for @groupCallsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Group calls are not available yet'**
  String get groupCallsUnavailable;

  /// No description provided for @startEncryptedVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'Start encrypted voice call'**
  String get startEncryptedVoiceCall;

  /// No description provided for @startEncryptedVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Start encrypted video call'**
  String get startEncryptedVideoCall;

  /// No description provided for @unmuteChat.
  ///
  /// In en, this message translates to:
  /// **'Unmute this chat'**
  String get unmuteChat;

  /// No description provided for @muteChat.
  ///
  /// In en, this message translates to:
  /// **'Mute this chat'**
  String get muteChat;

  /// No description provided for @chatAppearance.
  ///
  /// In en, this message translates to:
  /// **'Chat appearance: {appearance}'**
  String chatAppearance(String appearance);

  /// No description provided for @syncMessages.
  ///
  /// In en, this message translates to:
  /// **'Sync messages'**
  String get syncMessages;

  /// No description provided for @localSearchResults.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Local search · 1 result} other{Local search · {count} results}}'**
  String localSearchResults(int count);

  /// No description provided for @searchLocalMessages.
  ///
  /// In en, this message translates to:
  /// **'Search local messages · stays on this device'**
  String get searchLocalMessages;

  /// No description provided for @clearMessageSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear message search'**
  String get clearMessageSearch;

  /// No description provided for @direct.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get direct;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @unreadReceived.
  ///
  /// In en, this message translates to:
  /// **'Unread received'**
  String get unreadReceived;

  /// No description provided for @readReceived.
  ///
  /// In en, this message translates to:
  /// **'Read received'**
  String get readReceived;

  /// No description provided for @startDirectChat.
  ///
  /// In en, this message translates to:
  /// **'Start a direct chat'**
  String get startDirectChat;

  /// No description provided for @directChat.
  ///
  /// In en, this message translates to:
  /// **'Direct chat'**
  String get directChat;

  /// No description provided for @closeDirectChat.
  ///
  /// In en, this message translates to:
  /// **'Close direct chat'**
  String get closeDirectChat;

  /// No description provided for @verifyEncryptionIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify encryption identity'**
  String get verifyEncryptionIdentity;

  /// No description provided for @viewPublicProfile.
  ///
  /// In en, this message translates to:
  /// **'View public profile'**
  String get viewPublicProfile;

  /// No description provided for @groupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Group unavailable'**
  String get groupUnavailable;

  /// No description provided for @noSearchMessages.
  ///
  /// In en, this message translates to:
  /// **'No local messages match this search and filter.'**
  String get noSearchMessages;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Choose a registered account and send the first end-to-end encrypted message.'**
  String get noMessages;

  /// No description provided for @noUnreadMessages.
  ///
  /// In en, this message translates to:
  /// **'No unread received messages in this conversation.'**
  String get noUnreadMessages;

  /// No description provided for @noReadMessages.
  ///
  /// In en, this message translates to:
  /// **'No read received messages in this conversation.'**
  String get noReadMessages;

  /// No description provided for @viewOnce.
  ///
  /// In en, this message translates to:
  /// **'View once'**
  String get viewOnce;

  /// No description provided for @keepChatMessages.
  ///
  /// In en, this message translates to:
  /// **'Keep chat messages'**
  String get keepChatMessages;

  /// No description provided for @deleteAfterOneHour.
  ///
  /// In en, this message translates to:
  /// **'Delete after 1 hour'**
  String get deleteAfterOneHour;

  /// No description provided for @deleteAfterOneDay.
  ///
  /// In en, this message translates to:
  /// **'Delete after 1 day'**
  String get deleteAfterOneDay;

  /// No description provided for @deleteAfterSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Delete after 7 days'**
  String get deleteAfterSevenDays;

  /// No description provided for @autoDeleteEnabled.
  ///
  /// In en, this message translates to:
  /// **'Auto-delete enabled'**
  String get autoDeleteEnabled;

  /// No description provided for @appearanceStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get appearanceStandard;

  /// No description provided for @appearanceOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get appearanceOcean;

  /// No description provided for @appearanceSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get appearanceSunset;

  /// No description provided for @recordingDuration.
  ///
  /// In en, this message translates to:
  /// **'Recording {duration}'**
  String recordingDuration(String duration);

  /// No description provided for @cancelVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Cancel voice note'**
  String get cancelVoiceNote;

  /// No description provided for @finishVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Finish voice note'**
  String get finishVoiceNote;

  /// No description provided for @openConversationToReply.
  ///
  /// In en, this message translates to:
  /// **'Open a conversation to reply'**
  String get openConversationToReply;

  /// No description provided for @messageGroup.
  ///
  /// In en, this message translates to:
  /// **'Message the group'**
  String get messageGroup;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @chooseExpression.
  ///
  /// In en, this message translates to:
  /// **'Choose emoji or encrypted sticker'**
  String get chooseExpression;

  /// No description provided for @attachEncryptedFiles.
  ///
  /// In en, this message translates to:
  /// **'Attach encrypted files'**
  String get attachEncryptedFiles;

  /// No description provided for @sendEncryptedMessage.
  ///
  /// In en, this message translates to:
  /// **'Send encrypted message'**
  String get sendEncryptedMessage;

  /// No description provided for @recordEncryptedVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Record encrypted voice note'**
  String get recordEncryptedVoiceNote;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @sentSyncing.
  ///
  /// In en, this message translates to:
  /// **'Sent · syncing'**
  String get sentSyncing;

  /// No description provided for @notSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get notSent;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @messageConflict.
  ///
  /// In en, this message translates to:
  /// **'Message conflict'**
  String get messageConflict;

  /// No description provided for @opened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get opened;

  /// No description provided for @readByEveryone.
  ///
  /// In en, this message translates to:
  /// **'Read by everyone'**
  String get readByEveryone;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @deliveredToEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delivered to everyone'**
  String get deliveredToEveryone;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @tapToOpenMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Tap to open · mark read'**
  String get tapToOpenMarkRead;

  /// No description provided for @tapToViewOnce.
  ///
  /// In en, this message translates to:
  /// **'Tap to view once'**
  String get tapToViewOnce;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @encrypted.
  ///
  /// In en, this message translates to:
  /// **'encrypted'**
  String get encrypted;

  /// No description provided for @fileDecrypted.
  ///
  /// In en, this message translates to:
  /// **'The file was authenticated and decrypted on this device.'**
  String get fileDecrypted;

  /// No description provided for @pauseVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Pause voice note'**
  String get pauseVoiceNote;

  /// No description provided for @playVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Play voice note'**
  String get playVoiceNote;

  /// No description provided for @voiceNoteDecrypted.
  ///
  /// In en, this message translates to:
  /// **'authenticated and decrypted on this device'**
  String get voiceNoteDecrypted;

  /// No description provided for @confirmSafetyNumber.
  ///
  /// In en, this message translates to:
  /// **'Confirm safety number'**
  String get confirmSafetyNumber;

  /// No description provided for @compareSafetyNumber.
  ///
  /// In en, this message translates to:
  /// **'Only continue after comparing this number with your contact through another trusted channel.'**
  String get compareSafetyNumber;

  /// No description provided for @numbersMatch.
  ///
  /// In en, this message translates to:
  /// **'Numbers match'**
  String get numbersMatch;

  /// No description provided for @encryptionIdentity.
  ///
  /// In en, this message translates to:
  /// **'Encryption identity'**
  String get encryptionIdentity;

  /// No description provided for @encryptionIdentityFor.
  ///
  /// In en, this message translates to:
  /// **'Encryption identity · @{username}'**
  String encryptionIdentityFor(String username);

  /// No description provided for @trustComparisonHelp.
  ///
  /// In en, this message translates to:
  /// **'Compare each active device safety number through another trusted channel. Verification detects later identity changes but does not replace that first comparison.'**
  String get trustComparisonHelp;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @verifyDevice.
  ///
  /// In en, this message translates to:
  /// **'Verify device'**
  String get verifyDevice;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @trustLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load or verify this encryption identity.'**
  String get trustLoadFailed;

  /// No description provided for @trustUnverified.
  ///
  /// In en, this message translates to:
  /// **'Not verified yet. Messages can be sent, but compare every active device before relying on this identity.'**
  String get trustUnverified;

  /// No description provided for @trustVerified.
  ///
  /// In en, this message translates to:
  /// **'Every active device is verified.'**
  String get trustVerified;

  /// No description provided for @trustChanged.
  ///
  /// In en, this message translates to:
  /// **'Encryption identity changed. Sending is blocked until every active device is reviewed and verified.'**
  String get trustChanged;

  /// No description provided for @chatMuted.
  ///
  /// In en, this message translates to:
  /// **'Chat muted on this account.'**
  String get chatMuted;

  /// No description provided for @chatUnmuted.
  ///
  /// In en, this message translates to:
  /// **'Chat unmuted on this account.'**
  String get chatUnmuted;

  /// No description provided for @chatPreferenceSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the chat preference.'**
  String get chatPreferenceSaveFailed;

  /// No description provided for @chatAppearanceSaved.
  ///
  /// In en, this message translates to:
  /// **'{appearance} chat appearance saved on this account.'**
  String chatAppearanceSaved(String appearance);

  /// No description provided for @chatAppearanceSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the chat appearance.'**
  String get chatAppearanceSaveFailed;

  /// No description provided for @disappearingMessagesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages disabled for this chat.'**
  String get disappearingMessagesDisabled;

  /// No description provided for @disappearingMessagesEnabled.
  ///
  /// In en, this message translates to:
  /// **'New messages in this chat will {retention}.'**
  String disappearingMessagesEnabled(String retention);

  /// No description provided for @openConversationBeforeSending.
  ///
  /// In en, this message translates to:
  /// **'Open a conversation or enter a recipient before sending.'**
  String get openConversationBeforeSending;

  /// No description provided for @attachmentLimit.
  ///
  /// In en, this message translates to:
  /// **'A message can contain up to 8 attachments.'**
  String get attachmentLimit;

  /// No description provided for @attachmentSizeLimit.
  ///
  /// In en, this message translates to:
  /// **'Each attachment must be 64 MiB or smaller.'**
  String get attachmentSizeLimit;

  /// No description provided for @attachmentReadFailed.
  ///
  /// In en, this message translates to:
  /// **'The selected files could not be opened.'**
  String get attachmentReadFailed;

  /// No description provided for @stickerTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The rendered sticker exceeds the attachment limits.'**
  String get stickerTooLarge;

  /// No description provided for @stickerRenderFailed.
  ///
  /// In en, this message translates to:
  /// **'The sticker could not be rendered.'**
  String get stickerRenderFailed;

  /// No description provided for @microphoneStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The microphone could not start recording.'**
  String get microphoneStartFailed;

  /// No description provided for @voiceRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'The voice-note recording failed.'**
  String get voiceRecordingFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

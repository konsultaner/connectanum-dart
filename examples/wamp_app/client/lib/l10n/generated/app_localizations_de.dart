// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'WampApp';

  @override
  String get chats => 'Chats';

  @override
  String get settings => 'Einstellungen';

  @override
  String get account => 'Konto';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get appearance => 'Darstellung';

  @override
  String get dataAndStorage => 'Daten und Speicher';

  @override
  String get advanced => 'Erweitert';

  @override
  String get editProfile => 'Profil bearbeiten';

  @override
  String get contacts => 'Kontakte';

  @override
  String get contactsSubtitle =>
      'Auf diesem Gerät gespeicherte Namen verwalten';

  @override
  String get staySignedIn => 'Mit Biometrie angemeldet bleiben';

  @override
  String get staySignedInSubtitle =>
      'Gespeicherte Anmeldung mit Face ID, Touch ID oder Gerätebiometrie entsperren';

  @override
  String get biometricsUnavailable =>
      'Biometrische Anmeldung ist auf diesem Gerät nicht verfügbar.';

  @override
  String get biometricPasswordPrompt =>
      'Bestätige dein Kontopasswort, um die biometrische Anmeldung zu aktivieren.';

  @override
  String get signInWithBiometrics => 'Mit Biometrie anmelden';

  @override
  String get pushNotifications => 'Push-Benachrichtigungen';

  @override
  String get pushNotificationsSubtitle =>
      'Benachrichtigungen über neue Nachrichten erhalten, wenn WampApp nicht geöffnet ist';

  @override
  String get theme => 'Design';

  @override
  String get themeSystem => 'Geräteeinstellung verwenden';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get language => 'Sprache';

  @override
  String get languageSystem => 'Gerätesprache verwenden';

  @override
  String get languageEnglish => 'Englisch';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageSpanish => 'Spanisch';

  @override
  String get languageFrench => 'Französisch';

  @override
  String get languageItalian => 'Italienisch';

  @override
  String get languagePortuguese => 'Portugiesisch';

  @override
  String get backup => 'Sicherung';

  @override
  String get backupSubtitle =>
      'Verschlüsselte Sicherung exportieren oder wiederherstellen';

  @override
  String get serverBackup => 'Server-Sicherung';

  @override
  String get serverBackupSubtitle =>
      'Mit Wiederherstellungsphrase verschlüsselte Sicherung auf diesem Server speichern';

  @override
  String get mcpAccess => 'App- und Agentenzugriff';

  @override
  String get mcpAccessSubtitle =>
      'Zugriff auf dein öffentliches Profil steuern';

  @override
  String get technicalInformation => 'Technische Informationen';

  @override
  String get technicalInformationSubtitle =>
      'Verbindung, Verschlüsselung, Gerät und Endpunkte';

  @override
  String get signOut => 'Abmelden';

  @override
  String get technicalIntro =>
      'Diese Angaben helfen bei Support und Integration. Chats, Passwörter, Schlüssel und Tokens werden hier nie angezeigt.';

  @override
  String get connection => 'Verbindung';

  @override
  String get connected => 'Verbunden';

  @override
  String get server => 'Server';

  @override
  String get websocketEndpoint => 'WebSocket-Endpunkt';

  @override
  String get applicationRealm => 'Anwendungs-Realm';

  @override
  String get username => 'Benutzername';

  @override
  String get device => 'Gerät';

  @override
  String get deviceId => 'Geräte-ID';

  @override
  String get safetyNumber => 'Sicherheitsnummer';

  @override
  String get encryption => 'Verschlüsselung';

  @override
  String get encryptionSummary =>
      'Nachrichten und Anhänge sind Ende-zu-Ende verschlüsselt; Geräteschlüssel bleiben im verschlüsselten lokalen Tresor.';

  @override
  String get copy => 'Kopieren';

  @override
  String get copied => 'In die Zwischenablage kopiert';

  @override
  String get close => 'Schließen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get enable => 'Aktivieren';

  @override
  String get disable => 'Deaktivieren';

  @override
  String get save => 'Speichern';

  @override
  String get password => 'Passwort';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get signIn => 'Anmelden';

  @override
  String get serverAddress => 'Serveradresse';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get createAndConnect => 'Konto erstellen';

  @override
  String get connectSecurely => 'Sicher anmelden';

  @override
  String get restoreEncryptedBackup =>
      'Verschlüsselte Sicherung wiederherstellen';

  @override
  String get restoreBackupFromServer => 'Sicherung vom Server wiederherstellen';

  @override
  String get checkingServer => 'Dienstverfügbarkeit wird geprüft…';

  @override
  String get serverReady => 'Der Dienst ist bereit.';

  @override
  String get serverUnavailable =>
      'Dienst nicht erreichbar. Adresse prüfen und erneut versuchen.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get introHeadline => 'Private Gespräche, ganz unkompliziert.';

  @override
  String get introBody =>
      'Schreibe, telefoniere und teile mit wichtigen Menschen. Deine Gespräche bleiben auf allen Geräten Ende-zu-Ende verschlüsselt.';

  @override
  String get privateByDesign => 'Privat von Grund auf';

  @override
  String get realTimeMessaging => 'Nachrichten in Echtzeit';

  @override
  String get yourOwnAccount => 'Dein eigenes Konto';

  @override
  String get backupRestoreBoundary =>
      'Beide Wiederherstellungswege stellen die Geräteidentität, Chats, Einstellungen und Anhangsschlüssel dieses Kontos wieder her. Die Serverkopie ist Ende-zu-Ende verschlüsselt. Zwischengespeicherte Mediendaten sind nicht enthalten und müssen erneut heruntergeladen werden.';

  @override
  String get contactPrivacyBoundary =>
      'Nur der ausgewählte Anzeigename und der eingegebene WampApp-Benutzername werden im verschlüsselten Gerätespeicher gesichert. Telefonnummern, E-Mail-Adressen, Kontakt-IDs und Adressbuchdateien werden nie hochgeladen oder gespeichert.';

  @override
  String get importContacts => 'Kontakte importieren';

  @override
  String get addByUsername => 'Per Benutzername hinzufügen';

  @override
  String get importedDisplayName => 'Importierter Anzeigename';

  @override
  String get nameOnDevice => 'Name auf diesem Gerät';

  @override
  String get wampAppUsername => 'WampApp-Benutzername';

  @override
  String get contactVerifyHelper =>
      'Wird vor dem Speichern mit dem verbundenen Server geprüft.';

  @override
  String get contactRenameHelper =>
      'Das zugehörige Konto kann beim Umbenennen nicht geändert werden.';

  @override
  String get verifyAndSave => 'Prüfen und speichern';

  @override
  String get saveLocalName => 'Lokalen Namen speichern';

  @override
  String get noContactsSaved => 'Keine Kontakte auf diesem Gerät gespeichert.';

  @override
  String localContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lokale Kontakte',
      one: '1 lokaler Kontakt',
    );
    return '$_temp0';
  }

  @override
  String get renameLocalContact => 'Lokalen Kontakt umbenennen';

  @override
  String get removeLocalContact => 'Lokalen Kontakt entfernen';

  @override
  String get contactReadFailed =>
      'Der ausgewählte Kontakt konnte nicht gelesen werden.';

  @override
  String get encryptDeviceBackup => 'Gerätesicherung verschlüsseln';

  @override
  String get restoreBackup => 'Sicherung wiederherstellen';

  @override
  String get backupCreateHelp =>
      'Nur mit dieser Phrase kann der Export entschlüsselt werden. Sie wird weder gespeichert noch an den Server gesendet.';

  @override
  String get backupRestoreHelp =>
      'Gib die Wiederherstellungsphrase ein, mit der diese Gerätesicherung erstellt wurde.';

  @override
  String get recoveryPhrase => 'Wiederherstellungsphrase';

  @override
  String get confirmRecoveryPhrase => 'Wiederherstellungsphrase bestätigen';

  @override
  String get passphraseLength => 'Verwende 16 bis 1024 UTF-8-Bytes.';

  @override
  String get passphraseMismatch =>
      'Die Wiederherstellungsphrasen stimmen nicht überein.';

  @override
  String get createBackup => 'Sicherung erstellen';

  @override
  String get chooseBackup => 'Sicherung auswählen';

  @override
  String get unknown => 'unbekannt';

  @override
  String get incomingEncryptedVideoCall =>
      'Eingehender verschlüsselter Videoanruf';

  @override
  String get incomingEncryptedVoiceCall =>
      'Eingehender verschlüsselter Sprachanruf';

  @override
  String get decline => 'Ablehnen';

  @override
  String get accept => 'Annehmen';

  @override
  String get unmute => 'Stummschaltung aufheben';

  @override
  String get mute => 'Stummschalten';

  @override
  String get cameraOff => 'Kamera aus';

  @override
  String get cameraOn => 'Kamera an';

  @override
  String get earpiece => 'Hörer';

  @override
  String get speaker => 'Lautsprecher';

  @override
  String get endCall => 'Beenden';

  @override
  String get answeredOtherDevice => 'Auf einem anderen Gerät angenommen';

  @override
  String get callUnavailable => 'Anruf nicht verfügbar';

  @override
  String get callEnded => 'Anruf beendet';

  @override
  String get backToChats => 'Zurück zu Chats';

  @override
  String get callingSecurely => 'Sicherer Anruf…';

  @override
  String get connectingMedia => 'Medien werden verbunden…';

  @override
  String get encryptedSignaling => 'Ende-zu-Ende verschlüsselte Signalisierung';

  @override
  String get endingCall => 'Anruf wird beendet…';

  @override
  String get emojiAndStickers => 'Emojis und Sticker';

  @override
  String get closeExpressions => 'Emojis und Sticker schließen';

  @override
  String get searchExpressions => 'Emojis und Sticker suchen';

  @override
  String get emoji => 'Emojis';

  @override
  String get stickers => 'Sticker';

  @override
  String stickerLabel(String label) {
    return 'Sticker $label';
  }

  @override
  String get noMatchingExpressions => 'Keine passenden Inhalte';

  @override
  String get saveCopy => 'Kopie speichern';

  @override
  String get viewOnceMessage => 'Einmalansicht-Nachricht';

  @override
  String get viewOnceOpenFailed =>
      'Dieser Einmalansicht-Anhang konnte nicht geöffnet werden.';

  @override
  String get profileUpdated => 'Profil aktualisiert.';

  @override
  String get profileUpdateFailed => 'Profil konnte nicht aktualisiert werden.';

  @override
  String get allow => 'Erlauben';

  @override
  String get allowMcpProfileTitle =>
      'Zugriff auf öffentliches Profil erlauben?';

  @override
  String get mcpProfileConsentBoundary =>
      'Eine authentifizierte App oder ein Agent kann deinen Benutzernamen, Anzeigenamen, Status und die Profilrevision lesen. Chats, Nachrichten, Anhänge, Sicherungen, Geräte, Anrufe, Schlüssel und Avatar bleiben unzugänglich. Du kannst den Zugriff sofort widerrufen.';

  @override
  String get mcpConsentUpdateFailed =>
      'Der Zugriff auf das öffentliche Profil konnte nicht aktualisiert werden.';

  @override
  String get mcpConnectionLoadFailed =>
      'Verbindungsinformationen für Apps und Agenten konnten nicht geladen werden.';

  @override
  String get connectAiService => 'KI-Dienst verbinden';

  @override
  String get mcpConnectionHelp =>
      'Verwende den folgenden Endpunkt mit einem Client, der Streamable HTTP oder direktes JSON unterstützt. Der Client authentifiziert sich als dieses WampApp-Konto mit einer WAMP-SCRAM-Zugriffsfreigabe.';

  @override
  String get mcpEndpoint => 'MCP-Endpunkt';

  @override
  String get authenticationEndpoint => 'Authentifizierungsendpunkt';

  @override
  String get mcpEndpointCopied => 'MCP-Endpunkt kopiert.';

  @override
  String get authEndpointCopied => 'Authentifizierungsendpunkt kopiert.';

  @override
  String mcpAccount(String username) {
    return 'Konto: @$username';
  }

  @override
  String mcpRealm(String realm) {
    return 'Realm: $realm';
  }

  @override
  String get mcpAuthentication =>
      'Authentifizierung: WAMP-SCRAM-Zugriffsfreigabe';

  @override
  String get mcpCatalog =>
      'Kataloge: Tools, Ressourcen und Prompts · Transporte: Streamable HTTP und direktes JSON';

  @override
  String get allowPublicProfileAccess =>
      'Zugriff auf öffentliches Profil erlauben';

  @override
  String get accessEnabled => 'Aktiviert. Ein Widerruf wirkt sofort.';

  @override
  String get accessDisabledByDefault => 'Standardmäßig deaktiviert.';

  @override
  String visibleFields(String fields) {
    return 'Sichtbare Felder: $fields.';
  }

  @override
  String get mcpDataBoundary =>
      'Chats, Nachrichten, Anhänge, Sicherungen, Geräte, Anrufe, Schlüssel und Avatare bleiben unzugänglich. WampApp zeigt oder kopiert niemals dein Passwort, Zugriffs- oder Aktualisierungstoken.';

  @override
  String get enterRecipientFirst =>
      'Gib zuerst einen Empfänger-Benutzernamen ein.';

  @override
  String get profileLoadFailed => 'Dieses Profil konnte nicht geladen werden.';

  @override
  String get publicProfile => 'Öffentliches Profil';

  @override
  String get noStatusSet => 'Kein Status festgelegt';

  @override
  String get encryptedDeviceBackupSaved =>
      'Verschlüsselte Gerätesicherung gespeichert.';

  @override
  String get backupCancelled => 'Sicherung wurde abgebrochen.';

  @override
  String get encryptedServerBackupSaved =>
      'Verschlüsselte Sicherung auf diesem Server gespeichert.';

  @override
  String get cloudBackupCancelled => 'Server-Sicherung wurde abgebrochen.';

  @override
  String get encryptedBackup => 'Verschlüsselte Sicherung';

  @override
  String get saveBackupFile => 'Sicherungsdatei speichern';

  @override
  String get saveBackupFileSubtitle =>
      'Bewahre selbst ein verschlüsseltes Archiv auf.';

  @override
  String get backupToServer => 'Auf diesem Server sichern';

  @override
  String get backupToServerSubtitle =>
      'Der Server speichert nur das verschlüsselte Archiv.';

  @override
  String get newEncryptedGroup => 'Neue verschlüsselte Gruppe';

  @override
  String get groupName => 'Gruppenname';

  @override
  String get memberUsernames => 'Benutzernamen der Mitglieder';

  @override
  String get separateUsernames => 'Benutzernamen mit Kommas trennen';

  @override
  String get createGroup => 'Gruppe erstellen';

  @override
  String get editPublicProfile => 'Öffentliches Profil bearbeiten';

  @override
  String get chooseImage => 'Bild auswählen';

  @override
  String get remove => 'Entfernen';

  @override
  String get status => 'Status';

  @override
  String get available => 'Verfügbar';

  @override
  String get profileVisibilityBoundary =>
      'Dein Profil ist für authentifizierte WampApp-Mitglieder sichtbar. Nachrichteninhalte und Geräteschlüssel sind nie enthalten.';

  @override
  String copyLabel(String label) {
    return '$label kopieren';
  }

  @override
  String get online => 'Online';

  @override
  String get encryptedMessages => 'Verschlüsselte Nachrichten';

  @override
  String get groupCallsUnavailable => 'Gruppenanrufe sind noch nicht verfügbar';

  @override
  String get startEncryptedVoiceCall => 'Verschlüsselten Sprachanruf starten';

  @override
  String get startEncryptedVideoCall => 'Verschlüsselten Videoanruf starten';

  @override
  String get unmuteChat => 'Benachrichtigungen für diesen Chat aktivieren';

  @override
  String get muteChat => 'Diesen Chat stummschalten';

  @override
  String chatAppearance(String appearance) {
    return 'Chat-Darstellung: $appearance';
  }

  @override
  String get syncMessages => 'Nachrichten synchronisieren';

  @override
  String localSearchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lokale Suche · $count Ergebnisse',
      one: 'Lokale Suche · 1 Ergebnis',
    );
    return '$_temp0';
  }

  @override
  String get searchLocalMessages =>
      'Lokale Nachrichten durchsuchen · bleibt auf diesem Gerät';

  @override
  String get clearMessageSearch => 'Nachrichtensuche leeren';

  @override
  String get direct => 'Direkt';

  @override
  String get newGroup => 'Neue Gruppe';

  @override
  String get all => 'Alle';

  @override
  String get unreadReceived => 'Ungelesen empfangen';

  @override
  String get readReceived => 'Gelesen empfangen';

  @override
  String get startDirectChat => 'Direkten Chat beginnen';

  @override
  String get directChat => 'Direkter Chat';

  @override
  String get closeDirectChat => 'Direkten Chat schließen';

  @override
  String get verifyEncryptionIdentity => 'Verschlüsselungsidentität prüfen';

  @override
  String get viewPublicProfile => 'Öffentliches Profil ansehen';

  @override
  String get groupUnavailable => 'Gruppe nicht verfügbar';

  @override
  String get noSearchMessages =>
      'Keine lokalen Nachrichten entsprechen dieser Suche und dem Filter.';

  @override
  String get noMessages =>
      'Noch keine Nachrichten. Wähle ein registriertes Konto und sende die erste Ende-zu-Ende verschlüsselte Nachricht.';

  @override
  String get noUnreadMessages =>
      'Keine ungelesenen empfangenen Nachrichten in diesem Chat.';

  @override
  String get noReadMessages =>
      'Keine gelesenen empfangenen Nachrichten in diesem Chat.';

  @override
  String get viewOnce => 'Einmal ansehen';

  @override
  String get keepChatMessages => 'Chatnachrichten behalten';

  @override
  String get deleteAfterOneHour => 'Nach 1 Stunde löschen';

  @override
  String get deleteAfterOneDay => 'Nach 1 Tag löschen';

  @override
  String get deleteAfterSevenDays => 'Nach 7 Tagen löschen';

  @override
  String get autoDeleteEnabled => 'Automatisches Löschen aktiviert';

  @override
  String get appearanceStandard => 'Standard';

  @override
  String get appearanceOcean => 'Ozean';

  @override
  String get appearanceSunset => 'Sonnenuntergang';

  @override
  String recordingDuration(String duration) {
    return 'Aufnahme $duration';
  }

  @override
  String get cancelVoiceNote => 'Sprachnachricht verwerfen';

  @override
  String get finishVoiceNote => 'Sprachnachricht beenden';

  @override
  String get openConversationToReply => 'Öffne einen Chat, um zu antworten';

  @override
  String get messageGroup => 'Nachricht an die Gruppe';

  @override
  String get message => 'Nachricht';

  @override
  String get chooseExpression => 'Emoji oder verschlüsselten Sticker auswählen';

  @override
  String get attachEncryptedFiles => 'Verschlüsselte Dateien anhängen';

  @override
  String get sendEncryptedMessage => 'Verschlüsselte Nachricht senden';

  @override
  String get recordEncryptedVoiceNote =>
      'Verschlüsselte Sprachnachricht aufnehmen';

  @override
  String get sending => 'Wird gesendet…';

  @override
  String get sentSyncing => 'Gesendet · wird synchronisiert';

  @override
  String get notSent => 'Nicht gesendet';

  @override
  String get rejected => 'Abgelehnt';

  @override
  String get messageConflict => 'Nachrichtenkonflikt';

  @override
  String get opened => 'Geöffnet';

  @override
  String get readByEveryone => 'Von allen gelesen';

  @override
  String get read => 'Gelesen';

  @override
  String get deliveredToEveryone => 'An alle zugestellt';

  @override
  String get delivered => 'Zugestellt';

  @override
  String get sent => 'Gesendet';

  @override
  String get tapToOpenMarkRead => 'Antippen zum Öffnen · als gelesen markieren';

  @override
  String get tapToViewOnce => 'Antippen zur Einmalansicht';

  @override
  String get discard => 'Verwerfen';

  @override
  String get encrypted => 'verschlüsselt';

  @override
  String get fileDecrypted =>
      'Die Datei wurde auf diesem Gerät authentifiziert und entschlüsselt.';

  @override
  String get pauseVoiceNote => 'Sprachnachricht pausieren';

  @override
  String get playVoiceNote => 'Sprachnachricht abspielen';

  @override
  String get voiceNoteDecrypted =>
      'auf diesem Gerät authentifiziert und entschlüsselt';

  @override
  String get confirmSafetyNumber => 'Sicherheitsnummer bestätigen';

  @override
  String get compareSafetyNumber =>
      'Fahre erst fort, nachdem du diese Nummer über einen anderen vertrauenswürdigen Kanal mit deinem Kontakt verglichen hast.';

  @override
  String get numbersMatch => 'Nummern stimmen überein';

  @override
  String get encryptionIdentity => 'Verschlüsselungsidentität';

  @override
  String encryptionIdentityFor(String username) {
    return 'Verschlüsselungsidentität · @$username';
  }

  @override
  String get trustComparisonHelp =>
      'Vergleiche die Sicherheitsnummer jedes aktiven Geräts über einen anderen vertrauenswürdigen Kanal. Die Bestätigung erkennt spätere Identitätsänderungen, ersetzt aber nicht diesen ersten Vergleich.';

  @override
  String get verified => 'Bestätigt';

  @override
  String get verifyDevice => 'Gerät bestätigen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get trustLoadFailed =>
      'Diese Verschlüsselungsidentität konnte nicht geladen oder bestätigt werden.';

  @override
  String get trustUnverified =>
      'Noch nicht bestätigt. Nachrichten können gesendet werden, aber vergleiche jedes aktive Gerät, bevor du dieser Identität vertraust.';

  @override
  String get trustVerified => 'Jedes aktive Gerät ist bestätigt.';

  @override
  String get trustChanged =>
      'Die Verschlüsselungsidentität hat sich geändert. Senden ist blockiert, bis jedes aktive Gerät geprüft und bestätigt wurde.';

  @override
  String get chatMuted => 'Chat für dieses Konto stummgeschaltet.';

  @override
  String get chatUnmuted => 'Chat für dieses Konto nicht mehr stummgeschaltet.';

  @override
  String get chatPreferenceSaveFailed =>
      'Die Chat-Einstellung konnte nicht gespeichert werden.';

  @override
  String chatAppearanceSaved(String appearance) {
    return 'Chat-Darstellung $appearance für dieses Konto gespeichert.';
  }

  @override
  String get chatAppearanceSaveFailed =>
      'Die Chat-Darstellung konnte nicht gespeichert werden.';

  @override
  String get disappearingMessagesDisabled =>
      'Verschwindende Nachrichten für diesen Chat deaktiviert.';

  @override
  String disappearingMessagesEnabled(String retention) {
    return 'Neue Nachrichten in diesem Chat werden $retention.';
  }

  @override
  String get openConversationBeforeSending =>
      'Öffne einen Chat oder gib vor dem Senden einen Empfänger ein.';

  @override
  String get attachmentLimit =>
      'Eine Nachricht kann bis zu 8 Anhänge enthalten.';

  @override
  String get attachmentSizeLimit =>
      'Jeder Anhang darf höchstens 64 MiB groß sein.';

  @override
  String get attachmentReadFailed =>
      'Die ausgewählten Dateien konnten nicht geöffnet werden.';

  @override
  String get stickerTooLarge =>
      'Der erstellte Sticker überschreitet die Anhangsgrenzen.';

  @override
  String get stickerRenderFailed => 'Der Sticker konnte nicht erstellt werden.';

  @override
  String get microphoneStartFailed =>
      'Die Mikrofonaufnahme konnte nicht gestartet werden.';

  @override
  String get voiceRecordingFailed =>
      'Die Sprachnachricht konnte nicht aufgenommen werden.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'WampApp';

  @override
  String get chats => 'Discussions';

  @override
  String get settings => 'Réglages';

  @override
  String get account => 'Compte';

  @override
  String get privacy => 'Confidentialité';

  @override
  String get appearance => 'Apparence';

  @override
  String get dataAndStorage => 'Données et stockage';

  @override
  String get advanced => 'Avancé';

  @override
  String get editProfile => 'Modifier le profil';

  @override
  String get contacts => 'Contacts';

  @override
  String get contactsSubtitle => 'Gérer les noms enregistrés sur cet appareil';

  @override
  String get staySignedIn => 'Rester connecté avec la biométrie';

  @override
  String get staySignedInSubtitle =>
      'Déverrouiller la connexion enregistrée avec Face ID, Touch ID ou la biométrie de l\'appareil';

  @override
  String get biometricsUnavailable =>
      'La connexion biométrique n\'est pas disponible sur cet appareil.';

  @override
  String get biometricPasswordPrompt =>
      'Confirmez le mot de passe du compte pour activer la connexion biométrique.';

  @override
  String get signInWithBiometrics => 'Se connecter avec la biométrie';

  @override
  String get pushNotifications => 'Notifications push';

  @override
  String get pushNotificationsSubtitle =>
      'Recevoir les nouveaux messages lorsque WampApp n\'est pas ouvert';

  @override
  String get theme => 'Thème';

  @override
  String get themeSystem => 'Utiliser le réglage de l\'appareil';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Utiliser la langue de l\'appareil';

  @override
  String get languageEnglish => 'Anglais';

  @override
  String get languageGerman => 'Allemand';

  @override
  String get languageSpanish => 'Espagnol';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageItalian => 'Italien';

  @override
  String get languagePortuguese => 'Portugais';

  @override
  String get backup => 'Sauvegarde';

  @override
  String get backupSubtitle => 'Exporter ou restaurer la sauvegarde chiffrée';

  @override
  String get serverBackup => 'Sauvegarde serveur';

  @override
  String get serverBackupSubtitle =>
      'Stocker sur ce serveur une sauvegarde chiffrée par phrase de récupération';

  @override
  String get mcpAccess => 'Accès des apps et agents';

  @override
  String get mcpAccessSubtitle => 'Contrôler l\'accès à votre profil public';

  @override
  String get technicalInformation => 'Informations techniques';

  @override
  String get technicalInformationSubtitle =>
      'Connexion, chiffrement, appareil et endpoints';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get technicalIntro =>
      'Ces détails facilitent l\'assistance et l\'intégration. Les discussions, mots de passe, clés et jetons ne sont jamais affichés ici.';

  @override
  String get connection => 'Connexion';

  @override
  String get connected => 'Connecté';

  @override
  String get server => 'Serveur';

  @override
  String get websocketEndpoint => 'Endpoint WebSocket';

  @override
  String get applicationRealm => 'Realm de l\'application';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get device => 'Appareil';

  @override
  String get deviceId => 'ID de l\'appareil';

  @override
  String get safetyNumber => 'Numéro de sécurité';

  @override
  String get encryption => 'Chiffrement';

  @override
  String get encryptionSummary =>
      'Les messages et pièces jointes sont chiffrés de bout en bout; les clés restent dans le coffre local chiffré.';

  @override
  String get copy => 'Copier';

  @override
  String get copied => 'Copié dans le presse-papiers';

  @override
  String get close => 'Fermer';

  @override
  String get cancel => 'Annuler';

  @override
  String get enable => 'Activer';

  @override
  String get disable => 'Désactiver';

  @override
  String get save => 'Enregistrer';

  @override
  String get password => 'Mot de passe';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get signIn => 'Se connecter';

  @override
  String get serverAddress => 'Adresse du serveur';

  @override
  String get displayName => 'Nom affiché';

  @override
  String get createAndConnect => 'Créer et se connecter';

  @override
  String get connectSecurely => 'Se connecter en sécurité';

  @override
  String get restoreEncryptedBackup => 'Restaurer une sauvegarde chiffrée';

  @override
  String get restoreBackupFromServer => 'Restaurer depuis le serveur';

  @override
  String get checkingServer => 'Vérification du service…';

  @override
  String get serverReady => 'Le service est prêt.';

  @override
  String get serverUnavailable =>
      'Service indisponible. Vérifiez l’adresse et réessayez.';

  @override
  String get retry => 'Réessayer';

  @override
  String get introHeadline => 'Des conversations privées, tout simplement.';

  @override
  String get introBody =>
      'Échangez, appelez et partagez avec vos proches. Vos conversations restent chiffrées de bout en bout sur vos appareils.';

  @override
  String get privateByDesign => 'Privé par conception';

  @override
  String get realTimeMessaging => 'Messagerie en temps réel';

  @override
  String get yourOwnAccount => 'Votre propre compte';

  @override
  String get backupRestoreBoundary =>
      'Les deux méthodes restaurent l\'identité de l\'appareil, les discussions, les réglages et les clés de pièces jointes de ce compte. La copie du serveur est chiffrée de bout en bout. Les médias mis en cache ne sont pas inclus et doivent être téléchargés à nouveau.';

  @override
  String get contactPrivacyBoundary =>
      'Seuls le nom affiché sélectionné et le nom d\'utilisateur WampApp saisi sont conservés dans le coffre chiffré de l\'appareil. Les numéros, e-mails, identifiants et fichiers du carnet d\'adresses ne sont jamais envoyés ni conservés.';

  @override
  String get importContacts => 'Importer des contacts';

  @override
  String get addByUsername => 'Ajouter par nom d\'utilisateur';

  @override
  String get importedDisplayName => 'Nom affiché importé';

  @override
  String get nameOnDevice => 'Nom sur cet appareil';

  @override
  String get wampAppUsername => 'Nom d\'utilisateur WampApp';

  @override
  String get contactVerifyHelper =>
      'Vérifié auprès du serveur connecté avant l\'enregistrement.';

  @override
  String get contactRenameHelper =>
      'Le compte associé ne peut pas être modifié lors du renommage.';

  @override
  String get verifyAndSave => 'Vérifier et enregistrer';

  @override
  String get saveLocalName => 'Enregistrer le nom local';

  @override
  String get noContactsSaved => 'Aucun contact enregistré sur cet appareil.';

  @override
  String localContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contacts locaux',
      one: '1 contact local',
    );
    return '$_temp0';
  }

  @override
  String get renameLocalContact => 'Renommer le contact local';

  @override
  String get removeLocalContact => 'Supprimer le contact local';

  @override
  String get contactReadFailed => 'Impossible de lire le contact sélectionné.';

  @override
  String get encryptDeviceBackup => 'Chiffrer la sauvegarde de l\'appareil';

  @override
  String get restoreBackup => 'Restaurer une sauvegarde';

  @override
  String get backupCreateHelp =>
      'Cette phrase est le seul moyen de déchiffrer l\'export. Elle n\'est ni conservée ni envoyée au serveur.';

  @override
  String get backupRestoreHelp =>
      'Saisissez la phrase de récupération utilisée pour créer cette sauvegarde.';

  @override
  String get recoveryPhrase => 'Phrase de récupération';

  @override
  String get confirmRecoveryPhrase => 'Confirmer la phrase de récupération';

  @override
  String get passphraseLength => 'Utilisez de 16 à 1024 octets UTF-8.';

  @override
  String get passphraseMismatch =>
      'Les phrases de récupération ne correspondent pas.';

  @override
  String get createBackup => 'Créer la sauvegarde';

  @override
  String get chooseBackup => 'Choisir la sauvegarde';

  @override
  String get unknown => 'inconnu';

  @override
  String get incomingEncryptedVideoCall => 'Appel vidéo chiffré entrant';

  @override
  String get incomingEncryptedVoiceCall => 'Appel vocal chiffré entrant';

  @override
  String get decline => 'Refuser';

  @override
  String get accept => 'Accepter';

  @override
  String get unmute => 'Réactiver le son';

  @override
  String get mute => 'Couper le son';

  @override
  String get cameraOff => 'Couper la caméra';

  @override
  String get cameraOn => 'Activer la caméra';

  @override
  String get earpiece => 'Écouteur';

  @override
  String get speaker => 'Haut-parleur';

  @override
  String get endCall => 'Terminer';

  @override
  String get answeredOtherDevice => 'Pris sur un autre appareil';

  @override
  String get callUnavailable => 'Appel indisponible';

  @override
  String get callEnded => 'Appel terminé';

  @override
  String get backToChats => 'Retour aux discussions';

  @override
  String get callingSecurely => 'Appel sécurisé…';

  @override
  String get connectingMedia => 'Connexion des médias…';

  @override
  String get encryptedSignaling => 'Signalisation chiffrée de bout en bout';

  @override
  String get endingCall => 'Fin de l\'appel…';

  @override
  String get emojiAndStickers => 'Emojis et stickers';

  @override
  String get closeExpressions => 'Fermer les emojis et stickers';

  @override
  String get searchExpressions => 'Rechercher des emojis et stickers';

  @override
  String get emoji => 'Emojis';

  @override
  String get stickers => 'Stickers';

  @override
  String stickerLabel(String label) {
    return 'Sticker $label';
  }

  @override
  String get noMatchingExpressions => 'Aucun résultat';

  @override
  String get saveCopy => 'Enregistrer une copie';

  @override
  String get viewOnceMessage => 'Message à vue unique';

  @override
  String get viewOnceOpenFailed =>
      'Impossible d\'ouvrir cette pièce jointe à vue unique.';

  @override
  String get profileUpdated => 'Profil mis à jour.';

  @override
  String get profileUpdateFailed => 'Échec de la mise à jour du profil.';

  @override
  String get allow => 'Autoriser';

  @override
  String get allowMcpProfileTitle => 'Autoriser l\'accès au profil public ?';

  @override
  String get mcpProfileConsentBoundary =>
      'Une application ou un agent authentifié pourra lire votre nom d\'utilisateur, nom affiché, statut et révision de profil. Les discussions, messages, pièces jointes, sauvegardes, appareils, appels, clés et avatar restent inaccessibles. Vous pouvez révoquer l\'accès immédiatement.';

  @override
  String get mcpConsentUpdateFailed =>
      'Impossible de mettre à jour l\'accès au profil public.';

  @override
  String get mcpConnectionLoadFailed =>
      'Impossible de charger les informations de connexion des applications et agents.';

  @override
  String get connectAiService => 'Connecter un service d\'IA';

  @override
  String get mcpConnectionHelp =>
      'Utilisez le point d\'accès ci-dessous avec un client compatible avec Streamable HTTP ou JSON direct. Le client s\'authentifie comme ce compte WampApp à l\'aide d\'une autorisation WAMP-SCRAM.';

  @override
  String get mcpEndpoint => 'Point d\'accès MCP';

  @override
  String get authenticationEndpoint => 'Point d\'authentification';

  @override
  String get mcpEndpointCopied => 'Point d\'accès MCP copié.';

  @override
  String get authEndpointCopied => 'Point d\'authentification copié.';

  @override
  String mcpAccount(String username) {
    return 'Compte : @$username';
  }

  @override
  String mcpRealm(String realm) {
    return 'Realm : $realm';
  }

  @override
  String get mcpAuthentication => 'Authentification : autorisation WAMP-SCRAM';

  @override
  String get mcpCatalog =>
      'Catalogues : outils, ressources et prompts · Transports : Streamable HTTP et JSON direct';

  @override
  String get allowPublicProfileAccess => 'Autoriser l\'accès au profil public';

  @override
  String get accessEnabled => 'Activé. La révocation est immédiate.';

  @override
  String get accessDisabledByDefault => 'Désactivé par défaut.';

  @override
  String visibleFields(String fields) {
    return 'Champs visibles : $fields.';
  }

  @override
  String get mcpDataBoundary =>
      'Les discussions, messages, pièces jointes, sauvegardes, appareils, appels, clés et avatars restent inaccessibles. WampApp n\'affiche ni ne copie jamais votre mot de passe ou vos jetons.';

  @override
  String get enterRecipientFirst =>
      'Saisissez d\'abord le nom d\'utilisateur du destinataire.';

  @override
  String get profileLoadFailed => 'Impossible de charger ce profil.';

  @override
  String get publicProfile => 'Profil public';

  @override
  String get noStatusSet => 'Aucun statut';

  @override
  String get encryptedDeviceBackupSaved =>
      'Sauvegarde chiffrée de l\'appareil enregistrée.';

  @override
  String get backupCancelled => 'La sauvegarde a été annulée.';

  @override
  String get encryptedServerBackupSaved =>
      'Sauvegarde chiffrée enregistrée sur ce serveur.';

  @override
  String get cloudBackupCancelled => 'La sauvegarde serveur a été annulée.';

  @override
  String get encryptedBackup => 'Sauvegarde chiffrée';

  @override
  String get saveBackupFile => 'Enregistrer le fichier de sauvegarde';

  @override
  String get saveBackupFileSubtitle =>
      'Conservez vous-même une archive chiffrée.';

  @override
  String get backupToServer => 'Sauvegarder sur ce serveur';

  @override
  String get backupToServerSubtitle =>
      'Le serveur ne conserve que l\'archive chiffrée.';

  @override
  String get newEncryptedGroup => 'Nouveau groupe chiffré';

  @override
  String get groupName => 'Nom du groupe';

  @override
  String get memberUsernames => 'Noms d\'utilisateur des membres';

  @override
  String get separateUsernames => 'Séparez les noms par des virgules';

  @override
  String get createGroup => 'Créer le groupe';

  @override
  String get editPublicProfile => 'Modifier le profil public';

  @override
  String get chooseImage => 'Choisir une image';

  @override
  String get remove => 'Supprimer';

  @override
  String get status => 'Statut';

  @override
  String get available => 'Disponible';

  @override
  String get profileVisibilityBoundary =>
      'Votre profil est visible par les membres WampApp authentifiés. Le contenu des messages et les clés de l\'appareil ne sont jamais inclus.';

  @override
  String copyLabel(String label) {
    return 'Copier $label';
  }

  @override
  String get online => 'En ligne';

  @override
  String get encryptedMessages => 'Messages chiffrés';

  @override
  String get groupCallsUnavailable =>
      'Les appels de groupe ne sont pas encore disponibles';

  @override
  String get startEncryptedVoiceCall => 'Démarrer un appel vocal chiffré';

  @override
  String get startEncryptedVideoCall => 'Démarrer un appel vidéo chiffré';

  @override
  String get unmuteChat => 'Réactiver les notifications de cette discussion';

  @override
  String get muteChat => 'Mettre cette discussion en sourdine';

  @override
  String chatAppearance(String appearance) {
    return 'Apparence de la discussion : $appearance';
  }

  @override
  String get syncMessages => 'Synchroniser les messages';

  @override
  String localSearchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recherche locale · $count résultats',
      one: 'Recherche locale · 1 résultat',
    );
    return '$_temp0';
  }

  @override
  String get searchLocalMessages =>
      'Rechercher dans les messages locaux · reste sur cet appareil';

  @override
  String get clearMessageSearch => 'Effacer la recherche';

  @override
  String get direct => 'Direct';

  @override
  String get newGroup => 'Nouveau groupe';

  @override
  String get all => 'Tous';

  @override
  String get unreadReceived => 'Reçus non lus';

  @override
  String get readReceived => 'Reçus lus';

  @override
  String get startDirectChat => 'Démarrer une discussion directe';

  @override
  String get directChat => 'Discussion directe';

  @override
  String get closeDirectChat => 'Fermer la discussion directe';

  @override
  String get verifyEncryptionIdentity => 'Vérifier l\'identité de chiffrement';

  @override
  String get viewPublicProfile => 'Voir le profil public';

  @override
  String get groupUnavailable => 'Groupe indisponible';

  @override
  String get noSearchMessages =>
      'Aucun message local ne correspond à cette recherche et ce filtre.';

  @override
  String get noMessages =>
      'Aucun message. Choisissez un compte inscrit et envoyez le premier message chiffré de bout en bout.';

  @override
  String get noUnreadMessages =>
      'Aucun message reçu non lu dans cette discussion.';

  @override
  String get noReadMessages => 'Aucun message reçu lu dans cette discussion.';

  @override
  String get viewOnce => 'Voir une fois';

  @override
  String get keepChatMessages => 'Conserver les messages';

  @override
  String get deleteAfterOneHour => 'Supprimer après 1 heure';

  @override
  String get deleteAfterOneDay => 'Supprimer après 1 jour';

  @override
  String get deleteAfterSevenDays => 'Supprimer après 7 jours';

  @override
  String get autoDeleteEnabled => 'Suppression automatique activée';

  @override
  String get appearanceStandard => 'Standard';

  @override
  String get appearanceOcean => 'Océan';

  @override
  String get appearanceSunset => 'Coucher de soleil';

  @override
  String recordingDuration(String duration) {
    return 'Enregistrement $duration';
  }

  @override
  String get cancelVoiceNote => 'Annuler le message vocal';

  @override
  String get finishVoiceNote => 'Terminer le message vocal';

  @override
  String get openConversationToReply => 'Ouvrez une discussion pour répondre';

  @override
  String get messageGroup => 'Message au groupe';

  @override
  String get message => 'Message';

  @override
  String get chooseExpression => 'Choisir un emoji ou un sticker chiffré';

  @override
  String get attachEncryptedFiles => 'Joindre des fichiers chiffrés';

  @override
  String get sendEncryptedMessage => 'Envoyer le message chiffré';

  @override
  String get recordEncryptedVoiceNote => 'Enregistrer un message vocal chiffré';

  @override
  String get sending => 'Envoi…';

  @override
  String get sentSyncing => 'Envoyé · synchronisation';

  @override
  String get notSent => 'Non envoyé';

  @override
  String get rejected => 'Rejeté';

  @override
  String get messageConflict => 'Conflit de message';

  @override
  String get opened => 'Ouvert';

  @override
  String get readByEveryone => 'Lu par tout le monde';

  @override
  String get read => 'Lu';

  @override
  String get deliveredToEveryone => 'Remis à tout le monde';

  @override
  String get delivered => 'Remis';

  @override
  String get sent => 'Envoyé';

  @override
  String get tapToOpenMarkRead => 'Touchez pour ouvrir · marquer comme lu';

  @override
  String get tapToViewOnce => 'Touchez pour voir une fois';

  @override
  String get discard => 'Supprimer';

  @override
  String get encrypted => 'chiffré';

  @override
  String get fileDecrypted =>
      'Le fichier a été authentifié et déchiffré sur cet appareil.';

  @override
  String get pauseVoiceNote => 'Mettre le message vocal en pause';

  @override
  String get playVoiceNote => 'Lire le message vocal';

  @override
  String get voiceNoteDecrypted => 'authentifié et déchiffré sur cet appareil';

  @override
  String get confirmSafetyNumber => 'Confirmer le numéro de sécurité';

  @override
  String get compareSafetyNumber =>
      'Continuez seulement après avoir comparé ce numéro avec votre contact par un autre canal de confiance.';

  @override
  String get numbersMatch => 'Les numéros correspondent';

  @override
  String get encryptionIdentity => 'Identité de chiffrement';

  @override
  String encryptionIdentityFor(String username) {
    return 'Identité de chiffrement · @$username';
  }

  @override
  String get trustComparisonHelp =>
      'Comparez le numéro de sécurité de chaque appareil actif par un autre canal de confiance. La vérification détecte les changements ultérieurs, mais ne remplace pas cette première comparaison.';

  @override
  String get verified => 'Vérifié';

  @override
  String get verifyDevice => 'Vérifier l\'appareil';

  @override
  String get refresh => 'Actualiser';

  @override
  String get trustLoadFailed =>
      'Impossible de charger ou de vérifier cette identité de chiffrement.';

  @override
  String get trustUnverified =>
      'Pas encore vérifié. Les messages peuvent être envoyés, mais comparez chaque appareil actif avant de faire confiance à cette identité.';

  @override
  String get trustVerified => 'Tous les appareils actifs sont vérifiés.';

  @override
  String get trustChanged =>
      'L\'identité de chiffrement a changé. L\'envoi est bloqué jusqu\'à ce que chaque appareil actif soit contrôlé et vérifié.';

  @override
  String get chatMuted => 'Discussion mise en sourdine sur ce compte.';

  @override
  String get chatUnmuted => 'Sourdine désactivée pour cette discussion.';

  @override
  String get chatPreferenceSaveFailed =>
      'Impossible d\'enregistrer le réglage de la discussion.';

  @override
  String chatAppearanceSaved(String appearance) {
    return 'Apparence $appearance enregistrée sur ce compte.';
  }

  @override
  String get chatAppearanceSaveFailed =>
      'Impossible d\'enregistrer l\'apparence de la discussion.';

  @override
  String get disappearingMessagesDisabled =>
      'Messages éphémères désactivés pour cette discussion.';

  @override
  String disappearingMessagesEnabled(String retention) {
    return 'Les nouveaux messages de cette discussion seront $retention.';
  }

  @override
  String get openConversationBeforeSending =>
      'Ouvrez une discussion ou saisissez un destinataire avant l\'envoi.';

  @override
  String get attachmentLimit =>
      'Un message peut contenir jusqu\'à 8 pièces jointes.';

  @override
  String get attachmentSizeLimit =>
      'Chaque pièce jointe doit faire au maximum 64 Mio.';

  @override
  String get attachmentReadFailed =>
      'Impossible d\'ouvrir les fichiers sélectionnés.';

  @override
  String get stickerTooLarge => 'Le sticker créé dépasse la taille autorisée.';

  @override
  String get stickerRenderFailed => 'Impossible de créer le sticker.';

  @override
  String get microphoneStartFailed =>
      'Impossible de démarrer l\'enregistrement du microphone.';

  @override
  String get voiceRecordingFailed =>
      'Échec de l\'enregistrement du message vocal.';
}

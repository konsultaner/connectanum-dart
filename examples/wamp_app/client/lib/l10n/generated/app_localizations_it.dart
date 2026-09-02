// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'WampApp';

  @override
  String get chats => 'Chat';

  @override
  String get settings => 'Impostazioni';

  @override
  String get account => 'Account';

  @override
  String get privacy => 'Privacy';

  @override
  String get appearance => 'Aspetto';

  @override
  String get dataAndStorage => 'Dati e archiviazione';

  @override
  String get advanced => 'Avanzate';

  @override
  String get editProfile => 'Modifica profilo';

  @override
  String get contacts => 'Contatti';

  @override
  String get contactsSubtitle =>
      'Gestisci i nomi salvati su questo dispositivo';

  @override
  String get staySignedIn => 'Resta connesso con la biometria';

  @override
  String get staySignedInSubtitle =>
      'Sblocca l\'accesso salvato con Face ID, Touch ID o la biometria del dispositivo';

  @override
  String get biometricsUnavailable =>
      'L\'accesso biometrico non è disponibile su questo dispositivo.';

  @override
  String get biometricPasswordPrompt =>
      'Conferma la password dell\'account per attivare l\'accesso biometrico.';

  @override
  String get signInWithBiometrics => 'Accedi con la biometria';

  @override
  String get pushNotifications => 'Notifiche push';

  @override
  String get pushNotificationsSubtitle =>
      'Ricevi avvisi di nuovi messaggi quando WampApp non è aperta';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Usa impostazione del dispositivo';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get language => 'Lingua';

  @override
  String get languageSystem => 'Usa lingua del dispositivo';

  @override
  String get languageEnglish => 'Inglese';

  @override
  String get languageGerman => 'Tedesco';

  @override
  String get languageSpanish => 'Spagnolo';

  @override
  String get languageFrench => 'Francese';

  @override
  String get languageItalian => 'Italiano';

  @override
  String get languagePortuguese => 'Portoghese';

  @override
  String get backup => 'Backup';

  @override
  String get backupSubtitle => 'Esporta o ripristina il backup crittografato';

  @override
  String get serverBackup => 'Backup sul server';

  @override
  String get serverBackupSubtitle =>
      'Salva su questo server un backup cifrato con frase di recupero';

  @override
  String get mcpAccess => 'Accesso di app e agenti';

  @override
  String get mcpAccessSubtitle =>
      'Controlla l\'accesso al tuo profilo pubblico';

  @override
  String get technicalInformation => 'Informazioni tecniche';

  @override
  String get technicalInformationSubtitle =>
      'Connessione, crittografia, dispositivo ed endpoint';

  @override
  String get signOut => 'Esci';

  @override
  String get technicalIntro =>
      'Questi dettagli aiutano supporto e integrazione. Chat, password, chiavi e token non vengono mai mostrati qui.';

  @override
  String get connection => 'Connessione';

  @override
  String get connected => 'Connesso';

  @override
  String get server => 'Server';

  @override
  String get websocketEndpoint => 'Endpoint WebSocket';

  @override
  String get applicationRealm => 'Realm dell\'applicazione';

  @override
  String get username => 'Nome utente';

  @override
  String get device => 'Dispositivo';

  @override
  String get deviceId => 'ID dispositivo';

  @override
  String get safetyNumber => 'Numero di sicurezza';

  @override
  String get encryption => 'Crittografia';

  @override
  String get encryptionSummary =>
      'Messaggi e allegati sono crittografati end-to-end; le chiavi restano nella cassaforte locale cifrata.';

  @override
  String get copy => 'Copia';

  @override
  String get copied => 'Copiato negli appunti';

  @override
  String get close => 'Chiudi';

  @override
  String get cancel => 'Annulla';

  @override
  String get enable => 'Attiva';

  @override
  String get disable => 'Disattiva';

  @override
  String get save => 'Salva';

  @override
  String get password => 'Password';

  @override
  String get createAccount => 'Crea account';

  @override
  String get signIn => 'Accedi';

  @override
  String get serverAddress => 'Indirizzo del server';

  @override
  String get displayName => 'Nome visualizzato';

  @override
  String get createAndConnect => 'Crea e connetti';

  @override
  String get connectSecurely => 'Accedi in modo sicuro';

  @override
  String get restoreEncryptedBackup => 'Ripristina backup cifrato';

  @override
  String get restoreBackupFromServer => 'Ripristina backup dal server';

  @override
  String get checkingServer => 'Verifica della disponibilità del servizio…';

  @override
  String get serverReady => 'Il servizio è pronto.';

  @override
  String get serverUnavailable =>
      'Servizio non disponibile. Controlla l’indirizzo e riprova.';

  @override
  String get retry => 'Riprova';

  @override
  String get introHeadline => 'Conversazioni private, senza complicazioni.';

  @override
  String get introBody =>
      'Messaggia, chiama e condividi con chi conta. Le tue conversazioni restano crittografate end-to-end su tutti i dispositivi.';

  @override
  String get privateByDesign => 'Privato per progettazione';

  @override
  String get realTimeMessaging => 'Messaggi in tempo reale';

  @override
  String get yourOwnAccount => 'Il tuo account';

  @override
  String get backupRestoreBoundary =>
      'Entrambi i metodi ripristinano l\'identità del dispositivo, le chat, le impostazioni e le chiavi degli allegati di questo account. La copia sul server è crittografata end-to-end. I contenuti multimediali nella cache non sono inclusi e devono essere scaricati di nuovo.';

  @override
  String get contactPrivacyBoundary =>
      'Nel vault crittografato del dispositivo vengono salvati solo il nome visualizzato selezionato e il nome utente WampApp inserito. Numeri, email, ID contatto e file della rubrica non vengono mai caricati o conservati.';

  @override
  String get importContacts => 'Importa contatti';

  @override
  String get addByUsername => 'Aggiungi per nome utente';

  @override
  String get importedDisplayName => 'Nome visualizzato importato';

  @override
  String get nameOnDevice => 'Nome su questo dispositivo';

  @override
  String get wampAppUsername => 'Nome utente WampApp';

  @override
  String get contactVerifyHelper =>
      'Verificato con il server connesso prima del salvataggio.';

  @override
  String get contactRenameHelper =>
      'L\'account associato non può essere cambiato durante la rinomina.';

  @override
  String get verifyAndSave => 'Verifica e salva';

  @override
  String get saveLocalName => 'Salva nome locale';

  @override
  String get noContactsSaved =>
      'Nessun contatto salvato su questo dispositivo.';

  @override
  String localContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contatti locali',
      one: '1 contatto locale',
    );
    return '$_temp0';
  }

  @override
  String get renameLocalContact => 'Rinomina contatto locale';

  @override
  String get removeLocalContact => 'Rimuovi contatto locale';

  @override
  String get contactReadFailed =>
      'Impossibile leggere il contatto selezionato.';

  @override
  String get encryptDeviceBackup => 'Crittografa backup del dispositivo';

  @override
  String get restoreBackup => 'Ripristina backup';

  @override
  String get backupCreateHelp =>
      'Questa frase è l\'unico modo per decifrare l\'esportazione. Non viene salvata né inviata al server.';

  @override
  String get backupRestoreHelp =>
      'Inserisci la frase di recupero usata per creare questo backup.';

  @override
  String get recoveryPhrase => 'Frase di recupero';

  @override
  String get confirmRecoveryPhrase => 'Conferma frase di recupero';

  @override
  String get passphraseLength => 'Usa da 16 a 1024 byte UTF-8.';

  @override
  String get passphraseMismatch => 'Le frasi di recupero non corrispondono.';

  @override
  String get createBackup => 'Crea backup';

  @override
  String get chooseBackup => 'Scegli backup';

  @override
  String get unknown => 'sconosciuto';

  @override
  String get incomingEncryptedVideoCall =>
      'Videochiamata crittografata in arrivo';

  @override
  String get incomingEncryptedVoiceCall =>
      'Chiamata vocale crittografata in arrivo';

  @override
  String get decline => 'Rifiuta';

  @override
  String get accept => 'Accetta';

  @override
  String get unmute => 'Riattiva audio';

  @override
  String get mute => 'Disattiva audio';

  @override
  String get cameraOff => 'Disattiva fotocamera';

  @override
  String get cameraOn => 'Attiva fotocamera';

  @override
  String get earpiece => 'Auricolare';

  @override
  String get speaker => 'Altoparlante';

  @override
  String get endCall => 'Termina';

  @override
  String get answeredOtherDevice => 'Risposta su un altro dispositivo';

  @override
  String get callUnavailable => 'Chiamata non disponibile';

  @override
  String get callEnded => 'Chiamata terminata';

  @override
  String get backToChats => 'Torna alle chat';

  @override
  String get callingSecurely => 'Chiamata sicura…';

  @override
  String get connectingMedia => 'Connessione multimediale…';

  @override
  String get encryptedSignaling => 'Segnalazione crittografata end-to-end';

  @override
  String get endingCall => 'Chiusura chiamata…';

  @override
  String get emojiAndStickers => 'Emoji e sticker';

  @override
  String get closeExpressions => 'Chiudi emoji e sticker';

  @override
  String get searchExpressions => 'Cerca emoji e sticker';

  @override
  String get emoji => 'Emoji';

  @override
  String get stickers => 'Sticker';

  @override
  String stickerLabel(String label) {
    return 'Sticker $label';
  }

  @override
  String get noMatchingExpressions => 'Nessun risultato';

  @override
  String get saveCopy => 'Salva copia';

  @override
  String get viewOnceMessage => 'Messaggio visualizzabile una volta';

  @override
  String get viewOnceOpenFailed =>
      'Impossibile aprire questo allegato visualizzabile una volta.';

  @override
  String get profileUpdated => 'Profilo aggiornato.';

  @override
  String get profileUpdateFailed => 'Aggiornamento del profilo non riuscito.';

  @override
  String get allow => 'Consenti';

  @override
  String get allowMcpProfileTitle =>
      'Consentire l\'accesso al profilo pubblico?';

  @override
  String get mcpProfileConsentBoundary =>
      'Un\'app o un agente autenticato potrà leggere nome utente, nome visualizzato, stato e revisione del profilo. Chat, messaggi, allegati, backup, dispositivi, chiamate, chiavi e avatar restano inaccessibili. Puoi revocare subito l\'accesso.';

  @override
  String get mcpConsentUpdateFailed =>
      'Impossibile aggiornare l\'accesso al profilo pubblico.';

  @override
  String get mcpConnectionLoadFailed =>
      'Impossibile caricare le informazioni di connessione per app e agenti.';

  @override
  String get connectAiService => 'Collega un servizio IA';

  @override
  String get mcpConnectionHelp =>
      'Usa l\'endpoint seguente con un client che supporta Streamable HTTP o JSON diretto. Il client si autentica come questo account WampApp tramite un\'autorizzazione WAMP-SCRAM.';

  @override
  String get mcpEndpoint => 'Endpoint MCP';

  @override
  String get authenticationEndpoint => 'Endpoint di autenticazione';

  @override
  String get mcpEndpointCopied => 'Endpoint MCP copiato.';

  @override
  String get authEndpointCopied => 'Endpoint di autenticazione copiato.';

  @override
  String mcpAccount(String username) {
    return 'Account: @$username';
  }

  @override
  String mcpRealm(String realm) {
    return 'Realm: $realm';
  }

  @override
  String get mcpAuthentication => 'Autenticazione: autorizzazione WAMP-SCRAM';

  @override
  String get mcpCatalog =>
      'Cataloghi: strumenti, risorse e prompt · Trasporti: Streamable HTTP e JSON diretto';

  @override
  String get allowPublicProfileAccess => 'Consenti accesso al profilo pubblico';

  @override
  String get accessEnabled => 'Attivo. La revoca ha effetto immediato.';

  @override
  String get accessDisabledByDefault =>
      'Disattivato per impostazione predefinita.';

  @override
  String visibleFields(String fields) {
    return 'Campi visibili: $fields.';
  }

  @override
  String get mcpDataBoundary =>
      'Chat, messaggi, allegati, backup, dispositivi, chiamate, chiavi e avatar restano inaccessibili. WampApp non mostra né copia mai password o token di accesso e aggiornamento.';

  @override
  String get enterRecipientFirst =>
      'Inserisci prima il nome utente del destinatario.';

  @override
  String get profileLoadFailed => 'Impossibile caricare il profilo.';

  @override
  String get publicProfile => 'Profilo pubblico';

  @override
  String get noStatusSet => 'Nessuno stato';

  @override
  String get encryptedDeviceBackupSaved =>
      'Backup crittografato del dispositivo salvato.';

  @override
  String get backupCancelled => 'Backup annullato.';

  @override
  String get encryptedServerBackupSaved =>
      'Backup crittografato salvato su questo server.';

  @override
  String get cloudBackupCancelled => 'Backup del server annullato.';

  @override
  String get encryptedBackup => 'Backup crittografato';

  @override
  String get saveBackupFile => 'Salva file di backup';

  @override
  String get saveBackupFileSubtitle =>
      'Conserva personalmente un archivio crittografato.';

  @override
  String get backupToServer => 'Esegui backup su questo server';

  @override
  String get backupToServerSubtitle =>
      'Il server conserva solo l\'archivio crittografato.';

  @override
  String get newEncryptedGroup => 'Nuovo gruppo crittografato';

  @override
  String get groupName => 'Nome del gruppo';

  @override
  String get memberUsernames => 'Nomi utente dei membri';

  @override
  String get separateUsernames => 'Separa i nomi utente con virgole';

  @override
  String get createGroup => 'Crea gruppo';

  @override
  String get editPublicProfile => 'Modifica profilo pubblico';

  @override
  String get chooseImage => 'Scegli immagine';

  @override
  String get remove => 'Rimuovi';

  @override
  String get status => 'Stato';

  @override
  String get available => 'Disponibile';

  @override
  String get profileVisibilityBoundary =>
      'Il tuo profilo è visibile ai membri WampApp autenticati. Il contenuto dei messaggi e le chiavi del dispositivo non sono mai inclusi.';

  @override
  String copyLabel(String label) {
    return 'Copia $label';
  }

  @override
  String get online => 'Online';

  @override
  String get encryptedMessages => 'Messaggi crittografati';

  @override
  String get groupCallsUnavailable =>
      'Le chiamate di gruppo non sono ancora disponibili';

  @override
  String get startEncryptedVoiceCall => 'Avvia chiamata vocale crittografata';

  @override
  String get startEncryptedVideoCall => 'Avvia videochiamata crittografata';

  @override
  String get unmuteChat => 'Riattiva le notifiche della chat';

  @override
  String get muteChat => 'Silenzia questa chat';

  @override
  String chatAppearance(String appearance) {
    return 'Aspetto della chat: $appearance';
  }

  @override
  String get syncMessages => 'Sincronizza messaggi';

  @override
  String localSearchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ricerca locale · $count risultati',
      one: 'Ricerca locale · 1 risultato',
    );
    return '$_temp0';
  }

  @override
  String get searchLocalMessages =>
      'Cerca nei messaggi locali · resta su questo dispositivo';

  @override
  String get clearMessageSearch => 'Cancella ricerca messaggi';

  @override
  String get direct => 'Diretta';

  @override
  String get newGroup => 'Nuovo gruppo';

  @override
  String get all => 'Tutti';

  @override
  String get unreadReceived => 'Ricevuti non letti';

  @override
  String get readReceived => 'Ricevuti letti';

  @override
  String get startDirectChat => 'Avvia una chat diretta';

  @override
  String get directChat => 'Chat diretta';

  @override
  String get closeDirectChat => 'Chiudi chat diretta';

  @override
  String get verifyEncryptionIdentity => 'Verifica identità di crittografia';

  @override
  String get viewPublicProfile => 'Visualizza profilo pubblico';

  @override
  String get groupUnavailable => 'Gruppo non disponibile';

  @override
  String get noSearchMessages =>
      'Nessun messaggio locale corrisponde alla ricerca e al filtro.';

  @override
  String get noMessages =>
      'Ancora nessun messaggio. Scegli un account registrato e invia il primo messaggio crittografato end-to-end.';

  @override
  String get noUnreadMessages =>
      'Nessun messaggio ricevuto non letto in questa chat.';

  @override
  String get noReadMessages =>
      'Nessun messaggio ricevuto letto in questa chat.';

  @override
  String get viewOnce => 'Visualizza una volta';

  @override
  String get keepChatMessages => 'Conserva messaggi della chat';

  @override
  String get deleteAfterOneHour => 'Elimina dopo 1 ora';

  @override
  String get deleteAfterOneDay => 'Elimina dopo 1 giorno';

  @override
  String get deleteAfterSevenDays => 'Elimina dopo 7 giorni';

  @override
  String get autoDeleteEnabled => 'Eliminazione automatica attiva';

  @override
  String get appearanceStandard => 'Standard';

  @override
  String get appearanceOcean => 'Oceano';

  @override
  String get appearanceSunset => 'Tramonto';

  @override
  String recordingDuration(String duration) {
    return 'Registrazione $duration';
  }

  @override
  String get cancelVoiceNote => 'Annulla messaggio vocale';

  @override
  String get finishVoiceNote => 'Termina messaggio vocale';

  @override
  String get openConversationToReply => 'Apri una chat per rispondere';

  @override
  String get messageGroup => 'Messaggio al gruppo';

  @override
  String get message => 'Messaggio';

  @override
  String get chooseExpression => 'Scegli emoji o sticker crittografato';

  @override
  String get attachEncryptedFiles => 'Allega file crittografati';

  @override
  String get sendEncryptedMessage => 'Invia messaggio crittografato';

  @override
  String get recordEncryptedVoiceNote =>
      'Registra messaggio vocale crittografato';

  @override
  String get sending => 'Invio…';

  @override
  String get sentSyncing => 'Inviato · sincronizzazione';

  @override
  String get notSent => 'Non inviato';

  @override
  String get rejected => 'Rifiutato';

  @override
  String get messageConflict => 'Conflitto messaggio';

  @override
  String get opened => 'Aperto';

  @override
  String get readByEveryone => 'Letto da tutti';

  @override
  String get read => 'Letto';

  @override
  String get deliveredToEveryone => 'Consegnato a tutti';

  @override
  String get delivered => 'Consegnato';

  @override
  String get sent => 'Inviato';

  @override
  String get tapToOpenMarkRead => 'Tocca per aprire · segna come letto';

  @override
  String get tapToViewOnce => 'Tocca per visualizzare una volta';

  @override
  String get discard => 'Elimina';

  @override
  String get encrypted => 'crittografato';

  @override
  String get fileDecrypted =>
      'Il file è stato autenticato e decifrato su questo dispositivo.';

  @override
  String get pauseVoiceNote => 'Metti in pausa il messaggio vocale';

  @override
  String get playVoiceNote => 'Riproduci messaggio vocale';

  @override
  String get voiceNoteDecrypted =>
      'autenticato e decifrato su questo dispositivo';

  @override
  String get confirmSafetyNumber => 'Conferma numero di sicurezza';

  @override
  String get compareSafetyNumber =>
      'Continua solo dopo aver confrontato questo numero con il contatto tramite un altro canale fidato.';

  @override
  String get numbersMatch => 'I numeri corrispondono';

  @override
  String get encryptionIdentity => 'Identità di crittografia';

  @override
  String encryptionIdentityFor(String username) {
    return 'Identità di crittografia · @$username';
  }

  @override
  String get trustComparisonHelp =>
      'Confronta il numero di sicurezza di ogni dispositivo attivo tramite un altro canale fidato. La verifica rileva modifiche successive, ma non sostituisce il primo confronto.';

  @override
  String get verified => 'Verificato';

  @override
  String get verifyDevice => 'Verifica dispositivo';

  @override
  String get refresh => 'Aggiorna';

  @override
  String get trustLoadFailed =>
      'Impossibile caricare o verificare questa identità di crittografia.';

  @override
  String get trustUnverified =>
      'Non ancora verificato. Puoi inviare messaggi, ma confronta ogni dispositivo attivo prima di considerare attendibile questa identità.';

  @override
  String get trustVerified => 'Tutti i dispositivi attivi sono verificati.';

  @override
  String get trustChanged =>
      'L\'identità di crittografia è cambiata. L\'invio è bloccato finché ogni dispositivo attivo non viene controllato e verificato.';

  @override
  String get chatMuted => 'Chat silenziata per questo account.';

  @override
  String get chatUnmuted => 'Audio della chat riattivato per questo account.';

  @override
  String get chatPreferenceSaveFailed =>
      'Impossibile salvare la preferenza della chat.';

  @override
  String chatAppearanceSaved(String appearance) {
    return 'Aspetto $appearance salvato per questo account.';
  }

  @override
  String get chatAppearanceSaveFailed =>
      'Impossibile salvare l\'aspetto della chat.';

  @override
  String get disappearingMessagesDisabled =>
      'Messaggi a scomparsa disattivati per questa chat.';

  @override
  String disappearingMessagesEnabled(String retention) {
    return 'I nuovi messaggi in questa chat verranno $retention.';
  }

  @override
  String get openConversationBeforeSending =>
      'Apri una chat o inserisci un destinatario prima dell\'invio.';

  @override
  String get attachmentLimit => 'Un messaggio può contenere fino a 8 allegati.';

  @override
  String get attachmentSizeLimit =>
      'Ogni allegato deve essere di massimo 64 MiB.';

  @override
  String get attachmentReadFailed => 'Impossibile aprire i file selezionati.';

  @override
  String get stickerTooLarge =>
      'Lo sticker creato supera i limiti degli allegati.';

  @override
  String get stickerRenderFailed => 'Impossibile creare lo sticker.';

  @override
  String get microphoneStartFailed =>
      'Impossibile avviare la registrazione dal microfono.';

  @override
  String get voiceRecordingFailed =>
      'Registrazione del messaggio vocale non riuscita.';
}

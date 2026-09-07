// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'WampApp';

  @override
  String get chats => 'Chats';

  @override
  String get settings => 'Ajustes';

  @override
  String get account => 'Cuenta';

  @override
  String get privacy => 'Privacidad';

  @override
  String get appearance => 'Apariencia';

  @override
  String get dataAndStorage => 'Datos y almacenamiento';

  @override
  String get advanced => 'Avanzado';

  @override
  String get editProfile => 'Editar perfil';

  @override
  String get contacts => 'Contactos';

  @override
  String get contactsSubtitle =>
      'Gestiona los nombres guardados en este dispositivo';

  @override
  String get staySignedIn => 'Mantener la sesión con biometría';

  @override
  String get staySignedInSubtitle =>
      'Desbloquea el inicio de sesión guardado con Face ID, Touch ID o la biometría del dispositivo';

  @override
  String get biometricsUnavailable =>
      'El inicio de sesión biométrico no está disponible en este dispositivo.';

  @override
  String get biometricPasswordPrompt =>
      'Confirma la contraseña de tu cuenta para activar el inicio de sesión biométrico.';

  @override
  String get signInWithBiometrics => 'Iniciar sesión con biometría';

  @override
  String get pushNotifications => 'Notificaciones push';

  @override
  String get pushNotificationsSubtitle =>
      'Recibe avisos de mensajes nuevos cuando WampApp no esté abierto';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Usar ajuste del dispositivo';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get accentColor => 'Color de la aplicación';

  @override
  String get accentColorSubtitle => 'Elige el color principal de WampApp';

  @override
  String get accentTeal => 'Verde azulado';

  @override
  String get accentBlue => 'Azul';

  @override
  String get accentCoral => 'Coral';

  @override
  String get accentAmber => 'Ámbar';

  @override
  String get accentIndigo => 'Índigo';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Usar idioma del dispositivo';

  @override
  String get languageEnglish => 'Inglés';

  @override
  String get languageGerman => 'Alemán';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageFrench => 'Francés';

  @override
  String get languageItalian => 'Italiano';

  @override
  String get languagePortuguese => 'Portugués';

  @override
  String get backup => 'Copia de seguridad';

  @override
  String get backupSubtitle => 'Exporta o restaura tu copia cifrada';

  @override
  String get serverBackup => 'Copia en el servidor';

  @override
  String get serverBackupSubtitle =>
      'Guarda en este servidor una copia cifrada con frase de recuperación';

  @override
  String get mcpAccess => 'Acceso de apps y agentes';

  @override
  String get mcpAccessSubtitle => 'Controla el acceso a tu perfil público';

  @override
  String get technicalInformation => 'Información técnica';

  @override
  String get technicalInformationSubtitle =>
      'Conexión, cifrado, dispositivo y endpoints';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get technicalIntro =>
      'Estos datos ayudan con soporte e integración. Tus chats, contraseñas, claves y tokens nunca se muestran aquí.';

  @override
  String get connection => 'Conexión';

  @override
  String get connected => 'Conectado';

  @override
  String get server => 'Servidor';

  @override
  String get websocketEndpoint => 'Endpoint WebSocket';

  @override
  String get applicationRealm => 'Realm de la aplicación';

  @override
  String get username => 'Usuario';

  @override
  String get device => 'Dispositivo';

  @override
  String get deviceId => 'ID del dispositivo';

  @override
  String get safetyNumber => 'Número de seguridad';

  @override
  String get encryption => 'Cifrado';

  @override
  String get encryptionSummary =>
      'Los mensajes y adjuntos están cifrados de extremo a extremo; las claves permanecen en la bóveda local cifrada.';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado al portapapeles';

  @override
  String get close => 'Cerrar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get enable => 'Activar';

  @override
  String get disable => 'Desactivar';

  @override
  String get save => 'Guardar';

  @override
  String get password => 'Contraseña';

  @override
  String get showPassword => 'Mostrar contraseña';

  @override
  String get hidePassword => 'Ocultar contraseña';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get serverAddress => 'Dirección del servidor';

  @override
  String get advancedServerSettings => 'Ajustes avanzados del servidor';

  @override
  String get advancedServerSettingsSubtitle =>
      'Cambia la dirección del servidor solo si te lo indica tu proveedor';

  @override
  String get displayName => 'Nombre visible';

  @override
  String get createAndConnect => 'Crear y conectar';

  @override
  String get connectSecurely => 'Iniciar sesión de forma segura';

  @override
  String get restoreEncryptedBackup => 'Restaurar copia cifrada';

  @override
  String get restoreBackupFromServer => 'Restaurar copia del servidor';

  @override
  String get checkingServer => 'Comprobando la disponibilidad del servicio…';

  @override
  String get serverReady => 'El servicio está listo.';

  @override
  String get serverUnavailable =>
      'Servicio no disponible. Comprueba la dirección e inténtalo de nuevo.';

  @override
  String get retry => 'Reintentar';

  @override
  String get introHeadline => 'Conversaciones privadas sin complicaciones.';

  @override
  String get introBody =>
      'Envía mensajes, llama y comparte con quien importa. Tus conversaciones permanecen cifradas de extremo a extremo en tus dispositivos.';

  @override
  String get privateByDesign => 'Privado desde el diseño';

  @override
  String get realTimeMessaging => 'Mensajería en tiempo real';

  @override
  String get yourOwnAccount => 'Tu propia cuenta';

  @override
  String get backupRestoreBoundary =>
      'Ambas opciones restauran la identidad del dispositivo, los chats, los ajustes y las claves de archivos adjuntos de esta cuenta. La copia del servidor está cifrada de extremo a extremo. Los archivos multimedia en caché no se incluyen y deben descargarse de nuevo.';

  @override
  String get contactPrivacyBoundary =>
      'Solo se guardan en el almacén cifrado del dispositivo el nombre visible seleccionado y el usuario de WampApp que introduzcas. Los teléfonos, correos, identificadores y archivos de la agenda nunca se suben ni se conservan.';

  @override
  String get importContacts => 'Importar contactos';

  @override
  String get addByUsername => 'Añadir por usuario';

  @override
  String get importedDisplayName => 'Nombre visible importado';

  @override
  String get nameOnDevice => 'Nombre en este dispositivo';

  @override
  String get wampAppUsername => 'Usuario de WampApp';

  @override
  String get contactVerifyHelper =>
      'Se verifica con el servidor conectado antes de guardar.';

  @override
  String get contactRenameHelper =>
      'La cuenta asociada no se puede cambiar al renombrar.';

  @override
  String get verifyAndSave => 'Verificar y guardar';

  @override
  String get saveLocalName => 'Guardar nombre local';

  @override
  String get noContactsSaved =>
      'No hay contactos guardados en este dispositivo.';

  @override
  String localContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contactos locales',
      one: '1 contacto local',
    );
    return '$_temp0';
  }

  @override
  String get renameLocalContact => 'Renombrar contacto local';

  @override
  String get removeLocalContact => 'Eliminar contacto local';

  @override
  String get contactReadFailed => 'No se pudo leer el contacto seleccionado.';

  @override
  String get encryptDeviceBackup => 'Cifrar copia del dispositivo';

  @override
  String get restoreBackup => 'Restaurar copia';

  @override
  String get backupCreateHelp =>
      'Esta frase es la única forma de descifrar la exportación. No se guarda ni se envía al servidor.';

  @override
  String get backupRestoreHelp =>
      'Introduce la frase de recuperación usada al crear esta copia del dispositivo.';

  @override
  String get recoveryPhrase => 'Frase de recuperación';

  @override
  String get confirmRecoveryPhrase => 'Confirmar frase de recuperación';

  @override
  String get passphraseLength => 'Usa entre 16 y 1024 bytes UTF-8.';

  @override
  String get passphraseMismatch => 'Las frases de recuperación no coinciden.';

  @override
  String get createBackup => 'Crear copia';

  @override
  String get chooseBackup => 'Elegir copia';

  @override
  String get unknown => 'desconocido';

  @override
  String get incomingEncryptedVideoCall => 'Videollamada cifrada entrante';

  @override
  String get incomingEncryptedVoiceCall => 'Llamada de voz cifrada entrante';

  @override
  String get decline => 'Rechazar';

  @override
  String get accept => 'Aceptar';

  @override
  String get unmute => 'Activar sonido';

  @override
  String get mute => 'Silenciar';

  @override
  String get cameraOff => 'Apagar cámara';

  @override
  String get cameraOn => 'Encender cámara';

  @override
  String get earpiece => 'Auricular';

  @override
  String get speaker => 'Altavoz';

  @override
  String get endCall => 'Finalizar';

  @override
  String get answeredOtherDevice => 'Respondida en otro dispositivo';

  @override
  String get callUnavailable => 'Llamada no disponible';

  @override
  String get callEnded => 'Llamada finalizada';

  @override
  String get backToChats => 'Volver a chats';

  @override
  String get callingSecurely => 'Llamando de forma segura…';

  @override
  String get connectingMedia => 'Conectando multimedia…';

  @override
  String get encryptedSignaling => 'Señalización cifrada de extremo a extremo';

  @override
  String get endingCall => 'Finalizando llamada…';

  @override
  String get emojiAndStickers => 'Emojis y stickers';

  @override
  String get closeExpressions => 'Cerrar emojis y stickers';

  @override
  String get searchExpressions => 'Buscar emojis y stickers';

  @override
  String get emoji => 'Emojis';

  @override
  String get stickers => 'Stickers';

  @override
  String stickerLabel(String label) {
    return 'Sticker $label';
  }

  @override
  String get noMatchingExpressions => 'No hay resultados';

  @override
  String get saveCopy => 'Guardar copia';

  @override
  String get viewOnceMessage => 'Mensaje de una sola vista';

  @override
  String get viewOnceOpenFailed =>
      'No se pudo abrir este archivo adjunto de una sola vista.';

  @override
  String get profileUpdated => 'Perfil actualizado.';

  @override
  String get profileUpdateFailed => 'No se pudo actualizar el perfil.';

  @override
  String get allow => 'Permitir';

  @override
  String get allowMcpProfileTitle => '¿Permitir acceso al perfil público?';

  @override
  String get mcpProfileConsentBoundary =>
      'Una aplicación o agente autenticado podrá leer tu usuario, nombre visible, estado y revisión del perfil. Los chats, mensajes, adjuntos, copias, dispositivos, llamadas, claves y avatar seguirán inaccesibles. Puedes revocar el acceso de inmediato.';

  @override
  String get mcpConsentUpdateFailed =>
      'No se pudo actualizar el acceso al perfil público.';

  @override
  String get mcpConnectionLoadFailed =>
      'No se pudo cargar la información de conexión para aplicaciones y agentes.';

  @override
  String get connectAiService => 'Conectar un servicio de IA';

  @override
  String get mcpConnectionHelp =>
      'Usa el siguiente punto de acceso con un cliente compatible con Streamable HTTP o JSON directo. El cliente se autentica como esta cuenta WampApp mediante una concesión WAMP-SCRAM.';

  @override
  String get mcpEndpoint => 'Punto de acceso MCP';

  @override
  String get authenticationEndpoint => 'Punto de autenticación';

  @override
  String get mcpEndpointCopied => 'Punto MCP copiado.';

  @override
  String get authEndpointCopied => 'Punto de autenticación copiado.';

  @override
  String mcpAccount(String username) {
    return 'Cuenta: @$username';
  }

  @override
  String mcpRealm(String realm) {
    return 'Realm: $realm';
  }

  @override
  String get mcpAuthentication => 'Autenticación: concesión WAMP-SCRAM';

  @override
  String get mcpCatalog =>
      'Catálogos: herramientas, recursos y prompts · Transportes: Streamable HTTP y JSON directo';

  @override
  String get allowPublicProfileAccess => 'Permitir acceso al perfil público';

  @override
  String get accessEnabled => 'Activado. La revocación es inmediata.';

  @override
  String get accessDisabledByDefault => 'Desactivado por defecto.';

  @override
  String visibleFields(String fields) {
    return 'Campos visibles: $fields.';
  }

  @override
  String get mcpDataBoundary =>
      'Los chats, mensajes, adjuntos, copias, dispositivos, llamadas, claves y avatares siguen inaccesibles. WampApp nunca muestra ni copia tu contraseña ni tus tokens de acceso o actualización.';

  @override
  String get enterRecipientFirst =>
      'Introduce primero el usuario del destinatario.';

  @override
  String get profileLoadFailed => 'No se pudo cargar ese perfil.';

  @override
  String get publicProfile => 'Perfil público';

  @override
  String get noStatusSet => 'Sin estado';

  @override
  String get encryptedDeviceBackupSaved =>
      'Copia cifrada del dispositivo guardada.';

  @override
  String get backupCancelled => 'La copia se canceló.';

  @override
  String get encryptedServerBackupSaved =>
      'Copia cifrada guardada en este servidor.';

  @override
  String get cloudBackupCancelled => 'La copia del servidor se canceló.';

  @override
  String get encryptedBackup => 'Copia cifrada';

  @override
  String get saveBackupFile => 'Guardar archivo de copia';

  @override
  String get saveBackupFileSubtitle => 'Conserva tu propio archivo cifrado.';

  @override
  String get backupToServer => 'Guardar en este servidor';

  @override
  String get backupToServerSubtitle =>
      'El servidor solo almacena el archivo cifrado.';

  @override
  String get newEncryptedGroup => 'Nuevo grupo cifrado';

  @override
  String get groupName => 'Nombre del grupo';

  @override
  String get memberUsernames => 'Usuarios de los miembros';

  @override
  String get separateUsernames => 'Separa los usuarios con comas';

  @override
  String get createGroup => 'Crear grupo';

  @override
  String get editPublicProfile => 'Editar perfil público';

  @override
  String get chooseImage => 'Elegir imagen';

  @override
  String get remove => 'Eliminar';

  @override
  String get status => 'Estado';

  @override
  String get available => 'Disponible';

  @override
  String get profileVisibilityBoundary =>
      'Tu perfil es visible para miembros autenticados de WampApp. El contenido de los mensajes y las claves del dispositivo nunca se incluyen.';

  @override
  String copyLabel(String label) {
    return 'Copiar $label';
  }

  @override
  String get online => 'En línea';

  @override
  String get encryptedMessages => 'Mensajes cifrados';

  @override
  String get groupCallsUnavailable =>
      'Las llamadas de grupo aún no están disponibles';

  @override
  String get startEncryptedVoiceCall => 'Iniciar llamada de voz cifrada';

  @override
  String get startEncryptedVideoCall => 'Iniciar videollamada cifrada';

  @override
  String get unmuteChat => 'Activar notificaciones del chat';

  @override
  String get muteChat => 'Silenciar este chat';

  @override
  String chatAppearance(String appearance) {
    return 'Apariencia del chat: $appearance';
  }

  @override
  String get syncMessages => 'Sincronizar mensajes';

  @override
  String localSearchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Búsqueda local · $count resultados',
      one: 'Búsqueda local · 1 resultado',
    );
    return '$_temp0';
  }

  @override
  String get searchLocalMessages =>
      'Buscar mensajes locales · permanece en este dispositivo';

  @override
  String get clearMessageSearch => 'Borrar búsqueda de mensajes';

  @override
  String get direct => 'Directo';

  @override
  String get newGroup => 'Nuevo grupo';

  @override
  String get all => 'Todos';

  @override
  String get unreadReceived => 'Recibidos sin leer';

  @override
  String get readReceived => 'Recibidos leídos';

  @override
  String get startDirectChat => 'Iniciar un chat directo';

  @override
  String get directChat => 'Chat directo';

  @override
  String get closeDirectChat => 'Cerrar chat directo';

  @override
  String get verifyEncryptionIdentity => 'Verificar identidad de cifrado';

  @override
  String get viewPublicProfile => 'Ver perfil público';

  @override
  String get groupUnavailable => 'Grupo no disponible';

  @override
  String get noSearchMessages =>
      'Ningún mensaje local coincide con esta búsqueda y filtro.';

  @override
  String get noMessages =>
      'Aún no hay mensajes. Elige una cuenta registrada y envía el primer mensaje cifrado de extremo a extremo.';

  @override
  String get noUnreadMessages =>
      'No hay mensajes recibidos sin leer en este chat.';

  @override
  String get noReadMessages => 'No hay mensajes recibidos leídos en este chat.';

  @override
  String get viewOnce => 'Ver una vez';

  @override
  String get keepChatMessages => 'Conservar mensajes del chat';

  @override
  String get deleteAfterOneHour => 'Eliminar después de 1 hora';

  @override
  String get deleteAfterOneDay => 'Eliminar después de 1 día';

  @override
  String get deleteAfterSevenDays => 'Eliminar después de 7 días';

  @override
  String get autoDeleteEnabled => 'Eliminación automática activada';

  @override
  String get appearanceStandard => 'Estándar';

  @override
  String get appearanceOcean => 'Océano';

  @override
  String get appearanceSunset => 'Atardecer';

  @override
  String recordingDuration(String duration) {
    return 'Grabando $duration';
  }

  @override
  String get cancelVoiceNote => 'Cancelar nota de voz';

  @override
  String get finishVoiceNote => 'Finalizar nota de voz';

  @override
  String get openConversationToReply => 'Abre un chat para responder';

  @override
  String get messageGroup => 'Mensaje al grupo';

  @override
  String get message => 'Mensaje';

  @override
  String get chooseExpression => 'Elegir emoji o sticker cifrado';

  @override
  String get attachEncryptedFiles => 'Adjuntar archivos cifrados';

  @override
  String get sendEncryptedMessage => 'Enviar mensaje cifrado';

  @override
  String get recordEncryptedVoiceNote => 'Grabar nota de voz cifrada';

  @override
  String get sending => 'Enviando…';

  @override
  String get sentSyncing => 'Enviado · sincronizando';

  @override
  String get notSent => 'No enviado';

  @override
  String get rejected => 'Rechazado';

  @override
  String get messageConflict => 'Conflicto de mensaje';

  @override
  String get opened => 'Abierto';

  @override
  String get readByEveryone => 'Leído por todos';

  @override
  String get read => 'Leído';

  @override
  String get deliveredToEveryone => 'Entregado a todos';

  @override
  String get delivered => 'Entregado';

  @override
  String get sent => 'Enviado';

  @override
  String get tapToOpenMarkRead => 'Toca para abrir · marcar como leído';

  @override
  String get tapToViewOnce => 'Toca para ver una vez';

  @override
  String get discard => 'Descartar';

  @override
  String get encrypted => 'cifrado';

  @override
  String get fileDecrypted =>
      'El archivo se autenticó y descifró en este dispositivo.';

  @override
  String get pauseVoiceNote => 'Pausar nota de voz';

  @override
  String get playVoiceNote => 'Reproducir nota de voz';

  @override
  String get voiceNoteDecrypted =>
      'autenticado y descifrado en este dispositivo';

  @override
  String get confirmSafetyNumber => 'Confirmar número de seguridad';

  @override
  String get compareSafetyNumber =>
      'Continúa solo después de comparar este número con tu contacto por otro canal de confianza.';

  @override
  String get numbersMatch => 'Los números coinciden';

  @override
  String get encryptionIdentity => 'Identidad de cifrado';

  @override
  String encryptionIdentityFor(String username) {
    return 'Identidad de cifrado · @$username';
  }

  @override
  String get trustComparisonHelp =>
      'Compara el número de seguridad de cada dispositivo activo por otro canal de confianza. La verificación detecta cambios posteriores, pero no sustituye esa primera comparación.';

  @override
  String get verified => 'Verificado';

  @override
  String get verifyDevice => 'Verificar dispositivo';

  @override
  String get refresh => 'Actualizar';

  @override
  String get trustLoadFailed =>
      'No se pudo cargar o verificar esta identidad de cifrado.';

  @override
  String get trustUnverified =>
      'Aún sin verificar. Se pueden enviar mensajes, pero compara cada dispositivo activo antes de confiar en esta identidad.';

  @override
  String get trustVerified =>
      'Todos los dispositivos activos están verificados.';

  @override
  String get trustChanged =>
      'La identidad de cifrado ha cambiado. El envío está bloqueado hasta revisar y verificar todos los dispositivos activos.';

  @override
  String get chatMuted => 'Chat silenciado en esta cuenta.';

  @override
  String get chatUnmuted => 'Chat con sonido en esta cuenta.';

  @override
  String get chatPreferenceSaveFailed =>
      'No se pudo guardar la preferencia del chat.';

  @override
  String chatAppearanceSaved(String appearance) {
    return 'Apariencia $appearance guardada en esta cuenta.';
  }

  @override
  String get chatAppearanceSaveFailed =>
      'No se pudo guardar la apariencia del chat.';

  @override
  String get disappearingMessagesDisabled =>
      'Mensajes temporales desactivados para este chat.';

  @override
  String disappearingMessagesEnabled(String retention) {
    return 'Los nuevos mensajes de este chat se $retention.';
  }

  @override
  String get openConversationBeforeSending =>
      'Abre un chat o introduce un destinatario antes de enviar.';

  @override
  String get attachmentLimit =>
      'Un mensaje puede contener hasta 8 archivos adjuntos.';

  @override
  String get attachmentSizeLimit =>
      'Cada archivo adjunto debe tener 64 MiB o menos.';

  @override
  String get attachmentReadFailed =>
      'No se pudieron abrir los archivos seleccionados.';

  @override
  String get stickerTooLarge =>
      'El sticker creado supera los límites de archivos adjuntos.';

  @override
  String get stickerRenderFailed => 'No se pudo crear el sticker.';

  @override
  String get microphoneStartFailed =>
      'No se pudo iniciar la grabación del micrófono.';

  @override
  String get voiceRecordingFailed => 'No se pudo grabar la nota de voz.';
}

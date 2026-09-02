// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'WampApp';

  @override
  String get chats => 'Conversas';

  @override
  String get settings => 'Definições';

  @override
  String get account => 'Conta';

  @override
  String get privacy => 'Privacidade';

  @override
  String get appearance => 'Aparência';

  @override
  String get dataAndStorage => 'Dados e armazenamento';

  @override
  String get advanced => 'Avançado';

  @override
  String get editProfile => 'Editar perfil';

  @override
  String get contacts => 'Contactos';

  @override
  String get contactsSubtitle => 'Gerir os nomes guardados neste dispositivo';

  @override
  String get staySignedIn => 'Manter sessão com biometria';

  @override
  String get staySignedInSubtitle =>
      'Desbloqueie o início de sessão guardado com Face ID, Touch ID ou biometria do dispositivo';

  @override
  String get biometricsUnavailable =>
      'O início de sessão biométrico não está disponível neste dispositivo.';

  @override
  String get biometricPasswordPrompt =>
      'Confirme a palavra-passe da conta para ativar o início de sessão biométrico.';

  @override
  String get signInWithBiometrics => 'Iniciar sessão com biometria';

  @override
  String get pushNotifications => 'Notificações push';

  @override
  String get pushNotificationsSubtitle =>
      'Receba avisos de novas mensagens quando a WampApp não estiver aberta';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Usar definição do dispositivo';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Usar idioma do dispositivo';

  @override
  String get languageEnglish => 'Inglês';

  @override
  String get languageGerman => 'Alemão';

  @override
  String get languageSpanish => 'Espanhol';

  @override
  String get languageFrench => 'Francês';

  @override
  String get languageItalian => 'Italiano';

  @override
  String get languagePortuguese => 'Português';

  @override
  String get backup => 'Cópia de segurança';

  @override
  String get backupSubtitle => 'Exportar ou restaurar a cópia encriptada';

  @override
  String get serverBackup => 'Cópia no servidor';

  @override
  String get serverBackupSubtitle =>
      'Guardar neste servidor uma cópia encriptada com frase de recuperação';

  @override
  String get mcpAccess => 'Acesso de apps e agentes';

  @override
  String get mcpAccessSubtitle => 'Controlar o acesso ao seu perfil público';

  @override
  String get technicalInformation => 'Informações técnicas';

  @override
  String get technicalInformationSubtitle =>
      'Ligação, encriptação, dispositivo e endpoints';

  @override
  String get signOut => 'Terminar sessão';

  @override
  String get technicalIntro =>
      'Estes detalhes ajudam no suporte e integração. Conversas, palavras-passe, chaves e tokens nunca são mostrados aqui.';

  @override
  String get connection => 'Ligação';

  @override
  String get connected => 'Ligado';

  @override
  String get server => 'Servidor';

  @override
  String get websocketEndpoint => 'Endpoint WebSocket';

  @override
  String get applicationRealm => 'Realm da aplicação';

  @override
  String get username => 'Nome de utilizador';

  @override
  String get device => 'Dispositivo';

  @override
  String get deviceId => 'ID do dispositivo';

  @override
  String get safetyNumber => 'Número de segurança';

  @override
  String get encryption => 'Encriptação';

  @override
  String get encryptionSummary =>
      'Mensagens e anexos têm encriptação ponto a ponto; as chaves ficam no cofre local encriptado.';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado para a área de transferência';

  @override
  String get close => 'Fechar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get enable => 'Ativar';

  @override
  String get disable => 'Desativar';

  @override
  String get save => 'Guardar';

  @override
  String get password => 'Palavra-passe';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get signIn => 'Entrar';

  @override
  String get serverAddress => 'Endereço do servidor';

  @override
  String get displayName => 'Nome de exibição';

  @override
  String get createAndConnect => 'Criar e conectar';

  @override
  String get connectSecurely => 'Entrar com segurança';

  @override
  String get restoreEncryptedBackup => 'Restaurar cópia cifrada';

  @override
  String get restoreBackupFromServer => 'Restaurar cópia do servidor';

  @override
  String get checkingServer => 'A verificar a disponibilidade do serviço…';

  @override
  String get serverReady => 'O serviço está pronto.';

  @override
  String get serverUnavailable =>
      'Serviço indisponível. Verifique o endereço e tente novamente.';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get introHeadline => 'Conversas privadas sem complicações.';

  @override
  String get introBody =>
      'Envie mensagens, ligue e partilhe com quem importa. As suas conversas permanecem cifradas de ponta a ponta nos seus dispositivos.';

  @override
  String get privateByDesign => 'Privado desde o início';

  @override
  String get realTimeMessaging => 'Mensagens em tempo real';

  @override
  String get yourOwnAccount => 'A sua própria conta';

  @override
  String get backupRestoreBoundary =>
      'Ambas as opções restauram a identidade do dispositivo, as conversas, as definições e as chaves de anexos desta conta. A cópia no servidor é encriptada de ponta a ponta. Os ficheiros multimédia em cache não são incluídos e têm de ser transferidos novamente.';

  @override
  String get contactPrivacyBoundary =>
      'Apenas o nome apresentado selecionado e o nome de utilizador WampApp introduzido são guardados no cofre encriptado do dispositivo. Números, emails, IDs e ficheiros da agenda nunca são enviados nem conservados.';

  @override
  String get importContacts => 'Importar contactos';

  @override
  String get addByUsername => 'Adicionar por utilizador';

  @override
  String get importedDisplayName => 'Nome apresentado importado';

  @override
  String get nameOnDevice => 'Nome neste dispositivo';

  @override
  String get wampAppUsername => 'Nome de utilizador WampApp';

  @override
  String get contactVerifyHelper =>
      'Verificado com o servidor ligado antes de guardar.';

  @override
  String get contactRenameHelper =>
      'A conta associada não pode ser alterada ao mudar o nome.';

  @override
  String get verifyAndSave => 'Verificar e guardar';

  @override
  String get saveLocalName => 'Guardar nome local';

  @override
  String get noContactsSaved =>
      'Não existem contactos guardados neste dispositivo.';

  @override
  String localContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contactos locais',
      one: '1 contacto local',
    );
    return '$_temp0';
  }

  @override
  String get renameLocalContact => 'Mudar nome do contacto local';

  @override
  String get removeLocalContact => 'Remover contacto local';

  @override
  String get contactReadFailed =>
      'Não foi possível ler o contacto selecionado.';

  @override
  String get encryptDeviceBackup => 'Encriptar cópia do dispositivo';

  @override
  String get restoreBackup => 'Restaurar cópia';

  @override
  String get backupCreateHelp =>
      'Esta frase é a única forma de desencriptar a exportação. Não é guardada nem enviada ao servidor.';

  @override
  String get backupRestoreHelp =>
      'Introduza a frase de recuperação usada ao criar esta cópia do dispositivo.';

  @override
  String get recoveryPhrase => 'Frase de recuperação';

  @override
  String get confirmRecoveryPhrase => 'Confirmar frase de recuperação';

  @override
  String get passphraseLength => 'Utilize entre 16 e 1024 bytes UTF-8.';

  @override
  String get passphraseMismatch => 'As frases de recuperação não correspondem.';

  @override
  String get createBackup => 'Criar cópia';

  @override
  String get chooseBackup => 'Escolher cópia';

  @override
  String get unknown => 'desconhecido';

  @override
  String get incomingEncryptedVideoCall => 'Videochamada encriptada recebida';

  @override
  String get incomingEncryptedVoiceCall => 'Chamada de voz encriptada recebida';

  @override
  String get decline => 'Recusar';

  @override
  String get accept => 'Aceitar';

  @override
  String get unmute => 'Ativar som';

  @override
  String get mute => 'Silenciar';

  @override
  String get cameraOff => 'Desligar câmara';

  @override
  String get cameraOn => 'Ligar câmara';

  @override
  String get earpiece => 'Auricular';

  @override
  String get speaker => 'Altifalante';

  @override
  String get endCall => 'Terminar';

  @override
  String get answeredOtherDevice => 'Atendida noutro dispositivo';

  @override
  String get callUnavailable => 'Chamada indisponível';

  @override
  String get callEnded => 'Chamada terminada';

  @override
  String get backToChats => 'Voltar às conversas';

  @override
  String get callingSecurely => 'A efetuar chamada segura…';

  @override
  String get connectingMedia => 'A ligar multimédia…';

  @override
  String get encryptedSignaling => 'Sinalização encriptada de ponta a ponta';

  @override
  String get endingCall => 'A terminar chamada…';

  @override
  String get emojiAndStickers => 'Emojis e stickers';

  @override
  String get closeExpressions => 'Fechar emojis e stickers';

  @override
  String get searchExpressions => 'Procurar emojis e stickers';

  @override
  String get emoji => 'Emojis';

  @override
  String get stickers => 'Stickers';

  @override
  String stickerLabel(String label) {
    return 'Sticker $label';
  }

  @override
  String get noMatchingExpressions => 'Sem resultados';

  @override
  String get saveCopy => 'Guardar cópia';

  @override
  String get viewOnceMessage => 'Mensagem de visualização única';

  @override
  String get viewOnceOpenFailed =>
      'Não foi possível abrir este anexo de visualização única.';

  @override
  String get profileUpdated => 'Perfil atualizado.';

  @override
  String get profileUpdateFailed => 'Não foi possível atualizar o perfil.';

  @override
  String get allow => 'Permitir';

  @override
  String get allowMcpProfileTitle => 'Permitir acesso ao perfil público?';

  @override
  String get mcpProfileConsentBoundary =>
      'Uma aplicação ou agente autenticado poderá ler o seu nome de utilizador, nome apresentado, estado e revisão do perfil. Conversas, mensagens, anexos, cópias, dispositivos, chamadas, chaves e avatar continuam inacessíveis. Pode revogar o acesso imediatamente.';

  @override
  String get mcpConsentUpdateFailed =>
      'Não foi possível atualizar o acesso ao perfil público.';

  @override
  String get mcpConnectionLoadFailed =>
      'Não foi possível carregar as informações de ligação para aplicações e agentes.';

  @override
  String get connectAiService => 'Ligar um serviço de IA';

  @override
  String get mcpConnectionHelp =>
      'Use o ponto de acesso abaixo com um cliente compatível com Streamable HTTP ou JSON direto. O cliente autentica-se como esta conta WampApp através de uma autorização WAMP-SCRAM.';

  @override
  String get mcpEndpoint => 'Ponto de acesso MCP';

  @override
  String get authenticationEndpoint => 'Ponto de autenticação';

  @override
  String get mcpEndpointCopied => 'Ponto MCP copiado.';

  @override
  String get authEndpointCopied => 'Ponto de autenticação copiado.';

  @override
  String mcpAccount(String username) {
    return 'Conta: @$username';
  }

  @override
  String mcpRealm(String realm) {
    return 'Realm: $realm';
  }

  @override
  String get mcpAuthentication => 'Autenticação: autorização WAMP-SCRAM';

  @override
  String get mcpCatalog =>
      'Catálogos: ferramentas, recursos e prompts · Transportes: Streamable HTTP e JSON direto';

  @override
  String get allowPublicProfileAccess => 'Permitir acesso ao perfil público';

  @override
  String get accessEnabled => 'Ativado. A revogação tem efeito imediato.';

  @override
  String get accessDisabledByDefault => 'Desativado por predefinição.';

  @override
  String visibleFields(String fields) {
    return 'Campos visíveis: $fields.';
  }

  @override
  String get mcpDataBoundary =>
      'Conversas, mensagens, anexos, cópias, dispositivos, chamadas, chaves e avatares continuam inacessíveis. A WampApp nunca mostra nem copia a palavra-passe ou tokens de acesso e atualização.';

  @override
  String get enterRecipientFirst =>
      'Introduza primeiro o nome de utilizador do destinatário.';

  @override
  String get profileLoadFailed => 'Não foi possível carregar esse perfil.';

  @override
  String get publicProfile => 'Perfil público';

  @override
  String get noStatusSet => 'Sem estado';

  @override
  String get encryptedDeviceBackupSaved =>
      'Cópia encriptada do dispositivo guardada.';

  @override
  String get backupCancelled => 'A cópia foi cancelada.';

  @override
  String get encryptedServerBackupSaved =>
      'Cópia encriptada guardada neste servidor.';

  @override
  String get cloudBackupCancelled => 'A cópia do servidor foi cancelada.';

  @override
  String get encryptedBackup => 'Cópia encriptada';

  @override
  String get saveBackupFile => 'Guardar ficheiro de cópia';

  @override
  String get saveBackupFileSubtitle =>
      'Conserve o seu próprio arquivo encriptado.';

  @override
  String get backupToServer => 'Guardar neste servidor';

  @override
  String get backupToServerSubtitle =>
      'O servidor guarda apenas o arquivo encriptado.';

  @override
  String get newEncryptedGroup => 'Novo grupo encriptado';

  @override
  String get groupName => 'Nome do grupo';

  @override
  String get memberUsernames => 'Utilizadores do grupo';

  @override
  String get separateUsernames => 'Separe os utilizadores com vírgulas';

  @override
  String get createGroup => 'Criar grupo';

  @override
  String get editPublicProfile => 'Editar perfil público';

  @override
  String get chooseImage => 'Escolher imagem';

  @override
  String get remove => 'Remover';

  @override
  String get status => 'Estado';

  @override
  String get available => 'Disponível';

  @override
  String get profileVisibilityBoundary =>
      'O seu perfil é visível para membros autenticados da WampApp. O conteúdo das mensagens e as chaves do dispositivo nunca são incluídos.';

  @override
  String copyLabel(String label) {
    return 'Copiar $label';
  }

  @override
  String get online => 'Online';

  @override
  String get encryptedMessages => 'Mensagens encriptadas';

  @override
  String get groupCallsUnavailable =>
      'As chamadas de grupo ainda não estão disponíveis';

  @override
  String get startEncryptedVoiceCall => 'Iniciar chamada de voz encriptada';

  @override
  String get startEncryptedVideoCall => 'Iniciar videochamada encriptada';

  @override
  String get unmuteChat => 'Ativar notificações desta conversa';

  @override
  String get muteChat => 'Silenciar esta conversa';

  @override
  String chatAppearance(String appearance) {
    return 'Aspeto da conversa: $appearance';
  }

  @override
  String get syncMessages => 'Sincronizar mensagens';

  @override
  String localSearchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pesquisa local · $count resultados',
      one: 'Pesquisa local · 1 resultado',
    );
    return '$_temp0';
  }

  @override
  String get searchLocalMessages =>
      'Pesquisar mensagens locais · permanece neste dispositivo';

  @override
  String get clearMessageSearch => 'Limpar pesquisa de mensagens';

  @override
  String get direct => 'Direta';

  @override
  String get newGroup => 'Novo grupo';

  @override
  String get all => 'Todas';

  @override
  String get unreadReceived => 'Recebidas não lidas';

  @override
  String get readReceived => 'Recebidas lidas';

  @override
  String get startDirectChat => 'Iniciar conversa direta';

  @override
  String get directChat => 'Conversa direta';

  @override
  String get closeDirectChat => 'Fechar conversa direta';

  @override
  String get verifyEncryptionIdentity => 'Verificar identidade de encriptação';

  @override
  String get viewPublicProfile => 'Ver perfil público';

  @override
  String get groupUnavailable => 'Grupo indisponível';

  @override
  String get noSearchMessages =>
      'Nenhuma mensagem local corresponde a esta pesquisa e filtro.';

  @override
  String get noMessages =>
      'Ainda não existem mensagens. Escolha uma conta registada e envie a primeira mensagem encriptada de ponta a ponta.';

  @override
  String get noUnreadMessages =>
      'Não existem mensagens recebidas não lidas nesta conversa.';

  @override
  String get noReadMessages =>
      'Não existem mensagens recebidas lidas nesta conversa.';

  @override
  String get viewOnce => 'Ver uma vez';

  @override
  String get keepChatMessages => 'Manter mensagens da conversa';

  @override
  String get deleteAfterOneHour => 'Eliminar após 1 hora';

  @override
  String get deleteAfterOneDay => 'Eliminar após 1 dia';

  @override
  String get deleteAfterSevenDays => 'Eliminar após 7 dias';

  @override
  String get autoDeleteEnabled => 'Eliminação automática ativada';

  @override
  String get appearanceStandard => 'Padrão';

  @override
  String get appearanceOcean => 'Oceano';

  @override
  String get appearanceSunset => 'Pôr do sol';

  @override
  String recordingDuration(String duration) {
    return 'A gravar $duration';
  }

  @override
  String get cancelVoiceNote => 'Cancelar mensagem de voz';

  @override
  String get finishVoiceNote => 'Terminar mensagem de voz';

  @override
  String get openConversationToReply => 'Abra uma conversa para responder';

  @override
  String get messageGroup => 'Mensagem para o grupo';

  @override
  String get message => 'Mensagem';

  @override
  String get chooseExpression => 'Escolher emoji ou sticker encriptado';

  @override
  String get attachEncryptedFiles => 'Anexar ficheiros encriptados';

  @override
  String get sendEncryptedMessage => 'Enviar mensagem encriptada';

  @override
  String get recordEncryptedVoiceNote => 'Gravar mensagem de voz encriptada';

  @override
  String get sending => 'A enviar…';

  @override
  String get sentSyncing => 'Enviada · a sincronizar';

  @override
  String get notSent => 'Não enviada';

  @override
  String get rejected => 'Rejeitada';

  @override
  String get messageConflict => 'Conflito de mensagem';

  @override
  String get opened => 'Aberta';

  @override
  String get readByEveryone => 'Lida por todos';

  @override
  String get read => 'Lida';

  @override
  String get deliveredToEveryone => 'Entregue a todos';

  @override
  String get delivered => 'Entregue';

  @override
  String get sent => 'Enviada';

  @override
  String get tapToOpenMarkRead => 'Toque para abrir · marcar como lida';

  @override
  String get tapToViewOnce => 'Toque para ver uma vez';

  @override
  String get discard => 'Eliminar';

  @override
  String get encrypted => 'encriptado';

  @override
  String get fileDecrypted =>
      'O ficheiro foi autenticado e desencriptado neste dispositivo.';

  @override
  String get pauseVoiceNote => 'Pausar mensagem de voz';

  @override
  String get playVoiceNote => 'Reproduzir mensagem de voz';

  @override
  String get voiceNoteDecrypted =>
      'autenticado e desencriptado neste dispositivo';

  @override
  String get confirmSafetyNumber => 'Confirmar número de segurança';

  @override
  String get compareSafetyNumber =>
      'Continue apenas depois de comparar este número com o contacto através de outro canal de confiança.';

  @override
  String get numbersMatch => 'Os números correspondem';

  @override
  String get encryptionIdentity => 'Identidade de encriptação';

  @override
  String encryptionIdentityFor(String username) {
    return 'Identidade de encriptação · @$username';
  }

  @override
  String get trustComparisonHelp =>
      'Compare o número de segurança de cada dispositivo ativo através de outro canal de confiança. A verificação deteta alterações posteriores, mas não substitui essa primeira comparação.';

  @override
  String get verified => 'Verificado';

  @override
  String get verifyDevice => 'Verificar dispositivo';

  @override
  String get refresh => 'Atualizar';

  @override
  String get trustLoadFailed =>
      'Não foi possível carregar ou verificar esta identidade de encriptação.';

  @override
  String get trustUnverified =>
      'Ainda não verificado. As mensagens podem ser enviadas, mas compare cada dispositivo ativo antes de confiar nesta identidade.';

  @override
  String get trustVerified => 'Todos os dispositivos ativos estão verificados.';

  @override
  String get trustChanged =>
      'A identidade de encriptação mudou. O envio está bloqueado até todos os dispositivos ativos serem revistos e verificados.';

  @override
  String get chatMuted => 'Conversa silenciada nesta conta.';

  @override
  String get chatUnmuted => 'Som da conversa ativado nesta conta.';

  @override
  String get chatPreferenceSaveFailed =>
      'Não foi possível guardar a preferência da conversa.';

  @override
  String chatAppearanceSaved(String appearance) {
    return 'Aspeto $appearance guardado nesta conta.';
  }

  @override
  String get chatAppearanceSaveFailed =>
      'Não foi possível guardar o aspeto da conversa.';

  @override
  String get disappearingMessagesDisabled =>
      'Mensagens temporárias desativadas nesta conversa.';

  @override
  String disappearingMessagesEnabled(String retention) {
    return 'As novas mensagens nesta conversa serão $retention.';
  }

  @override
  String get openConversationBeforeSending =>
      'Abra uma conversa ou introduza um destinatário antes de enviar.';

  @override
  String get attachmentLimit => 'Uma mensagem pode conter até 8 anexos.';

  @override
  String get attachmentSizeLimit => 'Cada anexo deve ter no máximo 64 MiB.';

  @override
  String get attachmentReadFailed =>
      'Não foi possível abrir os ficheiros selecionados.';

  @override
  String get stickerTooLarge => 'O sticker criado excede os limites de anexos.';

  @override
  String get stickerRenderFailed => 'Não foi possível criar o sticker.';

  @override
  String get microphoneStartFailed =>
      'Não foi possível iniciar a gravação do microfone.';

  @override
  String get voiceRecordingFailed =>
      'Não foi possível gravar a mensagem de voz.';
}

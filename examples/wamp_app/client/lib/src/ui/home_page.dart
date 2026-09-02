import 'dart:async';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../../l10n/generated/app_localizations.dart';
import '../application/wamp_app_controller.dart';
import '../application/call_controller.dart';
import '../domain/local_app_preferences.dart';
import '../domain/local_chat_message.dart';
import '../domain/local_message_query.dart';
import '../domain/outbound_chat_message.dart';
import '../infrastructure/attachment_cipher.dart';
import '../infrastructure/contact_importer.dart';
import '../infrastructure/profile_avatar_picker.dart';
import '../infrastructure/voice_note_playback.dart';
import '../infrastructure/voice_note_recorder.dart';
import '../infrastructure/wamp_account_gateway.dart';
import 'backup_passphrase_dialog.dart';
import 'call_overlay.dart';
import 'contact_manager_dialog.dart';
import 'expression_picker.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.connection,
    this.voiceNoteCaptureFactory,
    this.stickerRenderer,
    this.contactImporter,
    this.profileAvatarPicker,
  });

  final WampAppController controller;
  final AccountConnection connection;
  final VoiceNoteCapture Function()? voiceNoteCaptureFactory;
  final StickerRenderer? stickerRenderer;
  final ContactImporter? contactImporter;
  final ProfileAvatarPicker? profileAvatarPicker;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recipientController = TextEditingController();
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  bool _oneTime = false;
  String? _selectedGroupId;
  String _searchQuery = '';
  LocalMessageReadFilter _readFilter = LocalMessageReadFilter.all;
  Timer? _searchDebounce;
  List<_SelectedAttachment> _attachments = const [];
  VoiceNoteCapture? _voiceNoteCapture;
  VoiceNoteCaptureSession? _voiceRecording;
  Timer? _voiceRecordingTicker;
  DateTime? _voiceRecordingStartedAt;
  Duration _voiceRecordingElapsed = Duration.zero;
  bool _voiceControlBusy = false;
  bool _stickerBusy = false;

  VoiceNoteCapture get _recorder => _voiceNoteCapture ??=
      widget.voiceNoteCaptureFactory?.call() ?? VoiceNoteRecorder();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _voiceRecordingTicker?.cancel();
    for (final attachment in _attachments) {
      attachment.dispose();
    }
    final recorder = _voiceNoteCapture;
    recorder?.dispose().ignore();
    _recipientController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final text = _messageController.text;
    final sentAttachments = _attachments;
    final groupId = _selectedGroupId;
    final recipientUsername = _recipientController.text.trim();
    if (groupId == null && recipientUsername.isEmpty) {
      _showMessage(l10n.openConversationBeforeSending);
      return;
    }
    if (text.trim().isEmpty && sentAttachments.isEmpty) return;
    final conversationId =
        groupId ?? widget.controller.directConversationIdFor(recipientUsername);
    final expiresAfter = conversationId == null
        ? null
        : widget.controller.disappearingMessagesFor(conversationId);
    final attachmentSources = sentAttachments
        .map((attachment) => attachment.source)
        .toList(growable: false);
    final queued = groupId == null
        ? await widget.controller.sendMessage(
            recipientUsername: recipientUsername,
            text: text,
            oneTime: _oneTime,
            expiresAfter: expiresAfter,
            attachmentSources: attachmentSources,
          )
        : await widget.controller.sendGroupMessage(
            groupId: groupId,
            text: text,
            expiresAfter: expiresAfter,
            attachmentSources: attachmentSources,
          );
    if (mounted && queued) {
      setState(() {
        if (_messageController.text == text) {
          _messageController.clear();
        }
        _attachments = List<_SelectedAttachment>.unmodifiable(
          _attachments.where(
            (attachment) => !sentAttachments.contains(attachment),
          ),
        );
      });
      for (final attachment in sentAttachments) {
        attachment.dispose();
      }
    }
  }

  Future<void> _pickAttachments() async {
    final l10n = AppLocalizations.of(context);
    try {
      final files = await openFiles();
      if (!mounted || files.isEmpty) return;
      final remaining =
          WampAppAttachmentLimits.maxAttachmentsPerMessage -
          _attachments.length;
      if (remaining <= 0 || files.length > remaining) {
        throw FormatException(l10n.attachmentLimit);
      }
      final selected = <_SelectedAttachment>[];
      for (final file in files) {
        final byteCount = await file.length();
        if (byteCount > WampAppAttachmentLimits.maxAttachmentBytes) {
          throw FormatException(l10n.attachmentSizeLimit);
        }
        selected.add(_SelectedAttachment(file, byteCount));
      }
      if (!mounted) return;
      setState(() {
        _attachments = List<_SelectedAttachment>.unmodifiable([
          ..._attachments,
          ...selected,
        ]);
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : l10n.attachmentReadFailed;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.toString())));
    }
  }

  Future<void> _showExpressionPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    for (var attempt = 0; attempt < 20; attempt += 1) {
      if (!mounted || MediaQuery.viewInsetsOf(context).bottom == 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (context) => ExpressionPicker(
        onEmojiSelected: _insertEmoji,
        onStickerSelected: _stageSticker,
      ),
    );
  }

  void _insertEmoji(String emoji) {
    final value = _messageController.value;
    final selection = value.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, value.text.length)
        : value.text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, value.text.length)
        : value.text.length;
    final text = value.text.replaceRange(start, end, emoji);
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<bool> _stageSticker(StickerDesign design) async {
    final l10n = AppLocalizations.of(context);
    if (_stickerBusy) return false;
    Uint8List? rendered;
    if (_attachments.length >=
        WampAppAttachmentLimits.maxAttachmentsPerMessage) {
      _showMessage(l10n.attachmentLimit);
      return false;
    }
    setState(() => _stickerBusy = true);
    try {
      rendered =
          await (widget.stickerRenderer ?? const BundledStickerRenderer())
              .render(design);
      if (rendered.isEmpty ||
          rendered.length > WampAppAttachmentLimits.maxAttachmentBytes) {
        throw FormatException(l10n.stickerTooLarge);
      }
      if (!mounted) {
        rendered.fillRange(0, rendered.length, 0);
        return false;
      }
      final selected = _SelectedAttachment.sticker(rendered, design.id);
      rendered = null;
      setState(() {
        _attachments = List<_SelectedAttachment>.unmodifiable([
          ..._attachments,
          selected,
        ]);
      });
      return true;
    } catch (error) {
      rendered?.fillRange(0, rendered.length, 0);
      if (!mounted) return false;
      final message = error is FormatException
          ? error.message
          : l10n.stickerRenderFailed;
      _showMessage(message.toString());
      return false;
    } finally {
      if (mounted) setState(() => _stickerBusy = false);
    }
  }

  void _removeAttachment(int index) {
    final removed = _attachments[index];
    setState(() {
      _attachments = List<_SelectedAttachment>.unmodifiable([
        ..._attachments.take(index),
        ..._attachments.skip(index + 1),
      ]);
    });
    removed.dispose();
  }

  Future<void> _toggleVoiceRecording() async {
    final l10n = AppLocalizations.of(context);
    final active = _voiceRecording;
    if (active != null) {
      setState(() => _voiceControlBusy = true);
      try {
        await active.stop();
      } catch (error) {
        _failVoiceRecording(active, error);
      }
      return;
    }
    if (_attachments.length >=
        WampAppAttachmentLimits.maxAttachmentsPerMessage) {
      _showMessage(l10n.attachmentLimit);
      return;
    }
    setState(() => _voiceControlBusy = true);
    try {
      final session = await _recorder.start();
      if (!mounted) {
        await session.cancel();
        return;
      }
      setState(() {
        _voiceRecording = session;
        _voiceRecordingStartedAt = DateTime.now();
        _voiceRecordingElapsed = Duration.zero;
        _voiceControlBusy = false;
      });
      _voiceRecordingTicker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _updateVoiceRecordingElapsed(session),
      );
      session.completed.then(
        (recording) => _completeVoiceRecording(session, recording),
        onError: (Object error, StackTrace _) =>
            _failVoiceRecording(session, error),
      );
    } on VoiceNoteRecordingException catch (error) {
      if (!mounted) return;
      setState(() => _voiceControlBusy = false);
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _voiceControlBusy = false);
      _showMessage(l10n.microphoneStartFailed);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    final active = _voiceRecording;
    if (active == null || _voiceControlBusy) return;
    setState(() => _voiceControlBusy = true);
    try {
      await active.cancel();
    } catch (error) {
      _failVoiceRecording(active, error);
    }
  }

  void _updateVoiceRecordingElapsed(VoiceNoteCaptureSession session) {
    if (!mounted || !identical(_voiceRecording, session)) return;
    final startedAt = _voiceRecordingStartedAt;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    const maximum = Duration(
      milliseconds: WampAppAttachmentLimits.maxVoiceNoteDurationMilliseconds,
    );
    setState(() {
      _voiceRecordingElapsed = elapsed > maximum ? maximum : elapsed;
    });
  }

  void _completeVoiceRecording(
    VoiceNoteCaptureSession session,
    VoiceNoteRecording recording,
  ) {
    if (!mounted || !identical(_voiceRecording, session)) {
      recording.dispose();
      return;
    }
    _voiceRecordingTicker?.cancel();
    _voiceRecordingTicker = null;
    final durationMilliseconds = recording.durationMilliseconds;
    final bytes = recording.takeBytes();
    recording.dispose();
    final attachment = _SelectedAttachment.voiceNote(
      bytes,
      durationMilliseconds: durationMilliseconds,
    );
    setState(() {
      _voiceRecording = null;
      _voiceRecordingStartedAt = null;
      _voiceRecordingElapsed = Duration.zero;
      _voiceControlBusy = false;
      _attachments = List<_SelectedAttachment>.unmodifiable([
        ..._attachments,
        attachment,
      ]);
    });
  }

  void _failVoiceRecording(VoiceNoteCaptureSession session, Object error) {
    if (!mounted || !identical(_voiceRecording, session)) return;
    _voiceRecordingTicker?.cancel();
    _voiceRecordingTicker = null;
    setState(() {
      _voiceRecording = null;
      _voiceRecordingStartedAt = null;
      _voiceRecordingElapsed = Duration.zero;
      _voiceControlBusy = false;
    });
    if (error is! VoiceNoteRecordingCancelled) {
      _showMessage(
        error is VoiceNoteRecordingException
            ? error.message
            : AppLocalizations.of(context).voiceRecordingFailed,
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAttachment(
    LocalChatMessage message,
    EncryptedAttachmentDescriptor attachment,
  ) async {
    if (!message.outgoing) {
      await widget.controller.markMessageRead(message.messageId);
    }
    final bytes = await widget.controller.loadAttachment(
      messageId: message.messageId,
      attachmentId: attachment.attachmentId,
    );
    if (bytes == null) return;
    await _showAttachmentBytes(attachment, bytes, allowSaveCopy: true);
  }

  Future<void> _showAttachmentBytes(
    EncryptedAttachmentDescriptor attachment,
    Uint8List bytes, {
    required bool allowSaveCopy,
  }) async {
    if (!mounted) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    final l10n = AppLocalizations.of(context);
    MemoryImage? preview;
    VoiceNotePlaybackController? voicePlayer;
    try {
      if (attachment.kind == ChatAttachmentKind.image ||
          attachment.kind == ChatAttachmentKind.gif ||
          attachment.kind == ChatAttachmentKind.sticker) {
        preview = MemoryImage(bytes);
      } else if (attachment.kind == ChatAttachmentKind.voiceNote) {
        voicePlayer = VoiceNotePlaybackController(
          bytes,
          expectedDuration: Duration(
            milliseconds: attachment.durationMilliseconds!,
          ),
        );
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(attachment.name),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
            child: voicePlayer != null
                ? _VoiceNotePlayer(
                    controller: voicePlayer,
                    attachment: attachment,
                  )
                : preview == null
                ? _FileSummary(attachment: attachment)
                : Image(
                    key: ValueKey(
                      'attachment-preview-${attachment.attachmentId}',
                    ),
                    image: preview,
                    fit: BoxFit.contain,
                    semanticLabel: attachment.name,
                    gaplessPlayback: true,
                  ),
          ),
          actions: [
            if (allowSaveCopy)
              TextButton.icon(
                onPressed: () async {
                  final location = await getSaveLocation(
                    suggestedName: attachment.name,
                  );
                  if (location == null) return;
                  await XFile.fromData(
                    bytes,
                    name: attachment.name,
                    mimeType: attachment.contentType,
                  ).saveTo(location.path);
                },
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.saveCopy),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
    } finally {
      try {
        await voicePlayer?.disposeAsync();
      } finally {
        await preview?.evict();
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  Future<void> _createGroup() async {
    final details = await showDialog<(String, List<String>)>(
      context: context,
      builder: (context) => const _CreateGroupDialog(),
    );
    if (!mounted || details == null) return;
    final group = await widget.controller.createGroup(
      title: details.$1,
      memberUsernames: details.$2,
    );
    if (mounted && group != null) {
      setState(() {
        _selectedGroupId = group.conversationId;
        _oneTime = false;
      });
    }
  }

  Future<void> _openMessage(LocalChatMessage message) async {
    setState(() {
      _selectedGroupId = message.isGroup ? message.conversationId : null;
      if (message.isGroup) {
        _oneTime = false;
      } else {
        _recipientController.text = message.peerUsername;
      }
    });
    if (message.outgoing) return;
    if (!message.oneTime) {
      await widget.controller.markMessageRead(message.messageId);
      return;
    }
    final opened = await widget.controller.consumeOneTimeMessage(
      message.messageId,
    );
    if (opened == null) return;
    if (!mounted) {
      await widget.controller.closeOpenedOneTimeMessage(opened);
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.viewOnceMessage),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
            child: SingleChildScrollView(
              child: Column(
                key: const Key('one-time-message-content'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (opened.text.isNotEmpty) Text(opened.text),
                  for (final attachment in opened.attachments) ...[
                    if (opened.text.isNotEmpty) const SizedBox(height: 10),
                    _AttachmentCard(
                      attachment: attachment,
                      onOpen: () async {
                        final bytes = await widget.controller
                            .loadOpenedOneTimeAttachment(
                              message: opened,
                              attachmentId: attachment.attachmentId,
                            );
                        if (bytes == null) {
                          _showMessage(l10n.viewOnceOpenFailed);
                          return;
                        }
                        await _showAttachmentBytes(
                          attachment,
                          bytes,
                          allowSaveCopy: false,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
    } finally {
      await widget.controller.closeOpenedOneTimeMessage(opened);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Future<void> _selectSearchResult(LocalChatMessage message) async {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _readFilter = LocalMessageReadFilter.all;
      _selectedGroupId = message.isGroup ? message.conversationId : null;
      if (!message.isGroup) _recipientController.text = message.peerUsername;
      if (message.isGroup) _oneTime = false;
    });
    await _openMessage(message);
  }

  Future<void> _editProfile() async {
    final update = await showDialog<AccountProfileUpdate>(
      context: context,
      builder: (context) => _EditProfileDialog(
        profile: widget.connection.profile,
        avatarPicker:
            widget.profileAvatarPicker ??
            const FileSelectorProfileAvatarPicker(),
      ),
    );
    if (update == null || !mounted) return;
    final saved = await widget.controller.updateProfile(update);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(
      saved
          ? l10n.profileUpdated
          : widget.controller.profileError ?? l10n.profileUpdateFailed,
    );
  }

  Future<void> _setMcpProfileReadAllowed(bool allowed) async {
    final l10n = AppLocalizations.of(context);
    if (allowed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.allowMcpProfileTitle),
          content: Text(l10n.mcpProfileConsentBoundary),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('mcp-profile-consent-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.allow),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final saved = await widget.controller.setMcpProfileReadAllowed(allowed);
    if (!mounted || saved) return;
    _showMessage(
      widget.controller.mcpConsentError ?? l10n.mcpConsentUpdateFailed,
    );
  }

  Future<void> _showMcpAccess() async {
    final l10n = AppLocalizations.of(context);
    final configuration = await widget.controller.loadMcpAccessConfiguration();
    if (!mounted) return;
    if (configuration == null) {
      _showMessage(
        widget.controller.mcpAccessError ?? l10n.mcpConnectionLoadFailed,
      );
      return;
    }
    final endpoint = configuration.mcpUriFor(widget.connection.endpoint);
    final authEndpoint = configuration.authUriFor(widget.connection.endpoint);
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => AlertDialog(
          key: const Key('mcp-access-dialog'),
          scrollable: true,
          title: Row(
            children: [
              const Icon(Icons.smart_toy_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.connectAiService)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.mcpConnectionHelp),
                const SizedBox(height: 16),
                _McpEndpointField(
                  label: l10n.mcpEndpoint,
                  keyName: 'mcp-access-endpoint',
                  uri: endpoint,
                  onCopy: () async {
                    await Clipboard.setData(
                      ClipboardData(text: endpoint.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text(l10n.mcpEndpointCopied)),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _McpEndpointField(
                  label: l10n.authenticationEndpoint,
                  keyName: 'mcp-auth-endpoint',
                  uri: authEndpoint,
                  onCopy: () async {
                    await Clipboard.setData(
                      ClipboardData(text: authEndpoint.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text(l10n.authEndpointCopied)),
                      );
                    }
                  },
                ),
                const SizedBox(height: 14),
                Text(l10n.mcpAccount(widget.connection.username)),
                Text(l10n.mcpRealm(WampAppProtocol.appRealm)),
                Text(l10n.mcpAuthentication),
                const SizedBox(height: 14),
                Text(l10n.mcpCatalog),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  key: const Key('mcp-access-profile-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.allowPublicProfileAccess),
                  subtitle: Text(
                    widget.controller.mcpConsent.profileReadAllowed
                        ? l10n.accessEnabled
                        : l10n.accessDisabledByDefault,
                  ),
                  value: widget.controller.mcpConsent.profileReadAllowed,
                  onChanged: widget.controller.mcpConsentBusy
                      ? null
                      : _setMcpProfileReadAllowed,
                ),
                Text(
                  l10n.visibleFields(configuration.profileFields.join(', ')),
                  key: const Key('mcp-access-profile-fields'),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.mcpDataBoundary,
                  key: const Key('mcp-access-data-boundary'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPeerProfile() async {
    final l10n = AppLocalizations.of(context);
    final username = _recipientController.text.trim();
    if (username.isEmpty) {
      _showMessage(l10n.enterRecipientFirst);
      return;
    }
    final profile = await widget.controller.lookupProfile(username);
    if (!mounted) return;
    if (profile == null) {
      _showMessage(widget.controller.profileError ?? l10n.profileLoadFailed);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.publicProfile),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileAvatar(
                key: const Key('peer-profile-avatar'),
                profile: profile,
                radius: 46,
              ),
              const SizedBox(height: 14),
              Text(
                profile.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('@${profile.username}'),
              const SizedBox(height: 12),
              Text(
                profile.status.isEmpty ? l10n.noStatusSet : profile.status,
                key: const Key('peer-profile-status'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _showPeerTrust() async {
    final l10n = AppLocalizations.of(context);
    final username = _recipientController.text.trim();
    if (username.isEmpty) {
      _showMessage(l10n.enterRecipientFirst);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _PeerTrustDialog(controller: widget.controller, username: username),
    );
  }

  Future<void> _setConversationMuted(String conversationId, bool muted) async {
    final saved = await widget.controller.setConversationMuted(
      conversationId,
      muted,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(
      saved
          ? muted
                ? l10n.chatMuted
                : l10n.chatUnmuted
          : widget.controller.preferenceError ?? l10n.chatPreferenceSaveFailed,
    );
  }

  Future<void> _setConversationAppearance(
    String conversationId,
    WampAppConversationAppearance appearance,
  ) async {
    final saved = await widget.controller.setConversationAppearance(
      conversationId,
      appearance,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(
      saved
          ? l10n.chatAppearanceSaved(
              _ConversationPanel._appearanceLabel(l10n, appearance),
            )
          : widget.controller.preferenceError ?? l10n.chatAppearanceSaveFailed,
    );
  }

  Future<void> _setConversationDisappearingMessages(
    String conversationId,
    Duration? duration,
  ) async {
    final saved = await widget.controller.setConversationDisappearingMessages(
      conversationId,
      duration,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(
      saved
          ? duration == null
                ? l10n.disappearingMessagesDisabled
                : l10n.disappearingMessagesEnabled(
                    _ConversationPanel._expiryLabel(
                      l10n,
                      duration,
                    ).toLowerCase(),
                  )
          : widget.controller.preferenceError ?? l10n.chatPreferenceSaveFailed,
    );
  }

  Future<void> _exportBackup() async {
    final recoveryPassphrase = await showBackupPassphraseDialog(
      context,
      confirm: true,
    );
    if (recoveryPassphrase == null || !mounted) return;
    final saved = await widget.controller.exportLocalBackup(
      recoveryPassphrase: recoveryPassphrase,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(
      saved
          ? l10n.encryptedDeviceBackupSaved
          : widget.controller.backupError ?? l10n.backupCancelled,
    );
  }

  Future<void> _uploadRemoteBackup() async {
    final recoveryPassphrase = await showBackupPassphraseDialog(
      context,
      confirm: true,
    );
    if (recoveryPassphrase == null || !mounted) return;
    final saved = await widget.controller.uploadRemoteBackup(
      recoveryPassphrase: recoveryPassphrase,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(
      saved
          ? l10n.encryptedServerBackupSaved
          : widget.controller.backupError ?? l10n.cloudBackupCancelled,
    );
  }

  Future<void> _showBackupMenu() async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.encryptedBackup,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const Key('backup-action-local'),
                leading: const Icon(Icons.save_alt_outlined),
                title: Text(l10n.saveBackupFile),
                subtitle: Text(l10n.saveBackupFileSubtitle),
                onTap: () => Navigator.of(context).pop('local'),
              ),
              ListTile(
                key: const Key('backup-action-remote'),
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text(l10n.backupToServer),
                subtitle: Text(l10n.backupToServerSubtitle),
                onTap: () => Navigator.of(context).pop('remote'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'local') await _exportBackup();
    if (action == 'remote') await _uploadRemoteBackup();
  }

  Future<void> _startCall(CallMediaKind media) async {
    final calls = widget.controller.calls;
    if (calls == null || _selectedGroupId != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await calls.startCall(
      recipientUsername: _recipientController.text,
      media: media,
    );
  }

  Future<void> _manageContacts() async {
    final username = await showContactManagerDialog(
      context: context,
      controller: widget.controller,
      importer: widget.contactImporter ?? createContactImporter(),
    );
    if (!mounted || username == null) return;
    setState(() {
      _selectedGroupId = null;
      _recipientController.text = username;
    });
  }

  Future<void> _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        controller: widget.controller,
        onEditProfile: _editProfile,
        onManageContacts: _manageContacts,
        onOpenMcpAccess: _showMcpAccess,
        onBackup: _showBackupMenu,
        onRemoteBackup: _uploadRemoteBackup,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final calls = widget.controller.calls!;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnimatedBuilder(
      animation: calls,
      builder: (context, _) => Stack(
        children: [
          Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final account = _AccountPanel(
                    connection: widget.connection,
                    compact: !wide,
                    onOpenSettings: _openSettings,
                  );
                  final conversation = _ConversationPanel(
                    controller: widget.controller,
                    calls: calls,
                    keyboardVisible: keyboardVisible,
                    recipientController: _recipientController,
                    messageController: _messageController,
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    readFilter: _readFilter,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: _clearSearch,
                    onReadFilterChanged: (value) =>
                        setState(() => _readFilter = value),
                    onSearchResultSelected: _selectSearchResult,
                    onSend: _send,
                    onViewProfile: _showPeerProfile,
                    onVerifyIdentity: _showPeerTrust,
                    onStartVoiceCall: () => _startCall(CallMediaKind.voice),
                    onStartVideoCall: () => _startCall(CallMediaKind.video),
                    oneTime: _oneTime,
                    expiresAfter: _selectedGroupId == null
                        ? switch (widget.controller.directConversationIdFor(
                            _recipientController.text,
                          )) {
                            final conversationId? =>
                              widget.controller.disappearingMessagesFor(
                                conversationId,
                              ),
                            null => null,
                          }
                        : widget.controller.disappearingMessagesFor(
                            _selectedGroupId!,
                          ),
                    selectedGroupId: _selectedGroupId,
                    onRecipientChanged: () => setState(() {}),
                    onConversationChanged: (value) => setState(() {
                      _selectedGroupId = value;
                      if (value != null) _oneTime = false;
                    }),
                    onCreateGroup: _createGroup,
                    onMuteChanged: _setConversationMuted,
                    onAppearanceChanged: _setConversationAppearance,
                    onOneTimeChanged: (value) =>
                        setState(() => _oneTime = value),
                    onExpiresAfterChanged: _setConversationDisappearingMessages,
                    onOpenMessage: _openMessage,
                    selectedAttachments: _attachments,
                    onPickAttachments: _pickAttachments,
                    onPickExpression: _showExpressionPicker,
                    onRemoveAttachment: _removeAttachment,
                    onOpenAttachment: _openAttachment,
                    voiceRecording: _voiceRecording != null,
                    voiceControlBusy: _voiceControlBusy,
                    voiceRecordingElapsed: _voiceRecordingElapsed,
                    onToggleVoiceRecording: _toggleVoiceRecording,
                    onCancelVoiceRecording: _cancelVoiceRecording,
                    stickerBusy: _stickerBusy,
                  );
                  return Padding(
                    padding: EdgeInsets.all(keyboardVisible ? 8 : 18),
                    child: wide
                        ? Row(
                            children: [
                              SizedBox(width: 320, child: account),
                              const SizedBox(width: 18),
                              Expanded(child: conversation),
                            ],
                          )
                        : Column(
                            children: [
                              if (!keyboardVisible) ...[
                                account,
                                const SizedBox(height: 18),
                              ],
                              Expanded(child: conversation),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
          if (calls.hasCall) CallOverlay(controller: calls),
        ],
      ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _title = TextEditingController();
  final _members = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _members.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.newEncryptedGroup),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('group-title'),
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.groupName),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('group-members'),
            controller: _members,
            decoration: InputDecoration(
              labelText: l10n.memberUsernames,
              helperText: l10n.separateUsernames,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('group-create'),
          onPressed: () =>
              Navigator.of(context)
                  .pop((_title.text, _members.text.split(','))),
          child: Text(l10n.createGroup),
        ),
      ],
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.profile, required this.avatarPicker});

  final AccountProfile profile;
  final ProfileAvatarPicker avatarPicker;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _displayName;
  late final TextEditingController _status;
  late ProfileAvatarAction _avatarAction;
  Uint8List? _avatarBytes;
  String? _avatarContentType;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(text: widget.profile.displayName);
    _status = TextEditingController(text: widget.profile.status);
    _avatarAction = ProfileAvatarAction.keep;
    _avatarBytes = widget.profile.avatarBytes;
    _avatarContentType = widget.profile.avatarContentType;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    ProfileAvatarSelection? selection;
    try {
      selection = await widget.avatarPicker.pickAvatar();
    } on ProfileAvatarPickerException catch (error) {
      if (mounted) setState(() => _validationError = error.message);
      return;
    } catch (_) {
      if (mounted) {
        setState(
          () => _validationError =
              'The selected profile image could not be read.',
        );
      }
      return;
    }
    if (selection == null || !mounted) return;
    final bytes = selection.bytes;
    if (bytes.length > AccountProfileLimits.maxAvatarBytes) {
      setState(() {
        _validationError = 'Profile images must be 256 KiB or smaller.';
      });
      return;
    }
    final contentType = _profileImageContentType(selection.name);
    if (contentType == null) {
      setState(() {
        _validationError = 'Choose a JPEG, PNG, or WebP image.';
      });
      return;
    }
    try {
      AccountProfileUpdate(
        expectedRevision: widget.profile.revision,
        displayName: widget.profile.displayName,
        status: widget.profile.status,
        avatarAction: ProfileAvatarAction.set,
        avatarBytes: bytes,
        avatarContentType: contentType,
      );
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
      return;
    }
    setState(() {
      _avatarAction = ProfileAvatarAction.set;
      _avatarBytes = Uint8List.fromList(bytes);
      _avatarContentType = contentType;
      _validationError = null;
    });
  }

  void _removeAvatar() {
    setState(() {
      _avatarAction = ProfileAvatarAction.remove;
      _avatarBytes = null;
      _avatarContentType = null;
      _validationError = null;
    });
  }

  void _save() {
    try {
      Navigator.pop(
        context,
        AccountProfileUpdate(
          expectedRevision: widget.profile.revision,
          displayName: _displayName.text.trim(),
          status: _status.text.trim(),
          avatarAction: _avatarAction,
          avatarBytes: _avatarAction == ProfileAvatarAction.set
              ? _avatarBytes
              : null,
          avatarContentType: _avatarAction == ProfileAvatarAction.set
              ? _avatarContentType
              : null,
        ),
      );
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = AccountProfile(
      username: widget.profile.username,
      displayName: widget.profile.displayName,
      status: '',
      revision: widget.profile.revision,
      updatedAt: widget.profile.updatedAt,
      avatarBytes: _avatarBytes,
      avatarContentType: _avatarContentType,
    );
    return AlertDialog(
      title: Text(l10n.editPublicProfile),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileAvatar(
                key: const Key('profile-avatar-preview'),
                profile: preview,
                radius: 42,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('profile-avatar-pick'),
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.chooseImage),
                  ),
                  if (_avatarBytes != null)
                    TextButton.icon(
                      key: const Key('profile-avatar-remove'),
                      onPressed: _removeAvatar,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.remove),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('profile-display-name'),
                controller: _displayName,
                maxLength: 80,
                decoration: InputDecoration(labelText: l10n.displayName),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('profile-status'),
                controller: _status,
                maxLength: AccountProfileLimits.maxStatusCharacters,
                decoration: InputDecoration(
                  labelText: l10n.status,
                  hintText: l10n.available,
                ),
              ),
              if (_validationError case final message?) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  key: const Key('profile-validation-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                l10n.profileVisibilityBoundary,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('profile-save'),
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _McpEndpointField extends StatelessWidget {
  const _McpEndpointField({
    required this.label,
    required this.keyName,
    required this.uri,
    required this.onCopy,
  });

  final String label;
  final String keyName;
  final Uri uri;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  uri.toString(),
                  key: ValueKey(keyName),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('$keyName-copy'),
            tooltip: AppLocalizations.of(context).copyLabel(label),
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    ),
  );
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.connection,
    required this.compact,
    required this.onOpenSettings,
  });

  final AccountConnection connection;
  final bool compact;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final settingsLabel = AppLocalizations.of(context).settings;
    final profile = connection.profile;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 10 : 18,
        ),
        child: Row(
          children: [
            _ProfileAvatar(
              key: const Key('account-profile-avatar'),
              profile: profile,
              radius: compact ? 22 : 27,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '@${connection.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!compact && profile.status.isNotEmpty)
                    Text(
                      profile.status,
                      key: const Key('account-profile-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!compact) const _OnlineBadge(),
            IconButton(
              key: const Key('account-settings'),
              tooltip: settingsLabel,
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    super.key,
    required this.profile,
    required this.radius,
  });

  final AccountProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = profile.displayName.characters.first.toUpperCase();
    Widget fallback() => Center(
      child: Text(
        initial,
        style: radius >= 40
            ? Theme.of(context).textTheme.headlineMedium
            : Theme.of(context).textTheme.titleLarge,
      ),
    );
    final bytes = profile.avatarBytes;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: bytes == null
          ? fallback()
          : ClipOval(
              child: Image.memory(
                bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              ),
            ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(radius: 4, backgroundColor: Color(0xFF38A66D)),
        const SizedBox(width: 6),
        Text(
          AppLocalizations.of(context).online,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _PeerTrustDialog extends StatefulWidget {
  const _PeerTrustDialog({required this.controller, required this.username});

  final WampAppController controller;
  final String username;

  @override
  State<_PeerTrustDialog> createState() => _PeerTrustDialogState();
}

class _PeerTrustDialogState extends State<_PeerTrustDialog> {
  PeerTrustSummary? _summary;
  Object? _error;
  bool _loading = true;
  String? _verifyingDeviceId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final summary = await widget.controller.inspectPeerTrust(widget.username);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _error = summary == null
            ? StateError('The account session changed.')
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _verify(PeerDeviceTrust device) async {
    final l10n = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmSafetyNumber),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.device.enrollment.deviceName),
            const SizedBox(height: 8),
            SelectableText(
              device.safetyNumber,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.compareSafetyNumber),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('peer-trust-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.numbersMatch),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _verifyingDeviceId = device.device.deviceId;
      _error = null;
    });
    try {
      final summary = await widget.controller.verifyPeerDevice(device);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _error = summary == null
            ? StateError('The account session changed.')
            : null;
        _verifyingDeviceId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _verifyingDeviceId = null;
      });
    }
  }

  String _errorMessage(AppLocalizations l10n) => switch (_error) {
    FormatException(:final message) => message,
    _ => l10n.trustLoadFailed,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = _summary;
    return AlertDialog(
      key: const Key('peer-trust-dialog'),
      title: Text(
        summary == null
            ? l10n.encryptionIdentity
            : l10n.encryptionIdentityFor(summary.username),
      ),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary != null) ...[
                      _PeerTrustStatusBanner(summary: summary),
                      const SizedBox(height: 12),
                      Text(l10n.trustComparisonHelp),
                      const SizedBox(height: 16),
                      for (final device in summary.devices) ...[
                        DecoratedBox(
                          key: ValueKey(
                            'peer-trust-device-${device.device.deviceId}',
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        device.device.enrollment.deviceName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                    if (device.verified)
                                      Chip(
                                        avatar: const Icon(
                                          Icons.verified,
                                          size: 18,
                                        ),
                                        label: Text(l10n.verified),
                                      ),
                                  ],
                                ),
                                SelectableText(
                                  device.safetyNumber,
                                  key: ValueKey(
                                    'peer-trust-number-${device.device.deviceId}',
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.tonalIcon(
                                    key: ValueKey(
                                      'peer-trust-verify-${device.device.deviceId}',
                                    ),
                                    onPressed:
                                        device.verified ||
                                            _verifyingDeviceId != null
                                        ? null
                                        : () => _verify(device),
                                    icon:
                                        _verifyingDeviceId ==
                                            device.device.deviceId
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.fact_check_outlined),
                                    label: Text(
                                      device.verified
                                          ? l10n.verified
                                          : l10n.verifyDevice,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (_error != null) ...[
                      Text(
                        _errorMessage(l10n),
                        key: const Key('peer-trust-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _verifyingDeviceId == null ? _load : null,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.refresh),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _PeerTrustStatusBanner extends StatelessWidget {
  const _PeerTrustStatusBanner({required this.summary});

  final PeerTrustSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, color, text) = switch (summary.status) {
      PeerTrustStatus.unverified => (
        Icons.shield_outlined,
        Theme.of(context).colorScheme.secondary,
        l10n.trustUnverified,
      ),
      PeerTrustStatus.verified => (
        Icons.verified_user,
        const Color(0xFF197A52),
        l10n.trustVerified,
      ),
      PeerTrustStatus.changed => (
        Icons.gpp_bad_outlined,
        Theme.of(context).colorScheme.error,
        l10n.trustChanged,
      ),
    };
    return DecoratedBox(
      key: const Key('peer-trust-status'),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.controller,
    required this.calls,
    required this.keyboardVisible,
    required this.recipientController,
    required this.messageController,
    required this.searchController,
    required this.searchQuery,
    required this.readFilter,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onReadFilterChanged,
    required this.onSearchResultSelected,
    required this.onSend,
    required this.onViewProfile,
    required this.onVerifyIdentity,
    required this.onStartVoiceCall,
    required this.onStartVideoCall,
    required this.oneTime,
    required this.expiresAfter,
    required this.selectedGroupId,
    required this.onRecipientChanged,
    required this.onConversationChanged,
    required this.onCreateGroup,
    required this.onMuteChanged,
    required this.onAppearanceChanged,
    required this.onOneTimeChanged,
    required this.onExpiresAfterChanged,
    required this.onOpenMessage,
    required this.selectedAttachments,
    required this.onPickAttachments,
    required this.onPickExpression,
    required this.onRemoveAttachment,
    required this.onOpenAttachment,
    required this.voiceRecording,
    required this.voiceControlBusy,
    required this.voiceRecordingElapsed,
    required this.onToggleVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.stickerBusy,
  });

  final WampAppController controller;
  final CallController calls;
  final bool keyboardVisible;
  final TextEditingController recipientController;
  final TextEditingController messageController;
  final TextEditingController searchController;
  final String searchQuery;
  final LocalMessageReadFilter readFilter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<LocalMessageReadFilter> onReadFilterChanged;
  final Future<void> Function(LocalChatMessage message) onSearchResultSelected;
  final Future<void> Function() onSend;
  final Future<void> Function() onViewProfile;
  final Future<void> Function() onVerifyIdentity;
  final VoidCallback onStartVoiceCall;
  final VoidCallback onStartVideoCall;
  final bool oneTime;
  final Duration? expiresAfter;
  final String? selectedGroupId;
  final VoidCallback onRecipientChanged;
  final ValueChanged<String?> onConversationChanged;
  final Future<void> Function() onCreateGroup;
  final Future<void> Function(String conversationId, bool muted) onMuteChanged;
  final Future<void> Function(
    String conversationId,
    WampAppConversationAppearance appearance,
  )
  onAppearanceChanged;
  final ValueChanged<bool> onOneTimeChanged;
  final Future<void> Function(String conversationId, Duration? duration)
  onExpiresAfterChanged;
  final Future<void> Function(LocalChatMessage message) onOpenMessage;
  final List<_SelectedAttachment> selectedAttachments;
  final Future<void> Function() onPickAttachments;
  final Future<void> Function() onPickExpression;
  final ValueChanged<int> onRemoveAttachment;
  final Future<void> Function(
    LocalChatMessage message,
    EncryptedAttachmentDescriptor attachment,
  )
  onOpenAttachment;
  final bool voiceRecording;
  final bool voiceControlBusy;
  final Duration voiceRecordingElapsed;
  final Future<void> Function() onToggleVoiceRecording;
  final Future<void> Function() onCancelVoiceRecording;
  final bool stickerBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedGroup = controller.groups
        .where((group) => group.conversationId == selectedGroupId)
        .firstOrNull;
    final groupMode = selectedGroupId != null;
    final directRecipient = recipientController.text.trim();
    final directConversationId = groupMode
        ? null
        : controller.directConversationIdFor(directRecipient);
    final activeConversationId =
        selectedGroup?.conversationId ?? directConversationId;
    final conversationMuted =
        activeConversationId != null &&
        controller.isConversationMuted(activeConversationId);
    final conversationAppearance = activeConversationId == null
        ? WampAppConversationAppearance.standard
        : controller.conversationAppearanceFor(activeConversationId);
    final canStartCall =
        !groupMode &&
        directConversationId != null &&
        !calls.hasCall &&
        !calls.busy;
    final query = LocalMessageQuery(
      text: searchQuery,
      readFilter: readFilter,
      selectedGroupId: selectedGroupId,
      selectedDirectConversationId: groupMode ? null : directConversationId,
    );
    final globalSearch = query.isGlobalSearch;
    final visibleMessages = query.select(controller.messages);
    final compact = MediaQuery.sizeOf(context).width < 760;
    final compactComposition =
        compact && (selectedAttachments.isNotEmpty || voiceRecording);
    final chromeHidden = keyboardVisible || compactComposition;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact || chromeHidden ? 8 : 22),
        child: Column(
          children: [
            if (!chromeHidden) ...[
              Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      selectedGroup?.title ??
                          (directRecipient.isEmpty
                              ? l10n.encryptedMessages
                              : '@$directRecipient'),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('conversation-voice-call'),
                    tooltip: groupMode
                        ? l10n.groupCallsUnavailable
                        : l10n.startEncryptedVoiceCall,
                    onPressed: canStartCall ? onStartVoiceCall : null,
                    icon: const Icon(Icons.call_outlined),
                  ),
                  IconButton(
                    key: const Key('conversation-video-call'),
                    tooltip: groupMode
                        ? l10n.groupCallsUnavailable
                        : l10n.startEncryptedVideoCall,
                    onPressed: canStartCall ? onStartVideoCall : null,
                    icon: const Icon(Icons.videocam_outlined),
                  ),
                  if (activeConversationId != null)
                    IconButton(
                      key: const Key('conversation-mute'),
                      tooltip: conversationMuted
                          ? l10n.unmuteChat
                          : l10n.muteChat,
                      onPressed: controller.preferenceBusy
                          ? null
                          : () => onMuteChanged(
                              activeConversationId,
                              !conversationMuted,
                            ),
                      icon: controller.preferenceBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              conversationMuted
                                  ? Icons.notifications_off
                                  : Icons.notifications_none,
                            ),
                    ),
                  PopupMenuButton<WampAppConversationAppearance>(
                    key: const Key('conversation-appearance-menu'),
                    enabled:
                        activeConversationId != null &&
                        !controller.preferenceBusy,
                    tooltip: l10n.chatAppearance(
                      _appearanceLabel(l10n, conversationAppearance),
                    ),
                    onSelected: activeConversationId == null
                        ? null
                        : (appearance) => unawaited(
                            onAppearanceChanged(
                              activeConversationId,
                              appearance,
                            ),
                          ),
                    itemBuilder: (context) => [
                      for (final appearance
                          in WampAppConversationAppearance.values)
                        CheckedPopupMenuItem<WampAppConversationAppearance>(
                          key: ValueKey(
                            'conversation-appearance-${appearance.wireName}',
                          ),
                          value: appearance,
                          checked: conversationAppearance == appearance,
                          child: Text(_appearanceLabel(l10n, appearance)),
                        ),
                    ],
                    icon: const Icon(Icons.palette_outlined),
                  ),
                  IconButton(
                    tooltip: l10n.syncMessages,
                    onPressed: controller.messageBusy
                        ? null
                        : controller.refreshMessages,
                    icon: const Icon(Icons.sync),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 12),
              TextField(
                key: const Key('message-global-search'),
                controller: searchController,
                maxLength: LocalMessageQuery.maxQueryLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                buildCounter: (
                  _, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
                decoration: InputDecoration(
                  labelText: globalSearch
                      ? l10n.localSearchResults(visibleMessages.length)
                      : l10n.searchLocalMessages,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('message-search-clear'),
                          tooltip: l10n.clearMessageSearch,
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: onSearchChanged,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              ),
              SizedBox(height: compact ? 4 : 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      key: const Key('conversation-direct'),
                      selected: !groupMode,
                      onSelected: controller.messageBusy
                          ? null
                          : (_) => onConversationChanged(null),
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(l10n.direct),
                    ),
                    for (final group in controller.groups) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: ValueKey(
                          'conversation-group-${group.conversationId}',
                        ),
                        selected: selectedGroupId == group.conversationId,
                        onSelected: controller.messageBusy
                            ? null
                            : (_) =>
                                  onConversationChanged(group.conversationId),
                        avatar: const Icon(Icons.group_outlined, size: 18),
                        label: Text(group.title),
                      ),
                    ],
                    const SizedBox(width: 8),
                    ActionChip(
                      key: const Key('conversation-create-group'),
                      onPressed: controller.messageBusy ? null : onCreateGroup,
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(l10n.newGroup),
                    ),
                    const SizedBox(width: 16),
                    FilterChip(
                      key: const Key('message-filter-all'),
                      selected: readFilter == LocalMessageReadFilter.all,
                      onSelected: (_) =>
                          onReadFilterChanged(LocalMessageReadFilter.all),
                      label: Text(l10n.all),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const Key('message-filter-unread'),
                      selected: readFilter == LocalMessageReadFilter.unread,
                      onSelected: (_) =>
                          onReadFilterChanged(LocalMessageReadFilter.unread),
                      avatar: const Icon(
                        Icons.mark_chat_unread_outlined,
                        size: 18,
                      ),
                      label: Text(l10n.unreadReceived),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const Key('message-filter-read'),
                      selected: readFilter == LocalMessageReadFilter.read,
                      onSelected: (_) =>
                          onReadFilterChanged(LocalMessageReadFilter.read),
                      avatar: const Icon(Icons.done_all, size: 18),
                      label: Text(l10n.readReceived),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 6 : 14),
            ],
            if (!chromeHidden &&
                !groupMode &&
                controller.contacts.isNotEmpty) ...[
              SizedBox(
                height: 38,
                child: ListView.separated(
                  key: const Key('contact-recipient-shortcuts'),
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.contacts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final contact = controller.contacts[index];
                    return ActionChip(
                      key: ValueKey('contact-recipient-${contact.username}'),
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(
                        '${contact.displayName} · @${contact.username}',
                      ),
                      onPressed: controller.messageBusy
                          ? null
                          : () {
                              recipientController.text = contact.username;
                              onRecipientChanged();
                            },
                    );
                  },
                ),
              ),
              SizedBox(height: compact ? 4 : 10),
            ],
            if (!groupMode)
              TextField(
                key: const Key('message-recipient'),
                controller: recipientController,
                enabled: !controller.messageBusy,
                decoration: InputDecoration(
                  labelText: directRecipient.isEmpty
                      ? l10n.startDirectChat
                      : l10n.directChat,
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (directRecipient.isNotEmpty)
                        IconButton(
                          key: const Key('recipient-clear'),
                          tooltip: l10n.closeDirectChat,
                          onPressed: controller.messageBusy
                              ? null
                              : () {
                                  recipientController.clear();
                                  onRecipientChanged();
                                },
                          icon: const Icon(Icons.close),
                        ),
                      IconButton(
                        key: const Key('recipient-identity-view'),
                        tooltip: l10n.verifyEncryptionIdentity,
                        onPressed: onVerifyIdentity,
                        icon: const Icon(Icons.verified_user_outlined),
                      ),
                      IconButton(
                        key: const Key('recipient-profile-view'),
                        tooltip: l10n.viewPublicProfile,
                        onPressed: controller.profileBusy
                            ? null
                            : onViewProfile,
                        icon: controller.profileBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.account_circle_outlined),
                      ),
                    ],
                  ),
                ),
                onChanged: (_) => onRecipientChanged(),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  selectedGroup == null
                      ? l10n.groupUnavailable
                      : selectedGroup.memberUsernames
                            .map((username) => '@$username')
                            .join('  '),
                  key: const Key('group-members-summary'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            SizedBox(
              height: chromeHidden
                  ? 4
                  : compact
                  ? 6
                  : 14,
            ),
            Expanded(
              child: visibleMessages.isEmpty
                  ? _NoMessages(
                      message: globalSearch
                          ? l10n.noSearchMessages
                          : switch (readFilter) {
                              LocalMessageReadFilter.all => l10n.noMessages,
                              LocalMessageReadFilter.unread =>
                                l10n.noUnreadMessages,
                              LocalMessageReadFilter.read =>
                                l10n.noReadMessages,
                            },
                    )
                  : ListView.separated(
                      key: const Key('message-history'),
                      reverse: true,
                      itemCount: visibleMessages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final message =
                            visibleMessages[visibleMessages.length - index - 1];
                        return _MessageBubble(
                          message: message,
                          appearance: controller.conversationAppearanceFor(
                            message.conversationId,
                          ),
                          outbound: controller.outboundMessageFor(
                            message.messageId,
                          ),
                          onTap: controller.messageBusy
                              ? null
                              : globalSearch
                              ? () => onSearchResultSelected(message)
                              : message.outgoing
                              ? null
                              : () => onOpenMessage(message),
                          onRetry: controller.messageBusy
                              ? null
                              : () async {
                                  await controller.retryMessage(
                                    message.messageId,
                                  );
                                },
                          onDiscard: controller.messageBusy
                              ? null
                              : () async {
                                  await controller.discardOutboundMessage(
                                    message.messageId,
                                  );
                                },
                          onOpenAttachment: controller.messageBusy
                              ? null
                              : (attachment) =>
                                    onOpenAttachment(message, attachment),
                        );
                      },
                    ),
            ),
            if (controller.platformPushError case final error?) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  key: const Key('platform-push-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            if (controller.messageError case final error?) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  key: const Key('message-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            if (!chromeHidden) ...[
              SizedBox(height: compact ? 6 : 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      key: const Key('message-one-time'),
                      selected: !groupMode && oneTime,
                      onSelected: controller.messageBusy || groupMode
                          ? null
                          : onOneTimeChanged,
                      avatar: const Icon(
                        Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      label: Text(l10n.viewOnce),
                    ),
                    const SizedBox(width: 12),
                    PopupMenuButton<Duration>(
                      key: const Key('message-expiry'),
                      enabled:
                          activeConversationId != null &&
                          !controller.messageBusy &&
                          !controller.preferenceBusy,
                      initialValue: expiresAfter ?? Duration.zero,
                      onSelected: activeConversationId == null
                          ? null
                          : (value) => onExpiresAfterChanged(
                              activeConversationId,
                              value == Duration.zero ? null : value,
                            ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: Duration.zero,
                          child: Text(l10n.keepChatMessages),
                        ),
                        PopupMenuItem(
                          value: const Duration(hours: 1),
                          child: Text(l10n.deleteAfterOneHour),
                        ),
                        PopupMenuItem(
                          value: const Duration(days: 1),
                          child: Text(l10n.deleteAfterOneDay),
                        ),
                        PopupMenuItem(
                          value: const Duration(days: 7),
                          child: Text(l10n.deleteAfterSevenDays),
                        ),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.timer_outlined, size: 18),
                        label: Text(_expiryLabel(l10n, expiresAfter)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
            ] else
              const SizedBox(height: 4),
            if (selectedAttachments.isNotEmpty) ...[
              SizedBox(
                height: 42,
                child: ListView.separated(
                  key: const Key('selected-attachments'),
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedAttachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => InputChip(
                    key: ValueKey('selected-attachment-$index'),
                    avatar: Icon(
                      _attachmentIcon(selectedAttachments[index].kind),
                      size: 18,
                    ),
                    label: Text(
                      '${selectedAttachments[index].name} · '
                      '${_formatBytes(selectedAttachments[index].byteCount)}'
                      '${_durationSuffix(selectedAttachments[index].durationMilliseconds)}',
                    ),
                    onDeleted: controller.messageBusy
                        ? null
                        : () => onRemoveAttachment(index),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _MessageComposer(
              messageController: messageController,
              recipientController: recipientController,
              directConversationIdFor: controller.directConversationIdFor,
              groupMode: groupMode,
              messageBusy: controller.messageBusy,
              preferenceBusy: controller.preferenceBusy,
              selectedAttachments: selectedAttachments,
              voiceRecording: voiceRecording,
              voiceControlBusy: voiceControlBusy,
              voiceRecordingElapsed: voiceRecordingElapsed,
              stickerBusy: stickerBusy,
              onSend: onSend,
              onPickAttachments: onPickAttachments,
              onPickExpression: onPickExpression,
              onToggleVoiceRecording: onToggleVoiceRecording,
              onCancelVoiceRecording: onCancelVoiceRecording,
            ),
          ],
        ),
      ),
    );
  }

  static String _expiryLabel(AppLocalizations l10n, Duration? value) =>
      switch (value) {
        null => l10n.keepChatMessages,
        const Duration(hours: 1) => l10n.deleteAfterOneHour,
        const Duration(days: 1) => l10n.deleteAfterOneDay,
        const Duration(days: 7) => l10n.deleteAfterSevenDays,
        _ => l10n.autoDeleteEnabled,
      };

  static String _appearanceLabel(
    AppLocalizations l10n,
    WampAppConversationAppearance appearance,
  ) => switch (appearance) {
    WampAppConversationAppearance.standard => l10n.appearanceStandard,
    WampAppConversationAppearance.ocean => l10n.appearanceOcean,
    WampAppConversationAppearance.sunset => l10n.appearanceSunset,
  };
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.messageController,
    required this.recipientController,
    required this.directConversationIdFor,
    required this.groupMode,
    required this.messageBusy,
    required this.preferenceBusy,
    required this.selectedAttachments,
    required this.voiceRecording,
    required this.voiceControlBusy,
    required this.voiceRecordingElapsed,
    required this.stickerBusy,
    required this.onSend,
    required this.onPickAttachments,
    required this.onPickExpression,
    required this.onToggleVoiceRecording,
    required this.onCancelVoiceRecording,
  });

  final TextEditingController messageController;
  final TextEditingController recipientController;
  final String? Function(String username) directConversationIdFor;
  final bool groupMode;
  final bool messageBusy;
  final bool preferenceBusy;
  final List<_SelectedAttachment> selectedAttachments;
  final bool voiceRecording;
  final bool voiceControlBusy;
  final Duration voiceRecordingElapsed;
  final bool stickerBusy;
  final Future<void> Function() onSend;
  final VoidCallback onPickAttachments;
  final VoidCallback onPickExpression;
  final VoidCallback onToggleVoiceRecording;
  final VoidCallback onCancelVoiceRecording;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (voiceRecording) {
      return Row(
        children: [
          Expanded(
            child: Container(
              key: const Key('voice-recording-status'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.recordingDuration(
                        _formatDuration(voiceRecordingElapsed),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const Key('voice-recording-cancel'),
                    tooltip: l10n.cancelVoiceNote,
                    onPressed: voiceControlBusy ? null : onCancelVoiceRecording,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const Key('message-voice'),
            tooltip: l10n.finishVoiceNote,
            onPressed: messageBusy || voiceControlBusy
                ? null
                : onToggleVoiceRecording,
            icon: voiceControlBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_rounded),
          ),
        ],
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: recipientController,
      builder: (context, recipientValue, _) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: messageController,
          builder: (context, value, _) {
            final hasActiveConversation =
                groupMode ||
                directConversationIdFor(recipientValue.text.trim()) != null;
            final canCompose = !messageBusy;
            final hasPayload =
                value.text.trim().isNotEmpty || selectedAttachments.isNotEmpty;
            final canSend =
                canCompose &&
                hasActiveConversation &&
                !preferenceBusy &&
                hasPayload;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('message-composer'),
                    controller: messageController,
                    enabled: canCompose,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: canSend ? (_) => onSend() : null,
                    decoration: InputDecoration(
                      hintText: !hasActiveConversation
                          ? l10n.openConversationToReply
                          : groupMode
                          ? l10n.messageGroup
                          : l10n.message,
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      prefixIcon: IconButton(
                        key: const Key('message-expression'),
                        tooltip: l10n.chooseExpression,
                        onPressed: !canCompose || stickerBusy
                            ? null
                            : onPickExpression,
                        icon: stickerBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.emoji_emotions_outlined),
                      ),
                      suffixIcon: IconButton(
                        key: const Key('message-attach'),
                        tooltip: l10n.attachEncryptedFiles,
                        onPressed:
                            !canCompose ||
                                selectedAttachments.length >=
                                    WampAppAttachmentLimits
                                        .maxAttachmentsPerMessage
                            ? null
                            : onPickAttachments,
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: Key(hasPayload ? 'message-send' : 'message-voice'),
                  tooltip: hasPayload
                      ? l10n.sendEncryptedMessage
                      : l10n.recordEncryptedVoiceNote,
                  onPressed: hasPayload
                      ? canSend
                            ? onSend
                            : null
                      : canCompose && !voiceControlBusy
                      ? onToggleVoiceRecording
                      : null,
                  icon: messageBusy || voiceControlBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          hasPayload
                              ? Icons.send_rounded
                              : Icons.mic_none_rounded,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NoMessages extends StatelessWidget {
  const _NoMessages({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

final class _ConversationAppearancePalette {
  const _ConversationAppearancePalette({
    required this.outgoingBackground,
    required this.incomingBackground,
    required this.outgoingForeground,
    required this.incomingForeground,
    required this.radius,
    required this.tailRadius,
  });

  final Color outgoingBackground;
  final Color incomingBackground;
  final Color outgoingForeground;
  final Color incomingForeground;
  final double radius;
  final double tailRadius;

  Color background(bool outgoing) =>
      outgoing ? outgoingBackground : incomingBackground;

  Color foreground(bool outgoing) =>
      outgoing ? outgoingForeground : incomingForeground;

  BorderRadius borderRadius(bool outgoing) => BorderRadius.only(
    topLeft: Radius.circular(radius),
    topRight: Radius.circular(radius),
    bottomLeft: Radius.circular(outgoing ? radius : tailRadius),
    bottomRight: Radius.circular(outgoing ? tailRadius : radius),
  );

  static _ConversationAppearancePalette resolve(
    BuildContext context,
    WampAppConversationAppearance appearance,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return switch (appearance) {
      WampAppConversationAppearance.standard => _ConversationAppearancePalette(
        outgoingBackground: theme.colorScheme.primaryContainer,
        incomingBackground: theme.colorScheme.surfaceContainerHighest,
        outgoingForeground: theme.colorScheme.onPrimaryContainer,
        incomingForeground: theme.colorScheme.onSurface,
        radius: 16,
        tailRadius: 16,
      ),
      WampAppConversationAppearance.ocean => _ConversationAppearancePalette(
        outgoingBackground: dark
            ? const Color(0xFF145766)
            : const Color(0xFFB7E5EA),
        incomingBackground: dark
            ? const Color(0xFF243E48)
            : const Color(0xFFD5EEF2),
        outgoingForeground: dark
            ? const Color(0xFFD6F7FA)
            : const Color(0xFF08363E),
        incomingForeground: dark
            ? const Color(0xFFE1F1F4)
            : const Color(0xFF17343B),
        radius: 22,
        tailRadius: 6,
      ),
      WampAppConversationAppearance.sunset => _ConversationAppearancePalette(
        outgoingBackground: dark
            ? const Color(0xFF74451F)
            : const Color(0xFFFFD29B),
        incomingBackground: dark
            ? const Color(0xFF51372A)
            : const Color(0xFFFFE7CC),
        outgoingForeground: dark
            ? const Color(0xFFFFE9D2)
            : const Color(0xFF4C2A06),
        incomingForeground: dark
            ? const Color(0xFFFDECE4)
            : const Color(0xFF452C16),
        radius: 12,
        tailRadius: 3,
      ),
    };
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.appearance,
    this.outbound,
    this.onTap,
    this.onRetry,
    this.onDiscard,
    this.onOpenAttachment,
  });

  final LocalChatMessage message;
  final WampAppConversationAppearance appearance;
  final OutboundChatMessage? outbound;
  final VoidCallback? onTap;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDiscard;
  final Future<void> Function(EncryptedAttachmentDescriptor attachment)?
  onOpenAttachment;

  String _statusLabel(AppLocalizations l10n) {
    final pending = outbound;
    if (pending != null) {
      return switch (pending.state) {
        OutboundMessageState.queued => l10n.sending,
        OutboundMessageState.accepted => l10n.sentSyncing,
        OutboundMessageState.retryable => l10n.notSent,
        OutboundMessageState.rejected => l10n.rejected,
        OutboundMessageState.conflict => l10n.messageConflict,
      };
    }
    return message.outgoing
        ? (message.readAt != null
              ? (message.oneTime
                    ? l10n.opened
                    : message.isGroup
                    ? l10n.readByEveryone
                    : l10n.read)
              : message.deliveredAt != null
              ? (message.isGroup ? l10n.deliveredToEveryone : l10n.delivered)
              : l10n.sent)
        : message.oneTime
        ? l10n.viewOnce
        : message.readAt != null
        ? l10n.read
        : l10n.tapToOpenMarkRead;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pending = outbound;
    final palette = _ConversationAppearancePalette.resolve(context, appearance);
    final borderRadius = palette.borderRadius(message.outgoing);
    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: InkWell(
        key: ValueKey('message-bubble-${message.messageId}'),
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          key: ValueKey('message-surface-${message.messageId}'),
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: palette.background(message.outgoing),
            borderRadius: borderRadius,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: palette.foreground(message.outgoing)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.isGroup
                      ? '${message.groupTitle} · @${message.peerUsername}'
                      : '@${message.peerUsername}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (message.text.isNotEmpty || message.oneTime) ...[
                  const SizedBox(height: 4),
                  Text(
                    message.oneTime && !message.outgoing
                        ? l10n.tapToViewOnce
                        : message.text,
                    key: message.oneTime && !message.outgoing
                        ? ValueKey('message-view-once-${message.messageId}')
                        : null,
                  ),
                ],
                for (final attachment
                    in message.oneTime && !message.outgoing
                        ? const <EncryptedAttachmentDescriptor>[]
                        : message.attachments) ...[
                  const SizedBox(height: 7),
                  _AttachmentCard(
                    attachment: attachment,
                    onOpen: onOpenAttachment == null
                        ? null
                        : () => onOpenAttachment!(attachment),
                  ),
                ],
                const SizedBox(height: 5),
                Text(_statusLabel(l10n), style: const TextStyle(fontSize: 10)),
                if (pending?.canRetry == true ||
                    pending?.canDiscard == true) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (pending?.canRetry == true)
                        TextButton.icon(
                          key: ValueKey('message-retry-${message.messageId}'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text(l10n.retry),
                        ),
                      if (pending?.canDiscard == true)
                        TextButton.icon(
                          key: ValueKey('message-discard-${message.messageId}'),
                          onPressed: onDiscard,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: Text(l10n.discard),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SelectedAttachment {
  _SelectedAttachment(XFile selectedFile, this.byteCount)
    : file = selectedFile,
      name = selectedFile.name,
      contentType = _contentType(selectedFile),
      kind = _attachmentKind(selectedFile),
      durationMilliseconds = null,
      _ownedBytes = null;

  _SelectedAttachment.voiceNote(
    Uint8List bytes, {
    required this.durationMilliseconds,
  }) : file = null,
       name = 'voice-note-${DateTime.now().toUtc().millisecondsSinceEpoch}.wav',
       byteCount = bytes.length,
       contentType = 'audio/wav',
       kind = ChatAttachmentKind.voiceNote,
       _ownedBytes = bytes;

  _SelectedAttachment.sticker(Uint8List bytes, String stickerId)
    : file = null,
      name =
          'sticker-$stickerId-${DateTime.now().toUtc().millisecondsSinceEpoch}.png',
      byteCount = bytes.length,
      contentType = 'image/png',
      kind = ChatAttachmentKind.sticker,
      durationMilliseconds = null,
      _ownedBytes = bytes;

  final XFile? file;
  final String name;
  final int byteCount;
  final String contentType;
  final ChatAttachmentKind kind;
  final int? durationMilliseconds;
  Uint8List? _ownedBytes;

  AttachmentPlaintextSource get source {
    final ownedBytes = _ownedBytes;
    return AttachmentPlaintextSource(
      name: name,
      contentType: contentType,
      kind: kind,
      byteCount: byteCount,
      durationMilliseconds: durationMilliseconds,
      openRead: ownedBytes == null
          ? file!.openRead
          : () {
              if (!identical(_ownedBytes, ownedBytes)) {
                throw StateError('The staged attachment was disposed.');
              }
              return Stream<List<int>>.value(ownedBytes);
            },
    );
  }

  void dispose() {
    final ownedBytes = _ownedBytes;
    _ownedBytes = null;
    ownedBytes?.fillRange(0, ownedBytes.length, 0);
  }

  static String _contentType(XFile file) {
    final explicit = file.mimeType?.trim().toLowerCase();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return switch (_extension(file.name)) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'json' => 'application/json',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'ogg' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      _ => 'application/octet-stream',
    };
  }

  static ChatAttachmentKind _attachmentKind(XFile file) {
    final contentType = _contentType(file);
    if (contentType == 'image/gif') return ChatAttachmentKind.gif;
    if (contentType.startsWith('image/')) return ChatAttachmentKind.image;
    return ChatAttachmentKind.file;
  }

  static String _extension(String name) {
    final separator = name.lastIndexOf('.');
    return separator < 0 ? '' : name.substring(separator + 1).toLowerCase();
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment, this.onOpen});

  final EncryptedAttachmentDescriptor attachment;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('attachment-open-${attachment.attachmentId}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_attachmentIcon(attachment.kind), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${_formatBytes(attachment.plaintextBytes)}'
                      '${_durationSuffix(attachment.durationMilliseconds)}'
                      ' · ${l10n.encrypted}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({required this.attachment});

  final EncryptedAttachmentDescriptor attachment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_attachmentIcon(attachment.kind), size: 52),
          const SizedBox(height: 14),
          Text(attachment.contentType),
          const SizedBox(height: 4),
          Text(_formatBytes(attachment.plaintextBytes)),
          const SizedBox(height: 12),
          Text(l10n.fileDecrypted, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _VoiceNotePlayer extends StatelessWidget {
  const _VoiceNotePlayer({required this.controller, required this.attachment});

  final VoiceNotePlaybackController controller;
  final EncryptedAttachmentDescriptor attachment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final durationMilliseconds = max(1, controller.duration.inMilliseconds);
        final positionMilliseconds = controller.position.inMilliseconds.clamp(
          0,
          durationMilliseconds,
        );
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                key: ValueKey('voice-play-${attachment.attachmentId}'),
                tooltip: controller.state == VoiceNotePlaybackState.playing
                    ? l10n.pauseVoiceNote
                    : l10n.playVoiceNote,
                onPressed: controller.busy ? null : controller.toggle,
                icon: controller.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        controller.state == VoiceNotePlaybackState.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
              Slider(
                key: ValueKey('voice-seek-${attachment.attachmentId}'),
                value: positionMilliseconds.toDouble(),
                max: durationMilliseconds.toDouble(),
                onChanged: controller.busy
                    ? null
                    : (value) => unawaited(
                        controller.seek(Duration(milliseconds: value.round())),
                      ),
              ),
              Text(
                '${_formatDuration(controller.position)} / '
                '${_formatDuration(controller.duration)}',
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatBytes(attachment.plaintextBytes)} · '
                '${l10n.voiceNoteDecrypted}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (controller.error case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

IconData _attachmentIcon(ChatAttachmentKind kind) => switch (kind) {
  ChatAttachmentKind.image => Icons.image_outlined,
  ChatAttachmentKind.gif => Icons.gif_box_outlined,
  ChatAttachmentKind.sticker => Icons.emoji_emotions_outlined,
  ChatAttachmentKind.voiceNote => Icons.graphic_eq_rounded,
  ChatAttachmentKind.file => Icons.insert_drive_file_outlined,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _durationSuffix(int? durationMilliseconds) =>
    durationMilliseconds == null
    ? ''
    : ' · ${_formatDuration(Duration(milliseconds: durationMilliseconds))}';

String? _profileImageContentType(String name) {
  final normalized = name.toLowerCase();
  if (normalized.endsWith('.png')) return 'image/png';
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (normalized.endsWith('.webp')) return 'image/webp';
  return null;
}

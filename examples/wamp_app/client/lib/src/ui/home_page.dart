import 'dart:async';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../application/wamp_app_controller.dart';
import '../domain/local_chat_message.dart';
import '../domain/local_message_query.dart';
import '../domain/outbound_chat_message.dart';
import '../infrastructure/attachment_cipher.dart';
import '../infrastructure/voice_note_playback.dart';
import '../infrastructure/voice_note_recorder.dart';
import '../infrastructure/wamp_account_gateway.dart';
import 'expression_picker.dart';
import 'wamp_app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.connection,
    this.voiceNoteCaptureFactory,
    this.stickerRenderer,
  });

  final WampAppController controller;
  final AccountConnection connection;
  final VoiceNoteCapture Function()? voiceNoteCaptureFactory;
  final StickerRenderer? stickerRenderer;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recipientController = TextEditingController();
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  bool _oneTime = false;
  Duration? _expiresAfter;
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
    final text = _messageController.text;
    final groupId = _selectedGroupId;
    final attachmentSources = _attachments
        .map((attachment) => attachment.source)
        .toList(growable: false);
    final queued = groupId == null
        ? await widget.controller.sendMessage(
            recipientUsername: _recipientController.text,
            text: text,
            oneTime: _oneTime,
            expiresAfter: _expiresAfter,
            attachmentSources: attachmentSources,
          )
        : await widget.controller.sendGroupMessage(
            groupId: groupId,
            text: text,
            expiresAfter: _expiresAfter,
            attachmentSources: attachmentSources,
          );
    if (mounted && queued) {
      final sentAttachments = _attachments;
      setState(() {
        _messageController.clear();
        _attachments = const [];
      });
      for (final attachment in sentAttachments) {
        attachment.dispose();
      }
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final files = await openFiles();
      if (!mounted || files.isEmpty) return;
      final remaining =
          WampAppAttachmentLimits.maxAttachmentsPerMessage -
          _attachments.length;
      if (remaining <= 0 || files.length > remaining) {
        throw const FormatException(
          'A message can contain up to 8 attachments.',
        );
      }
      final selected = <_SelectedAttachment>[];
      for (final file in files) {
        final byteCount = await file.length();
        if (byteCount > WampAppAttachmentLimits.maxAttachmentBytes) {
          throw const FormatException(
            'Each attachment must be 64 MiB or smaller.',
          );
        }
        selected.add(_SelectedAttachment(file, byteCount));
      }
      if (!mounted) return;
      setState(() {
        _attachments = List<_SelectedAttachment>.unmodifiable([
          ..._attachments,
          ...selected,
        ]);
        _oneTime = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'The selected files could not be opened.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.toString())));
    }
  }

  Future<void> _showExpressionPicker() {
    return showModalBottomSheet<void>(
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
    if (_stickerBusy) return false;
    Uint8List? rendered;
    if (_attachments.length >=
        WampAppAttachmentLimits.maxAttachmentsPerMessage) {
      _showMessage('A message can contain up to 8 attachments.');
      return false;
    }
    setState(() => _stickerBusy = true);
    try {
      rendered =
          await (widget.stickerRenderer ?? const BundledStickerRenderer())
              .render(design);
      if (rendered.isEmpty ||
          rendered.length > WampAppAttachmentLimits.maxAttachmentBytes) {
        throw const FormatException(
          'The rendered sticker exceeds the attachment limits.',
        );
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
        _oneTime = false;
      });
      return true;
    } catch (error) {
      rendered?.fillRange(0, rendered.length, 0);
      if (!mounted) return false;
      final message = error is FormatException
          ? error.message
          : 'The sticker could not be rendered.';
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
      _showMessage('A message can contain up to 8 attachments.');
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
      _showMessage('The microphone could not start recording.');
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
      _oneTime = false;
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
            : 'The voice-note recording failed.',
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
    if (!mounted) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
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
              label: const Text('Save copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
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
    final title = TextEditingController();
    final members = TextEditingController();
    final details = await showDialog<(String, List<String>)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New encrypted group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('group-title'),
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('group-members'),
              controller: members,
              decoration: const InputDecoration(
                labelText: 'Member usernames',
                helperText: 'Separate usernames with commas',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('group-create'),
            onPressed: () =>
                Navigator.of(context)
                    .pop((title.text, members.text.split(','))),
            child: const Text('Create group'),
          ),
        ],
      ),
    );
    title.dispose();
    members.dispose();
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
    if (message.outgoing) return;
    if (!message.oneTime) {
      await widget.controller.markMessageRead(message.messageId);
      return;
    }
    final text = await widget.controller.consumeOneTimeMessage(
      message.messageId,
    );
    if (!mounted || text == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('View-once message'),
        content: Text(text, key: const Key('one-time-message-content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
      builder: (context) =>
          _EditProfileDialog(profile: widget.connection.profile),
    );
    if (update == null || !mounted) return;
    final saved = await widget.controller.updateProfile(update);
    if (!mounted) return;
    _showMessage(
      saved
          ? 'Profile updated.'
          : widget.controller.profileError ?? 'Profile update failed.',
    );
  }

  Future<void> _showPeerProfile() async {
    final username = _recipientController.text.trim();
    if (username.isEmpty) {
      _showMessage('Enter a recipient username first.');
      return;
    }
    final profile = await widget.controller.lookupProfile(username);
    if (!mounted) return;
    if (profile == null) {
      _showMessage(
        widget.controller.profileError ?? 'Could not load that profile.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Public profile'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileAvatar(profile: profile, radius: 46),
              const SizedBox(height: 14),
              Text(
                profile.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('@${profile.username}'),
              const SizedBox(height: 12),
              Text(
                profile.status.isEmpty ? 'No status set' : profile.status,
                key: const Key('peer-profile-status'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final account = _AccountPanel(
              connection: widget.connection,
              localDevice: widget.controller.localDevice!,
              safetyNumber: widget.controller.safetyNumber!,
              compact: !wide,
              profileBusy: widget.controller.profileBusy,
              onEditProfile: _editProfile,
              onSignOut: widget.controller.signOut,
            );
            final conversation = _ConversationPanel(
              controller: widget.controller,
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
              oneTime: _oneTime,
              expiresAfter: _expiresAfter,
              selectedGroupId: _selectedGroupId,
              onConversationChanged: (value) => setState(() {
                _selectedGroupId = value;
                if (value != null) _oneTime = false;
              }),
              onCreateGroup: _createGroup,
              onOneTimeChanged: (value) => setState(() => _oneTime = value),
              onExpiresAfterChanged: (value) =>
                  setState(() => _expiresAfter = value),
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
              padding: const EdgeInsets.all(18),
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
                        account,
                        const SizedBox(height: 18),
                        Expanded(child: conversation),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.profile});

  final AccountProfile profile;

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
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Profile image',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > AccountProfileLimits.maxAvatarBytes) {
      setState(() {
        _validationError = 'Profile images must be 256 KiB or smaller.';
      });
      return;
    }
    final contentType = _profileImageContentType(file.name);
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
      title: const Text('Edit public profile'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileAvatar(profile: preview, radius: 42),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('profile-avatar-pick'),
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Choose image'),
                  ),
                  if (_avatarBytes != null)
                    TextButton.icon(
                      key: const Key('profile-avatar-remove'),
                      onPressed: _removeAvatar,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('profile-display-name'),
                controller: _displayName,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('profile-status'),
                controller: _status,
                maxLength: AccountProfileLimits.maxStatusCharacters,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  hintText: 'Available',
                ),
              ),
              if (_validationError case final message?) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  key: const Key('profile-validation-error'),
                  style: const TextStyle(color: Color(0xFF9E2A2B)),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Your profile is visible to authenticated WampApp members. '
                'Message contents and device keys are never included.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('profile-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.connection,
    required this.localDevice,
    required this.safetyNumber,
    required this.compact,
    required this.profileBusy,
    required this.onEditProfile,
    required this.onSignOut,
  });

  final AccountConnection connection;
  final DeviceRecord localDevice;
  final String safetyNumber;
  final bool compact;
  final bool profileBusy;
  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final profile = connection.profile;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.waves_rounded, color: WampAppTheme.pine),
                SizedBox(width: 9),
                Text(
                  'WampApp',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Spacer(),
                _OnlineBadge(),
              ],
            ),
            SizedBox(height: compact ? 12 : 24),
            Row(
              children: [
                _ProfileAvatar(profile: profile, radius: 25),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('@${connection.username}'),
                      if (profile.status.isNotEmpty)
                        Text(
                          profile.status,
                          key: const Key('account-profile-status'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('account-profile-edit'),
                  tooltip: 'Edit public profile',
                  onPressed: profileBusy ? null : onEditProfile,
                  icon: profileBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                ),
                if (compact)
                  IconButton(
                    key: const Key('account-sign-out-compact'),
                    tooltip: 'Sign out',
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                  ),
              ],
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              compact
                  ? '${localDevice.enrollment.deviceName} · ${connection.endpoint.websocketUri.authority}'
                  : connection.endpoint.websocketUri.authority,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            if (!compact) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: WampAppTheme.mint.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user_outlined, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Encrypted device vault',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(localDevice.enrollment.deviceName),
                    const SizedBox(height: 4),
                    Text(
                      safetyNumber,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.radius});

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
      backgroundColor: WampAppTheme.mint,
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
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: Color(0xFF38A66D)),
        SizedBox(width: 6),
        Text(
          'Online',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.controller,
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
    required this.oneTime,
    required this.expiresAfter,
    required this.selectedGroupId,
    required this.onConversationChanged,
    required this.onCreateGroup,
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
  final bool oneTime;
  final Duration? expiresAfter;
  final String? selectedGroupId;
  final ValueChanged<String?> onConversationChanged;
  final Future<void> Function() onCreateGroup;
  final ValueChanged<bool> onOneTimeChanged;
  final ValueChanged<Duration?> onExpiresAfterChanged;
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
    final selectedGroup = controller.groups
        .where((group) => group.conversationId == selectedGroupId)
        .firstOrNull;
    final groupMode = selectedGroupId != null;
    final query = LocalMessageQuery(
      text: searchQuery,
      readFilter: readFilter,
      selectedGroupId: selectedGroupId,
    );
    final globalSearch = query.isGlobalSearch;
    final visibleMessages = query.select(controller.messages);
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 22),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, color: WampAppTheme.pine),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    selectedGroup?.title ?? 'Encrypted messages',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Sync messages',
                  onPressed: controller.messageBusy
                      ? null
                      : controller.refreshMessages,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                    ? 'Local search · ${visibleMessages.length} result${visibleMessages.length == 1 ? '' : 's'}'
                    : 'Search local messages · stays on this device',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('message-search-clear'),
                        tooltip: 'Clear message search',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close),
                      ),
              ),
              onChanged: onSearchChanged,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
            ),
            const SizedBox(height: 10),
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
                    label: const Text('Direct'),
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
                          : (_) => onConversationChanged(group.conversationId),
                      avatar: const Icon(Icons.group_outlined, size: 18),
                      label: Text(group.title),
                    ),
                  ],
                  const SizedBox(width: 8),
                  ActionChip(
                    key: const Key('conversation-create-group'),
                    onPressed: controller.messageBusy ? null : onCreateGroup,
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('New group'),
                  ),
                  const SizedBox(width: 16),
                  FilterChip(
                    key: const Key('message-filter-all'),
                    selected: readFilter == LocalMessageReadFilter.all,
                    onSelected: (_) =>
                        onReadFilterChanged(LocalMessageReadFilter.all),
                    label: const Text('All'),
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
                    label: const Text('Unread received'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const Key('message-filter-read'),
                    selected: readFilter == LocalMessageReadFilter.read,
                    onSelected: (_) =>
                        onReadFilterChanged(LocalMessageReadFilter.read),
                    avatar: const Icon(Icons.done_all, size: 18),
                    label: const Text('Read received'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (!groupMode)
              TextField(
                key: const Key('message-recipient'),
                controller: recipientController,
                enabled: !controller.messageBusy,
                decoration: InputDecoration(
                  labelText: 'Recipient username',
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: IconButton(
                    key: const Key('recipient-profile-view'),
                    tooltip: 'View public profile',
                    onPressed: controller.profileBusy ? null : onViewProfile,
                    icon: controller.profileBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_circle_outlined),
                  ),
                ),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  selectedGroup == null
                      ? 'Group unavailable'
                      : selectedGroup.memberUsernames
                            .map((username) => '@$username')
                            .join('  '),
                  key: const Key('group-members-summary'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: visibleMessages.isEmpty
                  ? _NoMessages(
                      message: globalSearch
                          ? 'No local messages match this search and filter.'
                          : switch (readFilter) {
                              LocalMessageReadFilter.all => 'No messages yet. Choose a registered account and send the first end-to-end encrypted message.',
                              LocalMessageReadFilter.unread => 'No unread received messages in this conversation.',
                              LocalMessageReadFilter.read => 'No read received messages in this conversation.',
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
            if (controller.messageError case final error?) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  key: const Key('message-error'),
                  style: const TextStyle(color: Color(0xFF9E2A2B)),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    key: const Key('message-one-time'),
                    selected: !groupMode && oneTime,
                    onSelected:
                        controller.messageBusy ||
                            groupMode ||
                            selectedAttachments.isNotEmpty
                        ? null
                        : onOneTimeChanged,
                    avatar: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('View once'),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<Duration>(
                    key: const Key('message-expiry'),
                    enabled: !controller.messageBusy,
                    initialValue: expiresAfter ?? Duration.zero,
                    onSelected: (value) => onExpiresAfterChanged(
                      value == Duration.zero ? null : value,
                    ),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: Duration.zero,
                        child: Text('Keep messages'),
                      ),
                      PopupMenuItem(
                        value: Duration(hours: 1),
                        child: Text('Delete after 1 hour'),
                      ),
                      PopupMenuItem(
                        value: Duration(days: 1),
                        child: Text('Delete after 1 day'),
                      ),
                      PopupMenuItem(
                        value: Duration(days: 7),
                        child: Text('Delete after 7 days'),
                      ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.timer_outlined, size: 18),
                      label: Text(_expiryLabel(expiresAfter)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const Key('message-attach'),
                  tooltip: 'Attach encrypted files',
                  onPressed: controller.messageBusy || voiceRecording
                      ? null
                      : onPickAttachments,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('message-expression'),
                  tooltip: 'Choose emoji or encrypted sticker',
                  onPressed:
                      controller.messageBusy || voiceRecording || stickerBusy
                      ? null
                      : onPickExpression,
                  icon: stickerBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.emoji_emotions_outlined),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: voiceRecording
                      ? Container(
                          key: const Key('voice-recording-status'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE9E4),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.fiber_manual_record,
                                color: Color(0xFFB23A2B),
                                size: 15,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Recording ${_formatDuration(voiceRecordingElapsed)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const Key('voice-recording-cancel'),
                                tooltip: 'Cancel voice note',
                                onPressed: voiceControlBusy
                                    ? null
                                    : onCancelVoiceRecording,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        )
                      : TextField(
                          key: const Key('message-composer'),
                          controller: messageController,
                          enabled: !controller.messageBusy,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: groupMode
                                ? 'Write to the encrypted group'
                                : 'Write an encrypted message',
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('message-voice'),
                  tooltip: voiceRecording
                      ? 'Finish voice note'
                      : 'Record encrypted voice note',
                  onPressed:
                      controller.messageBusy ||
                          voiceControlBusy ||
                          (!voiceRecording &&
                              selectedAttachments.length >=
                                  WampAppAttachmentLimits
                                      .maxAttachmentsPerMessage)
                      ? null
                      : onToggleVoiceRecording,
                  icon: voiceControlBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          voiceRecording
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none_rounded,
                          color: voiceRecording
                              ? const Color(0xFFB23A2B)
                              : null,
                        ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  key: const Key('message-send'),
                  tooltip: 'Send encrypted message',
                  onPressed: controller.messageBusy || voiceRecording
                      ? null
                      : onSend,
                  icon: controller.messageBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _expiryLabel(Duration? value) => switch (value) {
    null => 'Keep messages',
    const Duration(hours: 1) => 'Delete after 1 hour',
    const Duration(days: 1) => 'Delete after 1 day',
    const Duration(days: 7) => 'Delete after 7 days',
    _ => 'Auto-delete enabled',
  };
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.outbound,
    this.onTap,
    this.onRetry,
    this.onDiscard,
    this.onOpenAttachment,
  });

  final LocalChatMessage message;
  final OutboundChatMessage? outbound;
  final VoidCallback? onTap;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDiscard;
  final Future<void> Function(EncryptedAttachmentDescriptor attachment)?
  onOpenAttachment;

  String get _statusLabel {
    final pending = outbound;
    if (pending != null) {
      return switch (pending.state) {
        OutboundMessageState.queued => 'Sending…',
        OutboundMessageState.accepted => 'Sent · syncing',
        OutboundMessageState.retryable => 'Not sent',
        OutboundMessageState.rejected => 'Rejected',
        OutboundMessageState.conflict => 'Message conflict',
      };
    }
    return message.outgoing
        ? (message.readAt != null
              ? (message.oneTime
                    ? 'Opened'
                    : message.isGroup
                    ? 'Read by everyone'
                    : 'Read')
              : message.deliveredAt != null
              ? (message.isGroup ? 'Delivered to everyone' : 'Delivered')
              : 'Sent')
        : message.oneTime
        ? 'View once'
        : message.readAt != null
        ? 'Read'
        : 'Tap to mark read';
  }

  @override
  Widget build(BuildContext context) {
    final pending = outbound;
    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: message.outgoing
                ? WampAppTheme.mint
                : const Color(0xFFF1EBDD),
            borderRadius: BorderRadius.circular(16),
          ),
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
                      ? 'Tap to view once'
                      : message.text,
                ),
              ],
              for (final attachment in message.attachments) ...[
                const SizedBox(height: 7),
                _AttachmentCard(
                  attachment: attachment,
                  onOpen: onOpenAttachment == null
                      ? null
                      : () => onOpenAttachment!(attachment),
                ),
              ],
              const SizedBox(height: 5),
              Text(_statusLabel, style: const TextStyle(fontSize: 10)),
              if (pending?.canRetry == true || pending?.canDiscard == true) ...[
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
                        label: const Text('Retry'),
                      ),
                    if (pending?.canDiscard == true)
                      TextButton.icon(
                        key: ValueKey('message-discard-${message.messageId}'),
                        onPressed: onDiscard,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Discard'),
                      ),
                  ],
                ),
              ],
            ],
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
    return Material(
      color: Colors.white.withValues(alpha: 0.55),
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
                      ' · encrypted',
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
          const Text(
            'The file was authenticated and decrypted on this device.',
            textAlign: TextAlign.center,
          ),
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
                    ? 'Pause voice note'
                    : 'Play voice note',
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
                'authenticated and decrypted on this device',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (controller.error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: const TextStyle(color: Color(0xFF9E2A2B))),
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

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../application/wamp_app_controller.dart';
import '../domain/local_chat_message.dart';
import '../domain/outbound_chat_message.dart';
import '../infrastructure/attachment_cipher.dart';
import '../infrastructure/voice_note_playback.dart';
import '../infrastructure/voice_note_recorder.dart';
import '../infrastructure/wamp_account_gateway.dart';
import 'wamp_app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.connection,
    this.voiceNoteCaptureFactory,
  });

  final WampAppController controller;
  final AccountConnection connection;
  final VoiceNoteCapture Function()? voiceNoteCaptureFactory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recipientController = TextEditingController();
  final _messageController = TextEditingController();
  bool _oneTime = false;
  Duration? _expiresAfter;
  String? _selectedGroupId;
  List<_SelectedAttachment> _attachments = const [];
  VoiceNoteCapture? _voiceNoteCapture;
  VoiceNoteCaptureSession? _voiceRecording;
  Timer? _voiceRecordingTicker;
  DateTime? _voiceRecordingStartedAt;
  Duration _voiceRecordingElapsed = Duration.zero;
  bool _voiceControlBusy = false;

  VoiceNoteCapture get _recorder => _voiceNoteCapture ??=
      widget.voiceNoteCaptureFactory?.call() ?? VoiceNoteRecorder();

  @override
  void dispose() {
    _voiceRecordingTicker?.cancel();
    for (final attachment in _attachments) {
      attachment.dispose();
    }
    final recorder = _voiceNoteCapture;
    recorder?.dispose().ignore();
    _recipientController.dispose();
    _messageController.dispose();
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
              onSignOut: widget.controller.signOut,
            );
            final conversation = _ConversationPanel(
              controller: widget.controller,
              recipientController: _recipientController,
              messageController: _messageController,
              onSend: _send,
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
              onRemoveAttachment: _removeAttachment,
              onOpenAttachment: _openAttachment,
              voiceRecording: _voiceRecording != null,
              voiceControlBusy: _voiceControlBusy,
              voiceRecordingElapsed: _voiceRecordingElapsed,
              onToggleVoiceRecording: _toggleVoiceRecording,
              onCancelVoiceRecording: _cancelVoiceRecording,
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

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.connection,
    required this.localDevice,
    required this.safetyNumber,
    required this.onSignOut,
  });

  final AccountConnection connection;
  final DeviceRecord localDevice;
  final String safetyNumber;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final initial = connection.displayName.characters.first.toUpperCase();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
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
            const SizedBox(height: 24),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: WampAppTheme.mint,
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
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
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TextField(
              enabled: false,
              decoration: const InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              connection.endpoint.websocketUri.authority,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
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
    required this.onSend,
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
    required this.onRemoveAttachment,
    required this.onOpenAttachment,
    required this.voiceRecording,
    required this.voiceControlBusy,
    required this.voiceRecordingElapsed,
    required this.onToggleVoiceRecording,
    required this.onCancelVoiceRecording,
  });

  final WampAppController controller;
  final TextEditingController recipientController;
  final TextEditingController messageController;
  final Future<void> Function() onSend;
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

  @override
  Widget build(BuildContext context) {
    final selectedGroup = controller.groups
        .where((group) => group.conversationId == selectedGroupId)
        .firstOrNull;
    final groupMode = selectedGroupId != null;
    final visibleMessages = controller.messages
        .where(
          (message) => groupMode
              ? message.conversationId == selectedGroupId && message.isGroup
              : !message.isGroup,
        )
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
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
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                  for (final group in controller.groups)
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
                  ActionChip(
                    key: const Key('conversation-create-group'),
                    onPressed: controller.messageBusy ? null : onCreateGroup,
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('New group'),
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
                decoration: const InputDecoration(
                  labelText: 'Recipient username',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
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
                  ? const _NoMessages()
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
                          onTap: message.outgoing || controller.messageBusy
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
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
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
            const SizedBox(height: 8),
            if (selectedAttachments.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const Key('selected-attachments'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < selectedAttachments.length;
                      index += 1
                    )
                      InputChip(
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
                  ],
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
  const _NoMessages();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No messages yet. Choose a registered account and send the first end-to-end encrypted message.',
          textAlign: TextAlign.center,
        ),
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
                throw StateError('The recorded voice note was disposed.');
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

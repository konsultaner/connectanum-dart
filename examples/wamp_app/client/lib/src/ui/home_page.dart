import 'package:flutter/material.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../application/wamp_app_controller.dart';
import '../domain/local_chat_message.dart';
import '../domain/outbound_chat_message.dart';
import '../infrastructure/wamp_account_gateway.dart';
import 'wamp_app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.connection,
  });

  final WampAppController controller;
  final AccountConnection connection;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recipientController = TextEditingController();
  final _messageController = TextEditingController();
  bool _oneTime = false;
  Duration? _expiresAfter;
  String? _selectedGroupId;

  @override
  void dispose() {
    _recipientController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text;
    final groupId = _selectedGroupId;
    final queued = groupId == null
        ? await widget.controller.sendMessage(
            recipientUsername: _recipientController.text,
            text: text,
            oneTime: _oneTime,
            expiresAfter: _expiresAfter,
          )
        : await widget.controller.sendGroupMessage(
            groupId: groupId,
            text: text,
            expiresAfter: _expiresAfter,
          );
    if (mounted && queued) {
      _messageController.clear();
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
                  onSelected: controller.messageBusy || groupMode
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
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
                const SizedBox(width: 10),
                IconButton.filled(
                  key: const Key('message-send'),
                  tooltip: 'Send encrypted message',
                  onPressed: controller.messageBusy ? null : onSend,
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
  });

  final LocalChatMessage message;
  final OutboundChatMessage? outbound;
  final VoidCallback? onTap;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDiscard;

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
              const SizedBox(height: 4),
              Text(
                message.oneTime && !message.outgoing
                    ? 'Tap to view once'
                    : message.text,
              ),
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

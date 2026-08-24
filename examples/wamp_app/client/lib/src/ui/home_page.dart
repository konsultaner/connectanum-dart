import 'package:flutter/material.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../application/wamp_app_controller.dart';
import '../domain/local_chat_message.dart';
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

  @override
  void dispose() {
    _recipientController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text;
    await widget.controller.sendMessage(
      recipientUsername: _recipientController.text,
      text: text,
    );
    if (mounted && widget.controller.messageError == null) {
      _messageController.clear();
    }
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
  });

  final WampAppController controller;
  final TextEditingController recipientController;
  final TextEditingController messageController;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
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
                    'Encrypted messages',
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
            const SizedBox(height: 14),
            TextField(
              key: const Key('message-recipient'),
              controller: recipientController,
              enabled: !controller.messageBusy,
              decoration: const InputDecoration(
                labelText: 'Recipient username',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: controller.messages.isEmpty
                  ? const _NoMessages()
                  : ListView.separated(
                      key: const Key('message-history'),
                      reverse: true,
                      itemCount: controller.messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final message = controller
                            .messages[controller.messages.length - index - 1];
                        return _MessageBubble(message: message);
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
                    decoration: const InputDecoration(
                      hintText: 'Write an encrypted message',
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
  const _MessageBubble({required this.message});

  final LocalChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: message.outgoing ? WampAppTheme.mint : const Color(0xFFF1EBDD),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@${message.peerUsername}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(message.text),
            const SizedBox(height: 5),
            Text(
              message.outgoing
                  ? (message.readAt != null
                        ? 'Read'
                        : message.deliveredAt != null
                        ? 'Delivered'
                        : 'Sent')
                  : 'Received',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

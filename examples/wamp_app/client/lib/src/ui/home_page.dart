import 'package:flutter/material.dart';

import '../application/wamp_app_controller.dart';
import '../infrastructure/wamp_account_gateway.dart';
import 'wamp_app_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.connection,
  });

  final WampAppController controller;
  final AccountConnection connection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final account = _AccountPanel(
              connection: connection,
              onSignOut: controller.signOut,
            );
            return Padding(
              padding: const EdgeInsets.all(18),
              child: wide
                  ? Row(
                      children: [
                        SizedBox(width: 320, child: account),
                        const SizedBox(width: 18),
                        const Expanded(child: _ConversationEmptyState()),
                      ],
                    )
                  : Column(
                      children: [
                        account,
                        const SizedBox(height: 18),
                        const Expanded(child: _ConversationEmptyState()),
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
  const _AccountPanel({required this.connection, required this.onSignOut});

  final AccountConnection connection;
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

class _ConversationEmptyState extends StatelessWidget {
  const _ConversationEmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    color: WampAppTheme.mint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    size: 42,
                    color: WampAppTheme.pine,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Connected, with room to talk',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Account registration and SCRAM login are live. Conversation storage and encrypted envelopes are the next vertical slice; this screen intentionally contains no fake messages.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

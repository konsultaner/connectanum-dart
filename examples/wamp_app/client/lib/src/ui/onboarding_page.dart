import 'dart:async';

import 'package:flutter/material.dart';

import '../application/wamp_app_controller.dart';
import 'backup_passphrase_dialog.dart';

enum _AccountMode { register, login }

enum _ServerProbeState { idle, checking, reachable, unreachable }

const _defaultServerAddress = String.fromEnvironment(
  'WAMP_APP_SERVER_ADDRESS',
  defaultValue: 'ws://localhost:8080/ws',
);

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.controller});

  final WampAppController controller;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _serverProbeDebounce = Duration(milliseconds: 350);

  final _server = TextEditingController(text: _defaultServerAddress);
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  _AccountMode _mode = _AccountMode.register;
  Timer? _serverProbeTimer;
  int _serverProbeGeneration = 0;
  _ServerProbeState _serverProbeState = _ServerProbeState.idle;

  @override
  void initState() {
    super.initState();
    _server.addListener(_onServerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleServerProbe(immediate: true);
    });
  }

  @override
  void dispose() {
    _serverProbeGeneration += 1;
    _serverProbeTimer?.cancel();
    _server.removeListener(_onServerChanged);
    _server.dispose();
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onServerChanged() => _scheduleServerProbe();

  void _scheduleServerProbe({bool immediate = false}) {
    if (!mounted) return;
    _serverProbeTimer?.cancel();
    final generation = ++_serverProbeGeneration;
    final serverAddress = _server.text.trim();
    if (serverAddress.isEmpty) {
      setState(() => _serverProbeState = _ServerProbeState.idle);
      return;
    }
    setState(() => _serverProbeState = _ServerProbeState.checking);
    if (immediate) {
      unawaited(_probeServer(serverAddress, generation));
      return;
    }
    _serverProbeTimer = Timer(_serverProbeDebounce, () {
      _serverProbeTimer = null;
      unawaited(_probeServer(serverAddress, generation));
    });
  }

  Future<void> _probeServer(String serverAddress, int generation) async {
    var nextState = _ServerProbeState.reachable;
    try {
      await widget.controller.probeServer(serverAddress: serverAddress);
    } catch (_) {
      nextState = _ServerProbeState.unreachable;
    }
    if (!mounted || generation != _serverProbeGeneration) return;
    setState(() => _serverProbeState = nextState);
  }

  Future<void> _submit() async {
    final password = _password.text;
    try {
      if (_mode == _AccountMode.register) {
        await widget.controller.registerAndConnect(
          serverAddress: _server.text,
          username: _username.text,
          displayName: _displayName.text,
          password: password,
        );
      } else {
        await widget.controller.login(
          serverAddress: _server.text,
          username: _username.text,
          password: password,
        );
      }
    } finally {
      _password.clear();
    }
  }

  Future<void> _restoreFromBackup() async {
    final recoveryPassphrase = await showBackupPassphraseDialog(
      context,
      confirm: false,
    );
    if (recoveryPassphrase == null || !mounted) return;
    final password = _password.text;
    try {
      await widget.controller.restoreLocalBackupAndLogin(
        serverAddress: _server.text,
        username: _username.text,
        password: password,
        recoveryPassphrase: recoveryPassphrase,
      );
    } finally {
      _password.clear();
    }
  }

  Future<void> _restoreFromCloud() async {
    final recoveryPassphrase = await showBackupPassphraseDialog(
      context,
      confirm: false,
    );
    if (recoveryPassphrase == null || !mounted) return;
    final password = _password.text;
    try {
      await widget.controller.restoreRemoteBackupAndLogin(
        serverAddress: _server.text,
        username: _username.text,
        password: password,
        recoveryPassphrase: recoveryPassphrase,
      );
    } finally {
      _password.clear();
    }
  }

  void _setMode(_AccountMode mode) {
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _Atmosphere()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: wide
                          ? Row(
                              children: [
                                const Expanded(child: _Intro()),
                                const SizedBox(width: 54),
                                Expanded(child: _AccountCard(state: this)),
                              ],
                            )
                          : Column(
                              children: [
                                const _Intro(compact: true),
                                const SizedBox(height: 30),
                                _AccountCard(state: this),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.state});

  final _OnboardingPageState state;

  @override
  Widget build(BuildContext context) {
    final controller = state.widget.controller;
    final registering = state._mode == _AccountMode.register;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_AccountMode>(
                segments: const [
                  ButtonSegment(
                    value: _AccountMode.register,
                    label: Text('Create account'),
                  ),
                  ButtonSegment(
                    value: _AccountMode.login,
                    label: Text('Sign in'),
                  ),
                ],
                selected: {state._mode},
                onSelectionChanged: controller.isBusy
                    ? null
                    : (selection) => state._setMode(selection.single),
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('server-address'),
                controller: state._server,
                enabled: !controller.isBusy,
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 8),
              _ServerProbeStatus(
                state: state._serverProbeState,
                onRetry: controller.isBusy
                    ? null
                    : () => state._scheduleServerProbe(immediate: true),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('username'),
                controller: state._username,
                enabled: !controller.isBusy,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              if (registering) ...[
                const SizedBox(height: 14),
                TextField(
                  key: const Key('display-name'),
                  controller: state._displayName,
                  enabled: !controller.isBusy,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                key: const Key('password'),
                controller: state._password,
                enabled: !controller.isBusy,
                obscureText: true,
                autofillHints: registering
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                onSubmitted: (_) => state._submit(),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
              if ((controller.backupError ?? controller.errorMessage)
                  case final message?) ...[
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const Key('connection-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('submit-account'),
                onPressed: controller.isBusy ? null : state._submit,
                icon: controller.isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(registering ? Icons.arrow_forward : Icons.login),
                label: Text(
                  registering ? 'Create and connect' : 'Connect securely',
                ),
              ),
              if (!registering) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('restore-local-backup'),
                  onPressed: controller.isBusy
                      ? null
                      : state._restoreFromBackup,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Restore encrypted backup'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('restore-remote-backup'),
                  onPressed: controller.isBusy ? null : state._restoreFromCloud,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Restore backup from server'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Both restore paths recover this account\'s device identity, chats, settings, and attachment keys. The server copy is end-to-end encrypted. Cached media bytes are not included and must be downloaded again.',
                  key: const Key('backup-restore-boundary'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'SCRAM derives the password key off the UI thread. Plaintext passwords are not stored by the app or server.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerProbeStatus extends StatelessWidget {
  const _ServerProbeStatus({required this.state, required this.onRetry});

  final _ServerProbeState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: switch (state) {
        _ServerProbeState.idle => const SizedBox.shrink(
          key: Key('server-probe-idle'),
        ),
        _ServerProbeState.checking => Semantics(
          key: const Key('server-probe-checking'),
          liveRegion: true,
          child: const Row(
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Expanded(child: Text('Checking router availability...')),
            ],
          ),
        ),
        _ServerProbeState.reachable => Semantics(
          key: const Key('server-probe-reachable'),
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Router ready for secure WAMP onboarding.'),
              ),
            ],
          ),
        ),
        _ServerProbeState.unreachable => Semantics(
          key: const Key('server-probe-unreachable'),
          liveRegion: true,
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Router not reachable. Check the address or start the server.',
                ),
              ),
              TextButton(
                key: const Key('server-probe-retry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      },
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        const _Wordmark(),
        const SizedBox(height: 26),
        Text(
          'Your conversations.\nYour keys. Your server.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 18),
        Text(
          'WampApp is the integration example for secure, real-time messaging over Connectanum. Start locally, then point the same client at your own WSS endpoint.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TrustChip(icon: Icons.lock_outline, label: 'E2EE-ready'),
            _TrustChip(icon: Icons.bolt_outlined, label: 'WAMP real time'),
            _TrustChip(icon: Icons.smart_toy_outlined, label: 'MCP-ready'),
          ],
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(
            Icons.waves_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'WampApp',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Atmosphere extends StatelessWidget {
  const _Atmosphere();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.primaryContainer.withValues(alpha: 0.72),
            colors.secondaryContainer.withValues(alpha: 0.62),
          ],
        ),
      ),
      child: CustomPaint(painter: _DotPainter(colors.outlineVariant)),
    );
  }
}

class _DotPainter extends CustomPainter {
  const _DotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.28);
    for (double x = 20; x < size.width; x += 34) {
      for (double y = 20; y < size.height; y += 34) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) =>
      color != oldDelegate.color;
}

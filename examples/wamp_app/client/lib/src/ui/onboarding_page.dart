import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
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
  bool _rememberWithBiometrics = false;
  bool _automaticBiometricAttempted = false;

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
    final biometricReason = AppLocalizations.of(context).signInWithBiometrics;
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
      if (_rememberWithBiometrics && widget.controller.connection != null) {
        await widget.controller.enableBiometricLogin(
          password: password,
          localizedReason: biometricReason,
        );
      }
    } finally {
      _password.clear();
    }
  }

  void _scheduleBiometricUnlock() {
    final controller = widget.controller;
    if (_automaticBiometricAttempted ||
        !controller.biometricRemembered ||
        controller.biometricBusy ||
        controller.connection != null) {
      return;
    }
    _automaticBiometricAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_unlockWithBiometrics());
    });
  }

  Future<void> _unlockWithBiometrics() =>
      widget.controller.unlockWithBiometrics(
        localizedReason: AppLocalizations.of(context).signInWithBiometrics,
      );

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

  void _setRememberWithBiometrics(bool value) {
    setState(() => _rememberWithBiometrics = value);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBiometricUnlock();
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
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_AccountMode>(
                segments: [
                  ButtonSegment(
                    value: _AccountMode.register,
                    label: Text(l10n.createAccount),
                  ),
                  ButtonSegment(
                    value: _AccountMode.login,
                    label: Text(l10n.signIn),
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
                decoration: InputDecoration(
                  labelText: l10n.serverAddress,
                  prefixIcon: const Icon(Icons.dns_outlined),
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
                decoration: InputDecoration(
                  labelText: l10n.username,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
              ),
              if (registering) ...[
                const SizedBox(height: 14),
                TextField(
                  key: const Key('display-name'),
                  controller: state._displayName,
                  enabled: !controller.isBusy,
                  decoration: InputDecoration(
                    labelText: l10n.displayName,
                    prefixIcon: const Icon(Icons.badge_outlined),
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
                decoration: InputDecoration(
                  labelText: l10n.password,
                  prefixIcon: const Icon(Icons.key_outlined),
                ),
              ),
              if (controller.biometricAvailable) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const Key('remember-with-biometrics'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.staySignedIn),
                  subtitle: Text(l10n.staySignedInSubtitle),
                  value: state._rememberWithBiometrics,
                  onChanged: controller.isBusy
                      ? null
                      : (value) =>
                            state._setRememberWithBiometrics(value ?? false),
                ),
              ],
              if ((controller.backupError ??
                      controller.biometricError ??
                      controller.errorMessage)
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
                  registering ? l10n.createAndConnect : l10n.connectSecurely,
                ),
              ),
              if (controller.biometricRemembered) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('biometric-sign-in'),
                  onPressed: controller.biometricBusy
                      ? null
                      : state._unlockWithBiometrics,
                  icon: controller.biometricBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(l10n.signInWithBiometrics),
                ),
              ],
              if (!registering) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('restore-local-backup'),
                  onPressed: controller.isBusy
                      ? null
                      : state._restoreFromBackup,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: Text(l10n.restoreEncryptedBackup),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('restore-remote-backup'),
                  onPressed: controller.isBusy ? null : state._restoreFromCloud,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(l10n.restoreBackupFromServer),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.backupRestoreBoundary,
                  key: const Key('backup-restore-boundary'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
    final l10n = AppLocalizations.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: switch (state) {
        _ServerProbeState.idle => const SizedBox.shrink(
          key: Key('server-probe-idle'),
        ),
        _ServerProbeState.checking => Semantics(
          key: const Key('server-probe-checking'),
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.checkingServer)),
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
              Expanded(child: Text(l10n.serverReady)),
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
              Expanded(child: Text(l10n.serverUnavailable)),
              TextButton(
                key: const Key('server-probe-retry'),
                onPressed: onRetry,
                child: Text(l10n.retry),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        const _Wordmark(),
        const SizedBox(height: 26),
        Text(
          l10n.introHeadline,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 18),
        Text(
          l10n.introBody,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TrustChip(icon: Icons.lock_outline, label: l10n.privateByDesign),
            _TrustChip(
              icon: Icons.bolt_outlined,
              label: l10n.realTimeMessaging,
            ),
            _TrustChip(icon: Icons.person_outline, label: l10n.yourOwnAccount),
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

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
  bool _obscurePassword = true;

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
    _password.clear();
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

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBiometricUnlock();
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(child: _WelcomeBackdrop()),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      constraints.maxWidth < 420 ? 16 : 24,
                      24,
                      constraints.maxWidth < 420 ? 16 : 24,
                      32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(child: _Wordmark()),
                          const SizedBox(height: 24),
                          const _WelcomeGraphic(),
                          const SizedBox(height: 22),
                          Text(
                            AppLocalizations.of(context).introHeadline,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            AppLocalizations.of(context).introBody,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 28),
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
        padding: const EdgeInsets.all(24),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_AccountMode>(
                showSelectedIcon: false,
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
                key: const Key('username'),
                controller: state._username,
                enabled: !controller.isBusy,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
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
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.displayName,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                key: const Key('password'),
                controller: state._password,
                enabled: !controller.isBusy,
                obscureText: state._obscurePassword,
                autofillHints: registering
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => state._submit(),
                decoration: InputDecoration(
                  labelText: l10n.password,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    key: const Key('password-visibility'),
                    tooltip: state._obscurePassword
                        ? l10n.showPassword
                        : l10n.hidePassword,
                    onPressed: state._togglePasswordVisibility,
                    icon: Icon(
                      state._obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                key: const Key('advanced-server-settings'),
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                leading: const Icon(Icons.tune_outlined),
                title: Text(l10n.advancedServerSettings),
                subtitle: Text(l10n.advancedServerSettingsSubtitle),
                children: [
                  TextField(
                    key: const Key('server-address'),
                    controller: state._server,
                    enabled: !controller.isBusy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.serverAddress,
                      prefixIcon: const Icon(Icons.dns_outlined),
                    ),
                  ),
                ],
              ),
              _ServerProbeStatus(
                state: state._serverProbeState,
                onRetry: controller.isBusy
                    ? null
                    : () => state._scheduleServerProbe(immediate: true),
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              key: const Key('connection-error'),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                key: const Key('submit-account'),
                onPressed: controller.isBusy ? null : state._submit,
                child: controller.isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        registering
                            ? l10n.createAndConnect
                            : l10n.connectSecurely,
                        textAlign: TextAlign.center,
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

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final stackWordmark = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    return Flex(
      direction: stackWordmark ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.chat_bubble_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        SizedBox(width: stackWordmark ? 0 : 10, height: stackWordmark ? 8 : 0),
        const Text(
          'WampApp',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _WelcomeGraphic extends StatelessWidget {
  const _WelcomeGraphic();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      child: Semantics(
        label: AppLocalizations.of(context).privateByDesign,
        image: true,
        child: SizedBox.square(
          dimension: 92,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.forum_rounded,
                    size: 46,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 3),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeBackdrop extends StatelessWidget {
  const _WelcomeBackdrop();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.46, 1],
          colors: [
            colors.primaryContainer.withValues(alpha: 0.58),
            colors.surface.withValues(alpha: 0.96),
            colors.surface,
          ],
        ),
      ),
    );
  }
}

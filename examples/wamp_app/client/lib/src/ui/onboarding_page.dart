import 'package:flutter/material.dart';

import '../application/wamp_app_controller.dart';
import 'wamp_app_theme.dart';

enum _AccountMode { register, login }

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.controller});

  final WampAppController controller;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _server = TextEditingController(text: 'ws://localhost:8080/ws');
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  _AccountMode _mode = _AccountMode.register;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
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
              if (controller.errorMessage case final message?) ...[
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
              const SizedBox(height: 14),
              const Text(
                'SCRAM derives the password key off the UI thread. Plaintext passwords are not stored by the app or server.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xB317342D)),
              ),
            ],
          ),
        ),
      ),
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
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: WampAppTheme.pine,
          child: Icon(Icons.waves_rounded, color: Colors.white),
        ),
        SizedBox(width: 12),
        Text(
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
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0x30204A40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: WampAppTheme.pine),
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF9F1E3), Color(0xFFE7F1E8), Color(0xFFF7E6D9)],
        ),
      ),
      child: CustomPaint(painter: _DotPainter()),
    );
  }
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x15204A40);
    for (double x = 20; x < size.width; x += 34) {
      for (double y = 20; y < size.height; y += 34) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

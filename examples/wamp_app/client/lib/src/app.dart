import 'package:flutter/material.dart';

import 'application/wamp_app_controller.dart';
import 'ui/home_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/wamp_app_theme.dart';

class WampApp extends StatefulWidget {
  const WampApp({super.key, this.controller});

  final WampAppController? controller;

  @override
  State<WampApp> createState() => _WampAppState();
}

class _WampAppState extends State<WampApp> {
  late final WampAppController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? WampAppController();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WampApp',
      debugShowCheckedModeBanner: false,
      theme: WampAppTheme.light(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final connection = _controller.connection;
          if (_controller.status == WampAppStatus.connected &&
              connection != null) {
            return HomePage(controller: _controller, connection: connection);
          }
          return OnboardingPage(controller: _controller);
        },
      ),
    );
  }
}

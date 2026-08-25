import 'package:flutter/material.dart';

import 'application/wamp_app_controller.dart';
import 'domain/local_app_preferences.dart';
import 'infrastructure/platform_push_token_source.dart';
import 'ui/home_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/wamp_app_theme.dart';

class WampApp extends StatefulWidget {
  const WampApp({super.key, this.controller, this.platformPushTokenSource})
    : assert(controller == null || platformPushTokenSource == null);

  final WampAppController? controller;
  final PlatformPushTokenSource? platformPushTokenSource;

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
    _controller =
        widget.controller ??
        WampAppController(
          platformPushTokenSource: widget.platformPushTokenSource,
        );
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'WampApp',
          debugShowCheckedModeBanner: false,
          theme: WampAppTheme.light(),
          darkTheme: WampAppTheme.dark(),
          themeMode: switch (_controller.themePreference) {
            WampAppThemePreference.system => ThemeMode.system,
            WampAppThemePreference.light => ThemeMode.light,
            WampAppThemePreference.dark => ThemeMode.dark,
          },
          home: Builder(
            builder: (context) {
              final connection = _controller.connection;
              if (_controller.status == WampAppStatus.connected &&
                  connection != null) {
                return HomePage(
                  controller: _controller,
                  connection: connection,
                );
              }
              return OnboardingPage(controller: _controller);
            },
          ),
        );
      },
    );
  }
}

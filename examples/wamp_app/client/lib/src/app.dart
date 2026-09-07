import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/wamp_app_controller.dart';
import 'domain/local_app_preferences.dart';
import 'infrastructure/contact_importer.dart';
import 'infrastructure/platform_push_token_source.dart';
import 'infrastructure/profile_avatar_picker.dart';
import '../l10n/generated/app_localizations.dart';
import 'ui/home_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/wamp_app_theme.dart';

class WampApp extends StatefulWidget {
  const WampApp({
    super.key,
    this.controller,
    this.platformPushTokenSource,
    this.contactImporter,
    this.profileAvatarPicker,
  }) : assert(controller == null || platformPushTokenSource == null);

  final WampAppController? controller;
  final PlatformPushTokenSource? platformPushTokenSource;
  final ContactImporter? contactImporter;
  final ProfileAvatarPicker? profileAvatarPicker;

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
    unawaited(_controller.initializeBiometricLogin());
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
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: switch (_controller.localePreference) {
            WampAppLocalePreference.system => null,
            final preference => Locale(preference.languageCode!),
          },
          theme: WampAppTheme.light(_controller.accentPreference),
          darkTheme: WampAppTheme.dark(_controller.accentPreference),
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
                  contactImporter: widget.contactImporter,
                  profileAvatarPicker: widget.profileAvatarPicker,
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

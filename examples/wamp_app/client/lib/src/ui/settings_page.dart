import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../application/wamp_app_controller.dart';
import '../domain/local_app_preferences.dart';
import 'technical_info_page.dart';
import 'wamp_app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onEditProfile,
    required this.onManageContacts,
    required this.onOpenMcpAccess,
    required this.onBackup,
    required this.onRemoteBackup,
  });

  final WampAppController controller;
  final VoidCallback onEditProfile;
  final VoidCallback onManageContacts;
  final VoidCallback onOpenMcpAccess;
  final VoidCallback onBackup;
  final VoidCallback onRemoteBackup;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _setBiometricLogin(bool enabled) async {
    final l10n = AppLocalizations.of(context);
    if (!enabled) {
      await widget.controller.disableBiometricLogin();
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _BiometricPasswordDialog(),
    );
    if (password == null || !mounted) return;
    await widget.controller.enableBiometricLogin(
      password: password,
      localizedReason: l10n.signInWithBiometrics,
    );
  }

  Future<void> _signOut() async {
    final signOut = widget.controller.signOut();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    await signOut;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final controller = widget.controller;
        final profile = controller.connection?.profile;
        if (profile == null) return const SizedBox.shrink();
        return Scaffold(
          key: const Key('settings-page'),
          appBar: AppBar(title: Text(l10n.settings)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel(l10n.account),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              key: const Key('account-profile-edit'),
                              leading: const Icon(Icons.person_outline),
                              title: Text(l10n.editProfile),
                              subtitle: Text(profile.displayName),
                              trailing: const Icon(Icons.chevron_right),
                              enabled: !controller.profileBusy,
                              onTap: widget.onEditProfile,
                            ),
                            ListTile(
                              key: const Key('account-contacts'),
                              leading: const Icon(Icons.contacts_outlined),
                              title: Text(l10n.contacts),
                              subtitle: Text(l10n.contactsSubtitle),
                              trailing: const Icon(Icons.chevron_right),
                              enabled: !controller.contactBusy,
                              onTap: widget.onManageContacts,
                            ),
                          ],
                        ),
                      ),
                      _SectionLabel(l10n.privacy),
                      Card(
                        child: Column(
                          children: [
                            SwitchListTile.adaptive(
                              key: const Key('settings-biometric-login'),
                              secondary: const Icon(Icons.fingerprint),
                              title: Text(l10n.staySignedIn),
                              subtitle: Text(
                                controller.biometricAvailable
                                    ? l10n.staySignedInSubtitle
                                    : l10n.biometricsUnavailable,
                              ),
                              value: controller.biometricRemembered,
                              onChanged:
                                  controller.biometricAvailable &&
                                      !controller.biometricBusy
                                  ? _setBiometricLogin
                                  : null,
                            ),
                            SwitchListTile.adaptive(
                              key: const Key('settings-push-notifications'),
                              secondary: const Icon(
                                Icons.notifications_outlined,
                              ),
                              title: Text(l10n.pushNotifications),
                              subtitle: Text(l10n.pushNotificationsSubtitle),
                              value: controller.pushNotificationsEnabled,
                              onChanged: controller.preferenceBusy
                                  ? null
                                  : controller.setPushNotificationsEnabled,
                            ),
                          ],
                        ),
                      ),
                      _SectionLabel(l10n.appearance),
                      Card(
                        child: Column(
                          children: [
                            PopupMenuButton<WampAppThemePreference>(
                              key: const Key('account-theme-menu'),
                              enabled: !controller.preferenceBusy,
                              initialValue: controller.themePreference,
                              onSelected: controller.setThemePreference,
                              itemBuilder: (context) => [
                                for (final preference
                                    in WampAppThemePreference.values)
                                  CheckedPopupMenuItem(
                                    key: ValueKey(
                                      'appearance-${preference.wireName}',
                                    ),
                                    value: preference,
                                    checked:
                                        preference ==
                                        controller.themePreference,
                                    child: Text(_themeLabel(l10n, preference)),
                                  ),
                              ],
                              child: ListTile(
                                leading: const Icon(
                                  Icons.brightness_6_outlined,
                                ),
                                title: Text(l10n.theme),
                                subtitle: Text(
                                  _themeLabel(l10n, controller.themePreference),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                            _AccentSelector(
                              selected: controller.accentPreference,
                              enabled: !controller.preferenceBusy,
                              onSelected: controller.setAccentPreference,
                            ),
                            PopupMenuButton<WampAppLocalePreference>(
                              key: const Key('settings-language-menu'),
                              enabled: !controller.preferenceBusy,
                              initialValue: controller.localePreference,
                              onSelected: controller.setLocalePreference,
                              itemBuilder: (context) => [
                                for (final preference
                                    in WampAppLocalePreference.values)
                                  CheckedPopupMenuItem(
                                    key: ValueKey(
                                      'language-${preference.wireName}',
                                    ),
                                    value: preference,
                                    checked:
                                        preference ==
                                        controller.localePreference,
                                    child: Text(
                                      _languageLabel(l10n, preference),
                                    ),
                                  ),
                              ],
                              child: ListTile(
                                leading: const Icon(Icons.language_outlined),
                                title: Text(l10n.language),
                                subtitle: Text(
                                  _languageLabel(
                                    l10n,
                                    controller.localePreference,
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SectionLabel(l10n.dataAndStorage),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              key: const Key('account-backup'),
                              leading: const Icon(Icons.backup_outlined),
                              title: Text(l10n.backup),
                              subtitle: Text(l10n.backupSubtitle),
                              trailing: const Icon(Icons.chevron_right),
                              enabled: !controller.backupBusy,
                              onTap: widget.onBackup,
                            ),
                            ListTile(
                              key: const Key('account-backup-remote'),
                              leading: const Icon(Icons.cloud_upload_outlined),
                              title: Text(l10n.serverBackup),
                              subtitle: Text(l10n.serverBackupSubtitle),
                              trailing: const Icon(Icons.chevron_right),
                              enabled: !controller.backupBusy,
                              onTap: widget.onRemoteBackup,
                            ),
                          ],
                        ),
                      ),
                      _SectionLabel(l10n.advanced),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              key: const Key('account-mcp-profile-consent'),
                              leading: const Icon(Icons.smart_toy_outlined),
                              title: Text(l10n.mcpAccess),
                              subtitle: Text(l10n.mcpAccessSubtitle),
                              trailing: const Icon(Icons.chevron_right),
                              enabled:
                                  !controller.mcpAccessBusy &&
                                  !controller.mcpConsentBusy,
                              onTap: widget.onOpenMcpAccess,
                            ),
                            ListTile(
                              key: const Key('settings-technical-info'),
                              leading: const Icon(Icons.info_outline),
                              title: Text(l10n.technicalInformation),
                              subtitle: Text(l10n.technicalInformationSubtitle),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      TechnicalInfoPage(controller: controller),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        key: const Key('settings-sign-out'),
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: Text(l10n.signOut),
                      ),
                      if (controller.biometricError case final message?) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.7,
      ),
    ),
  );
}

class _AccentSelector extends StatelessWidget {
  const _AccentSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final WampAppAccentPreference selected;
  final bool enabled;
  final ValueChanged<WampAppAccentPreference> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      key: const Key('settings-accent-color'),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.accentColor),
            subtitle: Text(l10n.accentColorSubtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preference in WampAppAccentPreference.values)
                  ChoiceChip(
                    key: ValueKey('accent-${preference.wireName}'),
                    avatar: DecoratedBox(
                      decoration: BoxDecoration(
                        color: WampAppTheme.accentColor(preference),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: const SizedBox.square(dimension: 18),
                    ),
                    label: Text(_accentLabel(l10n, preference)),
                    selected: selected == preference,
                    showCheckmark: true,
                    onSelected: enabled ? (_) => onSelected(preference) : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricPasswordDialog extends StatefulWidget {
  const _BiometricPasswordDialog();

  @override
  State<_BiometricPasswordDialog> createState() =>
      _BiometricPasswordDialogState();
}

class _BiometricPasswordDialogState extends State<_BiometricPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.staySignedIn),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.biometricPasswordPrompt),
          const SizedBox(height: 16),
          TextField(
            key: const Key('biometric-password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(labelText: l10n.password),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('biometric-enable'),
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: Text(l10n.enable),
        ),
      ],
    );
  }
}

String _themeLabel(AppLocalizations l10n, WampAppThemePreference preference) =>
    switch (preference) {
      WampAppThemePreference.system => l10n.themeSystem,
      WampAppThemePreference.light => l10n.themeLight,
      WampAppThemePreference.dark => l10n.themeDark,
    };

String _accentLabel(
  AppLocalizations l10n,
  WampAppAccentPreference preference,
) => switch (preference) {
  WampAppAccentPreference.teal => l10n.accentTeal,
  WampAppAccentPreference.blue => l10n.accentBlue,
  WampAppAccentPreference.coral => l10n.accentCoral,
  WampAppAccentPreference.amber => l10n.accentAmber,
  WampAppAccentPreference.indigo => l10n.accentIndigo,
};

String _languageLabel(
  AppLocalizations l10n,
  WampAppLocalePreference preference,
) => switch (preference) {
  WampAppLocalePreference.system => l10n.languageSystem,
  WampAppLocalePreference.english => l10n.languageEnglish,
  WampAppLocalePreference.german => l10n.languageGerman,
  WampAppLocalePreference.spanish => l10n.languageSpanish,
  WampAppLocalePreference.french => l10n.languageFrench,
  WampAppLocalePreference.italian => l10n.languageItalian,
  WampAppLocalePreference.portuguese => l10n.languagePortuguese,
};

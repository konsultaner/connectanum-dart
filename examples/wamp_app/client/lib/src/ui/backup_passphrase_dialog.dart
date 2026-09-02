import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

Future<String?> showBackupPassphraseDialog(
  BuildContext context, {
  required bool confirm,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _BackupPassphraseDialog(confirm: confirm),
  );
}

final class _BackupPassphraseDialog extends StatefulWidget {
  const _BackupPassphraseDialog({required this.confirm});

  final bool confirm;

  @override
  State<_BackupPassphraseDialog> createState() =>
      _BackupPassphraseDialogState();
}

final class _BackupPassphraseDialogState
    extends State<_BackupPassphraseDialog> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphrase.clear();
    _confirmation.clear();
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final passphrase = _passphrase.text;
    final encoded = utf8.encode(passphrase);
    final validLength = encoded.length >= 16 && encoded.length <= 1024;
    encoded.fillRange(0, encoded.length, 0);
    if (!validLength) {
      setState(() => _error = l10n.passphraseLength);
      return;
    }
    if (widget.confirm && passphrase != _confirmation.text) {
      setState(() => _error = l10n.passphraseMismatch);
      return;
    }
    Navigator.of(context).pop(passphrase);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.confirm ? l10n.encryptDeviceBackup : l10n.restoreBackup,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.confirm ? l10n.backupCreateHelp : l10n.backupRestoreHelp,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('backup-recovery-passphrase'),
              controller: _passphrase,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) {
                if (!widget.confirm) _submit();
              },
              decoration: InputDecoration(
                labelText: l10n.recoveryPhrase,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('backup-recovery-confirmation'),
                controller: _confirmation,
                obscureText: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.confirmRecoveryPhrase,
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                ),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              Text(
                error,
                key: const Key('backup-passphrase-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('backup-passphrase-submit'),
          onPressed: _submit,
          child: Text(widget.confirm ? l10n.createBackup : l10n.chooseBackup),
        ),
      ],
    );
  }
}

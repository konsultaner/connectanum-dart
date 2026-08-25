import 'dart:convert';

import 'package:flutter/material.dart';

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
    final passphrase = _passphrase.text;
    final encoded = utf8.encode(passphrase);
    final validLength = encoded.length >= 16 && encoded.length <= 1024;
    encoded.fillRange(0, encoded.length, 0);
    if (!validLength) {
      setState(() => _error = 'Use 16 to 1024 UTF-8 bytes.');
      return;
    }
    if (widget.confirm && passphrase != _confirmation.text) {
      setState(() => _error = 'The recovery phrases do not match.');
      return;
    }
    Navigator.of(context).pop(passphrase);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Encrypt device backup' : 'Restore backup'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.confirm
                  ? 'This phrase is the only way to decrypt the export. It is not stored or sent to the server.'
                  : 'Enter the recovery phrase used when this device backup was created.',
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
              decoration: const InputDecoration(
                labelText: 'Recovery phrase',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('backup-recovery-confirmation'),
                controller: _confirmation,
                obscureText: true,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm recovery phrase',
                  prefixIcon: Icon(Icons.verified_user_outlined),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('backup-passphrase-submit'),
          onPressed: _submit,
          child: Text(widget.confirm ? 'Create backup' : 'Choose backup'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../../l10n/generated/app_localizations.dart';
import '../application/wamp_app_controller.dart';

class TechnicalInfoPage extends StatelessWidget {
  const TechnicalInfoPage({super.key, required this.controller});

  final WampAppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connection = controller.connection;
    final device = controller.localDevice;
    final safetyNumber = controller.safetyNumber;
    if (connection == null || device == null || safetyNumber == null) {
      return const SizedBox.shrink();
    }
    final rows = <({String label, String value})>[
      (label: l10n.connection, value: l10n.connected),
      (
        label: l10n.websocketEndpoint,
        value: connection.endpoint.websocketUri.toString(),
      ),
      (label: l10n.applicationRealm, value: WampAppProtocol.appRealm),
      (label: l10n.username, value: '@${connection.username}'),
      (label: l10n.device, value: device.enrollment.deviceName),
      (label: l10n.deviceId, value: device.deviceId),
      (label: l10n.safetyNumber, value: safetyNumber),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.technicalInformation)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 12),
                          Expanded(child: Text(l10n.technicalIntro)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        for (final row in rows)
                          _TechnicalRow(label: row.label, value: row.value),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(l10n.encryption),
                      subtitle: Text(l10n.encryptionSummary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalRow extends StatelessWidget {
  const _TechnicalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(label),
      subtitle: SelectableText(value),
      trailing: IconButton(
        tooltip: l10n.copy,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.copied)));
        },
        icon: const Icon(Icons.copy_outlined),
      ),
    );
  }
}

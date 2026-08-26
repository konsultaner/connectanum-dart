import 'package:flutter/material.dart';

import '../application/wamp_app_controller.dart';
import '../domain/local_contact_alias.dart';
import '../infrastructure/contact_importer.dart';

Future<String?> showContactManagerDialog({
  required BuildContext context,
  required WampAppController controller,
  required ContactImporter importer,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _ContactManagerDialog(controller: controller, importer: importer),
);

class _ContactManagerDialog extends StatefulWidget {
  const _ContactManagerDialog({
    required this.controller,
    required this.importer,
  });

  final WampAppController controller;
  final ContactImporter importer;

  @override
  State<_ContactManagerDialog> createState() => _ContactManagerDialogState();
}

class _ContactManagerDialogState extends State<_ContactManagerDialog> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  List<ImportedContactCandidate> _candidates = const [];
  int _selectedCandidate = 0;
  String? _editingUsername;
  String? _importError;
  bool _importBusy = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_importBusy || widget.controller.contactBusy) return;
    setState(() {
      _importBusy = true;
      _importError = null;
    });
    try {
      final candidates = await widget.importer.pickContacts();
      if (!mounted || candidates.isEmpty) return;
      setState(() {
        _candidates = candidates;
        _selectedCandidate = 0;
        _editingUsername = null;
        _username.clear();
        _displayName.text = candidates.first.displayName;
      });
    } on ContactImportException catch (error) {
      if (mounted) setState(() => _importError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _importError = 'The selected contact could not be read.',
        );
      }
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  void _startManual() {
    setState(() {
      _candidates = const [];
      _editingUsername = null;
      _importError = null;
      _username.clear();
      _displayName.clear();
    });
  }

  void _edit(LocalContactAlias contact) {
    setState(() {
      _candidates = const [];
      _editingUsername = contact.username;
      _importError = null;
      _username.text = contact.username;
      _displayName.text = contact.displayName;
    });
  }

  void _selectCandidate(int index) {
    setState(() {
      _selectedCandidate = index;
      _displayName.text = _candidates[index].displayName;
      _username.clear();
    });
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final editingUsername = _editingUsername;
    final saved = editingUsername == null
        ? await widget.controller.bindContact(
            username: _username.text,
            displayName: _displayName.text,
          )
        : await widget.controller.renameContact(
            editingUsername,
            _displayName.text,
          );
    if (!mounted || !saved) return;
    setState(() {
      _editingUsername = null;
      _username.clear();
      if (_candidates.isEmpty) {
        _displayName.clear();
        return;
      }
      final remaining = _candidates.toList()..removeAt(_selectedCandidate);
      _candidates = List.unmodifiable(remaining);
      if (remaining.isEmpty) {
        _selectedCandidate = 0;
        _displayName.clear();
      } else {
        _selectedCandidate = _selectedCandidate.clamp(0, remaining.length - 1);
        _displayName.text = remaining[_selectedCandidate].displayName;
      }
    });
  }

  Future<void> _remove(LocalContactAlias contact) async {
    await widget.controller.removeContact(contact.username);
    if (!mounted) return;
    if (_editingUsername == contact.username) _startManual();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final contacts = widget.controller.contacts;
        final busy = _importBusy || widget.controller.contactBusy;
        return AlertDialog(
          title: const Text('Contacts'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: const Key('contact-privacy-boundary'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Only the selected display name and the WampApp username you enter are saved in this encrypted device vault. Phone numbers, email addresses, contact IDs, and address-book files are never uploaded or retained.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('contact-import'),
                        onPressed: busy ? null : _import,
                        icon: _importBusy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.contact_page_outlined),
                        label: Text(widget.importer.actionLabel),
                      ),
                      OutlinedButton.icon(
                        key: const Key('contact-add-manual'),
                        onPressed: busy ? null : _startManual,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Add by username'),
                      ),
                    ],
                  ),
                  if (_candidates.length > 1) ...[
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Imported display name',
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          key: const Key('contact-imported-name'),
                          isExpanded: true,
                          value: _selectedCandidate,
                          items: [
                            for (
                              var index = 0;
                              index < _candidates.length;
                              index += 1
                            )
                              DropdownMenuItem(
                                value: index,
                                child: Text(_candidates[index].displayName),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (index) {
                                  if (index != null) _selectCandidate(index);
                                },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('contact-display-name'),
                    controller: _displayName,
                    enabled: !busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Name on this device',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('contact-username'),
                    controller: _username,
                    enabled: !busy && _editingUsername == null,
                    maxLength: 64,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(
                      labelText: 'WampApp username',
                      helperText: _editingUsername == null
                          ? 'Verified with the connected server before saving.'
                          : 'The canonical account cannot be changed while renaming.',
                      prefixIcon: const Icon(Icons.alternate_email),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('contact-save'),
                      onPressed: busy ? null : _save,
                      icon: widget.controller.contactBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: Text(
                        _editingUsername == null
                            ? 'Verify and save'
                            : 'Save local name',
                      ),
                    ),
                  ),
                  if (_importError case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      key: const Key('contact-import-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (widget.controller.contactError case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      key: const Key('contact-save-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    contacts.isEmpty
                        ? 'No contacts saved on this device.'
                        : '${contacts.length} local contact${contacts.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (contacts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          return ListTile(
                            key: ValueKey('contact-${contact.username}'),
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Text(
                                contact.displayName.characters.first
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(contact.displayName),
                            subtitle: Text('@${contact.username}'),
                            onTap: () =>
                                Navigator.of(context).pop(contact.username),
                            trailing: Wrap(
                              spacing: 0,
                              children: [
                                IconButton(
                                  key: ValueKey(
                                    'contact-edit-${contact.username}',
                                  ),
                                  tooltip: 'Rename local contact',
                                  onPressed: busy ? null : () => _edit(contact),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  key: ValueKey(
                                    'contact-remove-${contact.username}',
                                  ),
                                  tooltip: 'Remove local contact',
                                  onPressed: busy
                                      ? null
                                      : () => _remove(contact),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('contact-close'),
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

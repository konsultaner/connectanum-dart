import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_contact_alias.dart';

void main() {
  test('normalizes usernames, names, and timestamps', () {
    final contact = LocalContactAlias(
      username: '  Alice.Example  ',
      displayName: '  Alice  ',
      importedAt: DateTime.parse('2026-08-26T08:00:00+02:00'),
    );

    expect(contact.username, 'alice.example');
    expect(contact.displayName, 'Alice');
    expect(contact.importedAt, DateTime.utc(2026, 8, 26, 6));
    expect(
      LocalContactAlias.fromJson(contact.toJson()).toJson(),
      contact.toJson(),
    );
  });

  test('rejects invalid usernames and non-visible names', () {
    expect(
      () => LocalContactAlias(
        username: 'ab',
        displayName: 'Alice',
        importedAt: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalContactAlias(
        username: 'alice',
        displayName: 'Alice\nInjected',
        importedAt: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalContactAlias(
        username: 'alice',
        displayName: List.filled(81, 'a').join(),
        importedAt: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
  });

  test('contact lists are bounded and unique by normalized username', () {
    LocalContactAlias contact(String username) => LocalContactAlias(
      username: username,
      displayName: username,
      importedAt: DateTime.utc(2026),
    );

    expect(
      () =>
          LocalContactAlias.validateList([contact('alice'), contact('ALICE')]),
      throwsFormatException,
    );
    expect(
      () => LocalContactAlias.validateList(
        List.generate(
          LocalContactAlias.maxContacts + 1,
          (index) => contact('contact-$index'),
        ),
      ),
      throwsFormatException,
    );
  });
}

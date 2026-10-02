@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/l10n/generated/app_localizations.dart';

import 'support/localization_accessors.dart';

const _interpolated =
    <String, (String, String Function(AppLocalizations, String))>{
      'stickerLabel': ('label', _stickerLabel),
      'mcpAccount': ('username', _mcpAccount),
      'mcpRealm': ('realm', _mcpRealm),
      'visibleFields': ('fields', _visibleFields),
      'copyLabel': ('label', _copyLabel),
      'chatAppearance': ('appearance', _chatAppearance),
      'recordingDuration': ('duration', _recordingDuration),
      'encryptionIdentityFor': ('username', _encryptionIdentityFor),
      'chatAppearanceSaved': ('appearance', _chatAppearanceSaved),
      'disappearingMessagesEnabled': (
        'retention',
        _disappearingMessagesEnabled,
      ),
    };

String _stickerLabel(AppLocalizations l, String v) => l.stickerLabel(v);
String _mcpAccount(AppLocalizations l, String v) => l.mcpAccount(v);
String _mcpRealm(AppLocalizations l, String v) => l.mcpRealm(v);
String _visibleFields(AppLocalizations l, String v) => l.visibleFields(v);
String _copyLabel(AppLocalizations l, String v) => l.copyLabel(v);
String _chatAppearance(AppLocalizations l, String v) => l.chatAppearance(v);
String _recordingDuration(AppLocalizations l, String v) =>
    l.recordingDuration(v);
String _encryptionIdentityFor(AppLocalizations l, String v) =>
    l.encryptionIdentityFor(v);
String _chatAppearanceSaved(AppLocalizations l, String v) =>
    l.chatAppearanceSaved(v);
String _disappearingMessagesEnabled(AppLocalizations l, String v) =>
    l.disappearingMessagesEnabled(v);

final _plurals = <String, String Function(AppLocalizations, int)>{
  'localContacts': (l, count) => l.localContacts(count),
  'localSearchResults': (l, count) => l.localSearchResults(count),
};

// The authored ARB files, not generated Dart text or Intl.pluralLogic, are the
// expected-value oracle. Only the exact-number ICU forms used by this app are
// accepted; new forms must get explicit contract tests rather than pass silently.
String _pluralExpected(String template, int count) {
  final match = RegExp(
    r'^\{count, plural, (?:=0\{([^{}]*)\} )?=1\{([^{}]*)\} other\{(.*)\}\}$',
  ).firstMatch(template);
  expect(match, isNotNull, reason: 'Unsupported authored plural: $template');
  final branch = count == 0 && match!.group(1) != null
      ? match.group(1)!
      : count == 1
      ? match!.group(2)!
      : match!.group(3)!;
  return branch.replaceAll('{count}', count.toString());
}

void main() {
  final documents = <String, Map<String, Object?>>{};
  for (final file in Directory('lib/l10n').listSync().whereType<File>()) {
    final match = RegExp(r'app_([a-z]+)\.arb$').firstMatch(file.path);
    if (match == null) continue;
    documents[match.group(1)!] = (jsonDecode(file.readAsStringSync()) as Map)
        .cast<String, Object?>();
  }

  test('supported locales and all authored message keys are covered', () {
    expect(
      documents.keys,
      unorderedEquals(['de', 'en', 'es', 'fr', 'it', 'pt']),
    );
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode),
      unorderedEquals(documents.keys),
    );
    final testedKeys = <String>[
      ...plainLocalizationAccessors.keys,
      ..._interpolated.keys,
      ..._plurals.keys,
    ];
    expect(testedKeys.toSet(), hasLength(testedKeys.length));
    for (final entry in documents.entries) {
      expect(entry.value['@@locale'], entry.key);
      final authoredKeys = entry.value.keys.where(
        (key) => !key.startsWith('@'),
      );
      expect(authoredKeys, unorderedEquals(testedKeys), reason: entry.key);
      for (final key in authoredKeys) {
        expect(entry.value[key], isA<String>(), reason: '${entry.key}.$key');
      }
    }
  });

  test('exact-number oracle does not use a locale plural category', () {
    const template = '{count, plural, =1{one} other{{count} items}}';
    expect(_pluralExpected(template, 0), '0 items');
    expect(_pluralExpected(template, 1), 'one');
    expect(_pluralExpected(template, 21), '21 items');
    expect(
      _pluralExpected(
        '{count, plural, =0{none} =1{one} other{{count} items}}',
        0,
      ),
      'none',
    );
  });

  for (final entry in documents.entries) {
    final language = entry.key;
    final authored = entry.value;
    test('$language getters match every authored label exactly', () async {
      final l = await AppLocalizations.delegate.load(Locale(language));
      expect(l.localeName, language);
      for (final getter in plainLocalizationAccessors.entries) {
        expect(
          getter.value(l),
          authored[getter.key],
          reason: '$language.${getter.key}',
        );
      }
    });
    test(
      '$language parameters preserve user text without reinterpretation',
      () async {
        final l = await AppLocalizations.delegate.load(Locale(language));
        for (final method in _interpolated.entries) {
          final (parameter, read) = method.value;
          final template = authored[method.key]! as String;
          expect(template, contains('{$parameter}'));
          for (final input in [
            '',
            '@alice',
            'a\n{username}\u00e9\u{1f642}\u200b\u00ad',
          ]) {
            expect(
              read(l, input),
              template.replaceAll('{$parameter}', input),
              reason: '$language.${method.key}: $input',
            );
          }
        }
      },
    );
    for (final plural in _plurals.entries) {
      for (final count in [0, 1, 2, 21, 101]) {
        test(
          '$language ${plural.key} count=$count matches exact ICU branches',
          () async {
            final l = await AppLocalizations.delegate.load(Locale(language));
            expect(
              plural.value(l, count),
              _pluralExpected(authored[plural.key]! as String, count),
            );
          },
        );
      }
    }
    test('$language regional variants select the authored language', () async {
      final regional = Locale.fromSubtags(
        languageCode: language,
        scriptCode: 'Latn',
        countryCode: 'ZZ',
      );
      expect(AppLocalizations.delegate.isSupported(regional), isTrue);
      final l = await AppLocalizations.delegate.load(regional);
      expect(l.localeName, language);
      expect(l.settings, authored['settings']);
    });
  }

  test(
    'unsupported locales fail explicitly and stable delegate does not reload',
    () {
      expect(
        AppLocalizations.delegate.isSupported(const Locale('ja')),
        isFalse,
      );
      expect(
        () => lookupAppLocalizations(const Locale('ja')),
        throwsA(isA<FlutterError>()),
      );
      expect(
        AppLocalizations.delegate.shouldReload(AppLocalizations.delegate),
        isFalse,
      );
    },
  );

  testWidgets('switching locales updates the mounted localized view', (
    tester,
  ) async {
    for (final language in ['en', 'de', 'fr', 'es', 'it', 'pt', 'en']) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              final l = AppLocalizations.of(context);
              return Text('${l.localeName}: ${l.settings}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('$language: ${documents[language]!['settings']}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

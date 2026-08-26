import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/contact_importer_contract.dart';
import 'package:wamp_app/src/infrastructure/vcard_contact_importer.dart';

void main() {
  test('vCard parser extracts names and never decodes unrelated PII', () {
    final bytes = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          'BEGIN:VCARD\r\n'
          'VERSION:4.0\r\n'
          'FN:Alice Example\r\n'
          'EMAIL:alice@example.invalid\r\n'
          'TEL:',
        ),
      )
      ..add([0xff, 0xfe])
      ..add(utf8.encode('\r\nADR:private address\r\nEND:VCARD\r\n'));

    final candidates = VCardContactParser.parse(bytes.takeBytes());

    expect(candidates.map((candidate) => candidate.displayName), [
      'Alice Example',
    ]);
  });

  test('vCard parser handles folded, escaped, and structured names', () {
    final candidates = VCardContactParser.parse(
      Uint8List.fromList(
        utf8.encode(
          'BEGIN:VCARD\n'
          'item1.FN:Alice\\, Very Long\n'
          ' Name\n'
          'END:VCARD\n'
          'BEGIN:VCARD\n'
          'N:Doe;Jane;Q.;Dr.;III\n'
          'END:VCARD\n',
        ),
      ),
    );

    expect(candidates.map((candidate) => candidate.displayName), [
      'Alice, Very LongName',
      'Dr. Jane Q. Doe III',
    ]);
  });

  test('vCard parser handles UTF-8 quoted-printable names and soft wraps', () {
    final candidates = VCardContactParser.parse(
      Uint8List.fromList(
        ascii.encode(
          'BEGIN:VCARD\r\n'
          'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:'
          'J=C3=B6rg=20=\r\nM=C3=BCller\r\n'
          'END:VCARD\r\n',
        ),
      ),
    );

    expect(candidates.single.displayName, 'Jörg Müller');
  });

  test('vCard parser rejects oversized files and selected name lines', () {
    expect(
      () => VCardContactParser.parse(
        Uint8List(VCardContactImporter.maximumFileBytes + 1),
      ),
      throwsA(isA<ContactImportException>()),
    );
    expect(
      () => VCardContactParser.parse(
        Uint8List.fromList(
          utf8.encode(
            'BEGIN:VCARD\nFN:${List.filled(5000, 'a').join()}\nEND:VCARD\n',
          ),
        ),
      ),
      throwsA(isA<ContactImportException>()),
    );
  });

  test('vCard parser ignores empty, incomplete, and unrelated input', () {
    expect(VCardContactParser.parse(Uint8List(0)), isEmpty);
    expect(
      VCardContactParser.parse(
        Uint8List.fromList(
          utf8.encode(
            'not-a-vcard:value\n'
            'END:VCARD\n'
            'BEGIN:VCARD\n'
            'TEL:+49 123 456\n',
          ),
        ),
      ),
      isEmpty,
    );
  });

  test('vCard parser rejects more than 500 unique contacts', () {
    final source = StringBuffer();
    for (var index = 0; index <= 500; index += 1) {
      source
        ..writeln('BEGIN:VCARD')
        ..writeln('FN:Contact $index')
        ..writeln('END:VCARD');
    }

    expect(
      () => VCardContactParser.parse(
        Uint8List.fromList(utf8.encode(source.toString())),
      ),
      throwsA(isA<ContactImportException>()),
    );
  });

  test('vCard importer wipes selected bytes after extracting names', () async {
    final source = Uint8List.fromList(
      utf8.encode('BEGIN:VCARD\nFN:Alice Example\nEND:VCARD\n'),
    );
    final importer = VCardContactImporter(
      picker: () async => XFile.fromData(source, name: 'contacts.vcf'),
    );

    final contacts = await importer.pickContacts();

    expect(contacts.single.displayName, 'Alice Example');
    expect(source, everyElement(0));
  });

  test('vCard importer treats picker cancellation as no contacts', () async {
    final importer = VCardContactImporter(picker: () async => null);

    expect(await importer.pickContacts(), isEmpty);
  });
}

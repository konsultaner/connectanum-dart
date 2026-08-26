import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'contact_importer_contract.dart';

typedef ContactFilePicker = Future<XFile?> Function();

final class VCardContactImporter implements ContactImporter {
  const VCardContactImporter({this.picker});

  static const maximumFileBytes = 4 * 1024 * 1024;
  final ContactFilePicker? picker;

  @override
  String get actionLabel => 'Import vCard';

  @override
  Future<List<ImportedContactCandidate>> pickContacts() async {
    final file = await (picker ?? _pickVCard)();
    if (file == null) return const [];
    Uint8List? bytes;
    try {
      if (await file.length() > maximumFileBytes) {
        throw const ContactImportException('The vCard file is too large.');
      }
      bytes = await file.readAsBytes();
      return VCardContactParser.parse(bytes);
    } catch (error) {
      if (error is ContactImportException) rethrow;
      throw const ContactImportException('The vCard file could not be read.');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  static Future<XFile?> _pickVCard() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'vCard contacts',
        extensions: ['vcf', 'vcard'],
        mimeTypes: ['text/vcard', 'text/x-vcard'],
        uniformTypeIdentifiers: ['public.vcard'],
      ),
    ],
  );
}

abstract final class VCardContactParser {
  static const _maximumSelectedLineBytes = 4096;

  static List<ImportedContactCandidate> parse(Uint8List bytes) {
    if (bytes.length > VCardContactImporter.maximumFileBytes) {
      throw const ContactImportException('The vCard file is too large.');
    }
    final selectedLines = _selectedLines(bytes);
    final candidates = <ImportedContactCandidate>[];
    final seenNames = <String>{};
    var inCard = false;
    String? formattedName;
    String? structuredName;

    void finishCard() {
      if (!inCard) return;
      final name = formattedName ?? _formatStructuredName(structuredName);
      if (name != null) {
        final candidate = ImportedContactCandidate(displayName: name);
        if (seenNames.add(candidate.displayName.toLowerCase())) {
          candidates.add(candidate);
        }
      }
      inCard = false;
      formattedName = null;
      structuredName = null;
    }

    for (final line in selectedLines) {
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VCARD') {
        finishCard();
        inCard = true;
        continue;
      }
      if (upper == 'END:VCARD') {
        finishCard();
        continue;
      }
      if (!inCard) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final metadata = line.substring(0, separator);
      final property = metadata.split(';').first.split('.').last.toUpperCase();
      final rawValue = line.substring(separator + 1);
      final decoded = _decodePropertyValue(metadata, rawValue);
      if (property == 'FN') {
        formattedName = _unescapeText(decoded);
      } else if (property == 'N' && structuredName == null) {
        structuredName = decoded;
      }
    }
    finishCard();
    if (candidates.length > 500) {
      throw const ContactImportException('The vCard has too many contacts.');
    }
    return List<ImportedContactCandidate>.unmodifiable(candidates);
  }

  static List<String> _selectedLines(Uint8List bytes) {
    final result = <String>[];
    List<int>? current;
    var start = 0;
    while (start <= bytes.length) {
      var end = start;
      while (end < bytes.length && bytes[end] != 10 && bytes[end] != 13) {
        end += 1;
      }
      var next = end;
      if (next < bytes.length && bytes[next] == 13) next += 1;
      if (next < bytes.length && bytes[next] == 10) next += 1;
      final folded = start < end && (bytes[start] == 32 || bytes[start] == 9);
      final quotedPrintableContinuation = current?.lastOrNull == 61;
      if ((folded || quotedPrintableContinuation) && current != null) {
        if (quotedPrintableContinuation) current.removeLast();
        final contentStart = folded ? start + 1 : start;
        current.addAll(Uint8List.sublistView(bytes, contentStart, end));
        _checkSelectedLineLength(current.length);
      } else {
        if (current != null) result.add(_decodeSelectedLine(current));
        current = _isSelectedProperty(bytes, start, end)
            ? Uint8List.sublistView(bytes, start, end).toList(growable: true)
            : null;
        if (current != null) _checkSelectedLineLength(current.length);
      }
      if (end >= bytes.length) break;
      start = next;
    }
    if (current != null) result.add(_decodeSelectedLine(current));
    return result;
  }

  static bool _isSelectedProperty(Uint8List bytes, int start, int end) {
    var boundary = start;
    while (boundary < end && bytes[boundary] != 58 && bytes[boundary] != 59) {
      boundary += 1;
    }
    if (boundary == end) return false;
    var propertyStart = start;
    for (var index = start; index < boundary; index += 1) {
      if (bytes[index] == 46) propertyStart = index + 1;
    }
    final property = ascii.decode(
      Uint8List.sublistView(bytes, propertyStart, boundary),
      allowInvalid: true,
    );
    return switch (property.toUpperCase()) {
      'BEGIN' || 'END' || 'FN' || 'N' => true,
      _ => false,
    };
  }

  static String _decodeSelectedLine(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false).trim();
    } on FormatException {
      throw const ContactImportException('The vCard text is not valid UTF-8.');
    }
  }

  static String _decodePropertyValue(String metadata, String value) {
    if (!metadata.toUpperCase().contains('ENCODING=QUOTED-PRINTABLE')) {
      return value;
    }
    final decoded = <int>[];
    for (var index = 0; index < value.length; index += 1) {
      final character = value.codeUnitAt(index);
      if (character == 61 && index + 2 < value.length) {
        final byte = int.tryParse(
          value.substring(index + 1, index + 3),
          radix: 16,
        );
        if (byte == null) {
          throw const ContactImportException(
            'The vCard name encoding is invalid.',
          );
        }
        decoded.add(byte);
        index += 2;
      } else {
        decoded.add(character);
      }
    }
    try {
      return utf8.decode(decoded, allowMalformed: false);
    } on FormatException {
      throw const ContactImportException('The vCard name encoding is invalid.');
    }
  }

  static String? _formatStructuredName(String? value) {
    if (value == null) return null;
    final fields = _splitEscaped(value, ';');
    while (fields.length < 5) {
      fields.add('');
    }
    final ordered = [fields[3], fields[1], fields[2], fields[0], fields[4]]
        .map(_unescapeText)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    final name = ordered.join(' ');
    return name.isEmpty ? null : name;
  }

  static List<String> _splitEscaped(String value, String separator) {
    final result = <String>[];
    final current = StringBuffer();
    var escaped = false;
    for (final codePoint in value.runes) {
      final character = String.fromCharCode(codePoint);
      if (!escaped && character == separator) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(character);
      }
      if (character == r'\' && !escaped) {
        escaped = true;
      } else {
        escaped = false;
      }
    }
    result.add(current.toString());
    return result;
  }

  static String _unescapeText(String value) {
    final result = StringBuffer();
    var escaped = false;
    for (final codePoint in value.runes) {
      final character = String.fromCharCode(codePoint);
      if (escaped) {
        result.write(switch (character) {
          'n' || 'N' => ' ',
          _ => character,
        });
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else {
        result.write(character);
      }
    }
    if (escaped) result.write(r'\');
    return result.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static void _checkSelectedLineLength(int length) {
    if (length > _maximumSelectedLineBytes) {
      throw const ContactImportException('A vCard name is too large.');
    }
  }
}

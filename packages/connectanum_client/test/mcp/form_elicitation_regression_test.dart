import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP form request validation', () {
    for (final field in ['inputRequestId', 'message']) {
      test('rejects an empty $field', () {
        expect(
          () => McpFormElicitationRequest(
            inputRequestId: field == 'inputRequestId' ? '' : 'input-1',
            message: field == 'message' ? '' : 'Choose a value',
            requestedSchema: const {'type': 'object', 'properties': {}},
          ),
          throwsArgumentError,
        );
      });
    }

    final invalidRoots = <McpJsonMap>[
      {},
      {'type': 'array', 'properties': {}},
      {'type': 'object'},
      {'type': 'object', 'properties': []},
      {
        'type': 'object',
        'properties': {
          1: {'type': 'string'},
        },
      },
      {
        'type': 'object',
        'properties': {
          '': {'type': 'string'},
        },
      },
      {'type': 'object', 'properties': {}, 'required': 'value'},
      {
        'type': 'object',
        'properties': {},
        'required': [1],
      },
      {
        'type': 'object',
        'properties': {},
        'required': [''],
      },
      {
        'type': 'object',
        'properties': {},
        'required': ['unknown'],
      },
    ];
    for (var i = 0; i < invalidRoots.length; i++) {
      test('rejects malformed root schema $i', () {
        expect(
          () => McpFormElicitationRequest(
            inputRequestId: 'input-1',
            message: 'Choose a value',
            requestedSchema: invalidRoots[i],
          ),
          throwsFormatException,
        );
      });
    }

    final invalidProperties = <Object?>[
      null,
      false,
      [],
      {1: 'string'},
      {},
      {'type': 'object'},
      {'type': 'string', 'title': 1},
      {'type': 'string', 'description': false},
      {'type': 'string', 'minLength': 2, 'maxLength': 1},
      {'type': 'string', 'format': 'unsupported'},
      {'type': 'string', 'default': 0},
      {'type': 'boolean', 'default': 'true'},
      {'type': 'number', 'minimum': 2, 'maximum': 1},
      {'type': 'integer', 'minimum': 2, 'maximum': 1},
      {'type': 'array', 'minItems': 2, 'maxItems': 1},
      {'type': 'array', 'items': null},
      {
        'type': 'array',
        'items': {
          'type': 'number',
          'enum': ['a'],
        },
      },
      {
        'type': 'array',
        'items': {'type': 'string'},
      },
      {
        'type': 'array',
        'items': {'anyOf': 'a'},
      },
      {
        'type': 'string',
        'enum': ['a'],
        'oneOf': [],
      },
      {'type': 'string', 'enum': 'a'},
      {'type': 'string', 'enum': []},
      {
        'type': 'string',
        'enum': ['a', 1],
      },
      {
        'type': 'string',
        'enum': ['a'],
        'enumNames': 'A',
      },
      {
        'type': 'string',
        'enum': ['a'],
        'enumNames': [],
      },
      {
        'type': 'string',
        'enum': ['a'],
        'enumNames': [1],
      },
      {
        'type': 'string',
        'enum': ['a'],
        'enumNames': ['A', 'B'],
      },
      {'type': 'string', 'oneOf': 'a'},
    ];
    for (final field in ['minLength', 'maxLength', 'minItems', 'maxItems']) {
      for (final value in [-1, 0.5, '1', true]) {
        invalidProperties.add({
          'type': field.endsWith('Length') ? 'string' : 'array',
          field: value,
          if (field.endsWith('Items'))
            'items': {
              'type': 'string',
              'enum': ['a'],
            },
        });
      }
    }
    for (final type in ['number', 'integer']) {
      for (final field in ['minimum', 'maximum', 'default']) {
        for (final value in [
          '1',
          true,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          invalidProperties.add({'type': type, field: value});
        }
      }
    }
    for (final choices in <Object?>[
      [],
      [false],
      [{}],
      [
        {'const': 'a'},
      ],
      [
        {'title': 'A'},
      ],
      [
        {'const': 1, 'title': 'A'},
      ],
      [
        {'const': 'a', 'title': 1},
      ],
    ]) {
      invalidProperties.add({'type': 'string', 'oneOf': choices});
      invalidProperties.add({
        'type': 'array',
        'items': {'anyOf': choices},
      });
    }
    for (final choices in [
      <Object?>[],
      <Object?>['a', false],
    ]) {
      invalidProperties.add({
        'type': 'array',
        'items': {'type': 'string', 'enum': choices},
      });
    }
    for (final value in <Object?>[
      'a',
      ['a', 1],
    ]) {
      invalidProperties.add({
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': ['a'],
        },
        'default': value,
      });
    }
    for (var i = 0; i < invalidProperties.length; i++) {
      test('rejects malformed property schema $i', () {
        expect(() => _request(invalidProperties[i]), throwsFormatException);
      });
    }

    for (final mode in [null, 'form']) {
      test('decodes supported form mode $mode without changing the schema', () {
        final request = McpFormElicitationRequest.fromJson('input-2', {
          'method': 'elicitation/create',
          'params': {
            'mode': ?mode,
            'message': 'Choose a value',
            'requestedSchema': {'type': 'object', 'properties': {}},
          },
        });
        expect(request.inputRequestId, 'input-2');
        expect(request.message, 'Choose a value');
        expect(request.requestedSchema, {'type': 'object', 'properties': {}});
        expect(McpFormElicitationResponse.accept({}).toJsonFor(request), {
          'action': 'accept',
          'content': {},
        });
      });
    }
    for (final mode in ['url', 'FORM', 1, false]) {
      test('rejects unsupported mode $mode before interpreting a form', () {
        expect(
          () => McpFormElicitationRequest.fromJson('input', {
            'method': 'elicitation/create',
            'params': {'mode': mode},
          }),
          throwsA(isA<McpStreamableProtocolException>()),
        );
      });
    }
    for (final method in [null, 'tools/call', 1]) {
      test('rejects unsupported input method $method', () {
        expect(
          () => McpFormElicitationRequest.fromJson('input', {'method': method}),
          throwsA(isA<McpStreamableProtocolException>()),
        );
      });
    }
    for (final message in [null, '', false, 1]) {
      test('rejects malformed wire message $message', () {
        expect(
          () => McpFormElicitationRequest.fromJson('input', {
            'method': 'elicitation/create',
            'params': {'message': message},
          }),
          throwsFormatException,
        );
      });
    }
  });

  group('MCP form response validation', () {
    test(
      'required, optional and undeclared values are handled independently',
      () {
        final required = _request({'type': 'string'});
        expect(
          () => McpFormElicitationResponse.accept({}).toJsonFor(required),
          throwsFormatException,
        );
        final optional = _request({
          'type': 'string',
          'default': 'fallback',
        }, requiredField: false);
        expect(McpFormElicitationResponse.accept({}).toJsonFor(optional), {
          'action': 'accept',
          'content': {},
        });
        expect(
          () => McpFormElicitationResponse.accept({
            'other': 'value',
          }).toJsonFor(optional),
          throwsFormatException,
        );
        expect(const McpFormElicitationResponse.decline().toJsonFor(required), {
          'action': 'decline',
        });
        expect(const McpFormElicitationResponse.cancel().toJsonFor(required), {
          'action': 'cancel',
        });
      },
    );

    final cases = <(String, McpJsonMap, List<Object?>, List<Object?>)>[
      (
        'Unicode length',
        {'type': 'string', 'minLength': 1, 'maxLength': 2},
        ['a', '\u{1f600}', '\u{1f600}a'],
        ['', 'abc', '\u{1f600}ab', null, 1],
      ),
      (
        'empty string',
        {'type': 'string', 'minLength': 0, 'maxLength': 0},
        [''],
        ['a'],
      ),
      (
        'email',
        {'type': 'string', 'format': 'email'},
        ['test@example.org'],
        ['user', 'a@b', 'a b@example.org'],
      ),
      (
        'URI',
        {'type': 'string', 'format': 'uri'},
        ['https://example.org', 'urn:example:test'],
        ['relative', '//example.org', 'http://[invalid'],
      ),
      (
        'enum',
        {
          'type': 'string',
          'enum': ['', 'a'],
          'enumNames': ['Empty', 'A'],
        },
        ['', 'a'],
        ['A', 'other'],
      ),
      (
        'titled enum',
        {
          'type': 'string',
          'oneOf': [
            {'const': 'a', 'title': 'A'},
          ],
        },
        ['a'],
        ['A', ''],
      ),
      (
        'number',
        {'type': 'number', 'minimum': -1, 'maximum': 1, 'default': 0},
        [-1, 0, 0.5, 1],
        [
          -1.01,
          1.01,
          '1',
          false,
          null,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ],
      ),
      (
        'integer',
        {'type': 'integer', 'minimum': -1, 'maximum': 1, 'default': 0},
        [-1, 0, 1, 1.0],
        [-2, 2, 0.5, '1', false, null, double.nan, double.infinity],
      ),
      (
        'equal numeric bounds',
        {'type': 'number', 'minimum': 0, 'maximum': 0},
        [0],
        [-1, 1],
      ),
      (
        'boolean',
        {'type': 'boolean', 'default': false},
        [true, false],
        ['true', 1, null],
      ),
      (
        'array',
        {
          'type': 'array',
          'minItems': 1,
          'maxItems': 2,
          'items': {
            'type': 'string',
            'enum': ['a', 'b'],
          },
        },
        [
          ['a'],
          ['a', 'b'],
        ],
        [
          [],
          ['a', 'b', 'a'],
          ['a', 'c'],
          ['a', 1],
          'a',
          null,
        ],
      ),
      (
        'titled array',
        {
          'type': 'array',
          'items': {
            'anyOf': [
              {'const': 'a', 'title': 'A'},
            ],
          },
          'default': [],
        },
        [
          [],
          ['a'],
        ],
        [
          ['A'],
          [null],
        ],
      ),
      (
        'empty array',
        {
          'type': 'array',
          'minItems': 0,
          'maxItems': 0,
          'items': {
            'type': 'string',
            'enum': ['a'],
          },
        },
        [[]],
        [
          ['a'],
        ],
      ),
    ];
    for (final (name, schema, accepted, rejected) in cases) {
      for (var i = 0; i < accepted.length; i++) {
        test('$name accepts boundary $i with exact output', () {
          expect(_respond(schema, accepted[i]), {
            'action': 'accept',
            'content': {'value': accepted[i]},
          });
        });
      }
      for (var i = 0; i < rejected.length; i++) {
        test('$name rejects invalid value $i', () {
          expect(() => _respond(schema, rejected[i]), throwsFormatException);
        });
      }
    }
  });

  group('MCP form calendar formats', () {
    final validDates = [
      '0000-01-01',
      '0001-01-01',
      '1900-02-28',
      '2000-02-29',
      '2024-02-29',
      '2026-04-30',
      '9999-12-31',
    ];
    final invalidDates = [
      '2023-02-29',
      '1900-02-29',
      '2026-02-30',
      '2026-04-31',
      '2026-00-01',
      '2026-13-01',
      '2026-01-00',
      '2026-01-32',
      '20260101',
      '2026-1-1',
      '2026-01-01\n',
      ' 2026-01-01',
      '2026-01-01T00:00:00Z',
    ];
    for (final value in validDates) {
      test('accepts calendar date $value unchanged', () {
        expect(_respond({'type': 'string', 'format': 'date'}, value), {
          'action': 'accept',
          'content': {'value': value},
        });
      });
    }
    for (final value in invalidDates) {
      test(
        'rejects invalid calendar date ${value.replaceAll('\n', r'\n')}',
        () {
          expect(
            () => _respond({'type': 'string', 'format': 'date'}, value),
            throwsFormatException,
          );
        },
      );
    }
    final validDateTimes = [
      '2024-02-29T00:00:00Z',
      '2024-02-29t23:59:59z',
      '0000-01-01T00:00:00+00:00',
      '9999-12-31T23:59:59-00:00',
      '2026-01-01T00:00:00.123456789Z',
      '2026-01-01T00:00:00+23:59',
      '2026-01-01T00:00:00-23:59',
      '1937-01-01T12:00:27.87+00:20',
      '1990-12-31T23:59:60Z',
      '1990-12-31T15:59:60-08:00',
      '1991-01-01T00:59:60+01:00',
      '2016-12-31T23:59:60.5Z',
      '2015-07-01T00:29:60+00:30',
      '2015-06-30T23:29:60-00:30',
    ];
    final invalidDateTimes = [
      '2026-01-01',
      '2026-01-01T00:00:00',
      '2026-01-01 00:00:00Z',
      '20260101T000000Z',
      '2026-01-01T00:00Z',
      '2026-01-01T00:00:00+0000',
      '2026-01-01T00:00:00+00',
      '2026-01-01T00:00:00,5Z',
      '2026-01-01T00:00:00.Z',
      '2026-01-01T24:00:00Z',
      '2026-01-01T00:60:00Z',
      '2026-01-01T00:00:61Z',
      '2026-01-01T00:00:00+24:00',
      '2026-01-01T00:00:00-00:60',
      '2026-02-30T00:00:00Z',
      '1900-02-29T00:00:00Z',
      '2026-01-00T00:00:00Z',
      '2026-13-01T00:00:00Z',
      '2026-01-01T00:00:00Z\n',
      '2026-01-01T00:00:00Z ',
      '1990-12-31T23:58:60Z',
      '1990-12-30T23:59:60Z',
      '1990-12-31T00:59:60+01:00',
      '1990-12-31T15:59:60+08:00',
    ];
    for (final value in validDateTimes) {
      test('accepts RFC3339 date-time $value unchanged', () {
        expect(_respond({'type': 'string', 'format': 'date-time'}, value), {
          'action': 'accept',
          'content': {'value': value},
        });
      });
    }
    for (final value in invalidDateTimes) {
      test(
        'rejects invalid RFC3339 date-time ${value.replaceAll('\n', r'\n')}',
        () {
          expect(
            () => _respond({'type': 'string', 'format': 'date-time'}, value),
            throwsFormatException,
          );
        },
      );
    }
  });
}

McpFormElicitationRequest _request(
  Object? property, {
  bool requiredField = true,
}) => McpFormElicitationRequest(
  inputRequestId: 'input-1',
  message: 'Choose a value',
  requestedSchema: {
    'type': 'object',
    'properties': {'value': property},
    if (requiredField) 'required': ['value'],
  },
);

McpJsonMap _respond(McpJsonMap schema, Object? value) =>
    McpFormElicitationResponse.accept({
      'value': value,
    }).toJsonFor(_request(schema));

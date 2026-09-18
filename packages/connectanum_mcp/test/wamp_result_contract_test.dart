import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart' show ResultPayload;
import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

import 'support/expect_valid.dart';

void main() {
  final call = McpWampToolCall(
    procedure: 'app.query',
    request: McpToolRequest(name: 'query', arguments: {}),
    payload: const McpWampCallPayload(),
  );

  test('empty tool arguments do not invent WAMP options or kwargs', () {
    final payload = McpWampCallPayload.fromToolArguments(call.request);
    expect(payload.arguments, isNull);
    expect(payload.argumentsKeywords, isNull);
    expect(payload.options, isNull);
  });

  for (final (label, payload, envelope)
      in <(String, ResultPayload, Map<String, Object?>?)>[
        ('absent', _result(), null),
        ('empty positional', _result(arguments: []), {'arguments': []}),
        ('empty keyword', _result(kwargs: {}), {'argumentsKeywords': {}}),
        ('empty details', _result(details: {}), {'details': {}}),
        (
          'positional only',
          _result(arguments: [null, 1]),
          {
            'arguments': [null, 1],
          },
        ),
        (
          'keyword only',
          _result(kwargs: {'ok': true}),
          {
            'argumentsKeywords': {'ok': true},
          },
        ),
      ]) {
    test('lossless result distinguishes $label from omitted fields', () {
      final result = mcpWampLosslessJsonResultMapper(call, payload);
      expect(result.isError, isFalse);
      expect(result.isInputRequired, isFalse);
      expect(result.hasStructuredContent, envelope != null);
      expect(result.structuredContent, envelope);
      expect(result.meta, isNull);
      expect(result.toJson(), {
        'content': [
          {
            'type': 'text',
            'text': envelope == null ? '' : jsonEncode(envelope),
          },
        ],
        'isError': false,
        if (envelope != null) 'structuredContent': envelope,
      });
    });
  }

  for (final value in <Object?>[null, true, false, 7, 'value', 1.25]) {
    test('JSON conversion retains scalar ${value.runtimeType}: $value', () {
      final converted = mcpWampJsonCompatible(value);
      expect(converted, value);
      expect(jsonEncode(converted), jsonEncode(value));
    });
  }
  for (final (value, expected) in [
    (double.infinity, 'Infinity'),
    (double.negativeInfinity, '-Infinity'),
    (double.nan, 'NaN'),
  ]) {
    test('JSON conversion makes $expected serializable', () {
      expect(mcpWampJsonCompatible(value), expected);
      expect(jsonEncode(mcpWampJsonCompatible(value)), jsonEncode(expected));
    });
  }
  test('JSON conversion recursively normalizes map keys and iterables', () {
    final value = <Object, Object?>{
      2: <Object?>[
        double.infinity,
        {3: double.nan},
      ].where((_) => true),
      false: const Duration(seconds: 1),
    };
    final converted = mcpWampJsonCompatible(value);
    expect(converted, {
      '2': [
        'Infinity',
        {'3': 'NaN'},
      ],
      'false': '0:00:01.000000',
    });
    expect(jsonDecode(jsonEncode(converted)), converted);
  });

  for (final resultType in <Object>['done', '', 1, false]) {
    test('rejects unknown WAMP MCP result type $resultType', () {
      expect(
        () => mcpWampLosslessJsonResultMapper(
          call,
          _result(
            details: {
              McpWampMrtrFields.resultType: resultType,
              McpWampMrtrFields.requestState: 'next',
            },
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  }
  for (final state in <Object>[1, false, [], {}]) {
    test('rejects non-string continuation state ${state.runtimeType}', () {
      expect(
        () => mcpWampLosslessJsonResultMapper(
          call,
          _result(
            details: {
              McpWampMrtrFields.resultType: 'input_required',
              McpWampMrtrFields.requestState: state,
            },
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  }
  for (final explicitRequests in [false, true]) {
    test(
      'state-only input request preserves absence, explicit=$explicitRequests',
      () {
        final result = expectValid(
          () => mcpWampLosslessJsonResultMapper(
            call,
            _result(
              details: {
                McpWampMrtrFields.resultType: 'input_required',
                McpWampMrtrFields.requestState: 'next',
                if (explicitRequests) McpWampMrtrFields.inputRequests: {},
              },
            ),
          ),
        );
        expect(result.isError, isFalse);
        expect(result.isInputRequired, isTrue);
        expect(result.hasStructuredContent, isFalse);
        expect(result.structuredContent, isNull);
        expect(result.meta, isNull);
        expect(result.toJson(clientCapabilities: {'elicitation': {}}), {
          'resultType': 'input_required',
          'inputRequests': {},
          'requestState': 'next',
        });
      },
    );
  }
  const form = <String, Object?>{
    'method': 'elicitation/create',
    'params': {
      'message': 'Confirm',
      'requestedSchema': {'type': 'object', 'properties': {}},
    },
  };
  test('input requests without continuation state remain input-required', () {
    final result = expectValid(
      () => mcpWampLosslessJsonResultMapper(
        call,
        _result(
          details: {
            McpWampMrtrFields.resultType: 'input_required',
            McpWampMrtrFields.inputRequests: {'confirm': form},
          },
        ),
      ),
    );
    expect(result.isInputRequired, isTrue);
    expect(result.isError, isFalse);
    expect(result.requestState, isNull);
    expect(
      result.toJson(
        clientCapabilities: {
          'elicitation': {'form': {}},
        },
      ),
      {
        'resultType': 'input_required',
        'inputRequests': {'confirm': form},
      },
    );
  });
  test('empty input request identifier is rejected', () {
    expect(
      () => McpToolResult.inputRequired(inputRequests: {'': form}),
      throwsArgumentError,
    );
  });
  for (final capabilities in <Map<String, Object?>>[
    {
      'elicitation': {'url': {}},
    },
    {
      'elicitation': {'form': true},
    },
    {
      'elicitation': {'form': null},
    },
  ]) {
    test('non-form elicitation capabilities fail closed: $capabilities', () {
      expect(
        () => McpToolResult.inputRequired(
          requestState: 'next',
        ).toJson(clientCapabilities: capabilities),
        throwsA(
          isA<McpException>().having(
            (error) => error.code,
            'code',
            McpErrorCodes.missingRequiredClientCapability,
          ),
        ),
      );
    });
  }
}

ResultPayload _result({
  List<dynamic>? arguments,
  Map<String, dynamic>? kwargs,
  Map<String, dynamic>? details,
}) => (
  callRequestId: 1,
  progress: false,
  pptScheme: null,
  pptSerializer: null,
  pptCipher: null,
  pptKeyId: null,
  customDetails: details,
  arguments: arguments,
  argumentsKeywords: kwargs,
);

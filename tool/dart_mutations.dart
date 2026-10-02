import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Generate single, syntactic mutations. Execution and scoring live in Python.
void main(List<String> paths) {
  if (paths.isEmpty) {
    stderr.writeln('Usage: dart tool/dart_mutations.dart <source.dart> ...');
    exitCode = 2;
    return;
  }
  final mutations = <Map<String, Object?>>[];
  for (final path in paths..sort()) {
    final source = File(path).readAsStringSync();
    final parsed = parseString(content: source, path: path);
    parsed.unit.accept(_Mutations(path, source, mutations));
  }
  stdout.writeln(jsonEncode(mutations));
}

class _Mutations extends RecursiveAstVisitor<void> {
  _Mutations(this.path, this.source, this.output);

  final String path;
  final String source;
  final List<Map<String, Object?>> output;

  void add(int offset, int length, String replacement, String operator) {
    final original = source.substring(offset, offset + length);
    if (original == replacement) return;
    output.add({
      'file': path,
      // Analyzer offsets are UTF-16; Python applies mutations to UTF-16 bytes.
      'offset': offset,
      'length': length,
      'line': '\n'.allMatches(source.substring(0, offset)).length + 1,
      'original': original,
      'replacement': replacement,
      'operator': operator,
    });
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    const replacements = {
      '==': ['!='],
      '!=': ['=='],
      '<': ['<=', '>'],
      '<=': ['<', '>'],
      '>': ['>=', '<'],
      '>=': ['>', '<'],
      '&&': ['||'],
      '||': ['&&'],
      '+': ['-'],
      '-': ['+'],
      '*': ['/'],
      '/': ['*'],
      '~/': ['*'],
      '%': ['*'],
      '&': ['|'],
      '|': ['&'],
      '^': ['|'],
      '<<': ['>>'],
      '>>': ['<<'],
    };
    for (final replacement
        in replacements[node.operator.lexeme] ?? <String>[]) {
      add(node.operator.offset, node.operator.length, replacement, 'binary');
    }
    if (node.operator.lexeme == '??') {
      add(
        node.offset,
        node.length,
        node.rightOperand.toSource(),
        'nullFallback',
      );
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    add(node.offset, node.length, '${!node.value}', 'boolean');
    super.visitBooleanLiteral(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.lexeme == '!') {
      add(node.operator.offset, node.operator.length, '', 'negation');
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    // Pattern bindings would become undefined after replacing an if-case.
    if (node.caseClause == null) {
      for (final value in ['true', 'false']) {
        add(node.expression.offset, node.expression.length, value, 'condition');
      }
    }
    super.visitIfStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    for (final value in ['true', 'false']) {
      add(node.condition.offset, node.condition.length, value, 'condition');
    }
    super.visitConditionalExpression(node);
  }
}

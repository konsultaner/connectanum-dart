import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from run_dart_mutations import apply_mutation


ROOT = Path(__file__).resolve().parents[1]


class DartMutationGeneratorTests(unittest.TestCase):
    def generate(self, source):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.dart'
            path.write_text(source)
            result = subprocess.run(['dart', 'tool/dart_mutations.dart', str(path)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=60)
        return result

    def test_ast_excludes_strings_comments_and_preserves_utf16_offsets(self):
        source = '// \U0001f512 false == &&\nString s = "false == &&";\nbool f(int a, int b) => a >= b && true;\n'
        result = self.generate(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = json.loads(result.stdout)
        self.assertEqual(len(mutations), 4)
        self.assertEqual({(m['original'], m['replacement']) for m in mutations},
                         {('>=', '>'), ('>=', '<'), ('&&', '||'), ('true', 'false')})
        for mutation in mutations:
            self.assertEqual(mutation['line'], 3)
            changed = apply_mutation(source, mutation)
            self.assertTrue(changed.startswith(source[:source.index('bool f')]))

    def test_control_flow_negation_and_null_fallback_are_independent_mutants(self):
        result = self.generate('bool f(bool? a, bool b) { if (!b) return a ?? b; return b ? true : false; }')
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = json.loads(result.stdout)
        self.assertEqual({m['operator'] for m in mutations},
                         {'condition', 'negation', 'nullFallback', 'boolean'})
        self.assertEqual(sum(m['operator'] == 'condition' for m in mutations), 4)
        self.assertEqual([m['replacement'] for m in mutations if m['operator'] == 'nullFallback'], ['b'])

    def test_if_case_bindings_are_not_replaced(self):
        result = self.generate('bool f(Object x) { if (x case int value) return value > 0; return false; }')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('condition', [m['operator'] for m in json.loads(result.stdout)])

    def test_invalid_source_fails_instead_of_yielding_partial_inventory(self):
        result = self.generate('bool f( => true;')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()

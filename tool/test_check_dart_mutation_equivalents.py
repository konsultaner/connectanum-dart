import contextlib
import copy
import hashlib
import io
from pathlib import Path
import tempfile
import unittest

import check_dart_mutation_equivalents as check
from run_dart_mutations import mutation_id


class MutationProofPreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = 'packages/core/lib/a.dart'
        p = self.root / self.source
        p.parent.mkdir(parents=True)
        p.write_text('bool enabled = true;\n')
        self.mutation = {'file': self.source, 'offset': 15, 'length': 4,
                         'line': 1, 'original': 'true', 'replacement': 'false',
                         'operator': 'boolean'}
        self.identifier = mutation_id(self.mutation)
        self.entry = {'sourceHash': hashlib.sha256(p.read_bytes()).hexdigest(),
                      'reason': 'The same unreachable predicate remains unchanged in this fixture.'}
        self.config = {'vm': {'sources': [self.source]}, 'web': {'sources': [self.source]}}
        self.proofs = {'vm': {self.identifier: self.entry}, 'web': {self.identifier: self.entry}}
        self.calls = []

    def generate(self, paths):
        self.calls.append(paths)
        return [self.mutation]

    def validate(self, proofs=None, config=None, generator=None):
        return check.validate_current_proofs(self.root, config or self.config,
            self.proofs if proofs is None else proofs, generator or self.generate)

    def test_validates_both_targets_with_one_complete_inventory(self):
        original = copy.deepcopy(self.proofs)
        self.assertEqual(self.validate(), {'targets': 2, 'proofs': 2, 'sources': 1})
        self.assertEqual(self.calls, [[self.source]])
        self.assertEqual(self.proofs, original)

    def test_source_edit_fails_before_generation_without_refreshing_proofs(self):
        (self.root / self.source).write_text('// shifted offsets\nbool enabled = true;\n')
        with self.assertRaisesRegex(ValueError, 'Stale equivalent'):
            self.validate()
        self.assertEqual(self.calls, [])

    def test_same_hash_cannot_hide_an_unknown_identifier(self):
        wrong = copy.deepcopy(self.proofs)
        wrong['vm'] = {'unknown': self.entry}
        with self.assertRaisesRegex(ValueError, 'Stale equivalent'):
            self.validate(proofs=wrong)

    def test_retired_target_records_are_not_reinterpreted_as_current_targets(self):
        records = {**self.proofs, 'retired': {'old': {'sourceHash': 'old'}}}
        self.assertEqual(self.validate(proofs=records)['proofs'], 2)

    def test_no_proofs_needs_no_generator(self):
        self.assertEqual(self.validate(proofs={}), {'targets': 0, 'proofs': 0, 'sources': 0})
        self.assertEqual(self.calls, [])

    def test_malformed_active_empty_records_are_rejected(self):
        for value in [[], None, '', 0]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.validate(proofs={'vm': value})

    def test_current_source_cannot_justify_a_mutation_outside_its_selected_scope(self):
        config = copy.deepcopy(self.config)
        config['vm']['mutationLineRanges'] = [[2, 3]]
        with self.assertRaisesRegex(ValueError, 'selected no generated'):
            self.validate(config=config)

    def test_another_source_hash_cannot_certify_this_mutation(self):
        other = 'packages/core/lib/b.dart'
        (self.root / other).write_text('different source')
        config = copy.deepcopy(self.config)
        config['vm']['sources'].append(other)
        records = copy.deepcopy(self.proofs)
        records['vm'][self.identifier]['sourceHash'] = hashlib.sha256((self.root / other).read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, 'Stale equivalent'):
            self.validate(proofs=records, config=config)

    def test_selected_proofs_retain_the_required_semantic_reason(self):
        records = copy.deepcopy(self.proofs)
        records['vm'][self.identifier]['reason'] = 'short'
        with self.assertRaisesRegex(ValueError, 'reasoning'):
            self.validate(proofs=records)

    def test_missing_sources_fail_closed(self):
        (self.root / self.source).unlink()
        with self.assertRaises(OSError):
            self.validate()

    def test_path_validation_is_shared_with_the_mutation_runner(self):
        with self.assertRaisesRegex(ValueError, 'Invalid production'):
            self.validate(config={'vm': {'sources': ['../secret.dart']}})

    def test_invalid_generated_inventory_is_rejected(self):
        for value in [{}, [None], ['mutant']]:
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'inventory'):
                self.validate(generator=lambda paths: value)

    def test_cli_preserves_duplicate_key_rejection(self):
        config = self.root / 'config.json'
        equivalents = self.root / 'proofs.json'
        config.write_text('{"vm": {}, "vm": {}}')
        equivalents.write_text('{}')
        with contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(check.main(['--config', str(config), '--equivalents', str(equivalents)]), 1)
        self.assertIn('duplicate', errors.getvalue().lower())


if __name__ == '__main__':
    unittest.main()

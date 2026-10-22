import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import benchmark_flatbuffers_dictionary as component


class ComponentTests(unittest.TestCase):
    def rows(self):
        result = []
        for shape in ('result', 'call'):
            for cycle in range(4):
                for index, variant in enumerate(('baseline', 'candidate', 'candidate', 'baseline')):
                    for round_index in range(-1, 4):
                        result.append({'cycle': cycle, 'order_index': index, 'round': round_index,
                            'info': {'shape': shape, 'variant': variant, 'pid': 100 + cycle * 4 + index,
                                     'payload_alias_verified': True, 'wire_sha256': ('a' if shape == 'result' else 'b') * 64},
                            'workload': {'shape': shape, 'variant': variant, 'count': 100000,
                                         'checksum': 3700000, 'control': round_index == -1,
                                         'elapsed_us': 100000 if variant == 'baseline' else 90000},
                            'allocated_bytes': 100 if round_index == -1 else 2000000,
                            'gc_count': 0, 'allocation_measurement': {'fixture': True}})
        return result

    def summarize(self, rows, findings=None):
        with mock.patch.object(component, 'allocation_evidence', return_value=(2000000, 0, findings or [])) as validate:
            result = component.summarize(rows)
        return result, validate

    def test_balanced_worker_pairs_keep_rounds_nested_and_validate_all_measured_windows(self):
        result, validate = self.summarize(self.rows())
        self.assertEqual(validate.call_count, 128)
        for shape in ('result', 'call'):
            self.assertEqual(len(result[shape]['worker_pairs']), 8)
            self.assertAlmostEqual(result[shape]['median_elapsed_ratio'], 0.9)
            self.assertEqual(result[shape]['worker_pairs'][0]['baseline']['managed_bytes_per_decode'], 20)

    def test_missing_replayed_wrong_variant_pid_alias_or_wire_fails_closed(self):
        changes = [lambda rows: rows.pop(), lambda rows: rows.append(copy.deepcopy(rows[0])),
                   lambda rows: rows[2]['info'].update(variant='candidate'),
                   lambda rows: rows[2]['info'].update(pid=999),
                   lambda rows: rows[2]['info'].update(payload_alias_verified=False),
                   lambda rows: rows[2]['info'].update(wire_sha256='c' * 64),
                   lambda rows: rows[2].update(round=True),
                   lambda rows: rows[2]['workload'].update(elapsed_us=True)]
        for change in changes:
            rows = self.rows()
            change(rows)
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.summarize(rows)

    def test_invalid_allocation_proof_cannot_be_a_component_success(self):
        with self.assertRaisesRegex(ValueError, 'incomplete evidence'):
            self.summarize(self.rows(), findings=['incomplete evidence'])

    def test_private_configs_resolve_every_package_and_bind_both_actual_core_variants(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'with spaces'
            output = root / 'output'
            output.mkdir(parents=True)
            for name in component.TARGETS:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('candidate source\n')
            config = root / '.dart_tool/package_config.json'
            config.parent.mkdir()
            runner = root / 'test-dependency/bin/test.dart'
            runner.parent.mkdir(parents=True)
            runner.write_text('test runner fixture')
            config.write_text(json.dumps({'packages': [
                {'name': 'connectanum_core', 'rootUri': '../packages/connectanum_core/', 'packageUri': 'lib/'},
                {'name': 'test', 'rootUri': (root / 'test-dependency').as_uri() + '/', 'packageUri': 'lib/'},
                {'name': 'other', 'rootUri': '../other/', 'packageUri': 'lib/'},
            ]}))
            def reply(command, **kwargs):
                if command[:2] == ['git', 'diff']: return '\n'.join(component.TARGETS)
                if command[:2] == ['git', 'show']: return b'baseline source\n'
                raise AssertionError(command)
            with mock.patch.object(component.subprocess, 'check_output', side_effect=reply):
                actual = component.prepare(root, output, 'a' * 40)
            self.assertEqual(actual, runner)
            for variant in ('baseline', 'candidate'):
                packages = json.loads((output / variant / 'package_config.json').read_text())['packages']
                selected = next(p for p in packages if p['name'] == 'connectanum_core')
                self.assertEqual(selected['rootUri'], (output / variant / 'core').as_uri() + '/')
                self.assertTrue(all(p['rootUri'].startswith('file:') for p in packages))
                projection = output / variant / 'core/lib/src/serializer/flatbuffers/message_projection.dart'
                self.assertIn(f"dictionaryPlanProbeVariant = '{variant}'", projection.read_text())
                self.assertTrue(projection.read_text().startswith(variant + ' source'))
            self.assertIn('actual private core variant is selected', (output / 'private-tests.dart').read_text())

    def test_baseline_must_be_full_explicit_and_core_diff_must_be_isolated(self):
        with mock.patch.object(component.subprocess, 'check_output', return_value='unrelated.dart'):
            for baseline in ('HEAD~1', 'a' * 39, 'a' * 40):
                with self.subTest(baseline=baseline), self.assertRaises(ValueError):
                    component.prepare(Path('/not-used'), Path('/not-used'), baseline)


if __name__ == '__main__':
    unittest.main()

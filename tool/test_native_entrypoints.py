from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from native_coverage import REPO, filter_lcov, main, snapshot


class NativeEntrypointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        target = REPO / "out/rust-coverage-scope-target"
        subprocess.run([
            "cargo", "build", "--quiet", "--manifest-path",
            str(REPO / "tool/rust_coverage_scope/Cargo.toml"),
            "--target-dir", str(target), "--locked",
        ], check=True)
        cls.analyzer = target / "debug/connectanum-coverage-scope"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()
        self.roots = {"bench": "bench/src/lib.rs"}
        self.entries = ["bench/src/bin/first.rs", "bench/src/bin/second.rs"]
        self.write("bench/Cargo.toml", '[package]\nname="bench"\nversion="0.0.0"\n')
        self.write("bench/src/lib.rs", "pub fn library() {}\n")
        self.write(self.entries[0], 'fn main() {}\n#[cfg(test)] fn fixture() {}\n')
        self.write(self.entries[1], 'fn main() {}\n')

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def capture(self):
        return snapshot(self.repo, self.roots, self.analyzer, entrypoints=self.entries)

    def test_binaries_share_one_inventory_and_keep_missed_lines(self):
        scope = self.capture()
        self.assertEqual(scope['entrypoints'], self.entries)
        self.assertEqual(len(scope['sources']), 3)
        self.assertTrue(all(value['component'] == 'bench' for value in scope['sources'].values()))
        raw = ('SF:bench/src/lib.rs\nDA:1,2\nend_of_record\n'
               'SF:bench/src/bin/first.rs\nDA:1,0\nDA:2,3\nend_of_record\n'
               'SF:bench/src/bin/second.rs\nDA:1,1\nend_of_record\n')
        filtered, report = filter_lcov(self.repo, scope, raw)
        component = report['components']['bench']
        self.assertEqual((component['hit'], component['found']), (2, 3))
        self.assertEqual(component['excludedTestLines'], 1)
        self.assertEqual(component['unmeasuredSources'], [])
        self.assertIn('DA:1,0', filtered)

    def test_extra_unclassified_binary_is_not_silently_excluded(self):
        self.write('bench/src/bin/third.rs', 'fn main() {}\n')
        with self.assertRaisesRegex(ValueError, 'Unreachable'):
            self.capture()

    def test_binary_reachable_shared_module_is_not_removed_as_test_only(self):
        self.write('bench/src/lib.rs', '#[cfg(test)] mod shared;\n')
        self.write(self.entries[0], '#[path="../shared.rs"] mod shared;\nfn main() {}\n')
        self.write('bench/src/shared.rs', 'pub fn live() {}\n')
        scope = self.capture()
        self.assertEqual(scope['sources']['bench/src/shared.rs']['classification'], 'production-candidate')
        raw = 'SF:bench/src/shared.rs\nDA:1,0\nend_of_record\n'
        _, report = filter_lcov(self.repo, scope, raw)
        self.assertEqual((report['components']['bench']['hit'], report['components']['bench']['found']), (0, 1))

    def test_missing_entrypoint_is_rejected(self):
        self.entries.append('bench/src/bin/missing.rs')
        with self.assertRaisesRegex(ValueError, 'entrypoint'):
            self.capture()

    def test_duplicate_or_primary_root_entrypoint_is_rejected(self):
        for extra in [self.entries[0], self.roots['bench']]:
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'entrypoint'):
                snapshot(self.repo, self.roots, self.analyzer,
                         entrypoints=[*self.entries, extra])

    def test_changed_or_unmeasured_binary_remains_visible(self):
        scope = self.capture()
        raw = 'SF:bench/src/lib.rs\nDA:1,1\nend_of_record\n'
        _, report = filter_lcov(self.repo, scope, raw)
        self.assertEqual(report['components']['bench']['unmeasuredSources'], self.entries)
        self.write(self.entries[0], 'fn main() { panic!("changed"); }\n')
        with self.assertRaisesRegex(ValueError, 'Stale coverage source'):
            filter_lcov(self.repo, scope, raw)

    def test_old_single_entrypoint_snapshot_shape_is_preserved(self):
        for path in self.entries:
            (self.repo / path).unlink()
        scope = snapshot(self.repo, self.roots, self.analyzer)
        self.assertNotIn('entrypoints', scope)
        self.assertEqual(list(scope['sources']), ['bench/src/lib.rs'])

    def test_cli_bench_scope_round_trip_rejects_the_wrong_workspace(self):
        files = [
            'native/bench/src/lib.rs',
            'native/bench/src/bin/check_artifact_gate.rs',
            'native/bench/src/bin/http_stream.rs',
            'native/bench/src/bin/transform_results.rs',
        ]
        for path in files:
            self.write(path, 'fn main() {}\n')
        scope = self.repo / 'scope.json'
        raw = self.write('fixture.info', ''.join(
            f'SF:{path}\nDA:1,{int(index != 2)}\nend_of_record\n'
            for index, path in enumerate(files)))
        output = self.repo / 'production.info'
        common = ['--scope', str(scope), '--analyzer', str(self.analyzer)]
        with patch('native_coverage.REPO', self.repo):
            with patch.object(sys, 'argv', ['native_coverage', 'snapshot', '--workspace', 'bench', *common]):
                main()
            args = ['native_coverage', 'filter', *common, '--lcov', str(raw), '--output', str(output)]
            with patch.object(sys, 'argv', args), self.assertRaisesRegex(ValueError, 'No Rust sources'):
                main()
            self.assertFalse(output.exists())
            with patch.object(sys, 'argv', [*args, '--workspace', 'bench']):
                main()
        summary = json.loads(output.with_suffix('.summary.json').read_text())
        component = summary['components']['connectanum_bench_orchestrator']
        self.assertEqual((component['hit'], component['found']), (3, 4))
        self.assertEqual(component['unmeasuredSources'], [])


if __name__ == '__main__':
    unittest.main()

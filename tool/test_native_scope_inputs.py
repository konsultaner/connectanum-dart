from pathlib import Path
import subprocess
import tempfile
import unittest

from native_coverage import REPO, snapshot, validate_snapshot


class ExternalNativeInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        target = REPO / 'out/rust-coverage-scope-target'
        subprocess.run([
            'cargo', 'build', '--quiet', '--manifest-path',
            str(REPO / 'tool/rust_coverage_scope/Cargo.toml'),
            '--target-dir', str(target), '--locked',
        ], check=True)
        cls.analyzer = target / 'debug/connectanum-coverage-scope'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()
        self.roots = {'bench': 'bench/src/lib.rs'}
        self.write('bench/src/lib.rs', 'pub fn run() {}\n')
        self.write('bench/Cargo.toml', '[package]\nname="bench"\nversion="0.0.0"\n')
        self.write('bench/tests/cli.rs', '#[test] fn behavior() { assert!(true); }\n')
        self.write('bench/tests/fixtures/data.json', '{"expected":1}\n')
        self.write('bench/scenarios/smoke.toml', 'name="smoke"\n')
        self.write('.cargo/config.toml', '[build]\njobs=1\n')
        self.write('Cargo.toml', '[workspace]\nmembers=["bench"]\n')
        self.write('rust-toolchain.toml', '[toolchain]\nchannel="stable"\n')

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def capture(self):
        return snapshot(self.repo, self.roots, self.analyzer)

    def test_external_tests_and_fixtures_are_hash_inputs_not_production_scope(self):
        scope = self.capture()
        self.assertEqual(list(scope['sources']), ['bench/src/lib.rs'])
        for name in ['bench/tests/cli.rs', 'bench/tests/fixtures/data.json',
                     'bench/scenarios/smoke.toml', '.cargo/config.toml',
                     'Cargo.toml', 'rust-toolchain.toml']:
            with self.subTest(name=name):
                self.assertIn(name, scope['inputHashes'])

    def test_external_test_fixture_and_cargo_changes_invalidate_evidence(self):
        for name in ['bench/tests/cli.rs', 'bench/tests/fixtures/data.json',
                     'bench/scenarios/smoke.toml', '.cargo/config.toml',
                     'Cargo.toml', 'rust-toolchain.toml']:
            with self.subTest(name=name):
                scope = self.capture()
                self.write(name, 'changed\n')
                with self.assertRaisesRegex(ValueError, 'Stale coverage source'):
                    validate_snapshot(self.repo, scope)

    def test_added_or_deleted_test_invalidates_input_inventory(self):
        scope = self.capture()
        self.write('bench/tests/new.rs', '#[test] fn new_case() {}\n')
        with self.assertRaisesRegex(ValueError, 'input inventory changed'):
            validate_snapshot(self.repo, scope)
        scope = self.capture()
        (self.repo / 'bench/tests/new.rs').unlink()
        with self.assertRaisesRegex(ValueError, 'input inventory changed'):
            validate_snapshot(self.repo, scope)

    def test_symlinked_test_inputs_fail_closed(self):
        original = self.repo / 'bench/tests/fixtures/data.json'
        original.unlink()
        try:
            original.symlink_to(self.repo / 'bench/scenarios/smoke.toml')
        except (NotImplementedError, OSError) as error:
            self.skipTest(f'Symlinks unavailable: {error}')
        with self.assertRaisesRegex(ValueError, 'input symlink'):
            self.capture()

    def test_symlinked_test_directory_fails_before_traversal(self):
        tests = self.repo / 'bench/tests'
        moved = self.repo / 'outside-tests'
        tests.rename(moved)
        try:
            tests.symlink_to(moved, target_is_directory=True)
        except (NotImplementedError, OSError) as error:
            self.skipTest(f'Symlinks unavailable: {error}')
        with self.assertRaisesRegex(ValueError, 'input symlink'):
            self.capture()

    def test_symlinked_cargo_configuration_directory_fails_closed(self):
        cargo = self.repo / '.cargo'
        moved = self.repo / 'outside-cargo'
        cargo.rename(moved)
        try:
            cargo.symlink_to(moved, target_is_directory=True)
        except (NotImplementedError, OSError) as error:
            self.skipTest(f'Symlinks unavailable: {error}')
        with self.assertRaisesRegex(ValueError, 'input symlink'):
            self.capture()

    def test_native_mutation_copy_preserves_hashed_root_configuration(self):
        import run_native_mutations as collector
        from native_coverage import digest

        source = 'native/transport/ct_core/src/lib.rs'
        self.write(source, 'pub fn measured() {}\n')
        for relative in collector.FIXTURES:
            self.write(relative, 'public test fixture\n')
        paths = [source, '.cargo/config.toml', 'rust-toolchain.toml',
                 *collector.FIXTURES]
        hashes = {path: digest(self.repo / path) for path in paths}
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            try:
                collector.copy_inputs(self.repo, work, hashes)
            except FileNotFoundError as error:
                self.fail(f'Frozen input was not copied: {error.filename}')
            collector.verify_inputs(work, hashes)
            for relative in ['.cargo/config.toml', 'rust-toolchain.toml']:
                (work / relative).write_text('private mutation\n')
                collector.verify_inputs(self.repo, hashes)


if __name__ == '__main__':
    unittest.main()

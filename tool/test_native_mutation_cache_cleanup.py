import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

import native_mutation_cache_cleanup as cleaner


CACHE_TAG = (
    'Signature: 8a477f597d28d172789f06886806bc55\n'
    '# This file is a cache directory tag created by cargo.\n'
)


class NativeMutationCacheCleanupTests(unittest.TestCase):
    def git(self, root, *args):
        return subprocess.run(
            ['git', *args],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )

    def repository(self, root):
        self.git(root, 'init', '-q')
        (root / '.gitignore').write_text('/native/bench/target/\n/out/\n')
        (root / 'tracked.txt').write_bytes(b'tracked source')
        evidence = root / 'out/evidence/raw.json'
        evidence.parent.mkdir(parents=True)
        evidence.write_bytes(b'raw evidence')
        self.git(root, 'add', '.gitignore', 'tracked.txt')
        return evidence

    def cargo_cache(self, path):
        path.mkdir(parents=True)
        (path / 'CACHEDIR.TAG').write_text(CACHE_TAG)
        (path / 'debug.o').write_bytes(b'generated object')
        return path

    def stage_cache(self, temporary, name='connectanum-flatbuffers-frame-stage-abcd1234', *, age=7200):
        stage = temporary / name
        (stage / 'native/transport').mkdir(parents=True)
        (stage / 'native/transport/Cargo.toml').write_bytes(b'[workspace]\n')
        self.cargo_cache(stage / 'target')
        timestamp = time.time() - age
        os.utime(stage, (timestamp, timestamp))
        return stage

    def test_removes_only_exact_owned_caches_and_preserves_sources_and_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            evidence = self.repository(repo)
            fixed = self.cargo_cache(repo / 'native/bench/target')
            stage = self.stage_cache(temp_root)
            proof = repo / 'cleanup-proof.json'

            with patch.object(cleaner, 'require_unused') as inspect:
                result = cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    proof,
                    now=time.time(),
                )

            self.assertEqual(inspect.call_count, 4)
            self.assertFalse(fixed.exists())
            self.assertFalse((stage / 'target').exists())
            self.assertEqual(
                (stage / 'native/transport/Cargo.toml').read_bytes(),
                b'[workspace]\n',
            )
            self.assertEqual(evidence.read_bytes(), b'raw evidence')
            self.assertEqual((repo / 'tracked.txt').read_bytes(), b'tracked source')
            self.assertEqual(result['state'], 'completed')
            self.assertTrue(result['trackedHashesUnchanged'])
            self.assertEqual(json.loads(proof.read_text()), result)
            self.assertFalse(proof.with_suffix('.json.tmp').exists())

    def test_missing_fixed_cache_and_recent_stage_are_safe_noops(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            stage = self.stage_cache(temp_root, age=30)

            result = cleaner.clean_owned_caches(
                repo,
                temp_root,
                repo / 'proof.json',
                now=time.time(),
            )

            self.assertTrue((stage / 'target').exists())
            self.assertEqual(result['cleaned'], [])
            self.assertEqual(result['missing'], ['native/bench/target'])
            self.assertEqual(len(result['recentStageCaches']), 1)

    def test_tracked_content_inside_generated_cache_fails_before_deletion(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            cache = self.cargo_cache(repo / 'native/bench/target')
            self.git(repo, 'add', '-f', 'native/bench/target/debug.o')

            with self.assertRaisesRegex(ValueError, 'tracked'):
                cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    repo / 'proof.json',
                    now=time.time(),
                )

            self.assertTrue(cache.exists())

    def test_symlinked_cache_never_removes_the_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            outside = sandbox / 'outside'
            repo.mkdir()
            temp_root.mkdir()
            outside.mkdir()
            self.repository(repo)
            (outside / 'keep.txt').write_bytes(b'keep')
            target = repo / 'native/bench/target'
            target.parent.mkdir(parents=True)
            target.symlink_to(outside, target_is_directory=True)

            with self.assertRaisesRegex(ValueError, 'symlink'):
                cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    repo / 'proof.json',
                    now=time.time(),
                )

            self.assertEqual((outside / 'keep.txt').read_bytes(), b'keep')
            self.assertTrue(target.is_symlink())

    def test_unmarked_stage_target_is_not_accepted_as_a_cargo_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            stage = self.stage_cache(temp_root)
            (stage / 'target/CACHEDIR.TAG').unlink()

            with self.assertRaisesRegex(ValueError, 'Cargo cache tag'):
                cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    repo / 'proof.json',
                    now=time.time(),
                )

            self.assertTrue((stage / 'target/debug.o').exists())

    def test_invalid_cargo_cache_signature_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            cache = self.cargo_cache(repo / 'native/bench/target')
            (cache / 'CACHEDIR.TAG').write_text('Signature: wrong\n')

            with self.assertRaisesRegex(ValueError, 'Invalid Cargo cache tag'):
                cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    repo / 'proof.json',
                    now=time.time(),
                )

            self.assertTrue((cache / 'debug.o').exists())

    def test_internal_symlink_is_unlinked_without_following_external_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            outside = sandbox / 'outside'
            repo.mkdir()
            temp_root.mkdir()
            outside.mkdir()
            self.repository(repo)
            cache = self.cargo_cache(repo / 'native/bench/target')
            (outside / 'keep.txt').write_bytes(b'keep')
            (cache / 'external').symlink_to(outside, target_is_directory=True)

            with patch.object(cleaner, 'require_unused'):
                cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    repo / 'proof.json',
                    now=time.time(),
                )

            self.assertFalse(cache.exists())
            self.assertEqual((outside / 'keep.txt').read_bytes(), b'keep')

    def test_tracked_inventory_drift_fails_with_durable_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            self.cargo_cache(repo / 'native/bench/target')
            proof = repo / 'proof.json'
            first = {'tracked.txt': {'sha256': 'before', 'mode': 0o644}}
            second = {'tracked.txt': {'sha256': 'after', 'mode': 0o644}}

            with patch.object(
                cleaner,
                'tracked_inventory',
                side_effect=[first, second],
            ), patch.object(cleaner, 'require_unused'):
                with self.assertRaisesRegex(RuntimeError, 'inventory changed'):
                    cleaner.clean_owned_caches(
                        repo,
                        temp_root,
                        proof,
                        now=time.time(),
                    )

            result = json.loads(proof.read_text())
            self.assertEqual(result['state'], 'failed')
            self.assertEqual(result['errorType'], 'RuntimeError')
            self.assertFalse(proof.with_suffix('.json.tmp').exists())

    def test_cache_directory_swap_before_quarantine_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            cache = self.cargo_cache(repo / 'native/bench/target')
            original = cache.with_name('target-original')
            proof = repo / 'proof.json'

            def swap_once(_root):
                if not original.exists():
                    cache.rename(original)
                    self.cargo_cache(cache)

            with patch.object(cleaner, 'require_unused', side_effect=swap_once):
                with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                    cleaner.clean_owned_caches(
                        repo,
                        temp_root,
                        proof,
                        now=time.time(),
                    )

            self.assertTrue((original / 'debug.o').exists())
            self.assertTrue((cache / 'debug.o').exists())
            self.assertEqual(json.loads(proof.read_text())['state'], 'failed')

    def test_live_user_failure_preserves_every_cache_and_records_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            cache = self.cargo_cache(repo / 'native/bench/target')
            proof = repo / 'proof.json'

            with patch.object(
                cleaner,
                'require_unused',
                side_effect=RuntimeError('live cache user'),
            ):
                with self.assertRaisesRegex(RuntimeError, 'live cache user'):
                    cleaner.clean_owned_caches(
                        repo,
                        temp_root,
                        proof,
                        now=time.time(),
                    )

            self.assertTrue(cache.exists())
            self.assertEqual(json.loads(proof.read_text())['state'], 'failed')

    def test_existing_proof_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            cache = self.cargo_cache(repo / 'native/bench/target')
            proof = repo / 'proof.json'
            proof.write_bytes(b'prior evidence')

            with self.assertRaises(FileExistsError):
                cleaner.clean_owned_caches(
                    repo,
                    temp_root,
                    proof,
                    now=time.time(),
                )

            self.assertEqual(proof.read_bytes(), b'prior evidence')
            self.assertTrue(cache.exists())

    def test_allocated_size_deduplicates_hardlinked_cargo_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = self.cargo_cache(Path(temporary) / 'target')
            before = cleaner._tree_size(cache)
            os.link(cache / 'debug.o', cache / 'debug-hardlink.o')
            self.assertEqual(cleaner._tree_size(cache), before)

    def test_rejects_outside_duplicate_and_non_stage_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            repo = sandbox / 'repo'
            temp_root = sandbox / 'tmp'
            repo.mkdir()
            temp_root.mkdir()
            self.repository(repo)
            wrong_stage = self.cargo_cache(temp_root / 'connectanum-other/target')

            for paths in (
                [sandbox / 'outside'],
                [wrong_stage],
                [repo / 'native/bench/target', repo / 'native/bench/target'],
            ):
                with self.subTest(paths=paths):
                    with self.assertRaises(ValueError):
                        cleaner.validate_selected_caches(repo, temp_root, paths)

    def test_require_unused_rejects_command_and_open_file_users(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary) / 'cache'
            cache.mkdir()
            foreign_pid = os.getpid() + 100000
            with patch.object(
                cleaner.subprocess,
                'check_output',
                return_value=f'{foreign_pid} python {cache}/worker.py\n',
            ):
                with self.assertRaisesRegex(RuntimeError, 'command user'):
                    cleaner.require_unused(cache)

            process_table = f'{foreign_pid} python worker.py\n'
            lsof = subprocess.CompletedProcess(
                [],
                0,
                stdout=f'p{foreign_pid}\nn{cache}/open.bin\n',
                stderr='',
            )
            with patch.object(
                cleaner.subprocess,
                'check_output',
                return_value=process_table,
            ), patch.object(cleaner.subprocess, 'run', return_value=lsof):
                with self.assertRaisesRegex(RuntimeError, 'open-file/cwd user'):
                    cleaner.require_unused(cache)

            diagnostic = f'{foreign_pid} rg {cache}.*worker diagnostic.log\n'
            empty_lsof = subprocess.CompletedProcess(
                [],
                0,
                stdout=f'p{foreign_pid}\n',
                stderr='',
            )
            with patch.object(
                cleaner.subprocess,
                'check_output',
                return_value=diagnostic,
            ), patch.object(cleaner.subprocess, 'run', return_value=empty_lsof):
                cleaner.require_unused(cache)


if __name__ == '__main__':
    unittest.main()

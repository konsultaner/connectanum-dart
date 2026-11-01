import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import prepare_mqtt_comparison_locks as locks


class CanonicalLocksTests(unittest.TestCase):
    def fixture(self, root):
        proof = root / 'evidence' / 'wamp-native-ppt-copy-proof'
        proof.mkdir(parents=True)
        hashes = {}
        for name in locks.LOCKS:
            data = ('fixed ' + name + '\n').encode()
            hashes[name] = hashlib.sha256(data).hexdigest()
            for batch in ('a', 'b'):
                path = proof / batch / 'campaign/inputs' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        (proof / 'inputs.json').write_text(json.dumps({
            'head': 'a' * 40, 'source_inputs': hashes,
        }))
        (proof / 'result.json').write_text(json.dumps({
            'head': 'a' * 40, 'source_inputs_unchanged': True,
            'binaries_unchanged': True,
        }))
        return root / 'evidence', (root / 'baseline', root / 'candidate')

    def test_all_retained_copies_bind_both_worktrees(self):
        with tempfile.TemporaryDirectory() as temp:
            evidence, roots = self.fixture(Path(temp))
            hashes = locks.restore(evidence, 'a' * 40, roots)
            locks.verify(roots, hashes)
            for root in roots:
                self.assertEqual(set(hashes), set(locks.LOCKS))
                for name in locks.LOCKS:
                    self.assertEqual(locks.sha(root / name), hashes[name])
            (roots[0] / locks.LOCKS[0]).write_text('changed by bootstrap')
            with self.assertRaisesRegex(ValueError, 'bootstrap changed'):
                locks.verify(roots, hashes)

    def test_wrong_revision_or_disagreeing_copy_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            evidence, roots = self.fixture(Path(temp))
            with self.assertRaisesRegex(ValueError, 'another source'):
                locks.restore(evidence, 'b' * 40, roots)
            copy = next(evidence.glob('*/b/campaign/inputs/pubspec.lock'))
            copy.write_text('changed retained duplicate')
            with self.assertRaisesRegex(ValueError, 'hash differs'):
                locks.restore(evidence, 'a' * 40, roots)

    def test_missing_lock_or_failed_source_guards_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            evidence, roots = self.fixture(Path(temp))
            for path in evidence.rglob('pubspec.lock'):
                path.unlink()
            with self.assertRaisesRegex(ValueError, 'missing retained'):
                locks.restore(evidence, 'a' * 40, roots)
        with tempfile.TemporaryDirectory() as temp:
            evidence, roots = self.fixture(Path(temp))
            path = next(evidence.rglob('result.json'))
            result = json.loads(path.read_text())
            result['binaries_unchanged'] = False
            path.write_text(json.dumps(result))
            with self.assertRaisesRegex(ValueError, 'guards failed'):
                locks.restore(evidence, 'a' * 40, roots)

    def test_symlink_outside_artifact_is_not_a_retained_lock(self):
        with tempfile.TemporaryDirectory() as temp:
            evidence, roots = self.fixture(Path(temp))
            path = next(evidence.glob('*/a/campaign/inputs/pubspec.lock'))
            external = Path(temp) / 'outside.lock'
            external.write_bytes(path.read_bytes())
            path.unlink()
            path.symlink_to(external)
            with self.assertRaisesRegex(ValueError, 'escapes'):
                locks.restore(evidence, 'a' * 40, roots)


if __name__ == '__main__':
    unittest.main(verbosity=2)

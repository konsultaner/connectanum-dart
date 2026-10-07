#!/usr/bin/env python3
"""Native mutation work and local inference must never overlap silently."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

import native_mutation_coordination as coordination


class CoordinationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.previous_home = os.environ.get('CODEX_HOME')
        self.previous_fd = os.environ.pop(coordination.LEASE_FD_ENV, None)
        os.environ['CODEX_HOME'] = str(Path(self.temporary.name) / 'codex-home')
        self.addCleanup(self.restore_environment)

    def restore_environment(self):
        if self.previous_home is None:
            os.environ.pop('CODEX_HOME', None)
        else:
            os.environ['CODEX_HOME'] = self.previous_home
        if self.previous_fd is None:
            os.environ.pop(coordination.LEASE_FD_ENV, None)
        else:
            os.environ[coordination.LEASE_FD_ENV] = self.previous_fd

    def test_shared_companion_leases_coexist(self):
        with coordination.resource_lease(exclusive=False) as first:
            with coordination.resource_lease(exclusive=False) as second:
                self.assertNotEqual(first.fd, second.fd)
                first.verify_identity()
                second.verify_identity()

    def test_exclusive_measurement_and_shared_companion_are_mutually_exclusive(self):
        with coordination.resource_lease(exclusive=False):
            with self.assertRaisesRegex(RuntimeError, 'local companion or native mutation campaign'):
                with coordination.resource_lease(exclusive=True):
                    self.fail('Exclusive mutation lease bypassed active inference')
        with coordination.resource_lease(exclusive=True):
            with self.assertRaisesRegex(RuntimeError, 'native mutation campaign is active'):
                with coordination.resource_lease(exclusive=False):
                    self.fail('Shared inference lease bypassed active mutation work')

    def test_closed_and_crashed_owners_release_the_lease(self):
        with coordination.resource_lease(exclusive=True):
            pass
        with coordination.resource_lease(exclusive=True):
            pass

        script = (
            'import os,sys;sys.path.insert(0,sys.argv[1]);'
            'import native_mutation_coordination as c;'
            'lease=c.resource_lease(exclusive=True);lease.__enter__();os._exit(0)'
        )
        subprocess.run([sys.executable, '-c', script, str(Path(__file__).parent)],
                       env=os.environ.copy(), check=True, timeout=10)
        with coordination.resource_lease(exclusive=True):
            pass

    def test_replaced_lock_path_is_detected(self):
        with coordination.resource_lease(exclusive=True) as lease:
            lease.path.unlink()
            lease.path.touch(mode=0o600)
            with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                lease.verify_identity()

    def test_permission_drift_and_double_close_are_safe(self):
        lease = coordination.acquire_resource_lease(exclusive=True)
        lease.path.chmod(0o666)
        with self.assertRaisesRegex(RuntimeError, 'private and user-owned'):
            lease.verify_identity()
        lease.close()
        lease.close()

    def test_symlinked_lock_and_nonprivate_lease_directory_fail_closed(self):
        path = coordination.lease_path()
        path.parent.mkdir(parents=True, mode=0o700)
        target = path.parent / 'target'
        target.touch(mode=0o600)
        path.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, 'symbolic link'):
            with coordination.resource_lease(exclusive=True):
                self.fail('Symlinked resource lock was accepted')
        path.unlink()
        path.parent.chmod(0o755)
        with self.assertRaisesRegex(RuntimeError, 'private'):
            with coordination.resource_lease(exclusive=True):
                self.fail('Public resource-lease directory was accepted')

    def test_exclusive_descriptor_is_reused_by_an_inherited_child(self):
        with coordination.resource_lease(exclusive=True) as lease:
            environment = lease.child_environment()
            script = (
                'import sys\n'
                'sys.path.insert(0, sys.argv[1])\n'
                'import native_mutation_coordination as c\n'
                'with c.resource_lease(exclusive=True) as lease:\n'
                '    lease.verify_identity()\n'
                '    print(lease.inherited)\n'
            )
            child = subprocess.run(
                [sys.executable, '-c', script, str(Path(__file__).parent)],
                env=environment,
                pass_fds=lease.pass_fds,
                text=True,
                capture_output=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(child.returncode, 0, child.stderr)
            self.assertEqual(child.stdout.strip(), 'True')
            with self.assertRaisesRegex(RuntimeError, 'native mutation campaign is active'):
                with coordination.resource_lease(exclusive=False):
                    self.fail('Inherited child weakened the parent lease')

    def test_inherited_descriptor_must_match_the_secure_lock_path(self):
        unrelated = os.open(Path(self.temporary.name) / 'unrelated',
                            os.O_RDWR | os.O_CREAT, 0o600)
        os.environ[coordination.LEASE_FD_ENV] = str(unrelated)
        with self.assertRaisesRegex(RuntimeError, 'identity'):
            with coordination.resource_lease(exclusive=True):
                self.fail('Unrelated inherited descriptor was trusted')

    def test_campaign_cli_takes_the_lease_before_argument_parsing(self):
        tool = Path(__file__).parent / 'run_native_mutation_campaign.py'
        with coordination.resource_lease(exclusive=False):
            result = subprocess.run(
                [sys.executable, str(tool), '--definitely-invalid'],
                env=os.environ.copy(),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=10,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local companion or native mutation campaign', result.stderr)
        self.assertNotIn('unrecognized arguments', result.stderr)

    def test_second_campaign_cli_is_rejected_while_first_main_holds_the_lease(self):
        tool_root = Path(__file__).parent
        marker = Path(self.temporary.name) / 'lease-held'
        launcher = (
            'import sys,time\n'
            'from pathlib import Path\n'
            'sys.path.insert(0, sys.argv[1])\n'
            'import run_native_mutation_campaign as campaign\n'
            'def hold():\n'
            '    Path(sys.argv[2]).write_text("held")\n'
            '    time.sleep(30)\n'
            '    return 0\n'
            'campaign._run_main = hold\n'
            'raise SystemExit(campaign.main())\n'
        )
        first = subprocess.Popen(
            [sys.executable, '-c', launcher, str(tool_root), str(marker)],
            env=os.environ.copy(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not marker.exists():
                if first.poll() is not None:
                    self.fail(first.communicate()[1])
                time.sleep(.02)
            self.assertTrue(marker.exists(), 'First campaign did not acquire its lease')
            second = subprocess.run(
                [sys.executable, str(tool_root / 'run_native_mutation_campaign.py'),
                 '--definitely-invalid'],
                env=os.environ.copy(),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=10,
            )
            self.assertEqual(second.returncode, 2, second.stderr)
            self.assertIn('local companion or native mutation campaign', second.stderr)
            self.assertNotIn('unrecognized arguments', second.stderr)
        finally:
            if first.poll() is None:
                first.terminate()
            first.communicate(timeout=10)
        with coordination.resource_lease(exclusive=True):
            pass


if __name__ == '__main__':
    unittest.main()

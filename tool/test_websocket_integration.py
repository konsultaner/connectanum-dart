"""Fail-first integration checks for the pending browser regression promotion."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SUITES = (
    'test/transport/websocket/websocket_browser_lifecycle_test.dart',
    'test/transport/websocket/websocket_attempt_lifecycle_test.dart',
)


class WebSocketIntegrationContractTest(unittest.TestCase):
    def test_browser_verification_runs_both_complete_regression_suites(self):
        script = (ROOT / 'bin/test-all').read_text()
        for suite in SUITES:
            self.assertRegex(script, rf'(?m)^\s+{re.escape(suite)}\s*$')

    def test_browser_coverage_runs_both_complete_regression_suites(self):
        script = (ROOT / 'bin/test-browser-coverage').read_text()
        for suite in SUITES:
            self.assertRegex(script, rf'(?m)^\s+{re.escape(suite)}\s+\\$')

    def test_mutation_inventory_includes_complete_source_and_legacy_suite(self):
        targets = json.loads((ROOT / 'tool/mutation_targets.json').read_text())
        self.assertIn('client-websocket-web', targets)
        target = targets['client-websocket-web']
        self.assertEqual(target['sources'], [
            'packages/connectanum_client/lib/src/transport/websocket/websocket_transport_web.dart',
        ])
        self.assertEqual(set(target['tests']), {
            'packages/connectanum_client/' + path for path in (
                *SUITES, 'test/transport/websocket/websocket_transport_web_test.dart',
            )
        })
        self.assertEqual(target['platform'], 'chrome')
        self.assertEqual(target['testRoot'], 'packages/connectanum_client')
        self.assertFalse(target.get('excludeOperators'))
        self.assertFalse(target.get('extraArgs'))
        self.assertFalse(target.get('requiresNativeLibrary'))

    def test_mutation_evidence_hashes_the_browser_event_observer(self):
        targets = json.loads((ROOT / 'tool/mutation_targets.json').read_text())
        observer = ('packages/connectanum_client/test/transport/websocket/'
                    'websocket_test_observer.dart')
        self.assertIn(observer, targets['client-websocket-web'].get('supportFiles', []))
        self.assertTrue((ROOT / observer).is_file())


if __name__ == '__main__':
    unittest.main()

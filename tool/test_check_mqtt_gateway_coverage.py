import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest import mock

import check_mqtt_gateway_coverage as gate


class GatewayCoverageTest(unittest.TestCase):
    def test_python_evidence_requires_every_source_and_zero_missing_or_excluded_lines(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'coverage.json'
            files={name:{'summary':{'num_statements':1,'missing_lines':0,'excluded_lines':0}} for name in gate.PYTHON_SOURCES}
            path.write_text(json.dumps({'files':files}))
            self.assertEqual(gate.require_python_coverage(path),len(files))
            for report in [{},{'files':{}},{'files':dict(files,extra={})}]:
                path.write_text(json.dumps(report))
                with self.assertRaises(ValueError):gate.require_python_coverage(path)
            for key,value in [('num_statements',0),('missing_lines',1),('excluded_lines',1)]:
                bad=json.loads(json.dumps(files));bad[next(iter(bad))]['summary'][key]=value
                path.write_text(json.dumps({'files':bad}))
                with self.assertRaises(ValueError):gate.require_python_coverage(path)

    def test_terminal_ci_gate_rejects_every_missing_or_unsuccessful_required_lane(self):
        import check_ci_needs as terminal
        complete={name:{'result':'success'} for name in terminal.REQUIRED}
        with contextlib.redirect_stdout(io.StringIO()):
            with mock.patch.dict(os.environ,CONNECTANUM_CI_NEEDS=json.dumps(complete)):
                self.assertEqual(terminal.main(),0)
                with self.assertRaises(SystemExit) as stopped:
                    runpy.run_path(terminal.__file__,run_name='__main__')
                self.assertEqual(stopped.exception.code,0)
            for invalid in [[],{}]+[{k:v for k,v in complete.items() if k != name} for name in complete]:
                with mock.patch.dict(os.environ,CONNECTANUM_CI_NEEDS=json.dumps(invalid)),self.assertRaises(ValueError):terminal.main()
            for name in complete:
                for status in ['failure','skipped','cancelled','pending',None]:
                    invalid={**complete,name:{'result':status}}
                    with mock.patch.dict(os.environ,CONNECTANUM_CI_NEEDS=json.dumps(invalid)),self.assertRaises(ValueError):terminal.main()

    def test_diff_tracks_new_executable_positions_without_counting_deleted_or_comment_lines(self):
        name = gate.SHARED[0]
        patch = f'diff --git a/{name} b/{name}\n--- a/{name}\n+++ b/{name}\n@@ -1,2 +3,3 @@ method\n-old\n+new\n unchanged\n+new\n\\ No newline at end of file\n'
        self.assertEqual(gate.added_lines(patch), {name: {3, 5}})
        self.assertEqual(gate.added_lines('+++ /dev/null\n'), {})
        for bad in ['@@ -1 +1 @@\n+added', '+++ b/source\n@@ malformed @@']:
            with self.assertRaises(ValueError): gate.added_lines(bad)
        sources = {name: {3: 1, 4: 0, 5: 1}, **{name: {1: 1} for name in gate.WHOLE}}
        report = gate.check(sources, patch)
        self.assertTrue(report['passed'])
        self.assertEqual(report['files'][name]['total'], 2)
        sources[name][5] = 0
        self.assertFalse(gate.check(sources, patch)['passed'])
        sources.pop(name)
        self.assertTrue(gate.check(sources, patch)['files'][name]['missing'])

    def test_every_new_source_requires_real_compiler_coverage_and_no_unexecuted_lines(self):
        sources = {name: {1: 1, 2: 1} for name in gate.WHOLE}
        self.assertTrue(gate.check(sources, '')['passed'])
        for name in gate.WHOLE:
            for lines in [None, {}, {1: 1, 2: 0}]:
                with self.subTest(name=name, lines=lines):
                    bad = dict(sources)
                    if lines is None: bad.pop(name)
                    else: bad[name] = lines
                    self.assertFalse(gate.check(bad, '')['passed'])

    def test_pending_rpc_lifetime_changes_require_session_compiler_coverage(self):
        name = 'packages/connectanum_client/lib/src/protocol/session.dart'
        self.assertIn(name, gate.SHARED)
        patch = f'+++ b/{name}\n@@ -1 +3 @@\n+request_id\n'
        sources = {name: {1: 1} for name in gate.WHOLE}
        self.assertFalse(gate.check(sources, patch)['passed'])
        sources[name] = {3: 0}
        self.assertFalse(gate.check(sources, patch)['passed'])
        sources[name] = {3: 1}
        self.assertTrue(gate.check(sources, patch)['passed'])

    def test_cli_combines_library_and_packaging_evidence_and_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary)
            lcov=directory/'coverage.lcov'
            output=directory/'report.json'
            lcov.write_text(''.join(f'SF:{name}\nDA:3,1\nDA:5,1\nend_of_record\n' for name in (*gate.WHOLE, *gate.SHARED)))
            name=gate.SHARED[0]
            patch=f'+++ b/{name}\n@@ -1 +3 @@\n+code\n'
            with mock.patch.object(gate.subprocess,'check_output',return_value=patch),contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gate.main([str(lcov),'--base','known-commit','--output',str(output)]),0)
                self.assertEqual(json.loads(output.read_text())['source_base'],'known-commit')
                lcov.write_text(lcov.read_text().replace('DA:3,1','DA:3,0'))
                self.assertEqual(gate.main([str(lcov),'--output',str(output)]),1)
                lcov.write_text('')
                self.assertEqual(gate.main([str(lcov),'--output',str(output)]),1)
        with mock.patch.object(sys,'argv',['check_mqtt_gateway_coverage.py','--help']),contextlib.redirect_stdout(io.StringIO()),self.assertRaises(SystemExit):
            runpy.run_path(gate.__file__,run_name='__main__')


if __name__ == '__main__':
    unittest.main()

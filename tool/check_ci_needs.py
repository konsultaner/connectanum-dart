#!/usr/bin/env python3
"""Make the protected Full Verify check fail on any omitted/unsuccessful lane."""
import json
import os

REQUIRED = frozenset(('fast', 'verification', 'wamp-app', 'flatbuffers-binding',
                      'native-memory', 'mutation-gates', 'mcp-mutations', 'browser-coverage'))


def main():
    needs = json.loads(os.environ['CONNECTANUM_CI_NEEDS'])
    if not isinstance(needs, dict) or set(needs) != REQUIRED:
        raise ValueError('Full Verify prerequisite inventory does not match the required lanes')
    failed = {name: job.get('result') for name, job in needs.items()
              if job.get('result') != 'success'}
    if failed:
        raise ValueError(f'Full Verify prerequisites did not succeed: {failed}')
    print('All required verification, coverage and mutation lanes succeeded.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

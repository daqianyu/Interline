#!/usr/bin/env python3
"""Reject test-only hooks/resources in an actual Release .app product."""
import argparse
import json
import plistlib
from pathlib import Path

MARKERS = (b'INTERLINE_UI_', b'UITestFileFixtures', b'InterlineQ01-', b'InterlineUISmoke-')


def verify(app: Path) -> dict:
    with (app / 'Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    for key in ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'):
        if info.get(key):
            raise ValueError(f'Test-only provider configuration present: {key}')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or not executable or Path(executable).name != executable:
        raise ValueError('Invalid or missing bundle executable')
    binary = (app / executable).read_bytes()
    if not binary:
        raise ValueError('Empty bundle executable')
    for marker in MARKERS:
        if marker in binary:
            raise ValueError(f'Test-only binary marker present: {marker.decode()}')
    for resource in app.rglob('*'):
        if resource.name in ('ProviderSamples', 'expected.json') or resource.name.startswith(('q01-', 'FP05-')):
            raise ValueError(f'Test-only resource present: {resource.relative_to(app)}')
    return {'result': 'passed', 'bundle_id': info.get('CFBundleIdentifier'),
            'executable': executable, 'binary_bytes': len(binary),
            'scope': 'Release product test-hook/resource isolation; no physical-device acceptance'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = verify(args.app)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('Release test isolation passed')


if __name__ == '__main__':
    main()

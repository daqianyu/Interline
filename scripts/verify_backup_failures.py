#!/usr/bin/env python3
"""Read retained FP06 evidence without modifying the app or its temporary files."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from verify_provider_sources import simulator_documents

SOURCES = {'FP06-valid.interlinebackup', 'FP06-truncated.interlinebackup',
           'FP06-badhash.interlinebackup', 'FP06-badquote.json'}
EVENTS = ['initial', 'rejected:FP06-truncated.interlinebackup',
          'rejected:FP06-badhash.interlinebackup', 'rejected:FP06-badquote.json',
          'prepared:FP06-valid.interlinebackup', 'cancelled', 'initial']


def file_hashes(root: Path) -> dict:
    return {str(file.relative_to(root)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in root.rglob('*') if file.is_file()}


def verify(documents: Path) -> dict:
    reports = list(documents.glob('InterlineQ01-*/fp06-evidence.json'))
    if len(reports) != 1:
        raise ValueError(f'Expected one FP06 report, found {len(reports)}')
    path = reports[0]
    report = json.loads(path.read_text())
    baseline = report['baseline']
    if baseline['counts'] != dict.fromkeys(['books', 'bookmarks', 'annotations', 'drafts'], 1):
        raise ValueError('Expected nonempty original library, bookmark, note and draft')
    if not {'catalog-v2.json', 'annotations-v1.json', 'drafts-v1.json'} <= baseline['files'].keys():
        raise ValueError('Missing original storage files')
    if not any(name.startswith('Contents/') for name in baseline['files']):
        raise ValueError('Missing original book body')
    if not {'interline_saved_preferences_v1', 'interline_saved_bookmarks_v1'} <= baseline['defaults'].keys() or not any(
            name.startswith('interline_reading_record_v2_') for name in baseline['defaults']):
        raise ValueError('Missing original preferences, bookmarks or reading record')
    if set(baseline['memory']) != {'books', 'preferences', 'bookmarks', 'annotations', 'drafts', 'maintenance'}:
        raise ValueError('Missing in-memory evidence')
    for kind in ('files', 'defaults', 'memory'):
        if not all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) for value in baseline[kind].values()):
            raise ValueError('Invalid snapshot hash')
    if [entry['name'] for entry in report['events']] != EVENTS:
        raise ValueError('Missing or reordered FP06 events')
    for entry in report['events']:
        if entry['snapshot'] != baseline:
            raise ValueError(f'Original data changed at {entry["name"]}')
        count = 1 if entry['name'].startswith('prepared:') else 0
        if len(entry['workspaces']) != count:
            raise ValueError(f'Unexpected workspace count at {entry["name"]}')
    if set(report['sources']) != SOURCES:
        raise ValueError('Missing FP06 source baseline')
    for name, entry in report['sources'].items():
        data = (path.parent / name).read_bytes()
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError(f'Original source changed: {name}')
    library = report['library']
    if not re.fullmatch(r'InterlineUISmoke-[0-9A-Fa-f-]{36}', library):
        raise ValueError('Invalid isolated library name')
    temporary = documents.parent / 'tmp'
    if file_hashes(temporary / library) != baseline['files']:
        raise ValueError('Persisted original files changed after relaunch')
    if list(temporary.glob('InterlineBackup-*')):
        raise ValueError('Backup workspaces remain after cancellation')
    return {'result': 'passed', 'events': EVENTS, 'counts': baseline['counts'],
            'sources': report['sources'], 'evidence': report, 'scope': 'FP06 local simulator failure and cancellation; no external-provider/device acceptance'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator-data-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(simulator_documents(args.simulator_data_root))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('FP06 original data, source bytes and workspace lifecycle passed')


if __name__ == '__main__':
    main()

import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import verify_backup_failures as probe


class BackupFailureEvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.documents = self.root / 'Documents'
        self.suite = self.documents / 'InterlineQ01-example'
        self.suite.mkdir(parents=True)
        self.library = 'InterlineUISmoke-AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
        library = self.root / 'tmp' / self.library
        (library / 'Contents').mkdir(parents=True)
        for name in ['catalog-v2.json', 'annotations-v1.json', 'drafts-v1.json', 'Contents/body.json']:
            (library / name).write_bytes(name.encode())
        digest = hashlib.sha256(b'original').hexdigest()
        baseline = {'files': probe.file_hashes(library), 'defaults': {
            'interline_saved_preferences_v1': digest, 'interline_saved_bookmarks_v1': digest,
            'interline_reading_record_v2_book': digest}, 'memory': dict.fromkeys(
                ['books', 'preferences', 'bookmarks', 'annotations', 'drafts', 'maintenance'], digest),
            'counts': dict.fromkeys(['books', 'bookmarks', 'annotations', 'drafts'], 1)}
        sources = {}
        for name in probe.SOURCES:
            data = name.encode()
            (self.suite / name).write_bytes(data)
            sources[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        self.report = {'library': self.library, 'baseline': baseline, 'sources': sources, 'events': [
            {'name': event, 'snapshot': copy.deepcopy(baseline),
             'workspaces': ['InterlineBackup-example'] if event.startswith('prepared:') else []}
            for event in probe.EVENTS]}
        self.save()

    def save(self):
        (self.suite / 'fp06-evidence.json').write_text(json.dumps(self.report))

    def test_complete_real_file_evidence_passes(self):
        self.assertEqual(probe.verify(self.documents)['result'], 'passed')

    def test_mutated_defaults_are_rejected(self):
        self.report['events'][2]['snapshot']['defaults']['interline_saved_preferences_v1'] = '0' * 64
        self.save()
        with self.assertRaisesRegex(ValueError, 'Original data changed'):
            probe.verify(self.documents)

    def test_missing_cancellation_event_is_rejected(self):
        self.report['events'].pop(5)
        self.save()
        with self.assertRaisesRegex(ValueError, 'Missing or reordered'):
            probe.verify(self.documents)

    def test_leaked_workspace_is_rejected(self):
        self.report['events'][5]['workspaces'] = ['InterlineBackup-leaked']
        self.save()
        with self.assertRaisesRegex(ValueError, 'workspace count'):
            probe.verify(self.documents)

    def test_actual_workspace_leak_is_rejected(self):
        (self.root / 'tmp' / 'InterlineBackup-leaked').mkdir()
        with self.assertRaisesRegex(ValueError, 'workspaces remain'):
            probe.verify(self.documents)

    def test_actual_source_mutation_is_rejected(self):
        (self.suite / 'FP06-badhash.interlinebackup').write_bytes(b'modified')
        with self.assertRaisesRegex(ValueError, 'Original source changed'):
            probe.verify(self.documents)

    def test_actual_library_file_mutation_is_rejected(self):
        (self.root / 'tmp' / self.library / 'drafts-v1.json').write_bytes(b'modified')
        with self.assertRaisesRegex(ValueError, 'Persisted original files changed'):
            probe.verify(self.documents)

    def test_empty_original_library_is_rejected(self):
        self.report['baseline']['counts']['books'] = 0
        self.save()
        with self.assertRaisesRegex(ValueError, 'nonempty original'):
            probe.verify(self.documents)

    def test_missing_report_is_rejected(self):
        (self.suite / 'fp06-evidence.json').unlink()
        with self.assertRaisesRegex(ValueError, 'Expected one FP06 report'):
            probe.verify(self.documents)

    def test_library_path_escape_is_rejected(self):
        self.report['library'] = '../other'
        self.save()
        with self.assertRaisesRegex(ValueError, 'Invalid isolated library'):
            probe.verify(self.documents)

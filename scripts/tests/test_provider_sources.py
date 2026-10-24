import hashlib
import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('provider', Path(__file__).parents[1] / 'verify_provider_sources.py')
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)


class ProviderSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.suite = self.root / 'InterlineQ01-example'
        self.suite.mkdir()
        (self.suite / 'sample.txt').write_bytes(b'original')
        self.manifest = self.root / 'expected.json'
        self.manifest.write_text(json.dumps({'files': [{'name': 'sample.txt', 'bytes': 8,
            'sha256': hashlib.sha256(b'original').hexdigest()}]}))

    def test_unchanged_source(self):
        result = provider.verify(self.root, self.manifest, 1)
        self.assertEqual(result['result'], 'passed')
        self.assertEqual(len(result['files']), 1)

    def test_same_length_changed_bytes_fail(self):
        (self.suite / 'sample.txt').write_bytes(b'modified')
        with self.assertRaisesRegex(ValueError, 'Source file changed'):
            provider.verify(self.root, self.manifest, 1)

    def test_missing_source_fails(self):
        (self.suite / 'sample.txt').unlink()
        with self.assertRaises(FileNotFoundError):
            provider.verify(self.root, self.manifest, 1)

    def test_missing_suites_fail(self):
        with self.assertRaisesRegex(ValueError, 'Expected at least'):
            provider.verify(self.root, self.manifest, 5)

    def test_exported_backup_unchanged(self):
        (self.suite / 'backup.interlinebackup').write_bytes(b'backup')
        (self.suite / 'backup-source.json').write_text(json.dumps({'name': 'backup.interlinebackup', 'bytes': 6, 'sha256': hashlib.sha256(b'backup').hexdigest()}))
        result = provider.verify(self.root, self.manifest, 1, True)
        self.assertEqual(len(result['backups']), 1)
        with self.assertRaisesRegex(ValueError, 'Expected 2 exported backup baseline'):
            provider.verify(self.root, self.manifest, 1, True, 2)

    def test_exported_backup_mutation_fails(self):
        (self.suite / 'backup.interlinebackup').write_bytes(b'change')
        (self.suite / 'backup-source.json').write_text(json.dumps({'name': 'backup.interlinebackup', 'bytes': 6, 'sha256': hashlib.sha256(b'backup').hexdigest()}))
        with self.assertRaisesRegex(ValueError, 'Exported backup source changed'):
            provider.verify(self.root, self.manifest, 1, True)

    def test_missing_backup_baseline_fails(self):
        with self.assertRaisesRegex(ValueError, 'Expected 1 exported backup baseline'):
            provider.verify(self.root, self.manifest, 1, True)


class SimulatorContainerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def container(self, folder, bundle):
        directory = self.root / 'Containers' / 'Data' / 'Application' / folder
        directory.mkdir(parents=True)
        (directory / '.com.apple.mobile_container_manager.metadata.plist').write_bytes(
            plistlib.dumps({'MCMMetadataIdentifier': bundle}, fmt=plistlib.FMT_BINARY))
        return directory / 'Documents'

    def test_selects_bundle_identity_not_directory_order(self):
        self.container('first', 'com.example.other')
        expected = self.container('second', 'com.interline.app')
        self.assertEqual(provider.simulator_documents(self.root), expected)

    def test_missing_app_container_fails(self):
        self.container('other', 'com.example.other')
        with self.assertRaisesRegex(ValueError, 'found 0'):
            provider.simulator_documents(self.root)

    def test_ambiguous_app_container_fails(self):
        self.container('one', 'com.interline.app')
        self.container('two', 'com.interline.app')
        with self.assertRaisesRegex(ValueError, 'found 2'):
            provider.simulator_documents(self.root)

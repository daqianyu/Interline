import hashlib
import importlib.util
import json
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

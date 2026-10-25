import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'verify_release_isolation.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseIsolationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app = Path(temporary.name) / 'Interline.app'
        self.app.mkdir()
        self.info = {'CFBundleExecutable': 'Interline', 'CFBundleIdentifier': 'com.interline.app'}
        self.write_info()
        (self.app / 'Interline').write_bytes(b'release binary')

    def write_info(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_clean_release_product(self):
        self.assertEqual(release.verify(self.app)['result'], 'passed')

    def test_debug_hooks_fail_even_without_symbols(self):
        for marker in release.MARKERS:
            with self.subTest(marker=marker):
                (self.app / 'Interline').write_bytes(b'prefix' + marker + b'suffix')
                with self.assertRaisesRegex(ValueError, 'binary marker'):
                    release.verify(self.app)

    def test_test_provider_configuration_fails(self):
        for key in ('UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'):
            with self.subTest(key=key):
                self.info[key] = True
                self.write_info()
                with self.assertRaisesRegex(ValueError, 'provider configuration'):
                    release.verify(self.app)
                del self.info[key]

    def test_nested_samples_fail(self):
        resources = self.app / 'Resources'
        resources.mkdir()
        for name in ('ProviderSamples', 'expected.json', 'q01-utf8.txt', 'FP05-v1.json'):
            with self.subTest(name=name):
                sample = resources / name
                sample.write_bytes(b'sample')
                with self.assertRaisesRegex(ValueError, 'resource present'):
                    release.verify(self.app)
                sample.unlink()

    def test_missing_or_empty_executable_fails(self):
        binary = self.app / 'Interline'
        binary.write_bytes(b'')
        with self.assertRaisesRegex(ValueError, 'Empty'):
            release.verify(self.app)
        binary.unlink()
        with self.assertRaises(FileNotFoundError):
            release.verify(self.app)

    def test_executable_path_escape_fails(self):
        self.info['CFBundleExecutable'] = '../other'
        self.write_info()
        with self.assertRaisesRegex(ValueError, 'Invalid'):
            release.verify(self.app)

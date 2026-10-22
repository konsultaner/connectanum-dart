import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import install_objectbox_test_library as installer


class ObjectBoxTestInstallerTest(unittest.TestCase):
    def test_linux_metadata_is_not_treated_as_a_shared_library(self):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as archive:
            for name, body in [('info/libobjectbox.so.txt', b'metadata'),
                               ('lib/libobjectbox.so', b'engine')]:
                member = tarfile.TarInfo(name)
                member.size = len(body)
                archive.addfile(member, io.BytesIO(body))
        self.assertEqual(installer.engine_bytes(data.getvalue(), 'sdk.tar.gz',
                                                'libobjectbox.so'), b'engine')

    def test_zip_extraction_reads_only_the_engine_without_extracting_paths(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as archive:
            archive.writestr('../unexpected.txt', b'not extracted')
            archive.writestr('lib/objectbox.dll', b'engine')
        self.assertEqual(installer.engine_bytes(data.getvalue(), 'sdk.zip',
                                                'objectbox.dll'), b'engine')

    def test_corrupt_cache_fails_before_installing_a_library(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary) / 'cache'
            cache.mkdir()
            (cache / 'objectbox-linux-x64.tar.gz').write_bytes(b'corrupt')
            destination = Path(temporary) / 'lib'
            with patch.object(installer.platform, 'system', return_value='Linux'), \
                    patch.object(installer.platform, 'machine', return_value='x86_64'):
                with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                    installer.install(destination, cache)
            self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main()

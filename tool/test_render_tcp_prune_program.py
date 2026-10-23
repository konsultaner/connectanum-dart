from pathlib import Path
import hashlib, importlib.util, struct, unittest

folder = Path(__file__).parent
def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, folder / filename)
    item = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(item)
    return item
renderer = module('private_renderer', 'render-tcp-prune-program.py')
fixtures = module('private_btf_fixtures', 'test_inspect_btf_types.py')

class Tests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.Tests()
        self.template = (folder / 'tcp-prune-smoke.bt').read_text()

    def test_live_field_offset_is_derived_and_program_is_hashed(self):
        source, evidence = renderer.render(self.fixture.blob(), self.template)
        self.assertEqual(evidence['generated_prefix_bytes'], 64)
        self.assertIn('char observed_prefix[64];', source)
        self.assertEqual(source.count(')->observed_ino'), 2)
        self.assertEqual(evidence['program_sha256'], hashlib.sha256(source.encode()).hexdigest())
        self.assertIn(evidence['btf_sha256'], source)

    def test_unsupported_endian_bitfield_and_reference_fail_closed(self):
        for data in [self.fixture.blob('>'), self.fixture.blob(flag=True), self.fixture.blob(bad_ref=True)]:
            with self.assertRaises(ValueError):
                renderer.render(data, self.template)

    def test_signed_or_nonfullwidth_integer_cannot_be_read_as_inode(self):
        for encoding in [(1 << 24) | 64, 32, (1 << 16) | 64]:
            data = bytearray(self.fixture.blob())
            struct.pack_into('<I', data, 36, encoding)
            with self.assertRaises(ValueError):
                renderer.render(data, self.template)

    def test_template_drift_is_rejected(self):
        with self.assertRaises(ValueError):
            renderer.render(self.fixture.blob(), self.template.replace('->i_ino', '->other'))

    def test_c_declaration_precedes_bpftrace_config_and_probes(self):
        source, _ = renderer.render(self.fixture.blob(), self.template)
        self.assertLess(source.index('struct ct_probe_inode'), source.index('config ='))

if __name__ == '__main__':
    unittest.main()

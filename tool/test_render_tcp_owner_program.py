from pathlib import Path
import importlib.util,unittest
p=Path(__file__).parent
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,p/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
renderer=module('owner_renderer','render-tcp-owner-program.py');fixture=module('owner_fixtures','test_inspect_btf_types.py')
class Tests(unittest.TestCase):
 def test_exact_three_inode_reads_and_live_layout(self):
  source,e=renderer.render(fixture.Tests().blob(),(p/'tcp-prune-owner-smoke.bt').read_text());self.assertEqual(source.count(')->observed_ino'),3);self.assertEqual(e['generated_prefix_bytes'],64);self.assertIn('kretfunc:tcp_v4_connect',source);self.assertIn('nsecs(monotonic), pid',source)
 def test_missing_or_extra_inode_reads_fail_closed(self):
  template=(p/'tcp-prune-owner-smoke.bt').read_text()
  for text in [template.replace('->i_ino','->other',1),template+'\n'+template]:
   with self.assertRaises(ValueError):renderer.render(fixture.Tests().blob(),text)
if __name__=='__main__':unittest.main()

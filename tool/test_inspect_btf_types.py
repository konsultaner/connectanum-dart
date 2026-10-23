from pathlib import Path
import importlib.util,struct,unittest
spec=importlib.util.spec_from_file_location('selected_btf',Path(__file__).with_name('inspect-btf-types.py'));btf=importlib.util.module_from_spec(spec);spec.loader.exec_module(btf)
class Tests(unittest.TestCase):
 def blob(self,endian='<',bad_ref=False,flag=False):
  strings=b'\0unsigned long\0inode\0i_ino\0ino_t\0';name=lambda x:strings.index(x.encode()+b'\0');pack=lambda *v:struct.pack(endian+'I'*len(v),*v)
  types=pack(name('unsigned long'),1<<24,8)+pack(64)
  types+=pack(name('ino_t'),8<<24,99 if bad_ref else 1)
  types+=pack(name('inode'),(4<<24)|1|(int(flag)<<31),128)+pack(name('i_ino'),2,(7<<24)|520 if flag else 512)
  types+=pack(name('inode'),7<<24,0)
  return struct.pack(endian+'HBB5I',0xeb9f,1,0,24,0,len(types),len(types),len(strings))+types+strings
 def test_endian_alias_full_and_forward_types(self):
  for endian in ['<','>']:
   d=btf.inspect(self.blob(endian));self.assertEqual(d['endian'],endian);self.assertEqual(d['type_count'],4);self.assertEqual([x['kind']for x in d['selected']],[4,7]);m=d['selected'][0]['members'][0];self.assertEqual((m['name'],m['bit_offset'],m['bitfield_width']),('i_ino',512,0));self.assertEqual(m['resolved_type']['size_bytes'],8)
 def test_bitfield_offset(self):
  m=btf.inspect(self.blob(flag=True))['selected'][0]['members'][0];self.assertEqual((m['bit_offset'],m['bitfield_width']),(520,7))
 def test_selected_invalid_alias_reference_rejected(self):
  with self.assertRaises(ValueError):btf.inspect(self.blob(bad_ref=True))
 def test_invalid_headers_and_bounds_rejected(self):
  for offset,value,fmt in [(0,0,'H'),(2,2,'B'),(3,1,'B'),(4,23,'I'),(8,0xffffffff,'I'),(16,0,'I')]:
   data=bytearray(self.blob());struct.pack_into('<'+fmt,data,offset,value)
   with self.subTest(offset=offset),self.assertRaises(ValueError):btf.inspect(data)
  for data in [b'',self.blob()[:-1],self.blob()+b'\0']:
   with self.assertRaises(ValueError):btf.inspect(data)
 def test_unknown_kind_and_reserved_info_rejected(self):
  for info in [20<<24,(1<<24)|(1<<16)]:
   data=bytearray(self.blob());struct.pack_into('<I',data,28,info)
   with self.assertRaises(ValueError):btf.inspect(data)
 def test_truncated_payload_and_alias_cycle_rejected(self):
  data=bytearray(self.blob());struct.pack_into('<I',data,24+16+4,8<<24);struct.pack_into('<I',data,24+16+8,2)
  with self.assertRaises(ValueError):btf.inspect(data)
  data=bytearray(self.blob());struct.pack_into('<I',data,24+28+4,(4<<24)|65535)
  with self.assertRaises(ValueError):btf.inspect(data)
if __name__=='__main__':unittest.main()

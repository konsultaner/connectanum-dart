"""Diagnostic only: attribute native malloc callers in the unchanged broker."""
import json,os,platform,subprocess,hashlib,gzip
from pathlib import Path
import run_mqtt_gateway_benchmark as bench
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/dart314-rss-probe';OUT.mkdir(parents=True,exist_ok=False)
assert not os.environ.get('DART_VM_OPTIONS')
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
profile=dict(id='tcp-5-cbor-65536-1-1',transport='tcp',mqtt_version='5',serializer='cbor',payload_bytes=65536,subscribers=1,window=1,mqtt_client='connectanum')
OUT.joinpath('environment.json').write_text(json.dumps(dict(diagnostic_only=True,kind='heaptrack-malloc-callstack-attribution',source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),production_source='2bd89a33d14c0980d808ecbb4b0ded46e2c3bd8f',system=platform.platform(),sdk=subprocess.check_output(['dart','--version'],text=True).strip(),normal_vm_options=os.environ.get('DART_VM_OPTIONS'),native_sha256=hashlib.sha256(library.read_bytes()).hexdigest()),indent=2))
worker=bench.compile_worker(OUT/'worker')
original=bench.Child
class ProfiledChild(original):
 def __init__(self,label,command,events,output,env):
  if label=='broker' and 'profiled' in output.name:
   env={**env,'LD_PRELOAD':os.environ['HEAPTRACK_PRELOAD'],'DUMP_HEAPTRACK_OUTPUT':str(output/'heaptrack.raw')}
  super().__init__(label,command,events,output,env)
bench.Child=ProfiledChild
for name in ['1-normal','2-profiled','3-profiled']:
 output=OUT/name;output.mkdir()
 config={**profile,'path':'mqtt_to_wamp','port':0,'native_library':str(library),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
 campaign=bench.Campaign(worker,output,config,timeout=300)
 try:
  rows=campaign.run(profile,'mqtt_to_wamp',5,5000,200,.5,1)
  output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
  print(json.dumps(dict(campaign=name,peaks=[r['processes']['broker']['peak_rss_bytes'] for r in rows])),flush=True)
 finally:campaign.close()
 raw=output/'heaptrack.raw'
 if raw.exists():
  interpreted=output/'heaptrack.gz'
  with raw.open('rb') as source,subprocess.Popen([os.environ['HEAPTRACK_INTERPRET']],stdin=source,stdout=subprocess.PIPE) as child,gzip.open(interpreted,'wb') as target:
   while data:=child.stdout.read(1048576):target.write(data)
   assert child.wait()==0,'heaptrack interpretation failed'
  result=subprocess.run(['heaptrack_print',str(interpreted),'--print-overall-allocated','--print-peaks','--print-allocators','--peak-limit','25','--sub-peak-limit','5'],capture_output=True,text=True,check=True)
  output.joinpath('allocation-report.txt').write_text(result.stdout+'\n'+result.stderr)
  with raw.open('rb') as source,gzip.open(output/'heaptrack.raw.gz','wb') as target:
   while data:=source.read(1048576):target.write(data)
  raw.unlink()

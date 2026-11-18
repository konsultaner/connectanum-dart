"""Diagnostic-only cold-cycle RSS/heap observation; no performance verdict."""
import json, os, platform, subprocess
from pathlib import Path
import run_mqtt_gateway_benchmark as bench

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/dart314-rss-probe'
OUT.mkdir(parents=True,exist_ok=False)
assert not os.environ.get('DART_VM_OPTIONS'), 'Default VM options required'
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
profile=next(p for p in bench.profiles('release') if p['id']=='ws-3.1.1-msgpack-65536-4-1')
metadata={'diagnostic_only':True,'system':platform.platform(),'page_size':os.sysconf('SC_PAGESIZE'),'cpus':os.cpu_count(),'affinity':sorted(os.sched_getaffinity(0)),'source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'sdk':subprocess.check_output(['dart','--version'],text=True).strip(),'normal_vm_options':os.environ.get('DART_VM_OPTIONS')}
OUT.joinpath('environment.json').write_text(json.dumps(metadata,indent=2))
workers={'normal':bench.compile_worker(OUT/'normal-worker'),'heap':bench.compile_worker(OUT/'heap-worker','test/support/ci_heap_worker.dart')}
for index,label in enumerate(['normal','heap','normal','heap','normal','heap','normal','heap'],1):
 output=OUT/f'{index}-{label}'
 output.mkdir()
 config={**profile,'path':'mqtt_to_wamp','port':0,'native_library':str(library),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
 campaign=bench.Campaign(workers[label],output,config,load_timeout=300)
 try:
  rows=campaign.run(profile,'mqtt_to_wamp',5,5000,200,.5,1)
  output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
  for row in rows:print(json.dumps({'campaign':index,'worker':label,'cycle':row['run'],'broker':row['processes']['broker'],'queues':row['queues']}),flush=True)
 finally:campaign.close()

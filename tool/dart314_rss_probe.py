"""Diagnostic-only cold-cycle RSS/heap observation; no performance verdict."""
import json, os, platform, subprocess, hashlib
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
paths=[ROOT/'packages/connectanum_router/lib/src/router/router_instance'/name for name in ['router_worker.dart','router_boss.dart']]
candidate={p:p.read_bytes() for p in paths}
try:
 for path in paths:
  path.write_bytes(subprocess.check_output(['git','show',f'4de24d255b5e7c24dbbd9a5bdfe49bf792dcb57b:{path.relative_to(ROOT)}']))
 workers={'baseline':bench.compile_worker(OUT/'baseline-worker')}
finally:
 for path,data in candidate.items():path.write_bytes(data)
workers['candidate']=bench.compile_worker(OUT/'candidate-worker')
OUT.joinpath('candidate-source-sha256.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(data).hexdigest() for p,data in candidate.items()},indent=2))
for index,label in enumerate(['baseline','candidate']*4,1):
 output=OUT/f'{index}-{label}'
 output.mkdir()
 config={**profile,'path':'mqtt_to_wamp','port':0,'native_library':str(library),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
 campaign=bench.Campaign(workers[label],output,config,load_timeout=300)
 campaign.env['RSS_PROBE_DIR']=str(output)
 campaign.env['RSS_PROBE_LIB']=str(ROOT/'out/probe-heap/libprobe.so')
 try:
  rows=campaign.run(profile,'mqtt_to_wamp',5,5000,200,.5,1)
  output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
  for row in rows:print(json.dumps({'campaign':index,'worker':label,'cycle':row['run'],'broker':row['processes']['broker'],'queues':row['queues']}),flush=True)
 finally:campaign.close()

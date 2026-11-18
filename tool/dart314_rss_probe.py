"""Diagnostic-only paired overload ownership comparison; numeric gates unchanged."""
import json,os,platform,subprocess,hashlib
from pathlib import Path
import run_mqtt_gateway_benchmark as bench
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/dart314-rss-probe'
OUT.mkdir(parents=True,exist_ok=False)
assert not os.environ.get('DART_VM_OPTIONS'),'Default VM options required'
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
profile=dict(id='overload-tcp',transport='tcp',mqtt_version='5',serializer='cbor',payload_bytes=65536,subscribers=2,window=16,mqtt_client='connectanum')
metadata=dict(diagnostic_only=True,candidate='external-mqtt-frame-body',source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),baseline='f3798ef45fd9bb746b55fcb2d66cc47c39299f58',system=platform.platform(),sdk=subprocess.check_output(['dart','--version'],text=True).strip(),normal_vm_options=os.environ.get('DART_VM_OPTIONS'),runs=3,messages=2048,stall_ms=20000,drain_seconds=.5)
OUT.joinpath('environment.json').write_text(json.dumps(metadata,indent=2))
paths=[ROOT/'packages/connectanum_core/lib/src/mqtt/frame_codec.dart',ROOT/'packages/connectanum_router/lib/src/native/runtime.dart']
candidate={p:p.read_bytes() for p in paths}
try:
 for path in paths:path.write_bytes(subprocess.check_output(['git','show',f'f3798ef45fd9bb746b55fcb2d66cc47c39299f58:{path.relative_to(ROOT)}']))
 workers={'baseline':bench.compile_worker(OUT/'baseline-worker')}
 workers['baseline-heap']=bench.compile_worker(OUT/'baseline-heap-worker','test/support/ci_heap_worker.dart')
finally:
 for path,data in candidate.items():path.write_bytes(data)
workers['candidate']=bench.compile_worker(OUT/'candidate-worker')
workers['candidate-heap']=bench.compile_worker(OUT/'candidate-heap-worker','test/support/ci_heap_worker.dart')
OUT.joinpath('candidate-source-sha256.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(data).hexdigest() for p,data in candidate.items()},indent=2))
for index,label in enumerate(['baseline','candidate']*4+['baseline-heap','candidate-heap'],1):
 output=OUT/f'{index}-{label}';output.mkdir()
 config={**profile,'path':'mqtt_to_wamp','port':0,'native_library':str(library),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
 campaign=bench.Campaign(workers[label],output,config,timeout=90)
 try:
  rows=campaign.run_overload(profile,'mqtt_to_wamp',3,2048,20000,.5)
  output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
  for row in rows:print(json.dumps(dict(campaign=index,worker=label,cycle=row['run'],broker=row['processes']['broker'],queues=row['queues'])),flush=True)
 finally:campaign.close()

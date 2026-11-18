"""Read-only GC attribution. Instrumented runs never qualify numeric gates."""
import hashlib,json,os,subprocess
from pathlib import Path
import run_mqtt_gateway_benchmark as bench
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/dart314-gc-probe';OUT.mkdir(parents=True,exist_ok=False)
FLAGS='--verbose_gc,--timeline_streams=GC,--timeline_recorder=file'
profile=dict(id='tcp-5-cbor-65536-1-1',transport='tcp',mqtt_version='5',serializer='cbor',payload_bytes=65536,subscribers=1,window=1,mqtt_client='connectanum')
versions={'managed':'c7abfdef0ec63e5913cfa0ce67d53286f1ce2180','mapped':'207cfff1dd4598381a1dc11dbadbbf1518135d2d','heap':None}
libraries={'managed':ROOT/'out/probe-c7/probe-candidate/libct_ffi.so','mapped':ROOT/'out/probe-baseline/probe-candidate/libct_ffi.so','heap':ROOT/'out/probe-candidate/libct_ffi.so'}
paths=[ROOT/'packages/connectanum_core/lib/src/mqtt/frame_codec.dart',ROOT/'packages/connectanum_router/lib/src/native/runtime.dart',ROOT/'packages/connectanum_router/lib/src/router/router_instance.dart',*[ROOT/'packages/connectanum_router/lib/src/router/router_instance'/n for n in ['router_worker.dart','router_boss.dart','router_internal_session.dart']],ROOT/'packages/connectanum_router/lib/src/native/mqtt_frame_buffer.dart']
original={p:p.read_bytes() for p in paths};workers={}
for label,version in versions.items():
 try:
  if version:
   for p in paths:p.write_bytes(subprocess.check_output(['git','show',f'{version}:{p.relative_to(ROOT)}']))
  workers[label]=bench.compile_worker(OUT/f'{label}-worker')
 finally:
  for p,data in original.items():p.write_bytes(data)
metadata=dict(observation_only=True,source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),vm_options=FLAGS,heap_options_changed=False,forced_gc=False,versions=versions,native_sha256={k:hashlib.sha256(p.read_bytes()).hexdigest() for k,p in libraries.items()},workload=dict(runs=5,messages=5000,warmup=200,warmup_seconds=1,drain_seconds=.5))
OUT.joinpath('environment.json').write_text(json.dumps(metadata,indent=2))
original_init=bench.Child.__init__
def observed_init(self,label,command,events,output,env):
 if label=='broker':env={**env,'DART_VM_OPTIONS':FLAGS}
 return original_init(self,label,command,events,output,env)
bench.Child.__init__=observed_init
for index,label in enumerate(['managed','mapped','heap','heap','mapped','managed'],1):
 output=OUT/f'{index}-{label}';output.mkdir();os.chdir(output)
 config={**profile,'path':'mqtt_to_wamp','port':0,'native_library':str(libraries[label]),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
 campaign=bench.Campaign(workers[label],output,config,timeout=300)
 try:
  rows=campaign.run(profile,'mqtt_to_wamp',5,5000,200,.5,1)
  output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
  for row in rows:print(json.dumps(dict(variant=label,cycle=row['run'],p99_us=row['p99_us'],broker=row['processes']['broker'])),flush=True)
 finally:campaign.close();os.chdir(ROOT)
 trace=output/'dart-timeline.json'
 if not trace.exists():raise RuntimeError(f'No GC timeline for {label}')
 print(json.dumps(dict(variant=label,timeline_bytes=trace.stat().st_size)),flush=True)

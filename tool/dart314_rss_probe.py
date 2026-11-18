"""Diagnostic-only paired overload ownership comparison; numeric gates unchanged."""
import json,os,platform,subprocess,hashlib,threading,time
from pathlib import Path
import run_mqtt_gateway_benchmark as bench
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/dart314-rss-probe'
OUT.mkdir(parents=True,exist_ok=False)
assert not os.environ.get('DART_VM_OPTIONS'),'Default VM options required'
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
profile=dict(id='tcp-5-cbor-65536-1-1',transport='tcp',mqtt_version='5',serializer='cbor',payload_bytes=65536,subscribers=1,window=1,mqtt_client='connectanum')
overload=dict(id='overload-tcp',transport='tcp',mqtt_version='5',serializer='cbor',payload_bytes=65536,subscribers=2,window=16,mqtt_client='connectanum')
metadata=dict(diagnostic_only=True,candidate='managed-snapshots-plus-portable-mapped-native-input',source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),baseline='711e5d32ac4363ac287655830d475c5a13b862b7',system=platform.platform(),sdk=subprocess.check_output(['dart','--version'],text=True).strip(),normal_vm_options=os.environ.get('DART_VM_OPTIONS'),runs=5,messages=5000,warmup=200,warmup_seconds=1,drain_seconds=.5)
OUT.joinpath('environment.json').write_text(json.dumps(metadata,indent=2))
candidate_library=Path(os.environ['RSS_PROBE_CANDIDATE_LIB']).resolve()
OUT.joinpath('allocator-sha256.json').write_text(json.dumps(dict(baseline_binary=hashlib.sha256(library.read_bytes()).hexdigest(),candidate_binary=hashlib.sha256(candidate_library.read_bytes()).hexdigest()),indent=2))
paths=[ROOT/'packages/connectanum_core/lib/src/mqtt/frame_codec.dart',ROOT/'packages/connectanum_router/lib/src/native/runtime.dart',ROOT/'packages/connectanum_router/lib/src/router/router_instance.dart',*[ROOT/'packages/connectanum_router/lib/src/router/router_instance'/n for n in ['router_worker.dart','router_boss.dart','router_internal_session.dart']]]
candidate={p:p.read_bytes() for p in paths}
extra=[ROOT/name for name in ['packages/connectanum_router/lib/src/native/mqtt_frame_buffer.dart','native/transport/ct_ffi/Cargo.toml','native/transport/ct_ffi/src/runtime/mod.rs','native/transport/ct_ffi/src/runtime/mapped_bytes.rs']]
candidate.update({p:p.read_bytes() for p in extra})
try:
 for path in paths:path.write_bytes(subprocess.check_output(['git','show',f'711e5d32ac4363ac287655830d475c5a13b862b7:{path.relative_to(ROOT)}']))
 workers={'baseline':bench.compile_worker(OUT/'baseline-worker')}
finally:
 for path,data in candidate.items():path.write_bytes(data)
workers['candidate']=bench.compile_worker(OUT/'candidate-worker')
OUT.joinpath('candidate-source-sha256.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(data).hexdigest() for p,data in candidate.items()},indent=2))
for kind,selected,repetitions in [('normal',profile,8),('overload',overload,2)]:
 for index,label in enumerate(['baseline','candidate']*repetitions,1):
  output=OUT/f'{kind}-{index}-{label}';output.mkdir()
  config={**selected,'path':'mqtt_to_wamp','port':0,'native_library':str(candidate_library if label=='candidate' else library),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
  campaign=bench.Campaign(workers[label],output,config,timeout=90 if kind=='overload' else 300)
  try:
   rows=campaign.run_overload(selected,'mqtt_to_wamp',3,2048,20000,.5) if kind=='overload' else campaign.run(selected,'mqtt_to_wamp',5,5000,200,.5,1)
   output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
   for row in rows:print(json.dumps(dict(kind=kind,campaign=index,worker=label,cycle=row['run'],broker=row['processes']['broker'],queues=row['queues'])),flush=True)
  finally:campaign.close()

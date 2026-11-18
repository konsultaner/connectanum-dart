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
metadata=dict(diagnostic_only=True,candidate='read-only-normal-CBOR-heap-and-OS-observation',source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),baseline='2bd89a33d14c0980d808ecbb4b0ded46e2c3bd8f',system=platform.platform(),sdk=subprocess.check_output(['dart','--version'],text=True).strip(),normal_vm_options=os.environ.get('DART_VM_OPTIONS'),runs=5,messages=5000,warmup=200,warmup_seconds=1,drain_seconds=.5)
OUT.joinpath('environment.json').write_text(json.dumps(metadata,indent=2))
paths=[ROOT/'packages/connectanum_core/lib/src/mqtt/frame_codec.dart',ROOT/'packages/connectanum_router/lib/src/native/runtime.dart',ROOT/'packages/connectanum_router/lib/src/router/router_instance.dart',*[ROOT/'packages/connectanum_router/lib/src/router/router_instance'/n for n in ['router_worker.dart','router_boss.dart','router_internal_session.dart']]]
source={p:p.read_bytes() for p in paths}
workers={'normal':bench.compile_worker(OUT/'normal-worker'),'heap':bench.compile_worker(OUT/'heap-worker','test/support/ci_heap_worker.dart')}
OUT.joinpath('candidate-source-sha256.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(data).hexdigest() for p,data in source.items()},indent=2))
for index,label in enumerate(['normal','heap']*4,1):
 output=OUT/f'{index}-{label}';output.mkdir()
 config={**profile,'path':'mqtt_to_wamp','port':0,'native_library':str(library),'paho_python':os.environ['PAHO_PYTHON'],'mosquitto':'mosquitto','diagnostic_only':True,'certificate':str(bench.reference.TLS_CERT),'ca_certificate':str(bench.reference.TLS_CA),'key':str(bench.reference.TLS_KEY)}
 campaign=bench.Campaign(workers[label],output,config,timeout=300)
 stopped=threading.Event()
 def monitor():
  with (output/'os-memory.jsonl').open('w') as log:
   while not stopped.is_set():
    broker=campaign.children.get('broker')
    if broker:
     try:
      readings={}
      for name,pid in [('broker',broker.measurement_pid),('controller',os.getpid())]:
       status=Path(f'/proc/{pid}/status').read_text()
       readings[name]={line.split(':')[0]:line.split(':')[1].strip() for line in status.splitlines() if line.startswith(('VmRSS:','VmHWM:','VmData:','VmStk:','VmSwap:','Threads:'))}
      log.write(json.dumps(dict(time=time.time(),pid=broker.measurement_pid,**readings))+'\n');log.flush()
     except (OSError,ValueError):pass
    stopped.wait(.05)
 thread=threading.Thread(target=monitor,daemon=True);thread.start()
 try:
  rows=campaign.run(profile,'mqtt_to_wamp',5,5000,200,.5,1)
  output.joinpath('rows.json').write_text(json.dumps(rows,indent=2))
  for row in rows:print(json.dumps(dict(campaign=index,worker=label,cycle=row['run'],broker=row['processes']['broker'],queues=row['queues'])),flush=True)
 finally:
  try:campaign.close()
  finally:stopped.set();thread.join(timeout=5)

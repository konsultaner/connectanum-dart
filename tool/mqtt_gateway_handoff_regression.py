"""Diagnostic slow-peer regression; no performance acceptance from single runs."""
import hashlib,json,os,subprocess,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
root=gate.ROOT/'out/mqtt-handoff-regression';root.mkdir(parents=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
metadata=dict(diagnostic_only=True,qualification_scope='WSS slow-peer functionality only; four single cycles, not numeric release evidence',source_commit=source,normal_vm_options=None,native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest())
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
with tempfile.TemporaryDirectory() as temp:
 temp=Path(temp)
 workers=[gate.compile_worker(temp/'normal'),gate.compile_retention_worker(temp/'retention',root/'retention-self-test.json')]
 profile=gate.overload_profiles()[1]
 samples=[]
 for stress in [False,True]:
  for direction in gate.DIRECTIONS:
   output=root/('retention' if stress else 'normal')/profile['id']/direction
   output.mkdir(parents=True)
   config=dict(profile,path=direction,port=0,native_library=str(library),paho_python=os.environ['PAHO_PYTHON'],certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
   if stress:config['retention_protocol']=gate.RETENTION_PROTOCOL
   campaign=gate.Campaign(workers[int(stress)],output,config,timeout=90)
   try:rows=campaign.run_overload(profile,direction,1,2048,20000,.5,retention=stress)
   finally:campaign.close()
   assert len(rows)==1
   row=rows[0]
   assert row['sent']==row['received']==2048 and row['duplicates']==0
   assert row['load_disconnects']==1 and row['slow_disconnected'] and row['recovery_received']==64
   gate.check_publications(row['queues'],direction,2112)
   gate.check_publications(row['recovery_queues'],direction,2176)
   for process in row['processes'].values():gate.check_memory(process)
   if stress:assert row['memory_protocol']==gate.RETENTION_PROTOCOL
   samples.append(dict(retention=stress,direction=direction,received=row['received'],recovery=row['recovery_received']))
   print('Exact WSS slow-peer and recovery cycle passed',stress,direction,flush=True)
(root/'verified.json').write_text(json.dumps(dict(**metadata,passed=True,samples=samples),indent=2)+'\n')

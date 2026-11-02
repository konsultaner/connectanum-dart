"""Diagnostic only: unchanged default workload, no collection or tuning."""
import hashlib,json,os,platform,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
repository=gate.ROOT
root=repository/'out/mqtt-heap-attribution';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repository,text=True).strip()
metadata=dict(diagnostic_only=True,scope='same-source-normal-vs-heap-metrics-ABBA-no-GC',normal_vm_options=None,source_commit=source,native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256())
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
with tempfile.TemporaryDirectory() as temporary:
    temporary=Path(temporary)
    workers={name:gate.compile_worker(temporary/name,target) for name,target in [('normal','bin/mqtt_gateway_worker.dart'),('observed','test/support/mqtt_gateway_heap_attribution.dart')]}
    metadata['workers']={name:hashlib.sha256(worker.read_bytes()).hexdigest() for name,worker in workers.items()}
    (root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
    for pair in range(2):
        for variant in (['normal','observed'] if pair==0 else ['observed','normal']):
            cases=[(next(p for p in gate.profiles('release') if p['id']=='tcp-3.1.1-flatbuffers-65536-4-1'),'mqtt_to_wamp',False),(gate.overload_profiles()[1],'wamp_to_mqtt',True)]
            for profile,path,overload in cases:
                directory=root/variant/f'pair-{pair+1}'/profile['id']/path;directory.mkdir(parents=True)
                config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
                campaign=gate.Campaign(workers[variant],directory,config,timeout=90,load_timeout=300)
                try:
                    rows=campaign.run_overload(profile,path,3,2048,20000,.5) if overload else campaign.run(profile,path,5,5000,200,.5,1)
                finally:campaign.close()
                print(json.dumps(dict(variant=variant,pair=pair+1,profile=profile['id'],path=path,samples=len(rows),processes=gate.process_summary(rows))),flush=True)

"""Diagnostic only: preserve default-VM overload workload and trim native idle caches."""
import hashlib,json,os,platform,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
(root/'environment.json').write_text(json.dumps(dict(diagnostic_only=True,normal_vm_options=None,source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256()),indent=2)+'\n')
profile=next(p for p in gate.overload_profiles() if p['id']=='overload-wss');path='mqtt_to_wamp'
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    normal=gate.compile_worker(Path(temporary)/'normal')
    trimmed=gate.compile_worker(Path(temporary)/'trim','test/support/mqtt_gateway_trim_probe.dart')
    for mode,worker in [('default',normal),('idle_native_trim',trimmed)]:
        directory=root/mode;directory.mkdir()
        config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
        campaign=gate.Campaign(worker,directory,config,timeout=90)
        try:rows=campaign.run_overload(profile,path,3,2048,20000,.5)
        finally:campaign.close()
        report=dict(mode=mode,processes=gate.process_summary(rows),rows=rows)
        reports.append(report);print(json.dumps(report),flush=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')

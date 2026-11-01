"""Diagnostic only: isolate nursery size from explicit collection overhead."""
import hashlib,json,os,platform,subprocess,sys,tempfile,time
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
metadata=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256(),native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),diagnostic_only=True)
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
profile=next(p for p in gate.profiles('release') if p['id']=='tls-5-cbor-1024-4-1')
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    normal=gate.compile_worker(Path(temporary)/'normal')
    stress=gate.compile_retention_worker(Path(temporary)/'retention',root/'retention-self-test.json')
    for mode,worker,bounded,collected in [('default',normal,False,False),('bounded_only',normal,True,False),('bounded_collected',stress,True,True)]:
        directory=root/mode;directory.mkdir()
        config=dict(profile,path='wamp_to_mqtt',port=0,native_library=str(library),paho_python=sys.executable,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
        if bounded:config['retention_protocol']=gate.RETENTION_PROTOCOL
        campaign=gate.Campaign(worker,directory,config,load_timeout=300)
        try:rows=campaign.run(profile,'wamp_to_mqtt',1,300,300,.5,1,retention=collected)
        finally:campaign.close()
        report=dict(mode=mode,rows=rows)
        reports.append(report);print(json.dumps(report),flush=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')

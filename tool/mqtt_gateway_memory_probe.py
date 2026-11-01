"""Diagnostic only: preserve complete cold and workload-sized warm-up lifecycles."""
import hashlib,json,os,platform,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
profile=next(p for p in gate.profiles('release') if p['id']=='tcp-5-cbor-65536-1-1')
metadata=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256(),
    native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),profile=profile,runs=10,messages=5000)
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
with tempfile.TemporaryDirectory() as temporary:
    worker=gate.compile_worker(Path(temporary))
    for warm in [200,5000]:
        directory=root/f'warm-{warm}';directory.mkdir(exist_ok=False)
        config=dict(profile,path='mqtt_to_wamp',port=0,native_library=str(library),paho_python=sys.executable,
            mosquitto='not-used',diagnostic_only=True,certificate=str(gate.reference.TLS_CERT),
            ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
        campaign=gate.Campaign(worker,directory,config,load_timeout=300)
        try:rows=campaign.run(profile,'mqtt_to_wamp',10,5000,warm,.5,1)
        finally:campaign.close()
        print('WARMUP',warm,flush=True)
        for row in rows:
            p=row['processes']['broker']
            print(json.dumps(dict(run=row['run'],warm_messages=row['warmup_messages'],
                warm_mib=p['warm_rss_bytes']/1048576,peak_mib=p['peak_rss_bytes']/1048576,
                drained_mib=p['drained_rss_bytes']/1048576,received=row['received'],duplicates=row['duplicates'])),flush=True)

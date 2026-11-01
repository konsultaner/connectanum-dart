"""Diagnostic only: complete workload-sized warm-up and extended lifecycle traces."""
import hashlib,json,os,platform,statistics,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
budgets=json.loads((gate.ROOT/'tool/mqtt_gateway_arm64_benchmark_budgets.json').read_text())
metadata=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),architecture=platform.machine(),
    logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256(),native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest())
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
cases=[('tls-5-flatbuffers-65536-1-16','mqtt_to_wamp'),('tls-3.1.1-json-65536-4-16-paho','mqtt_to_wamp')]
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    worker=gate.compile_retention_worker(Path(temporary),root/'retention-self-test.json')
    for profile_id,path in cases:
        profile=next(p for p in gate.profiles('release') if p['id']==profile_id)
        directory=root/profile_id/path;directory.mkdir(parents=True,exist_ok=False)
        config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,mosquitto='not-used',
            diagnostic_only=True,retention_protocol='collected_rss_v1',certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
        campaign=gate.Campaign(worker,directory,config,load_timeout=300)
        try:rows=campaign.run(profile,path,5,5000,5000,.5,1,retention=True)
        finally:campaign.close()
        limit=budgets['profiles'][profile_id][path];processes=gate.process_summary(rows)
        drains=[r['processes']['broker']['drained_rss_bytes'] for r in rows]
        checks=dict(peak_rss=max(r['processes']['broker']['peak_rss_bytes'] for r in rows)<=limit['max_peak_rss_bytes'],
            drained_rss=max(drains)<=limit['max_drained_rss_bytes'],
            retained_growth=max(0,max(drains)-drains[0])<=limit['max_retained_growth_bytes'],
            lifecycle_slope=max(0,statistics.linear_regression(range(len(drains)),drains).slope)<=limit['max_rss_growth_bytes_per_cycle'])
        for name,process in processes.items():
            role='subscriber' if name.startswith('subscriber') else name
            for field in ['peak_rss_bytes','drained_rss_bytes','retained_bytes','cpu_seconds_per_million_messages']:
                checks[name+'_'+field]=process[field]<=limit['processes'][role]['max_'+field]
        report=dict(profile=profile_id,path=path,checks=checks,processes=processes,drains_mib=[v/1048576 for v in drains])
        reports.append(report);print(json.dumps(report),flush=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')
raise SystemExit(int(not all(all(r['checks'].values()) for r in reports)))

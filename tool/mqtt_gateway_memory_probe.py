"""Diagnostic only: isolate nursery size from explicit collection overhead."""
import hashlib,json,os,platform,subprocess,sys,tempfile,time
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
metadata=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256(),native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),diagnostic_only=True)
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
cases=[('tls-5-cbor-1024-4-1','wamp_to_mqtt'),('tls-5-flatbuffers-65536-1-16','mqtt_to_wamp'),('tls-3.1.1-json-65536-4-16-paho','mqtt_to_wamp')]
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    worker=gate.compile_retention_worker(Path(temporary)/'retention',root/'retention-self-test.json')
    budgets=json.loads((gate.ROOT/'tool/mqtt_gateway_arm64_benchmark_budgets.json').read_text())
    for profile_id,path in cases:
        profile=next(p for p in gate.profiles('release') if p['id']==profile_id)
        directory=root/profile_id/path;directory.mkdir(parents=True)
        config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,retention_protocol=gate.RETENTION_PROTOCOL,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
        campaign=gate.Campaign(worker,directory,config,load_timeout=300)
        try:rows=campaign.run(profile,path,5,5000,5000,.5,1,retention=True)
        finally:campaign.close()
        processes=gate.process_summary(rows);drains=[row['processes']['broker']['drained_rss_bytes'] for row in rows]
        limit=budgets['profiles'][profile_id][path]
        growth=max(0,max(drains)-drains[0])
        import statistics
        slope=max(0,statistics.linear_regression(range(len(drains)),drains).slope)
        checks=dict(retained_growth=growth<=limit['max_retained_growth_bytes'],lifecycle_slope=slope<=limit['max_rss_growth_bytes_per_cycle'])
        for role,process in processes.items():
            budget_role='subscriber' if role.startswith('subscriber') else role
            checks[role+'_retained_bytes']=process['retained_bytes']<=limit['processes'][budget_role]['max_retained_bytes']
        report=dict(profile=profile_id,path=path,processes=processes,retained_growth_bytes=growth,rss_growth_bytes_per_cycle=slope,checks=checks,passed=all(checks.values()),load_seconds=[row['duration_seconds'] for row in rows])
        reports.append(report);print(json.dumps(report),flush=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')
raise SystemExit(int(not all(row['passed'] for row in reports)))

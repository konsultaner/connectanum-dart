"""Diagnostic qualification: default VM, unchanged overload rate/latency/absolute RSS."""
import hashlib,json,os,platform,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
metadata=dict(diagnostic_only=True,scope='default_overload_performance_and_absolute_rss_only',normal_vm_options=None,source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256())
(root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
budgets=json.loads((gate.ROOT/'tool/mqtt_gateway_arm64_benchmark_budgets.json').read_text())
gate.check_hardware(budgets,dict(metadata,cpu_model=platform.processor() or platform.machine()),gate.profiles('release'))
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    worker=gate.compile_worker(Path(temporary),'test/support/mqtt_gateway_heap_probe.dart')
    profile=next(p for p in gate.profiles('release') if p['id']=='tls-3.1.1-json-65536-4-16')
    path='mqtt_to_wamp'
    directory=root/profile['id']/path;directory.mkdir(parents=True)
    config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
    campaign=gate.Campaign(worker,directory,config,load_timeout=300)
    try:rows=campaign.run(profile,path,5,5000,200,.5,1)
    finally:campaign.close()
    process=gate.process_summary(rows)
    limit=budgets['profiles'][profile['id']][path]
    checks={role:values['drained_rss_bytes']<=limit['processes']['subscriber' if role.startswith('subscriber-') else role]['max_drained_rss_bytes'] for role,values in process.items()}
    report=dict(profile=profile['id'],direction=path,processes=process,absolute_drained_rss_checks=checks,default_metrics_passed=all(checks.values()))
    reports.append(report);print(json.dumps(report),flush=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')
raise SystemExit(int(not all(x['default_metrics_passed'] for x in reports)))

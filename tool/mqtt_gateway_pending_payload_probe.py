"""Same-host diagnostic: fixed default-VM overload, every sample retained."""
import hashlib,json,os,platform,statistics,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
repository=gate.ROOT
root=repository/'out/mqtt-pending-payload-pair';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
baseline='afb342df55be9fbaf19070f2515e428daaab160f'
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repository,text=True).strip()
metadata=dict(diagnostic_only=True,scope='paired_bidirectional_wss_default_overload_performance_and_absolute_rss_only',normal_vm_options=None,source_commit=source,baseline_source=baseline,native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256())
metadata['candidate_runtime_source']='efd6bb5feec01e2cbf7e9e52d7abc844497a2a38'
budgets=json.loads((repository/'tool/mqtt_gateway_arm64_benchmark_budgets.json').read_text())
gate.check_hardware(budgets,dict(metadata,cpu_model=platform.processor() or platform.machine()),gate.profiles('release'))
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    temporary=Path(temporary)
    baseline_root=temporary/'baseline-source'
    subprocess.run(['git','fetch','--depth=1','origin',baseline],cwd=repository,check=True)
    subprocess.run(['git','worktree','add','--detach',str(baseline_root),baseline],cwd=repository,check=True)
    subprocess.run(['dart','pub','get'],cwd=baseline_root,check=True)
    workers={}
    try:
        gate.ROOT=baseline_root
        workers['baseline']=gate.compile_worker(temporary/'baseline-worker','bin/mqtt_gateway_worker.dart')
    finally:
        gate.ROOT=repository
    workers['candidate']=gate.compile_worker(temporary/'candidate-worker','bin/mqtt_gateway_worker.dart')
    metadata['workers']={variant:dict(sha256=hashlib.sha256(worker.read_bytes()).hexdigest(),source_commit=baseline if variant=='baseline' else source) for variant,worker in workers.items()}
    (root/'environment.json').write_text(json.dumps(metadata,indent=2)+'\n')
    profile=gate.overload_profiles()[1]
    for pair in range(2):
        for variant in (['baseline','candidate'] if pair==0 else ['candidate','baseline']):
            for path in gate.DIRECTIONS:
                directory=root/variant/f'pair-{pair+1}'/profile['id']/path;directory.mkdir(parents=True)
                config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
                campaign=gate.Campaign(workers[variant],directory,config,timeout=90)
                try:rows=campaign.run_overload(profile,path,3,2048,20000,.5)
                finally:campaign.close()
                report=dict(variant=variant,pair=pair+1,profile=profile['id'],direction=path,delivered_per_sec=statistics.median(x['delivered_per_sec'] for x in rows),p99_us=statistics.median(x['p99_us'] for x in rows),retained_growth_bytes=max(0,max(x['processes']['broker']['drained_rss_bytes'] for x in rows)-rows[0]['processes']['broker']['drained_rss_bytes']),processes=gate.process_summary(rows))
                all_checks=gate.overload_checks(report,budgets['overload'][profile['id']][path])
                checks={key:value for key,value in all_checks.items() if 'retained' not in key and 'retention' not in key}
                report.update(default_metrics_checks=checks,default_metrics_passed=all(checks.values()),raw_retention_checks={key:value for key,value in all_checks.items() if 'retained' in key})
                reports.append(report);print(json.dumps(report),flush=True)
    subprocess.run(['git','worktree','remove','--force',str(baseline_root)],cwd=repository,check=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')
raise SystemExit(int(not all(x['default_metrics_passed'] for x in reports if x['variant']=='candidate')))

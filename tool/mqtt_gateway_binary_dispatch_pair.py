"""Same-host diagnostic: fixed default-VM FlatBuffers fanout, every sample retained."""
import hashlib,json,os,platform,statistics,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
repository=gate.ROOT
root=repository/'out/mqtt-binary-dispatch-pair';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
baseline='6d48d9b9bb39abe6d068b664aaf15f34f2d3ca46'
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repository,text=True).strip()
metadata=dict(diagnostic_only=True,scope='paired_flatbuffers_mqtt_to_wamp_default_performance_and_absolute_rss_only',normal_vm_options=None,source_commit=source,baseline_source=baseline,native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256())
metadata['candidate_runtime_source']='6017c83e37a19a40b71c2cd94fbc7173e29e6217'
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
    profile=next(p for p in gate.profiles('release') if p['id']=='tcp-3.1.1-flatbuffers-65536-4-1')
    for pair in range(2):
        for variant in (['baseline','candidate'] if pair==0 else ['candidate','baseline']):
            for path in ('mqtt_to_wamp',):
                directory=root/variant/f'pair-{pair+1}'/profile['id']/path;directory.mkdir(parents=True)
                config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
                campaign=gate.Campaign(workers[variant],directory,config,timeout=90)
                try:rows=campaign.run(profile,path,5,5000,200,.5,1)
                finally:campaign.close()
                report=dict(variant=variant,pair=pair+1,profile=profile['id'],direction=path,delivered_per_sec=statistics.median(x['delivered_per_sec'] for x in rows),p99_us=statistics.median(x['p99_us'] for x in rows),retained_growth_bytes=max(0,max(x['processes']['broker']['drained_rss_bytes'] for x in rows)-rows[0]['processes']['broker']['drained_rss_bytes']),processes=gate.process_summary(rows))
                limits=budgets['profiles'][profile['id']][path]
                checks=dict(absolute_throughput=report['delivered_per_sec']>=limits['min_delivered_per_sec'],absolute_p99=report['p99_us']<=limits['max_p99_us'])
                for role,process in report['processes'].items():
                    bound=limits['processes']['subscriber' if role.startswith('subscriber-') else role]
                    for field in ('peak_rss_bytes','drained_rss_bytes','cpu_seconds_per_million_messages'):
                        checks[f'{role}_{field}']=process[field]<=bound['max_'+field]
                report.update(default_metrics_checks=checks,default_metrics_passed=all(checks.values()),scope='Default-runtime causal comparison only; no matched-control, retention or full-matrix qualification')
                reports.append(report);print(json.dumps(report),flush=True)
    subprocess.run(['git','worktree','remove','--force',str(baseline_root)],cwd=repository,check=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')
raise SystemExit(int(not all(x['default_metrics_passed'] for x in reports if x['variant']=='candidate')))

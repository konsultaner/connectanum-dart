"""Diagnostic only: default teardown, one yield, no-op FFI and native trimming."""
import hashlib,json,os,platform,subprocess,sys,tempfile
from pathlib import Path
import run_mqtt_gateway_benchmark as gate
assert not os.environ.get('DART_VM_OPTIONS')
root=gate.ROOT/'out/mqtt-memory-probe';root.mkdir(parents=True,exist_ok=True)
library=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
(root/'environment.json').write_text(json.dumps(dict(diagnostic_only=True,normal_vm_options=None,source_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),native_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),architecture=platform.machine(),logical_cpus=os.cpu_count(),cpu_signature_sha256=gate.cpu_signature_sha256()),indent=2)+'\n')
class IdleCampaign(gate.Campaign):
    def spawn(self,label,role):
        child=super().spawn(label,role)
        if label=='broker':
            send=child.send
            def idle(command):
                if command['op']=='sample' and set(self.children)=={'broker'}:command=dict(command,op='collect')
                send(command)
            child.send=idle
        return child
    def event(self,*args,**kwargs):
        label,message=super().event(*args,**kwargs)
        if label=='broker' and message['kind']=='collected':message=dict(message,kind='sampled')
        return label,message
profile=next(p for p in gate.overload_profiles() if p['id']=='overload-wss');path='mqtt_to_wamp'
reports=[]
with tempfile.TemporaryDirectory() as temporary:
    normal=gate.compile_worker(Path(temporary)/'normal')
    yielded=gate.compile_worker(Path(temporary)/'yield','test/support/mqtt_gateway_yield_probe.dart')
    probe=gate.compile_worker(Path(temporary)/'probe','test/support/mqtt_gateway_trim_probe.dart')
    for mode,worker in [('default',normal),('yield',yielded),('noop',probe),('trim',probe)]:
        directory=root/mode;directory.mkdir()
        config=dict(profile,path=path,port=0,native_library=str(library),paho_python=sys.executable,allocator_probe_mode=mode,certificate=str(gate.reference.TLS_CERT),ca_certificate=str(gate.reference.TLS_CA),key=str(gate.reference.TLS_KEY))
        campaign=(IdleCampaign if mode in ('noop','trim') else gate.Campaign)(worker,directory,config,timeout=90)
        try:rows=campaign.run_overload(profile,path,3,2048,20000,.5)
        finally:campaign.close()
        report=dict(mode=mode,processes=gate.process_summary(rows),rows=rows)
        reports.append(report);print(json.dumps(report),flush=True)
(root/'checks.json').write_text(json.dumps(reports,indent=2)+'\n')

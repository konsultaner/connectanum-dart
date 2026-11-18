"""Unchanged strict 64-KiB MQTT gate, alternating old/new input allocators."""
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/dart314-qos-probe';OUT.mkdir(parents=True,exist_ok=False)
assert not os.environ.get('DART_VM_OPTIONS')
paths=[ROOT/'packages/connectanum_router/lib/src/native'/n for n in ['runtime.dart','mqtt_frame_buffer.dart']]
original={p:p.read_bytes() for p in paths};baseline='669a7bc81fd964fa6df4ed0847340120f7213756'
OUT.joinpath('environment.json').write_text(json.dumps(dict(baseline=baseline,candidate=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),vm_options=os.environ.get('DART_VM_OPTIONS'),native_sha256=hashlib.sha256(Path(os.environ['RSS_PROBE_CANDIDATE_LIB']).read_bytes()).hexdigest(),source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(v).hexdigest() for p,v in original.items()}),indent=2))
for index,label in enumerate(['baseline','candidate','candidate','baseline'],1):
 try:
  if label=='baseline':
   for p in paths:p.write_bytes(subprocess.check_output(['git','show',f'{baseline}:{p.relative_to(ROOT)}']))
  output=OUT/f'{index}-{label}'
  env={**os.environ,'CONNECTANUM_NATIVE_LIB':os.environ['RSS_PROBE_CANDIDATE_LIB']}
  done=subprocess.run([sys.executable,'tool/run_mqtt_benchmark_gate.py','--native-router','--budget','tool/mqtt_native_64k_sustained_benchmark_budget.json','--output',str(output)],cwd=ROOT,env=env,text=True,capture_output=True,timeout=300)
  OUT.joinpath(f'{index}-{label}.stdout.log').write_text(done.stdout);OUT.joinpath(f'{index}-{label}.stderr.log').write_text(done.stderr)
  if not output.joinpath('summary.json').exists():raise RuntimeError(f'No summary: {done.returncode}: {done.stderr[-3000:]}')
  summary=json.loads(output.joinpath('summary.json').read_text());print(json.dumps(dict(label=label,campaign=index,exit_code=done.returncode,summary=summary)),flush=True)
 finally:
  for p,v in original.items():p.write_bytes(v)

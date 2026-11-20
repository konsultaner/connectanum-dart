"""Unqualified CPU profiles; canonical workloads and compiler defaults unchanged."""
from pathlib import Path
import hashlib,json,os,subprocess,time
root=Path.cwd();out=root/'out/wamp-profile-diagnostics';out.mkdir(parents=True,exist_ok=True)
lib=Path(os.environ['CONNECTANUM_NATIVE_LIB']).resolve()
worker_dir=out/'profile-worker'
with (out/'worker-build.log').open('w') as log:
 subprocess.run(['dart','build','cli','--target','bin/wamp_client_worker.dart','--output',str(worker_dir)],cwd=root/'packages/connectanum_bench',stdout=log,stderr=subprocess.STDOUT,check=True)
worker=worker_dir/'bundle/bin/wamp_client_worker'
bench=root/'native/bench/target/release/http_stream'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source_files=[p for p in root.glob('packages/*/lib/**/*.dart')]+[p for p in root.glob('native/transport/ct_*/src/**/*.rs')]
source_hashes={str(p.relative_to(root)):sha(p) for p in source_files}
(out/'source-hashes.json').write_text(json.dumps(source_hashes,indent=2)+'\n')
chosen={
 'wamp_websocket_fragmentation_throughput':['websocket_tls_pubsub_json_4m_native_contiguous','websocket_tls_pubsub_json_4m_native_fragmented_4k','websocket_tls_pubsub_cbor_4m_native_contiguous','websocket_tls_pubsub_cbor_4m_native_fragmented_4k'],
 'wamp_large_rawsocket_frames_heavy':['rawsocket_rpc_json_256m_native','rawsocket_rpc_cbor_256m_native'],
 'wamp_file_transfer_throughput':['websocket_file_json_64m_dart_buffered'],
}
scenarios=[]
for name,names in chosen.items():
 original=root/'native/bench/scenarios'/f'{name}.toml'
 parts=original.read_text().split('[[workloads]]')
 blocks=[p for p in parts[1:] if any('name = "'+n+'"' in p for n in names)]
 assert len(blocks)==len(names)
 subset=out/(name+'.toml');subset.write_text(parts[0]+'[[workloads]]'+'[[workloads]]'.join(blocks))
 scenarios.append((name,original,subset))
inputs=[lib,bench,root/'native/bench/bench_router.json',*(p for p in worker_dir.rglob('*') if p.is_file()),*(p for _,original,subset in scenarios for p in [original,subset])]
frozen={str(p):sha(p) for p in inputs}
(out/'input-hashes.json').write_text(json.dumps(frozen,indent=2)+'\n')
for name,original,subset in scenarios:
 for profiled in [False,True]:
  label=name+('-gprofng' if profiled else '-plain');folder=out/label
  experiment=out/(name+'.er')
  command=[str(bench),'--native-lib',str(lib),'--scenario',str(subset),'--results',str(folder/'results.jsonl'),'--artifact-dir',str(folder),'--router-worker-counts','1','--native-runtime-thread-counts','1','--workload-timeout-ms','300000','--wamp-worker-executable',str(worker)]
  if profiled:command=['gprofng','collect','app','-p','10','-h','off','-F','on','-a','off','-o',str(experiment),*command]
  else:command=['/usr/bin/time','-v','-o',str(out/(name+'.time.txt')), *command]
  start=time.monotonic()
  with (out/(label+'.log')).open('w') as log:result=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode:raise subprocess.CalledProcessError(result.returncode,command)
  print(json.dumps({'scenario':name,'profiled':profiled,'elapsedSeconds':time.monotonic()-start}),flush=True)
  if profiled:
   for suffix,report in [('flat','-functions'),('callgraph','-calltree')]:
    with (out/(name+'.'+suffix+'.txt')).open('w') as log:subprocess.run(['gprofng','display','text','-limit','100',report,str(experiment)],stdout=log,stderr=subprocess.STDOUT,check=True)
assert frozen=={str(p):sha(p) for p in inputs}
assert source_hashes=={str(p.relative_to(root)):sha(p) for p in source_files}
print('Unqualified user-space sampling complete; workloads, bundles and sources stayed frozen.',flush=True)

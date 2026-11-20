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
perf=Path(os.environ['CONNECTANUM_PERF_EXECUTABLE'])
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
perf_available=True
for name,original,subset in scenarios:
 for profiled in [False,True]:
  if profiled and not perf_available:continue
  label=name+('-perf' if profiled else '-plain');folder=out/label
  command=[str(bench),'--native-lib',str(lib),'--scenario',str(subset),'--results',str(folder/'results.jsonl'),'--artifact-dir',str(folder),'--router-worker-counts','1','--native-runtime-thread-counts','1','--workload-timeout-ms','300000','--wamp-worker-executable',str(worker)]
  if profiled:command=[str(perf),'record','-e','cpu-clock:u','-F','99','--call-graph','dwarf,4096','-o',str(out/(name+'.perf.data')),'--',*command]
  else:command=['/usr/bin/time','-v','-o',str(out/(name+'.time.txt')), *command]
  start=time.monotonic()
  with (out/(label+'.log')).open('w') as log:result=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode:
   error=(out/(label+'.log')).read_text()
   if profiled and 'Failure to open event' in error and 'Access to performance monitoring' in error:
    perf_available=False
    (out/'profiling-limitations.txt').write_text('Kernel performance sampling is blocked for this runner. No kernel profile is qualified. All plain canonical workloads still run with original parameters.\n'+error)
    print('Kernel sampling blocked; continuing the original unqualified baseline workloads.',flush=True)
    continue
   raise subprocess.CalledProcessError(result.returncode,command)
  print(json.dumps({'scenario':name,'profiled':profiled,'elapsedSeconds':time.monotonic()-start}),flush=True)
  if profiled:
   for suffix,extra in [('flat',['--no-children','--sort','comm,dso,symbol']),('callgraph',[])]:
    with (out/(name+'.'+suffix+'.txt')).open('w') as log:subprocess.run([str(perf),'report','--stdio','--percent-limit','0.3','-i',str(out/(name+'.perf.data')),*extra],stdout=log,stderr=subprocess.STDOUT,check=True)
assert frozen=={str(p):sha(p) for p in inputs}
assert source_hashes=={str(p.relative_to(root)):sha(p) for p in source_files}
print('Unqualified baseline complete; perfAvailable='+str(perf_available)+'; workloads, bundles and sources stayed frozen.',flush=True)

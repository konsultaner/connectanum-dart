from pathlib import Path
import argparse,json,re,subprocess,sys
parser=argparse.ArgumentParser();parser.add_argument('--program',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);a=parser.parse_args()
output=a.output.resolve();output.mkdir(exist_ok=False,parents=True);tool=Path(__file__).parent
command=[sys.executable,str(tool/'supervise-tcp-probe.py'),'--root-observer',str(tool/'tcp-probe-lifecycle-smoke.py'),'--program',str(a.program),'--output',str(output/'supervised'),'--max-seconds','60','--',sys.executable,str(tool/'tcp-owner-dummy.py'),str(output/'fd-witness.json')]
result=subprocess.run(command,capture_output=True,text=True);(output/'driver.stdout.txt').write_text(result.stdout);(output/'driver.stderr.txt').write_text(result.stderr);assert result.returncode==0
root=json.loads((output/'supervised/root/result.json').read_text());wrapper=json.loads((output/'supervised/result.json').read_text());fd=json.loads((output/'fd-witness.json').read_text());assert root['passed'] and wrapper['passed']
text=(output/'supervised/root/trace.txt').read_text();stderr=(output/'supervised/root/trace.stderr.txt').read_text();assert stderr=='__BPFTRACE_NOTIFY_PROBES_ATTACHED\n'
connections=[list(map(int,line.split()[1:])) for line in text.splitlines() if line.startswith('TCP_CONNECT ')]
assert len(connections)==1 and len(connections[0])==9
stamp,pid,inode,netns,source,destination,local,remote,retval=connections[0]
assert pid==fd['pid']==wrapper['workload_pid'] and fd['uid']==fd['euid']==wrapper['supervisor_uid']!=0
assert inode==fd['inode'] and netns==fd['netns'] and source==destination==16777343 and retval==0
assert fd['local']==['127.0.0.1',local] and fd['remote']==['127.0.0.1',int.from_bytes(remote.to_bytes(2,'little'),'big')]==['127.0.0.1',8083]
assert root['ready_at_monotonic_ns']<=wrapper['ready_monotonic_ns']<=wrapper['workload_started_monotonic_ns']<=fd['started_monotonic_ns']<=stamp<=fd['observed_monotonic_ns']<fd['finished_monotonic_ns']<=root['finished_monotonic_ns']
assert fd['finished_monotonic_ns']-fd['observed_monotonic_ns']>=2_000_000_000
assert not re.search('lost |error:|warning:',text+stderr,re.I)
assert text.count('TCP_PRUNE_BEGIN\n')==text.count('TCP_PRUNE_END\n')==1
counter_rows=re.findall(r'@(connects|entries|exits|duplicates): (\d+)',text)
assert len(counter_rows)==4 and len({k for k,v in counter_rows})==4
counts={k:int(v) for k,v in counter_rows}
assert counts=={'connects':2,'entries':1,'exits':1,'duplicates':1}
proof={'passed':True,'actual_unprivileged_fd_inode_tuple_pid_and_namespace_match':True,'actual_connect_clock_between_dummy_start_and_fd_observation':True,'graceful_probe_cleanup':True,'root_program_sha256':root['program_sha256'],'scope':'Two-second TCP FD/owner mapping smoke only. No WAMP/prune cause/performance acceptance.'}
(output/'result.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps(proof))

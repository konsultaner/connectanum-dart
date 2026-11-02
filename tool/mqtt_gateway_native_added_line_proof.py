"""Build a source-pinned native added-line proof; validate before writing."""
from pathlib import Path
import gzip,hashlib,json,os,re,subprocess
repo=Path.cwd()
roots=[Path(os.environ['GATEWAY_NATIVE_CARGO']),Path(os.environ['GATEWAY_NATIVE_FFI'])]
assert json.loads((roots[1]/'collection.json').read_text())['complete']
scopes=[json.loads((p/'source-scopes.json').read_text()) for p in roots]
assert scopes[0]['inputHashes']==scopes[1]['inputHashes']
coverage=[]
for p in roots:
    cov={}; source=None
    for line in (p/'production.info').read_text().splitlines():
        if line.startswith('SF:'): source=line[3:];cov.setdefault(source,{})
        elif line.startswith('DA:'):
            n,c=map(int,line[3:].split(',')[:2]);cov[source][n]=max(cov[source].get(n,0),c)
    coverage.append(cov)
base='73d840c96661533befa44dd3b76d079698b09803'
diff=subprocess.check_output(['git','diff','--patience','--unified=0',base,'--','native/transport'],text=True)
added={}; name=None
for line in diff.splitlines():
    if line.startswith('+++ b/'):name=line[6:]
    elif line.startswith('@@'):
        m=re.match(r'@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@',line)
        if m:added.setdefault(name,set()).update(range(int(m[1]),int(m[1])+int(m[2] or 1)))
hashdata=lambda data:hashlib.sha256(data).hexdigest()
r=dict(schemaVersion=1,baseCommit=base,diffAlgorithm='git diff --patience --unified=0',scope='New executable production lines under native/transport; Rust production filter, union of Cargo unit and Dart FFI runtime counts. Tests/comments/non-executable lines excluded.',platform='Linux arm64 GNU',features=['ffi-test'],files={},reports={})
archives={}
for role,p in zip(['cargo-unit','dart-ffi'],roots):
    name=f'mqtt-native-added-line-coverage-ready-yield-{role}.info.gz'
    raw=(p/'production.info').read_bytes(); data=gzip.compress(raw,mtime=0);archives[name]=data
    r['reports'][role]=dict(file=name,sha256=hashdata(data),productionInfoSha256=hashdata(raw),sourceScopeSha256=hashdata((p/'source-scopes.json').read_bytes()))
for name,lines in added.items():
    a,b=[c.get(name,{}) for c in coverage]; executable=sorted(lines&(a.keys()|b.keys()))
    if not executable:continue
    digest=hashdata((repo/name).read_bytes())
    assert all(s['inputHashes'][name]==digest for s in scopes),name
    missing=[n for n in executable if max(a.get(n,0),b.get(n,0))==0]
    r['files'][name]=dict(sourceSha256=digest,addedLines=len(lines),executableAddedLines=executable,covered=len(executable)-len(missing),total=len(executable),uncoveredLines=missing,cargoCovered=sum(a.get(n,0)>0 for n in executable),ffiCovered=sum(b.get(n,0)>0 for n in executable))
r['covered']=sum(f['covered'] for f in r['files'].values());r['total']=sum(f['total'] for f in r['files'].values())
assert 'native/transport/ct_core/src/idle_allocator.rs' in r['files']
print(json.dumps({n:dict(covered=f['covered'],total=f['total'],uncovered=f['uncoveredLines']) for n,f in r['files'].items()},indent=2))
output=Path(os.environ.get('GATEWAY_NATIVE_OUTPUT','out/mqtt-gateway/native-current-proof-check'))
output.mkdir(parents=True,exist_ok=True)
(output/'proof.json').write_text(json.dumps(r,indent=2)+'\n')
assert r['covered']==r['total'], 'Uncovered native lines; source is not qualified'
if os.environ.get('GATEWAY_NATIVE_PUBLISH')=='1':
    destination=output
    for name,data in archives.items():
        temporary=destination/(name+'.tmp');temporary.write_bytes(data);temporary.replace(destination/name)
    temporary=destination/'mqtt-native-added-line-coverage-ready-yield.json.tmp'
    temporary.write_text(json.dumps(r,indent=2)+'\n');temporary.replace(destination/'mqtt-native-added-line-coverage-ready-yield.json')
print(f"Native MQTT added-line coverage: {r['covered']}/{r['total']}")

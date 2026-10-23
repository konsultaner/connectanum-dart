"""Linux-only two-second owned-FD witness; no WAMP workload."""
from pathlib import Path
import json,os,socket,sys,time
assert os.geteuid()!=0
started=time.monotonic_ns()
with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as listener:
 listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
 listener.bind(('127.0.0.1',8083));listener.listen(1)
 with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as client:
  client.connect(('127.0.0.1',8083))
  with listener.accept()[0] as peer:
   client.sendall(b'x');assert peer.recv(1)==b'x'
   peer.sendall(b'y');assert client.recv(1)==b'y'
   inode=os.fstat(client.fileno()).st_ino
   assert os.readlink('/proc/self/fd/'+str(client.fileno()))=='socket:['+str(inode)+']'
   record={'pid':os.getpid(),'uid':os.getuid(),'euid':os.geteuid(),'inode':inode,
           'local':list(client.getsockname()),'remote':list(client.getpeername()),
           'netns':os.stat('/proc/self/ns/net').st_ino,'started_monotonic_ns':started,
           'observed_monotonic_ns':time.monotonic_ns()}
   time.sleep(2)
   record['finished_monotonic_ns']=time.monotonic_ns()
Path(sys.argv[1]).write_text(json.dumps(record,indent=2)+'\n')

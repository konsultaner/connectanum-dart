"""Read TCP_INFO only for a verified owner's established IPv4 loopback sockets."""
import ipaddress
from pathlib import Path
import re
import subprocess
import tempfile

from wamp_stall_vm_services import identity_matches


def endpoint(value):
    if not re.fullmatch(r'[0-9A-Fa-f]{8}:[0-9A-Fa-f]{4}', value):
        raise ValueError('invalid proc IPv4 endpoint')
    address, port = value.split(':')
    address = ipaddress.IPv4Address(bytes.fromhex(address)[::-1])
    port = int(port, 16)
    if not address.is_loopback or not 0 < port < 65536:
        raise ValueError('TCP_INFO requires nonzero loopback endpoints')
    return str(address), port


def capture_tcp_info(target, sockets, application_ports, proc_root=Path('/proc')):
    """Socket counters are diagnostic, non-atomic and outside copy accounting."""
    result = {'scope': 'owned established IPv4 loopback application sockets only',
              'sockets': [], 'errors': []}
    ports = set(application_ports)
    if any(type(port) is not int or not 0 < port < 65536 for port in ports):
        raise ValueError('invalid application port')
    if not ports:
        return result
    if not identity_matches(target, proc_root):
        return {'error': 'owned process identity changed before TCP_INFO observation'}
    selected = 0
    for entry in sockets:
        if entry['family'] != 'tcp' or entry['state_hex'] != '01':
            continue
        try:
            local, remote = endpoint(entry['local_hex']), endpoint(entry['remote_hex'])
            if local[1] not in ports and remote[1] not in ports:
                continue
            if type(entry['inode']) is not int or entry['inode'] <= 0:
                raise ValueError('invalid socket inode')
            selected += 1
            if selected > 8:
                result['errors'].append({'error': 'socket limit reached'})
                break
            if not identity_matches(target, proc_root):
                return {'error': 'owned process identity changed during TCP_INFO observation'}
            local_text, remote_text = ':'.join(map(str, local)), ':'.join(map(str, remote))
            command = ['ss', '-H', '-O', '-n', '-t', '-4', '-i', '-m', '-e', '-o',
                       'state', 'established', 'src', local_text, 'dst', remote_text]
            # A file bounds retained output without unbounded pipe buffering.
            # No shell, process inventory, DNS, or socket-mutating ss options.
            with tempfile.TemporaryFile() as stream:
                completed = subprocess.run(command, stdout=stream, stderr=subprocess.DEVNULL,
                                           timeout=2, check=False)
                if completed.returncode:
                    raise ValueError('ss failed')
                stream.seek(0)
                raw = stream.read(16385)
            if len(raw) > 16384:
                raise ValueError('ss output exceeds diagnostic limit')
            text = raw.decode('ascii').strip()
            if not text:
                result.setdefault('unavailable', []).append({
                    'inode': entry['inode'], 'reason': 'socket closed or changed state before ss snapshot'})
                continue
            columns = text.split()
            # Some iproute2 versions omit State for a single-state filter.
            if columns and columns[0] == 'ESTAB':
                columns = columns[1:]
            if (len(text.splitlines()) != 1 or len(columns) < 4
                    or not all(value.isdigit() for value in columns[:2])
                    or columns[2:4] != [local_text, remote_text]
                    or re.findall(r'\bino:(\d+)\b', text) != [str(entry['inode'])]):
                raise ValueError('ss result does not match owned socket')
            result['sockets'].append({'inode': entry['inode'], 'local': local_text,
                                      'remote': remote_text, 'ss': text})
        except (OSError, ValueError, UnicodeError, subprocess.TimeoutExpired) as error:
            result['errors'].append({'inode': entry.get('inode'), 'error': type(error).__name__})
    if not identity_matches(target, proc_root):
        return {'error': 'owned process identity changed during TCP_INFO observation'}
    return result

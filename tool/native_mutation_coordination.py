#!/usr/bin/env python3
"""Coordinate machine-wide native mutation work with local model inference."""

from contextlib import contextmanager
import errno
import fcntl
import os
from pathlib import Path
import stat


LEASE_FD_ENV = 'CONNECTANUM_NATIVE_MUTATION_LEASE_FD'
LEASE_DIRECTORY = 'native-mutation-resources'
LEASE_FILENAME = 'machine.lock'


class ResourceLeaseError(RuntimeError):
    pass


def lease_path(environment=None):
    values = os.environ if environment is None else environment
    home = Path(values.get('CODEX_HOME') or Path.home() / '.codex').expanduser()
    return home / 'runlocks' / LEASE_DIRECTORY / LEASE_FILENAME


def _validate_directory(directory):
    try:
        info = directory.lstat()
    except OSError as error:
        raise ResourceLeaseError(
            f'native mutation resource-lease directory unavailable: {type(error).__name__}'
        ) from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise ResourceLeaseError('native mutation resource-lease directory must not be a symbolic link')
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise ResourceLeaseError('native mutation resource-lease directory must be private and user-owned')


def _prepare_directory(directory):
    try:
        directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    except OSError as error:
        raise ResourceLeaseError(
            f'native mutation resource-lease directory unavailable: {type(error).__name__}'
        ) from error
    _validate_directory(directory)


def _validate_file(fd, path):
    try:
        descriptor = os.fstat(fd)
        current = path.lstat()
    except OSError as error:
        raise ResourceLeaseError('native mutation resource-lease identity changed') from error
    if stat.S_ISLNK(current.st_mode):
        raise ResourceLeaseError('native mutation resource-lease path is a symbolic link')
    if not stat.S_ISREG(descriptor.st_mode) or not stat.S_ISREG(current.st_mode):
        raise ResourceLeaseError('native mutation resource lease must be a regular file')
    if descriptor.st_uid != os.getuid() or stat.S_IMODE(descriptor.st_mode) & 0o077:
        raise ResourceLeaseError('native mutation resource lease must be private and user-owned')
    if (descriptor.st_dev, descriptor.st_ino) != (current.st_dev, current.st_ino):
        raise ResourceLeaseError('native mutation resource-lease identity changed')


def _open_file(path):
    flags = os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        return os.open(path, flags | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        try:
            return os.open(path, flags)
        except OSError as error:
            if error.errno == errno.ELOOP:
                raise ResourceLeaseError(
                    'native mutation resource-lease path is a symbolic link'
                ) from error
            raise ResourceLeaseError(
                f'native mutation resource lease unavailable: {type(error).__name__}'
            ) from error
    except OSError as error:
        if error.errno == errno.ELOOP:
            raise ResourceLeaseError('native mutation resource-lease path is a symbolic link') from error
        raise ResourceLeaseError(
            f'native mutation resource lease unavailable: {type(error).__name__}'
        ) from error


def _parse_inherited_fd(raw_fd):
    if not raw_fd.isascii() or not raw_fd.isdecimal():
        raise ResourceLeaseError('Invalid inherited native mutation resource-lease descriptor')
    return int(raw_fd)


def inherited_resource_lease_pass_fds(environment=None):
    values = os.environ if environment is None else environment
    raw_fd = values.get(LEASE_FD_ENV)
    if raw_fd is None:
        return ()
    fd = _parse_inherited_fd(raw_fd)
    path = lease_path(values)
    _validate_directory(path.parent)
    _validate_file(fd, path)
    return (fd,)


class ResourceLease:
    def __init__(self, fd, path, *, exclusive, inherited):
        self.fd = fd
        self.path = path
        self.exclusive = exclusive
        self.inherited = inherited
        self.closed = False

    @property
    def pass_fds(self):
        if not self.exclusive or self.closed:
            raise ResourceLeaseError('Only an active exclusive mutation lease can be inherited')
        return (self.fd,)

    def verify_identity(self):
        if self.closed:
            raise ResourceLeaseError('Native mutation resource lease is closed')
        _validate_directory(self.path.parent)
        _validate_file(self.fd, self.path)

    def child_environment(self, environment=None):
        if not self.exclusive:
            raise ResourceLeaseError('A shared local-inference lease cannot launch mutation work')
        self.verify_identity()
        values = dict(os.environ if environment is None else environment)
        values[LEASE_FD_ENV] = str(self.fd)
        return values

    def close(self):
        if self.closed:
            return
        try:
            if not self.inherited:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
        finally:
            os.close(self.fd)
            self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, _type, _value, _traceback):
        self.close()


def acquire_resource_lease(*, exclusive, environment=None):
    values = os.environ if environment is None else environment
    path = lease_path(values)
    _prepare_directory(path.parent)
    inherited = False
    raw_fd = values.get(LEASE_FD_ENV) if exclusive else None
    if raw_fd is not None:
        fd = _parse_inherited_fd(raw_fd)
        inherited = True
        try:
            _validate_file(fd, path)
        except BaseException:
            try:
                os.close(fd)
            except OSError:
                pass
            raise
    else:
        fd = _open_file(path)
        try:
            _validate_file(fd, path)
        except BaseException:
            os.close(fd)
            raise
    operation = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
    try:
        fcntl.flock(fd, operation | fcntl.LOCK_NB)
    except OSError as error:
        os.close(fd)
        if error.errno in (errno.EACCES, errno.EAGAIN):
            conflict = ('another local companion or native mutation campaign is active' if exclusive
                        else 'native mutation campaign is active')
            raise ResourceLeaseError(f'native mutation resource lease unavailable: {conflict}') from error
        raise ResourceLeaseError(
            f'native mutation resource lease unavailable: {type(error).__name__}'
        ) from error
    lease = ResourceLease(fd, path, exclusive=exclusive, inherited=inherited)
    try:
        lease.verify_identity()
    except BaseException:
        lease.close()
        raise
    return lease


@contextmanager
def resource_lease(*, exclusive, environment=None):
    lease = acquire_resource_lease(exclusive=exclusive, environment=environment)
    try:
        yield lease
    finally:
        lease.close()

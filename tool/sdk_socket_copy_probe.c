// Linux diagnostic only. This interposer changes short-write/EINTR behavior
// for one explicitly selected loopback port. Do not preload into other tasks.
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/socket.h>
#include <unistd.h>

typedef ssize_t (*write_fn)(int, const void *, size_t);
typedef struct {
  uintptr_t address;
  size_t requested, submitted;
  ssize_t accepted;
  int error;
} observation;
static write_fn real_write;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint16_t peer_port;
static size_t write_limit, used;
static int inject_eintr, overflow;
static observation observations[8192];

__attribute__((constructor)) static void init(void) {
  real_write = (write_fn)dlsym(RTLD_NEXT, "write");
  if (!real_write) _exit(120);
}

void probe_reset(uint16_t port, size_t limit, int interrupted) {
  pthread_mutex_lock(&lock);
  peer_port = port;
  write_limit = limit;
  inject_eintr = interrupted;
  used = 0;
  overflow = 0;
  pthread_mutex_unlock(&lock);
}

ssize_t write(int fd, const void *buffer, size_t count) {
  int previous_errno = errno;
  struct sockaddr_in peer;
  socklen_t length = sizeof(peer);
  pthread_mutex_lock(&lock);
  int selected = peer_port && getpeername(fd, (struct sockaddr *)&peer, &length) == 0
      && length == sizeof(peer) && peer.sin_family == AF_INET
      && ntohl(peer.sin_addr.s_addr) == INADDR_LOOPBACK
      && ntohs(peer.sin_port) == peer_port;
  errno = previous_errno;
  if (!selected) {
    pthread_mutex_unlock(&lock);
    return real_write(fd, buffer, count);
  }
  size_t submitted = write_limit && count > write_limit ? write_limit : count;
  ssize_t accepted;
  if (inject_eintr) {
    inject_eintr = 0;
    errno = EINTR;
    accepted = -1;
    submitted = 0;
  } else {
    accepted = real_write(fd, buffer, submitted);
  }
  int saved_errno = errno;
  if (used < 8192) {
    observations[used++] = (observation){(uintptr_t)buffer, count, submitted,
        accepted, accepted < 0 ? saved_errno : 0};
  } else {
    overflow = 1;
  }
  pthread_mutex_unlock(&lock);
  errno = saved_errno;
  return accepted;
}

size_t probe_count(void) { return used; }
int probe_overflow(void) { return overflow; }
uintptr_t probe_address(size_t index) { return observations[index].address; }
size_t probe_requested(size_t index) { return observations[index].requested; }
size_t probe_submitted(size_t index) { return observations[index].submitted; }
ssize_t probe_accepted(size_t index) { return observations[index].accepted; }
int probe_error(size_t index) { return observations[index].error; }

// Independent positive control: call the same interposed function from C.
ssize_t probe_control(uint16_t port, const void *buffer, size_t count) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  struct sockaddr_in peer = {.sin_family = AF_INET,
      .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
  if (connect(fd, (struct sockaddr *)&peer, sizeof(peer)) != 0) {
    close(fd);
    return -1;
  }
  ssize_t result = write(fd, buffer, count);
  close(fd);
  return result;
}

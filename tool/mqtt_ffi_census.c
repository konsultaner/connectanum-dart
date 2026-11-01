// Diagnostic only: count calls around an unchanged, explicitly linked native
// library. No payload access, delayed submission, retry or return-value change.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef int32_t (*poll_fn)(int32_t, uint8_t *, int32_t);
typedef int32_t (*send_fn)(int32_t, const uint8_t *, int32_t);
typedef void (*arm_fn)(void);
static poll_fn real_poll;
static send_fn real_send;
static arm_fn real_arm;
static const char *output_path;
static _Atomic uint64_t poll_calls, poll_empty, poll_errors, poll_positive;
static _Atomic uint64_t poll_bytes, send_calls, send_errors, send_bytes, arms;
static _Atomic uint64_t poll_sizes[9], send_sizes[9];
static const int32_t upper_bounds[9] = {64, 128, 256, 512, 1024, 4096,
                                       16384, 65536, INT32_MAX};

static void increment(_Atomic uint64_t *counter, uint64_t count) {
  atomic_fetch_add_explicit(counter, count, memory_order_relaxed);
}

static uint64_t load(_Atomic uint64_t *counter) {
  return atomic_load_explicit(counter, memory_order_relaxed);
}

static void size_count(_Atomic uint64_t *counters, int32_t length) {
  if (length <= 0) return;
  for (size_t index = 0; index < 9; index++) {
    if (length <= upper_bounds[index]) {
      increment(&counters[index], 1);
      return;
    }
  }
}

static void write_result(void) {
  int fd = open(output_path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  if (fd < 0) _exit(121);
  FILE *file = fdopen(fd, "w");
  if (!file) { close(fd); _exit(121); }
  int failed = fprintf(file,
      "{\"diagnostic_only\":true,\"poll_calls\":%" PRIu64
      ",\"poll_empty\":%" PRIu64 ",\"poll_errors\":%" PRIu64
      ",\"poll_positive\":%" PRIu64 ",\"poll_bytes\":%" PRIu64
      ",\"send_calls\":%" PRIu64 ",\"send_errors\":%" PRIu64
      ",\"send_requested_positive_bytes\":%" PRIu64
      ",\"arm_calls\":%" PRIu64 ",\"size_upper_bounds\":[",
      load(&poll_calls), load(&poll_empty), load(&poll_errors),
      load(&poll_positive), load(&poll_bytes), load(&send_calls),
      load(&send_errors), load(&send_bytes), load(&arms)) < 0;
  for (size_t index = 0; index < 9; index++)
    failed |= fprintf(file, "%s%d", index ? "," : "", upper_bounds[index]) < 0;
  failed |= fprintf(file, "],\"poll_sizes\":[") < 0;
  for (size_t index = 0; index < 9; index++)
    failed |= fprintf(file, "%s%" PRIu64, index ? "," : "", load(&poll_sizes[index])) < 0;
  failed |= fprintf(file, "],\"send_sizes\":[") < 0;
  for (size_t index = 0; index < 9; index++)
    failed |= fprintf(file, "%s%" PRIu64, index ? "," : "", load(&send_sizes[index])) < 0;
  failed |= fprintf(file, "]}\n") < 0;
  failed |= fclose(file) != 0;
  if (failed) _exit(121);
}

__attribute__((constructor)) static void initialise(void) {
  output_path = getenv("CONNECTANUM_MQTT_CENSUS_OUTPUT");
  if (!output_path || !*output_path) _exit(120);
  real_poll = (poll_fn)dlsym(RTLD_NEXT, "ct_poll_mqtt_chunk");
  real_send = (send_fn)dlsym(RTLD_NEXT, "ct_send_mqtt_chunk");
  real_arm = (arm_fn)dlsym(RTLD_NEXT, "ct_arm_message_ready_callback_v1");
  if (!real_poll || !real_send || !real_arm || atexit(write_result)) _exit(120);
}

int32_t ct_poll_mqtt_chunk(int32_t connection, uint8_t *output, int32_t capacity) {
  increment(&poll_calls, 1);
  int32_t result = real_poll(connection, output, capacity);
  int saved_errno = errno;
  if (result < 0) increment(&poll_errors, 1);
  else if (!result) increment(&poll_empty, 1);
  else {
    increment(&poll_positive, 1);
    increment(&poll_bytes, (uint64_t)result);
    size_count(poll_sizes, result);
  }
  errno = saved_errno;
  return result;
}

int32_t ct_send_mqtt_chunk(int32_t connection, const uint8_t *bytes, int32_t length) {
  increment(&send_calls, 1);
  if (length > 0) increment(&send_bytes, (uint64_t)length);
  size_count(send_sizes, length);
  int32_t result = real_send(connection, bytes, length);
  int saved_errno = errno;
  if (result < 0) increment(&send_errors, 1);
  errno = saved_errno;
  return result;
}

void ct_arm_message_ready_callback_v1(void) {
  increment(&arms, 1);
  real_arm();
}

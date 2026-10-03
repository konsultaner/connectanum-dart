// Fake database resource owned by a dedicated native producer thread.
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int32_t handle; const void *identity; } BufferToken;
typedef void (*Release)(void *);
typedef int32_t (*Create)(size_t, uint32_t);
typedef int32_t (*OwnerOp)(int32_t);
typedef int32_t (*OwnerCountOp)(int32_t, uint32_t);
typedef int32_t (*Register)(int32_t, const uint8_t *, size_t, size_t, size_t,
                            Release, void *, BufferToken *);

typedef struct {
  void *library;
  pthread_t thread;
  pthread_mutex_t mutex;
  pthread_cond_t ready;
  Create create;
  OwnerOp close_owner, destroy_owner;
  OwnerCountOp dispatch, wait;
  Register register_buffer;
  BufferToken token;
  uint8_t *bytes;
  int ready_flag, error, stop, stopped, released, wrong_thread;
} Actor;

static void release_resource(void *token) {
  Actor *actor = token;
  pthread_mutex_lock(&actor->mutex);
  if (!pthread_equal(pthread_self(), actor->thread)) actor->wrong_thread = 1;
  actor->released++;
  free(actor->bytes);
  actor->bytes = NULL;
  pthread_mutex_unlock(&actor->mutex);
}

static void *produce(void *argument) {
  Actor *actor = argument;
  int32_t owner = actor->create(5, 1);
  int error = owner > 0 ? 0 : owner;
  if (!error) {
    const uint8_t values[] = {42, 0, 255, 7, 8};
    actor->bytes = malloc(sizeof(values));
    if (!actor->bytes) error = -7;
    else {
      memcpy(actor->bytes, values, sizeof(values));
      error = actor->register_buffer(owner, actor->bytes, 5, 1, 3,
                                     release_resource, actor, &actor->token);
    }
  }
  if (error && owner > 0) {
    free(actor->bytes);
    actor->bytes = NULL;
    actor->close_owner(owner);
    actor->destroy_owner(owner);
  }
  pthread_mutex_lock(&actor->mutex);
  actor->error = error;
  actor->ready_flag = 1;
  pthread_cond_signal(&actor->ready);
  pthread_mutex_unlock(&actor->mutex);
  if (!error) {
    for (;;) {
      pthread_mutex_lock(&actor->mutex);
      int stop = actor->stop;
      pthread_mutex_unlock(&actor->mutex);
      if (stop) actor->close_owner(owner);
      actor->dispatch(owner, 16);
      if (stop && actor->destroy_owner(owner) == 0) break;
      actor->wait(owner, 20);
    }
  }
  pthread_mutex_lock(&actor->mutex);
  actor->stopped = 1;
  pthread_mutex_unlock(&actor->mutex);
  return NULL;
}

void *fixture_create(const char *native_library, BufferToken *out) {
  Actor *actor = calloc(1, sizeof(Actor));
  if (!actor) return NULL;
  actor->library = dlopen(native_library, RTLD_NOW | RTLD_LOCAL);
  if (!actor->library) { free(actor); return NULL; }
  actor->create = (Create)dlsym(actor->library, "ct_external_owner_create");
  actor->close_owner = (OwnerOp)dlsym(actor->library, "ct_external_owner_close");
  actor->destroy_owner = (OwnerOp)dlsym(actor->library, "ct_external_owner_destroy");
  actor->dispatch = (OwnerCountOp)dlsym(actor->library, "ct_external_owner_dispatch");
  actor->wait = (OwnerCountOp)dlsym(actor->library, "ct_external_owner_wait");
  actor->register_buffer = (Register)dlsym(actor->library, "ct_external_buffer_register");
  if (!actor->create || !actor->close_owner || !actor->destroy_owner ||
      !actor->dispatch || !actor->wait || !actor->register_buffer) {
    dlclose(actor->library); free(actor); return NULL;
  }
  pthread_mutex_init(&actor->mutex, NULL);
  pthread_cond_init(&actor->ready, NULL);
  if (pthread_create(&actor->thread, NULL, produce, actor)) {
    pthread_cond_destroy(&actor->ready);
    pthread_mutex_destroy(&actor->mutex);
    dlclose(actor->library); free(actor); return NULL;
  }
  pthread_mutex_lock(&actor->mutex);
  while (!actor->ready_flag) pthread_cond_wait(&actor->ready, &actor->mutex);
  int error = actor->error;
  *out = actor->token;
  pthread_mutex_unlock(&actor->mutex);
  if (error) {
    pthread_join(actor->thread, NULL);
    pthread_cond_destroy(&actor->ready);
    pthread_mutex_destroy(&actor->mutex);
    dlclose(actor->library); free(actor); return NULL;
  }
  return actor;
}

int32_t fixture_state(void *argument) {
  Actor *actor = argument;
  pthread_mutex_lock(&actor->mutex);
  int result = actor->released | (actor->wrong_thread ? 256 : 0) |
               (actor->stopped ? 512 : 0);
  pthread_mutex_unlock(&actor->mutex);
  return result;
}

void fixture_stop(void *argument) {
  Actor *actor = argument;
  pthread_mutex_lock(&actor->mutex);
  actor->stop = 1;
  pthread_mutex_unlock(&actor->mutex);
}

int32_t fixture_destroy(void *argument) {
  Actor *actor = argument;
  if (!(fixture_state(actor) & 512)) return -1;
  pthread_join(actor->thread, NULL);
  pthread_cond_destroy(&actor->ready);
  pthread_mutex_destroy(&actor->mutex);
  dlclose(actor->library);
  free(actor);
  return 0;
}

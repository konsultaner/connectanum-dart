#include <stdint.h>
#include <stddef.h>

// Complete symbol inventory with a configurable version. A supported fixture
// is used only to prove library identity rejection before submission. It never
// supplies allocations and must never receive the real library's handles.
#ifndef OWNED_BUFFER_VERSION
#define OWNED_BUFFER_VERSION 2
#endif
uint32_t ct_owned_buffer_abi_version(void) { return OWNED_BUFFER_VERSION; }
int32_t ct_owned_buffer_allocate(int32_t length) { (void)length; return -4; }
int32_t ct_owned_buffer_info(int32_t id, void *out) { (void)id; (void)out; return -4; }
int32_t ct_owned_buffer_freeze(int32_t id, size_t start, size_t length) { (void)id; (void)start; (void)length; return -4; }
int32_t ct_owned_buffer_slice(int32_t id, size_t start, size_t length) { (void)id; (void)start; (void)length; return -4; }
int32_t ct_owned_buffer_release(int32_t id) { (void)id; return -4; }
void ct_owned_buffer_handle_finalizer(void *token) { (void)token; }
int32_t ct_owned_buffer_export(int32_t id, void *out) { (void)id; (void)out; return -4; }
void ct_owned_buffer_view_finalizer(void *token) { (void)token; }
int32_t ct_owned_buffer_send(int32_t connection, int32_t id) { (void)connection; (void)id; return -4; }

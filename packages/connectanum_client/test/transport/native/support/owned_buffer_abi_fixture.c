#include <stdint.h>
#include <stddef.h>

// Complete symbol inventory with a configurable version. A supported fixture
// is used only to prove library identity rejection before submission. It never
// supplies allocations and must never receive the real library's handles.
#ifndef OWNED_BUFFER_VERSION
#define OWNED_BUFFER_VERSION 2
#endif

#ifdef WRITE_RECEIPT_VERSION
uint32_t ct_write_receipt_abi_version(void) { return WRITE_RECEIPT_VERSION; }
int32_t ct_owned_buffer_send_tracked(int32_t connection, int32_t id) { (void)connection; (void)id; return -4; }
int32_t ct_connection_drain_writes(int32_t connection) { (void)connection; return -4; }
int32_t ct_write_receipt_state(int32_t id) { (void)id; return -4; }
int32_t ct_write_receipt_release(int32_t id) { (void)id; return -4; }
#ifndef OMIT_WRITE_FINALIZER
void ct_write_receipt_finalizer(void *token) { (void)token; }
#endif
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

#ifdef OWNED_SEGMENTS_VERSION
uint32_t ct_owned_buffer_segments_abi_version(void) { return OWNED_SEGMENTS_VERSION; }
int32_t ct_owned_buffer_send_segments(const void *identity, int32_t connection, const int32_t *ids, size_t count) {
  (void)identity; (void)connection; (void)ids; (void)count; return -4;
}
#ifndef OMIT_SEGMENTS_TRACKED
int32_t ct_owned_buffer_send_segments_tracked(const void *identity, int32_t connection, const int32_t *ids, size_t count) {
  (void)identity; (void)connection; (void)ids; (void)count; return -4;
}
#endif
#endif

#ifdef EXTERNAL_LEASE_VERSION
uint32_t ct_external_lease_abi_version(void) { return EXTERNAL_LEASE_VERSION; }
const void *ct_external_buffer_store_identity(void) { return (const void *)&ct_owned_buffer_abi_version; }
int32_t ct_external_owner_create(size_t bytes, uint32_t count) { (void)bytes; (void)count; return -4; }
int32_t ct_external_owner_close(int32_t id) { (void)id; return -4; }
int32_t ct_external_owner_destroy(int32_t id) { (void)id; return -4; }
int32_t ct_external_owner_dispatch(int32_t id, uint32_t count) { (void)id; (void)count; return -4; }
int32_t ct_external_owner_wait(int32_t id, uint32_t timeout) { (void)id; (void)timeout; return -4; }
int32_t ct_external_owner_metrics(int32_t id, void *out) { (void)id; (void)out; return -4; }
int32_t ct_external_buffer_register(int32_t id, const uint8_t *base, size_t span,
                                  size_t offset, size_t length, void (*release)(void *),
                                  void *token, void *out) {
  (void)id; (void)base; (void)span; (void)offset; (void)length;
  (void)release; (void)token; (void)out; return -4;
}
#endif

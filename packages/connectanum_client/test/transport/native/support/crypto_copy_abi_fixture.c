#include <stdint.h>
#include <stdlib.h>

// Retain the real runtime dependency, which supplies mandatory older symbols.
extern int ct_start_runtime(void);
int keep_runtime_dependency(void) { return ct_start_runtime(); }

uint32_t ct_e2ee_copy_metrics_abi_version(void) { return 2; }

// An unknown layout must never be called with Dart's v1 allocation.
int ct_e2ee_copy_metrics_snapshot(void *out) {
  (void)out;
  abort();
}

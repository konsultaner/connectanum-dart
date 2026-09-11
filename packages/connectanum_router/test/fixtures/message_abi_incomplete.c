#include <stdint.h>

#ifndef ABI_VERSION
#define ABI_VERSION 1
#endif

uint32_t ct_message_handle_abi_version(void) { return ABI_VERSION; }

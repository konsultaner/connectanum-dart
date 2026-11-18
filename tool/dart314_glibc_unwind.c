// Diagnostic-only fallback: Ubuntu ARM libunwind stops before caller frames.
// Keep the system allocator; substitute glibc's verified stack unwinder only.
#include <execinfo.h>
extern int __backtrace(void **, int);
int unw_backtrace(void **frames, int count) {
    return __backtrace(frames, count);
}

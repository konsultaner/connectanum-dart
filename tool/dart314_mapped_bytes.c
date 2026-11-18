#include <stddef.h>
#include <stdint.h>
#include <sys/mman.h>

typedef union { size_t length; max_align_t alignment; } Header;
void *probe_mapped_allocate(size_t length) {
    if (length == 0 || length > SIZE_MAX - sizeof(Header)) return NULL;
    size_t total = length + sizeof(Header);
    Header *header = mmap(NULL, total, PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (header == MAP_FAILED) return NULL;
    header->length = total;
    return header + 1;
}
void probe_mapped_free(void *pointer) {
    if (pointer == NULL) return;
    Header *header = (Header *)pointer - 1;
    size_t length = header->length;
    munmap(header, length);
}

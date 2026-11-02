#include <stdint.h>
#include <stddef.h>
void fill_pattern(uint8_t *out, size_t n, uint64_t nonce) {
 for(size_t i=0;i<n;i++) {
  if(i<8) {out[i]=(uint8_t)(nonce>>(i*8));continue;}
  uint64_t x=nonce+(uint64_t)i*UINT64_C(0x9e3779b97f4a7c15);
  x=(x^(x>>30))*UINT64_C(0xbf58476d1ce4e5b9);
  x=(x^(x>>27))*UINT64_C(0x94d049bb133111eb);
  out[i]=(uint8_t)(x^(x>>31));
 }
}

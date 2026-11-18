#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
typedef void (*chunk_fn)(void*,uint8_t*,intptr_t,bool);
typedef char* (*snapshot_fn)(chunk_fn,void*);
static void chunk(void*ctx,uint8_t*data,intptr_t size,bool last){(void)last;fwrite(data,1,(size_t)size,(FILE*)ctx);free(data);}
int capture_heap(void*fn,const char*path){FILE*f=fopen(path,"wb");if(!f)return -1;char*error=((snapshot_fn)fn)(chunk,f);fclose(f);if(error){fprintf(stderr,"snapshot error: %s\n",error);free(error);return -2;}return 0;}

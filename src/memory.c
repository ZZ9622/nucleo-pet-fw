#include <stddef.h>
void *memcpy(void *destination, const void *source, size_t count);
void *memset(void *destination, int value, size_t count);
void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *d = destination;
    const unsigned char *s = source;
    for (size_t i=0; i<count; ++i) { d[i]=s[i]; }
    return destination;
}
void *memset(void *destination, int value, size_t count)
{
    unsigned char *d = destination;
    for (size_t i=0; i<count; ++i) { d[i]=(unsigned char)value; }
    return destination;
}

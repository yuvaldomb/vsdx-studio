#ifndef CZLIB_H
#define CZLIB_H

#include <stdint.h>

int cz_crc32(const unsigned char *data, int len);
int cz_deflate_raw(const unsigned char *src, int srcLen, unsigned char **dst, int *dstLen);
int cz_inflate_raw(const unsigned char *src, int srcLen, unsigned char *dst, int dstLen);

#endif

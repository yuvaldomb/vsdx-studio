#include "CZLib.h"
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

int cz_crc32(const unsigned char *data, int len) {
    unsigned long c = crc32(0L, Z_NULL, 0);
    c = crc32(c, data, (uInt)len);
    return (int)c;
}

int cz_deflate_raw(const unsigned char *src, int srcLen, unsigned char **dst, int *dstLen) {
    z_stream strm;
    int bound;
    unsigned char *buffer;
    int ret;
    memset(&strm, 0, sizeof(strm));
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return -1;
    }
    bound = deflateBound(&strm, (uLong)srcLen);
    if (bound < 64) bound = 64;
    buffer = (unsigned char *)malloc((size_t)bound);
    if (!buffer) {
        deflateEnd(&strm);
        return -1;
    }
    strm.next_in = (Bytef *)src;
    strm.avail_in = (uInt)srcLen;
    strm.next_out = buffer;
    strm.avail_out = (uInt)bound;
    ret = deflate(&strm, Z_FINISH);
    *dstLen = (int)strm.total_out;
    deflateEnd(&strm);
    if (ret != Z_STREAM_END) {
        free(buffer);
        return -1;
    }
    *dst = buffer;
    return 0;
}

int cz_inflate_raw(const unsigned char *src, int srcLen, unsigned char *dst, int dstLen) {
    z_stream strm;
    int ret;
    memset(&strm, 0, sizeof(strm));
    if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) return -1;
    strm.next_in = (Bytef *)src;
    strm.avail_in = (uInt)srcLen;
    strm.next_out = dst;
    strm.avail_out = (uInt)dstLen;
    ret = inflate(&strm, Z_FINISH);
    inflateEnd(&strm);
    if (ret != Z_STREAM_END) return -1;
    return (int)strm.total_out;
}

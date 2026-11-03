// Round trip: compress the fuzz input with a codec chosen by the first three bytes, decompress it
// and require the original back. Buffer sizes follow bench/lzbench.cpp (GET_COMPRESS_BOUND
// output; PAD_SIZE slack after the input and the decompressed data).
#include <stdio.h>
#include "lzbench_fuzz_common.h"

// A mismatch is a codec bug (lzbench itself reports "decompressed data differs"); name the codec so
// the defect is not mistaken for a harness precondition failing.
__attribute__((noinline, noreturn)) static void roundtrip_mismatch(const compressor_desc_t *desc, int level,
                                                                     size_t size, int64_t dlen)
{
    fprintf(stderr, "lzbench round trip mismatch: codec=%s level=%d size=%zu dlen=%lld (%s)\n", desc->name, level,
            size, (long long)dlen, dlen != (int64_t)size ? "decompressed length differs" : "memcmp differs");
    abort();
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 4)
        return -1;
    int level;
    const compressor_desc_t *desc = pick_codec(data, &level);
    if (!desc)
        return -1;
    // GLZA compresses text only: on arbitrary bytes GLZAformat/GLZAcompress read out of bounds and its own
    // output decodes to the wrong length (e.g. 00 00 69), so every input ends in one of its bugs.
    if (!strcmp(desc->name, "glza"))
        return -1;
    // lzma sizes its match finder from the level, not the input: level 7 asks for one 1.2 GB block and
    // levels 8-9 for 2.4 GB (over libFuzzer's 2 GB malloc limit) even for a 32 KB payload.
    if (!strcmp(desc->name, "lzma") && level > 6)
        return -1;
    data += 3;
    size -= 3;
    if (size > kMaxPayload)
        size = kMaxPayload;
    if (desc->max_input_size && size > desc->max_input_size)
        return -1;

    char *in = (char *)calloc(1, size + PAD_SIZE);
    size_t bound = GET_COMPRESS_BOUND(size);
    char *comp = (char *)malloc(bound + PAD_SIZE);
    char *out = (char *)calloc(1, size + PAD_SIZE);
    memcpy(in, data, size);

    codec_ctx ctx;
    if (codec_open(&ctx, desc, level, size)) {
        int64_t clen = desc->compress(in, size, comp, bound, &ctx.opt);
        if (clen > 0) {
            int64_t dlen = desc->decompress(comp, (size_t)clen, out, size, &ctx.opt);
            if (dlen != (int64_t)size || memcmp(in, out, size) != 0)
                roundtrip_mismatch(desc, level, size, dlen);
        }
        codec_close(&ctx);
    }
    free(in);
    free(comp);
    free(out);
    return 0;
}

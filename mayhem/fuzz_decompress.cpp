// Decompress arbitrary bytes with a codec chosen by the first three bytes (restricted to the decoders
// whose libraries are meant to take untrusted input; the legacy ones trust their stream by design). The next two bytes give
// the size of the output buffer the codec is told it may fill (lzbench passes the original chunk
// size there); the rest is the "compressed" stream, followed by PAD_SIZE bytes of slack as in lzbench's compbuf.
#include "lzbench_fuzz_common.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 6)
        return -1;
    static const char *const kUntrustedInput[] = {
        "brotli", "bzip2", "bzip3", "fastlzma2", "libdeflate", "lizard", "lz4", "lzfse", "lzma",
        "lzlib", "snappy", "xz", "zlib", "zlib-ng", "zstd", "lzvn", "lzg", "fastlz", "lzf",
    };
    const size_t nsafe = sizeof(kUntrustedInput) / sizeof(kUntrustedInput[0]);
    const compressor_desc_t *desc = NULL;
    for (int i = 0; i < LZBENCH_COMPRESSOR_COUNT && !desc; i++)
        if (!strcmp(comp_desc[i].name, kUntrustedInput[data[0] % nsafe]) && comp_desc[i].decompress)
            desc = &comp_desc[i];
    if (!desc)
        return -1;
    int level = desc->first_level + (data[1] | (data[2] << 8)) % (desc->last_level - desc->first_level + 1);
    size_t outsize = ((size_t)data[3] | ((size_t)data[4] << 8)) * 4 + 1;
    data += 5;
    size -= 5;
    if (size > kMaxPayload)
        size = kMaxPayload;

    // These two allocate from a size the stream declares, so a 13-byte header can ask for 2 GB (over
    // libFuzzer's malloc limit) even though the output is at most ~256 KB. Reject streams a lzbench
    // compressor could not have produced for an input this small, as the other decoders do themselves.
    if (!strcmp(desc->name, "bzip3")) {
        // bz3_decompress(): "BZ3v1", then the s32 block size; the compressor never exceeds
        // max(65 KB, bz3_bound(insize)) and insize <= outsize here.
        uint32_t block = size >= 13 ? (uint32_t)data[5] | (uint32_t)data[6] << 8 | (uint32_t)data[7] << 16 |
                                          (uint32_t)data[8] << 24
                                    : 0;
        if (block > outsize + outsize / 16 + 128 * 1024)
            return -1;
    }
    // lzma: first byte is the LZMA2 dictionary property; lzbench's levels stop at a 64 MB dictionary
    // (property 28), property 38 declares 2 GB.
    if (!strcmp(desc->name, "lzma") && size >= 1 && (uint8_t)data[0] > 28)
        return -1;

    char *in = (char *)calloc(1, size + PAD_SIZE);
    char *out = (char *)calloc(1, outsize + PAD_SIZE);
    memcpy(in, data, size);

    codec_ctx ctx;
    if (codec_open(&ctx, desc, level, outsize)) {
        desc->decompress(in, size, out, outsize, &ctx.opt);
        codec_close(&ctx);
    }
    free(in);
    free(out);
    return 0;
}

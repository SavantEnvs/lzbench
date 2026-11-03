// Shared by the lzbench codec harnesses: picks a codec/level out of lzbench's own
// comp_desc table (bench/lzbench.h) and calls it exactly as bench/lzbench.cpp does.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "bench/lzbench.h"

// Largest payload the harnesses hand to a codec: keeps every exec fast and the
// heap of the memory-hungry codecs (zpaq, lzham, brotli -d24, ...) bounded.
static const size_t kMaxPayload = 32 * 1024;

static const compressor_desc_t *pick_codec(const uint8_t *data, int *level) // data[0] = codec, data[1..2] = level
{
    const compressor_desc_t *desc = &comp_desc[data[0] % LZBENCH_COMPRESSOR_COUNT];
    if (!desc->compress || !desc->decompress)
        return NULL;
    int range = desc->last_level - desc->first_level + 1;
    *level = desc->first_level + (data[1] | (data[2] << 8)) % range;
    return desc;
}

struct codec_ctx
{
    const compressor_desc_t *desc;
    codec_options_t opt;
};

// Returns false when the codec could not be initialised (out of memory etc.).
static bool codec_open(codec_ctx *c, const compressor_desc_t *desc, int level, size_t insize)
{
    c->desc = desc;
    c->opt.level = level;
    c->opt.additional_param = desc->additional_param;
    c->opt.threads = 1;
    c->opt.work_mem = NULL;
    if (desc->init) {
        c->opt.work_mem = desc->init(insize, level, desc->additional_param);
        if (!c->opt.work_mem)
            return false;
    }
    return true;
}

static void codec_close(codec_ctx *c)
{
    if (c->desc->deinit && c->opt.work_mem)
        c->desc->deinit(c->opt.work_mem);
}

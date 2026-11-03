// Weak no-op coverage callbacks so the -standalone reproducers link when SANITIZER_FLAGS is empty
// (the library objects are always compiled with sanitizer-coverage); a real sanitizer runtime overrides them.
#include <stdint.h>
__attribute__((weak)) void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) { (void)start; (void)stop; }
__attribute__((weak)) void __sanitizer_cov_trace_pc_guard(uint32_t *guard) { (void)guard; }

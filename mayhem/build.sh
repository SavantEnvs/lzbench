#!/usr/bin/env bash
# Builds lzbench twice out of tree (sanitized + coverage-instrumented for the fuzzers, normal flags for
# test.sh) and links the libFuzzer harnesses plus their -standalone reproducers.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
M="$SRC/mayhem"
FUZZ="$M/build-fuzz"
TEST="$M/build-test"

# Checks that fire on lzbench's benign codec idioms (unaligned word loads, pointer-wrap bounds tests,
# shifts of the codec's own bit buffers, memcpy(NULL, 0), calls through casted function pointers, clz(0) in lizard).
# ASan and every other UBSan check stay halting.
RELAX="-fno-sanitize=alignment,pointer-overflow,shift,nonnull-attribute,function,builtin"

# 1) Sanitized, coverage-instrumented library objects. Every make runs from a fresh directory.
rm -rf "$FUZZ" "$TEST"
mkdir -p "$FUZZ" "$TEST"
cd "$FUZZ"
MK=(make -f "$SRC/Makefile" -j"$MAYHEM_JOBS" CC="$CC" CXX="$CXX")
BASEFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $RELAX -fsanitize=fuzzer-no-link"
# bzip3 relies on wrapping signed arithmetic and fast-lzma2 on a deliberate [-1] index: relax only those objects.
"${MK[@]}" MOREFLAGS="$BASEFLAGS -fno-sanitize=signed-integer-overflow" bwt/bzip3/src/libbz3.o
"${MK[@]}" MOREFLAGS="$BASEFLAGS -fno-sanitize=bounds" lz+entropy/fast-lzma2/lzma2_enc.o
# lzrw hashes with a signed multiply that overflows on purpose.
"${MK[@]}" MOREFLAGS="$BASEFLAGS -fno-sanitize=signed-integer-overflow" \
    lz/lzrw/lzrw1-a.o lz/lzrw/lzrw1.o lz/lzrw/lzrw2.o lz/lzrw/lzrw3.o lz/lzrw/lzrw3-a.o
"${MK[@]}" MOREFLAGS="$BASEFLAGS"

DEFS=$(sed 's/^codecs: //' bench/codecs.stamp)
# lzbench.objs is a single line holding every object; the harnesses bring their own main().
OBJS=$(tr ' ' '\n' < lzbench.objs | grep -v '^bench/lzbench\.o$' | tr '\n' ' ')

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$M/lsan_off.cc" -o lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$M/cov_stub.c" -o cov_stub.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o standalone_main.o

for h in fuzz_roundtrip fuzz_decompress; do
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $RELAX -O1 -I"$SRC" $DEFS $LIB_FUZZING_ENGINE \
      "$M/$h.cpp" $OBJS lsan_off.o -pthread -o "$SRC/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $RELAX -O1 -I"$SRC" $DEFS \
      "$M/$h.cpp" standalone_main.o $OBJS lsan_off.o cov_stub.o -pthread -o "$SRC/$h-standalone"
done

# 2) The program itself with its normal flags, for mayhem/test.sh.
cd "$TEST"
TMK=(env -u CFLAGS -u CXXFLAGS -u LDFLAGS make -f "$SRC/Makefile" -j"$MAYHEM_JOBS" CC="$CC" CXX="$CXX" MOREFLAGS="$COVERAGE_FLAGS")
# Without sanitizers clang-19 spends 30+ minutes (and 3.5 GB) optimizing this one AVX-512 file at any -O1 and
# above, so it is compiled unoptimized; the fuzz build above compiles it in under a second.
"${TMK[@]}" OPT_LEVEL=O0 lz+entropy/openzl/src/openzl/codecs/pivco_huffman/arch/encode_pivco_avx512.o
"${TMK[@]}" lzbench

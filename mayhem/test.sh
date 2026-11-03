#!/usr/bin/env bash
#
# Runs the lzbench binary that mayhem/build.sh built with its normal flags (mayhem/build-test/lzbench) over
# a fixed input and checks every codec's output: lzbench compresses, decompresses and compares the bytes
# itself (printing "ERROR" otherwise) and reports the compressed size. The codecs are vendored at fixed
# versions, so each size is deterministic; a program that does nothing, or a change to a codec that alters
# its stream, fails here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/mayhem/build-test/lzbench"
IN=mayhem/test/sample.txt
if [ ! -x "$BIN" ]; then
  echo "missing $BIN: mayhem/build.sh did not build it" >&2
  emit_ctrf lzbench-known-answer 0 1 0
  exit 1
fi

# "<-e selector>|<codec name prefix>|<expected compressed size>|<extra options>"
CASES=(
  "lz4|lz4 |10937|"
  "lz4hc,9|lz4hc |6799|"
  "lz4fast,5|lz4 |11216|"
  "zstd,3|zstd |5479|"
  "zstd,19|zstd |4640|"
  "zlib,6|zlib |5002|"
  "zlib-ng,6|zlib-ng |5035|"
  "libdeflate,6|libdeflate |5192|"
  "bzip2,5|bzip2 |3229|"
  "bzip3,5|bzip3 |3128|"
  "lzma,3|lzma |5385|"
  "xz,3|xz |5184|"
  "brotli,5|brotli |5376|"
  "snappy|snappy |8356|"
  "lzf,1|lzf |8661|"
  "lzfse|lzfse |5749|"
  "fastlz,2|fastlz |8718|"
  "lizard,20|lizard |10023|"
  "lzg,5|lzg |7573|"
  "quicklz,2|quicklz |8227|"
  "ppmd8,5|ppmd8 |3044|"
  "csc,3|csc |4983|"
  "zpaq,1|zpaq |7022|"
  "memcpy|memcpy|24002|"
  "lz4|lz4 |11523|-b4"
  "zstd,3|zstd |6438|-b4"
)

passed=0
failed=0
for c in "${CASES[@]}"; do
  IFS='|' read -r sel prefix want extra <<< "$c"
  out=$(timeout 300 "$BIN" -t0,0 -i1,1 -qq -o4 $extra -e"$sel" "$IN" 2>&1)
  got=$(printf '%s\n' "$out" | awk -F, -v p="$prefix" 'NR>1 && index($1,p)==1 {print $5; exit}')
  if printf '%s\n' "$out" | grep -q 'ERROR'; then
    echo "FAIL $sel $extra: lzbench reported an error"
    failed=$((failed + 1))
  elif [ "$got" = "$want" ]; then
    echo "ok   $sel $extra: $got bytes"
    passed=$((passed + 1))
  else
    echo "FAIL $sel $extra: compressed size '${got}' != expected $want"
    failed=$((failed + 1))
  fi
done

emit_ctrf lzbench-known-answer "$passed" "$failed" 0

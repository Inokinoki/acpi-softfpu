#!/usr/bin/env bash
set -euo pipefail

AML_FILE="${AML_FILE:-softfpu.aml}"
ACPIEXEC_BIN="${ACPIEXEC_BIN:-acpiexec}"

tests=0
failures=0

die() {
  echo "error: $*" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_file() {
  [[ -f "$1" ]] || die "missing required file: $1 (run: make softfpu.aml)"
}

u64_hex_upper() {
  # Normalize a hex string (no 0x, 16 hex chars).
  local x="${1#0x}"
  x="${x// /}"
  echo "${x^^}"
}

u32_to_u64hex() {
  # Print u32 as 16-hex-digit, zero-extended u64.
  local x="${1#0x}"
  printf "00000000%08X" "$((16#$x))"
}

extract_last_integer_u64hex() {
  local output="$1"
  local v=""
  while IFS= read -r line; do
    if [[ "$line" == "  [Integer] = "* ]]; then
      v="${line##* = }"
    fi
  done <<<"$output"
  v="$(u64_hex_upper "$v")"
  [[ -n "$v" ]] || return 1
  echo "$v"
}

run_acpiexec() {
  local cmd="$1"
  "$ACPIEXEC_BIN" -dt -b "$cmd" "$AML_FILE" 2>/dev/null || return 1
}

assert_u64hex_eq() {
  local expected="$1"
  local cmd="$2"
  local name="${3:-$cmd}"

  tests=$((tests + 1))
  echo "Running: $name"

  local out actual
  if ! out="$(run_acpiexec "$cmd")"; then
    failures=$((failures + 1))
    echo "FAIL: $name"
    echo "  acpiexec invocation failed"
    return 0
  fi

  if ! actual="$(extract_last_integer_u64hex "$out")"; then
    failures=$((failures + 1))
    echo "FAIL: $name"
    echo "  could not parse integer result"
    echo "$out" | tail -30
    return 0
  fi

  expected="$(u64_hex_upper "$expected")"
  if [[ "$actual" != "$expected" ]]; then
    failures=$((failures + 1))
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  got:      $actual"
    return 0
  fi

  echo "PASS: $name"
}

assert_u32hex_eq() {
  local expected_u32="$1"
  local cmd="$2"
  local name="${3:-$cmd}"
  assert_u64hex_eq "$(u32_to_u64hex "$expected_u32")" "$cmd" "$name"
}

assert_true() {
  local cmd="$1"
  local name="${2:-$cmd}"
  assert_u64hex_eq "FFFFFFFFFFFFFFFF" "$cmd" "$name"
}

assert_false() {
  local cmd="$1"
  local name="${2:-$cmd}"
  assert_u64hex_eq "0000000000000000" "$cmd" "$name"
}

get_u32hex_from_cmd() {
  local cmd="$1"
  local out u64
  out="$(run_acpiexec "$cmd")"
  u64="$(extract_last_integer_u64hex "$out")"
  # last 8 hex chars
  echo "${u64:8:8}"
}

assert_result_isnan() {
  local cmd="$1"
  local name="${2:-$cmd}"
  tests=$((tests + 1))
  echo "Running: $name (isnan)"
  local u32
  if ! u32="$(get_u32hex_from_cmd "$cmd")"; then
    failures=$((failures + 1))
    echo "FAIL: $name (isnan)"
    echo "  could not evaluate command"
    return 0
  fi
  local out actual
  out="$(run_acpiexec "exec \\SFPU\\ISNA 0x$u32")"
  actual="$(extract_last_integer_u64hex "$out")"
  if [[ "$actual" != "FFFFFFFFFFFFFFFF" ]]; then
    failures=$((failures + 1))
    echo "FAIL: $name (isnan)"
    echo "  expected result to be NaN"
    echo "  got bits: 0x$u32"
    return 0
  fi
  echo "PASS: $name (isnan)"
}

main() {
  require_cmd "$ACPIEXEC_BIN"
  require_file "$AML_FILE"

  # --- Construction / basic bit helpers ---
  assert_u32hex_eq "3EEF1AA0" "exec \\SFPU\\GENF 0 125 7281312" "GENF builds float bits"
  assert_u32hex_eq "3EEF1AA0" "exec \\SFPU\\FABS 0x3EEF1AA0" "FABS keeps positive"
  assert_u32hex_eq "3EEF1AA0" "exec \\SFPU\\FABS 0xBEEF1AA0" "FABS clears sign"
  assert_u32hex_eq "BEEF1AA0" "exec \\SFPU\\MTH3 0x3EEF1AA0" "MTH3 flips sign"
  assert_u32hex_eq "3EEF1AA0" "exec \\SFPU\\MTH3 0xBEEF1AA0" "MTH3 flips sign back"

  assert_true  "exec \\SFPU\\NEG 0xff800001" "NEG detects negative"
  assert_false "exec \\SFPU\\NEG 0x7f800001" "NEG detects positive"

  assert_u64hex_eq "000000000000007D" "exec \\SFPU\\EXP 0x3EEF1AA0" "EXP extracts exponent"
  assert_u64hex_eq "0000000000000000" "exec \\SFPU\\SIGN 0x3EEF1AA0" "SIGN extracts sign=0"
  assert_u64hex_eq "0000000000000001" "exec \\SFPU\\SIGN 0xBEEF1AA0" "SIGN extracts sign=1"
  assert_u64hex_eq "00000000006F1AA0" "exec \\SFPU\\FRAC 0x3EEF1AA0" "FRAC extracts fraction"

  # --- Classification ---
  assert_true  "exec \\SFPU\\INFI 0x7f800000" "INFI +inf"
  assert_true  "exec \\SFPU\\INFI 0xff800000" "INFI -inf"
  assert_false "exec \\SFPU\\INFI 0x7f800001" "INFI not inf (payload)"
  assert_true  "exec \\SFPU\\ISIN 0x7f800000" "ISIN +inf"
  assert_false "exec \\SFPU\\ISIN 0x7f800001" "ISIN not inf"

  assert_true  "exec \\SFPU\\ISZE 0x00000000" "ISZE +0"
  assert_true  "exec \\SFPU\\ISZE 0x80000000" "ISZE -0"
  assert_false "exec \\SFPU\\ISZE 0x3f800000" "ISZE not zero"

  assert_true  "exec \\SFPU\\ISNO 0x3f800000" "ISNO 1.0 is normal"
  assert_false "exec \\SFPU\\ISNO 0x00000000" "ISNO zero not normal"
  assert_false "exec \\SFPU\\ISNO 0x007FFFFF" "ISNO subnormal not normal"
  assert_false "exec \\SFPU\\ISNO 0x7f800000" "ISNO inf not normal"

  assert_true  "exec \\SFPU\\ISNA 0x7fc00000" "ISNA qNaN"
  assert_true  "exec \\SFPU\\ISNA 0x7f800001" "ISNA sNaN-ish payload"
  assert_false "exec \\SFPU\\ISNA 0x7f800000" "ISNA not NaN (inf)"
  assert_false "exec \\SFPU\\ISNA 0x3f800000" "ISNA not NaN (normal)"

  # --- Comparisons (note: NaN comparisons must return false) ---
  assert_true  "exec \\SFPU\\FEQL 0x00000000 0x80000000" "FEQL +0 == -0"
  assert_true  "exec \\SFPU\\FEQL 0x3f800000 0x3f800000" "FEQL 1 == 1"
  assert_false "exec \\SFPU\\FEQL 0x3f800000 0x40000000" "FEQL 1 != 2"
  assert_false "exec \\SFPU\\FEQL 0x7fc00000 0x3f800000" "FEQL NaN == x is false"

  assert_false "exec \\SFPU\\FNEQ 0x00000000 0x80000000" "FNEQ +0 != -0 is false"
  assert_true  "exec \\SFPU\\FNEQ 0x3f800000 0x40000000" "FNEQ 1 != 2"
  assert_false "exec \\SFPU\\FNEQ 0x7fc00000 0x3f800000" "FNEQ NaN != x is false"

  assert_true  "exec \\SFPU\\FLET 0xbf800000 0x3f800000" "FLET -1 < 1"
  assert_false "exec \\SFPU\\FLET 0x3f800000 0xbf800000" "FLET 1 < -1 is false"
  assert_true  "exec \\SFPU\\FLEQ 0x3f800000 0x3f800000" "FLEQ 1 <= 1"
  assert_true  "exec \\SFPU\\FGRT 0x40000000 0x3f800000" "FGRT 2 > 1"
  assert_true  "exec \\SFPU\\FGEQ 0x3f800000 0x3f800000" "FGEQ 1 >= 1"

  # --- Arithmetic ---
  # 0.1 + 0.2 = 0.3000000119... (float32: 0x3E99999A)
  assert_u32hex_eq "3E99999A" "exec \\SFPU\\FADD 0x3dcccccd 0x3e4ccccd" "FADD 0.1 + 0.2"
  # 0.3000000119... - 0.200000003... = 0.1000000089... (float32: 0x3DCCCCCE)
  assert_u32hex_eq "3DCCCCCE" "exec \\SFPU\\FSUB 0x3E99999A 0x3E4CCCCD" "FSUB 0.3 - 0.2"
  assert_u32hex_eq "40000000" "exec \\SFPU\\FMUL 0x3f800000 0x40000000" "FMUL 1 * 2"
  assert_u32hex_eq "3F000000" "exec \\SFPU\\FDIV 0x3f800000 0x40000000" "FDIV 1 / 2"

  # NaN propagation checks (payload may differ; assert NaN-ness)
  assert_result_isnan "exec \\SFPU\\FADD 0x7fc00001 0x3f800000" "FADD NaN + 1"
  assert_result_isnan "exec \\SFPU\\FMUL 0x7fc00001 0x40000000" "FMUL NaN * 2"

  # --- SQRT / rounding / conversions ---
  assert_u32hex_eq "3FB504F3" "exec \\SFPU\\SQRT 0x40000000" "SQRT(2.0) ~= 1.4142135"
  assert_u32hex_eq "40000000" "exec \\SFPU\\RINT 0x40200000" "RINT(2.5) -> 2.0 (ties-to-even)"
  assert_u32hex_eq "40800000" "exec \\SFPU\\RINT 0x40600000" "RINT(3.5) -> 4.0 (ties-to-even)"

  assert_u32hex_eq "3F800000" "exec \\SFPU\\IN2F 0x00000001" "IN2F(1) -> 1.0"
  assert_u32hex_eq "BF800000" "exec \\SFPU\\IN2F 0xFFFFFFFF" "IN2F(-1) -> -1.0"

  assert_u64hex_eq "0000000000000001" "exec \\SFPU\\F2IN 0x3f800000" "F2IN(1.0) -> 1"
  assert_u64hex_eq "FFFFFFFFFFFFFFFF" "exec \\SFPU\\F2IN 0xbf800000" "F2IN(-1.0) -> -1"
  assert_u64hex_eq "0000000000000000" "exec \\SFPU\\F2IN 0x80000000" "F2IN(-0.0) -> 0"

  echo
  echo "Executed $tests checks, failures: $failures"
  if [[ "$failures" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"

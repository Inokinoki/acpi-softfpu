#!/usr/bin/env bash
set -euo pipefail

AML_FILE="${AML_FILE:-softfpu.aml}"
ACPIEXEC_BIN="${ACPIEXEC_BIN:-acpiexec}"

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
  local x="${1#0x}"
  x="${x// /}"
  echo "${x^^}"
}

u32_to_u64hex() {
  local x="${1#0x}"
  printf "00000000%08X" "$((16#$x))"
}

is_nan_u64() {
  # IEEE754 binary32 NaN: exponent all-ones and nonzero payload.
  local u64="$1"
  local u32="$((16#${u64: -8}))"
  local abs=$((u32 & 0x7FFFFFFF))
  (( abs > 0x7F800000 ))
}

declare -a TEST_KIND TEST_EXPECTED TEST_CMD TEST_NAME

add_test() {
  TEST_KIND+=("$1")
  TEST_EXPECTED+=("$2")
  TEST_CMD+=("$3")
  TEST_NAME+=("$4")
}

expect_u32() { add_test u32 "$1" "$2" "$3"; }
expect_u64() { add_test u64 "$1" "$2" "$3"; }
expect_true() { add_test bool "FFFFFFFFFFFFFFFF" "$1" "$2"; }
expect_false() { add_test bool "0000000000000000" "$1" "$2"; }
expect_nan() { add_test nan "" "$1" "$2"; }

define_tests() {
  # --- Construction / basic bit helpers ---
  expect_u32 "3EEF1AA0" "exec \\SFPU\\GENF 0 125 7281312" "GENF builds float bits"
  expect_u32 "3EEF1AA0" "exec \\SFPU\\FABS 0x3EEF1AA0" "FABS keeps positive"
  expect_u32 "3EEF1AA0" "exec \\SFPU\\FABS 0xBEEF1AA0" "FABS clears sign"
  expect_u32 "BEEF1AA0" "exec \\SFPU\\MTH3 0x3EEF1AA0" "MTH3 flips sign"
  expect_u32 "3EEF1AA0" "exec \\SFPU\\MTH3 0xBEEF1AA0" "MTH3 flips sign back"
  expect_u32 "80000000" "exec \\SFPU\\MTH3 0x00000000" "MTH3 +0 -> -0"
  expect_u32 "00000000" "exec \\SFPU\\MTH3 0x80000000" "MTH3 -0 -> +0"

  expect_true  "exec \\SFPU\\NEG 0xff800001" "NEG detects negative"
  expect_false "exec \\SFPU\\NEG 0x7f800001" "NEG detects positive"
  expect_false "exec \\SFPU\\NEG 0x00000000" "NEG +0 is not negative"
  expect_true  "exec \\SFPU\\NEG 0x80000000" "NEG -0 is negative"

  expect_u64 "000000000000007D" "exec \\SFPU\\EXP 0x3EEF1AA0" "EXP extracts exponent"
  expect_u64 "0000000000000000" "exec \\SFPU\\SIGN 0x3EEF1AA0" "SIGN extracts sign=0"
  expect_u64 "0000000000000001" "exec \\SFPU\\SIGN 0xBEEF1AA0" "SIGN extracts sign=1"
  expect_u64 "00000000006F1AA0" "exec \\SFPU\\FRAC 0x3EEF1AA0" "FRAC extracts fraction"

  # --- Classification ---
  expect_true  "exec \\SFPU\\INFI 0x7f800000" "INFI +inf"
  expect_true  "exec \\SFPU\\INFI 0xff800000" "INFI -inf"
  expect_false "exec \\SFPU\\INFI 0x7f800001" "INFI not inf (payload)"
  expect_true  "exec \\SFPU\\ISIN 0x7f800000" "ISIN +inf"
  expect_false "exec \\SFPU\\ISIN 0x7f800001" "ISIN not inf"

  expect_true  "exec \\SFPU\\ISZE 0x00000000" "ISZE +0"
  expect_true  "exec \\SFPU\\ISZE 0x80000000" "ISZE -0"
  expect_false "exec \\SFPU\\ISZE 0x3f800000" "ISZE not zero"
  expect_false "exec \\SFPU\\ISZE 0x007FFFFF" "ISZE subnormal is not zero"

  expect_true  "exec \\SFPU\\ISNO 0x3f800000" "ISNO 1.0 is normal"
  expect_false "exec \\SFPU\\ISNO 0x00000000" "ISNO zero not normal"
  expect_false "exec \\SFPU\\ISNO 0x007FFFFF" "ISNO subnormal not normal"
  expect_false "exec \\SFPU\\ISNO 0x7f800000" "ISNO inf not normal"
  expect_false "exec \\SFPU\\ISNO 0x7fc00000" "ISNO NaN not normal"

  expect_true  "exec \\SFPU\\ISNA 0x7fc00000" "ISNA qNaN"
  expect_true  "exec \\SFPU\\ISNA 0x7f800001" "ISNA sNaN-ish payload"
  expect_false "exec \\SFPU\\ISNA 0x7f800000" "ISNA not NaN (inf)"
  expect_false "exec \\SFPU\\ISNA 0x3f800000" "ISNA not NaN (normal)"

  # --- Comparisons ---
  expect_true  "exec \\SFPU\\FEQL 0x00000000 0x80000000" "FEQL +0 == -0"
  expect_true  "exec \\SFPU\\FEQL 0x3f800000 0x3f800000" "FEQL 1 == 1"
  expect_false "exec \\SFPU\\FEQL 0x3f800000 0x40000000" "FEQL 1 != 2"
  expect_false "exec \\SFPU\\FEQL 0x7fc00000 0x3f800000" "FEQL NaN == x is false"
  expect_false "exec \\SFPU\\FEQL 0x7fc00000 0x7fc00000" "FEQL NaN == NaN is false"

  expect_false "exec \\SFPU\\FNEQ 0x00000000 0x80000000" "FNEQ +0 != -0 is false"
  expect_true  "exec \\SFPU\\FNEQ 0x3f800000 0x40000000" "FNEQ 1 != 2"
  expect_false "exec \\SFPU\\FNEQ 0x7fc00000 0x3f800000" "FNEQ NaN != x is false"

  expect_true  "exec \\SFPU\\FLET 0xbf800000 0x3f800000" "FLET -1 < 1"
  expect_false "exec \\SFPU\\FLET 0x3f800000 0xbf800000" "FLET 1 < -1 is false"
  expect_false "exec \\SFPU\\FLET 0x3f800000 0x3f800000" "FLET 1 < 1 is false"
  expect_false "exec \\SFPU\\FLET 0x00000000 0x80000000" "FLET +0 < -0 is false"
  expect_false "exec \\SFPU\\FLET 0x7fc00000 0x3f800000" "FLET NaN < x is false"

  expect_true  "exec \\SFPU\\FLEQ 0x3f800000 0x3f800000" "FLEQ 1 <= 1"
  expect_true  "exec \\SFPU\\FLEQ 0x00000000 0x80000000" "FLEQ +0 <= -0"
  expect_true  "exec \\SFPU\\FLEQ 0xbf800000 0x3f800000" "FLEQ -1 <= 1"
  expect_false "exec \\SFPU\\FLEQ 0x7fc00000 0x3f800000" "FLEQ NaN <= x is false"

  expect_true  "exec \\SFPU\\FGRT 0x40000000 0x3f800000" "FGRT 2 > 1"
  expect_false "exec \\SFPU\\FGRT 0x3f800000 0x3f800000" "FGRT 1 > 1 is false"
  expect_false "exec \\SFPU\\FGRT 0x7fc00000 0x3f800000" "FGRT NaN > x is false"

  expect_true  "exec \\SFPU\\FGEQ 0x3f800000 0x3f800000" "FGEQ 1 >= 1"
  expect_true  "exec \\SFPU\\FGEQ 0x40000000 0x3f800000" "FGEQ 2 >= 1"
  expect_false "exec \\SFPU\\FGEQ 0x7fc00000 0x3f800000" "FGEQ NaN >= x is false"

  # --- Addition ---
  # 0.1 + 0.2 = 0.3000000119... (float32: 0x3E99999A)
  expect_u32 "3E99999A" "exec \\SFPU\\FADD 0x3dcccccd 0x3e4ccccd" "FADD 0.1 + 0.2"
  # Original suite: 12345 + 67890 = 80235
  expect_u32 "479CB580" "exec \\SFPU\\FADD 0x4640e400 0x47849900" "FADD 12345 + 67890"
  expect_u32 "40000000" "exec \\SFPU\\FADD 0x3f800000 0x3f800000" "FADD 1 + 1"
  expect_u32 "3F000000" "exec \\SFPU\\FADD 0x3f800000 0xbf000000" "FADD 1 + -0.5"
  expect_u32 "00000000" "exec \\SFPU\\FADD 0x3f800000 0xbf800000" "FADD 1 + -1 -> +0"

  # Issue #1: adding zero must preserve the other operand's sign
  expect_u32 "BF000000" "exec \\SFPU\\FADD 0x0 0xBF000000" "FADD +0 + -0.5"
  expect_u32 "BF000000" "exec \\SFPU\\FADD 0xBF000000 0x0" "FADD -0.5 + +0"
  expect_u32 "3F000000" "exec \\SFPU\\FADD 0x0 0x3F000000" "FADD +0 + +0.5"
  expect_u32 "3F000000" "exec \\SFPU\\FADD 0x3F000000 0x0" "FADD +0.5 + +0"
  expect_u32 "3F800000" "exec \\SFPU\\FADD 0x3f800000 0x80000000" "FADD 1 + -0"
  expect_u32 "00000000" "exec \\SFPU\\FADD 0x0 0x80000000" "FADD +0 + -0 -> +0"

  expect_u32 "7F800000" "exec \\SFPU\\FADD 0x7f800000 0x3f800000" "FADD +inf + 1"
  expect_u32 "7F800000" "exec \\SFPU\\FADD 0x7f800000 0x7f800000" "FADD +inf + +inf"
  expect_u32 "FF800000" "exec \\SFPU\\FADD 0xff800000 0xff800000" "FADD -inf + -inf"
  expect_nan "exec \\SFPU\\FADD 0x7f800000 0xff800000" "FADD +inf + -inf"
  expect_nan "exec \\SFPU\\FADD 0x7fc00001 0x3f800000" "FADD NaN + 1"

  # --- Subtraction ---
  # 0.3000000119... - 0.200000003... = 0.1000000089... (float32: 0x3DCCCCCE)
  expect_u32 "3DCCCCCE" "exec \\SFPU\\FSUB 0x3E99999A 0x3E4CCCCD" "FSUB 0.3 - 0.2"
  expect_u32 "3F800000" "exec \\SFPU\\FSUB 0x40000000 0x3f800000" "FSUB 2 - 1"
  expect_u32 "BF800000" "exec \\SFPU\\FSUB 0x3f800000 0x40000000" "FSUB 1 - 2"
  expect_u32 "3FC00000" "exec \\SFPU\\FSUB 0x3f800000 0xbf000000" "FSUB 1 - -0.5"
  expect_u32 "BF000000" "exec \\SFPU\\FSUB 0x0 0x3F000000" "FSUB +0 - +0.5"
  expect_u32 "3F000000" "exec \\SFPU\\FSUB 0x3F000000 0x0" "FSUB +0.5 - +0"
  expect_nan "exec \\SFPU\\FSUB 0x7f800000 0x7f800000" "FSUB +inf - +inf"

  # --- Multiply ---
  expect_u32 "40000000" "exec \\SFPU\\FMUL 0x3f800000 0x40000000" "FMUL 1 * 2"
  expect_u32 "40C00000" "exec \\SFPU\\FMUL 0x40000000 0x40400000" "FMUL 2 * 3"
  expect_u32 "C0C00000" "exec \\SFPU\\FMUL 0x40000000 0xC0400000" "FMUL 2 * -3"
  expect_u32 "00000000" "exec \\SFPU\\FMUL 0x0 0x40000000" "FMUL +0 * 2"
  expect_u32 "80000000" "exec \\SFPU\\FMUL 0x80000000 0x40000000" "FMUL -0 * 2"
  expect_u32 "00000001" "exec \\SFPU\\FMUL 0x00000001 0x3f800000" "FMUL min-subnormal * 1"
  expect_u32 "7F800000" "exec \\SFPU\\FMUL 0x7f800000 0x40000000" "FMUL +inf * 2"
  expect_nan "exec \\SFPU\\FMUL 0x7f800000 0x0" "FMUL +inf * 0"
  expect_nan "exec \\SFPU\\FMUL 0x0 0x7f800000" "FMUL 0 * +inf"
  expect_nan "exec \\SFPU\\FMUL 0x7fc00001 0x40000000" "FMUL NaN * 2"

  # --- Divide ---
  expect_u32 "3F000000" "exec \\SFPU\\FDIV 0x3f800000 0x40000000" "FDIV 1 / 2"
  expect_u32 "40000000" "exec \\SFPU\\FDIV 0x40C00000 0x40400000" "FDIV 6 / 3"
  expect_u32 "BF000000" "exec \\SFPU\\FDIV 0x3f800000 0xc0000000" "FDIV 1 / -2"
  expect_u32 "00000000" "exec \\SFPU\\FDIV 0x0 0x3f800000" "FDIV +0 / 1"
  expect_u32 "7F800000" "exec \\SFPU\\FDIV 0x3f800000 0x0" "FDIV 1 / +0 -> +inf"
  expect_u32 "FF800000" "exec \\SFPU\\FDIV 0xbf800000 0x0" "FDIV -1 / +0 -> -inf"
  expect_u32 "00000000" "exec \\SFPU\\FDIV 0x3f800000 0x7f800000" "FDIV 1 / +inf -> +0"
  expect_nan "exec \\SFPU\\FDIV 0x0 0x0" "FDIV 0 / 0"
  expect_nan "exec \\SFPU\\FDIV 0x7f800000 0x7f800000" "FDIV inf / inf"

  # --- SQRT / rounding / conversions ---
  expect_u32 "3FB504F3" "exec \\SFPU\\SQRT 0x40000000" "SQRT(2.0) ~= 1.4142135"
  expect_u32 "00000000" "exec \\SFPU\\SQRT 0x00000000" "SQRT(+0)"
  expect_u32 "80000000" "exec \\SFPU\\SQRT 0x80000000" "SQRT(-0)"
  expect_u32 "3F800000" "exec \\SFPU\\SQRT 0x3f800000" "SQRT(1)"
  expect_u32 "40000000" "exec \\SFPU\\SQRT 0x40800000" "SQRT(4)"
  expect_u32 "7F800000" "exec \\SFPU\\SQRT 0x7f800000" "SQRT(+inf)"
  expect_nan "exec \\SFPU\\SQRT 0xbf800000" "SQRT(-1)"
  expect_nan "exec \\SFPU\\SQRT 0xff800000" "SQRT(-inf)"

  expect_u32 "40000000" "exec \\SFPU\\RINT 0x40200000" "RINT(2.5) -> 2.0 (ties-to-even)"
  expect_u32 "40800000" "exec \\SFPU\\RINT 0x40600000" "RINT(3.5) -> 4.0 (ties-to-even)"
  expect_u32 "00000000" "exec \\SFPU\\RINT 0x3F000000" "RINT(0.5) -> +0 (ties-to-even)"
  expect_u32 "80000000" "exec \\SFPU\\RINT 0xBF000000" "RINT(-0.5) -> -0 (ties-to-even)"
  expect_u32 "3F800000" "exec \\SFPU\\RINT 0x3F400000" "RINT(0.75) -> 1.0"
  expect_u32 "00000000" "exec \\SFPU\\RINT 0x00000000" "RINT(+0)"
  expect_u32 "3F800000" "exec \\SFPU\\RINT 0x3F800000" "RINT(1.0) unchanged"

  expect_u32 "00000000" "exec \\SFPU\\IN2F 0x00000000" "IN2F(0) -> +0"
  expect_u32 "3F800000" "exec \\SFPU\\IN2F 0x00000001" "IN2F(1) -> 1.0"
  expect_u32 "BF800000" "exec \\SFPU\\IN2F 0xFFFFFFFF" "IN2F(-1) -> -1.0"
  expect_u32 "40000000" "exec \\SFPU\\IN2F 0x00000002" "IN2F(2) -> 2.0"

  expect_u64 "0000000000000000" "exec \\SFPU\\F2IN 0x00000000" "F2IN(+0.0) -> 0"
  expect_u64 "0000000000000001" "exec \\SFPU\\F2IN 0x3f800000" "F2IN(1.0) -> 1"
  expect_u64 "FFFFFFFFFFFFFFFF" "exec \\SFPU\\F2IN 0xbf800000" "F2IN(-1.0) -> -1"
  expect_u64 "0000000000000000" "exec \\SFPU\\F2IN 0x80000000" "F2IN(-0.0) -> 0"
  expect_u64 "0000000000000002" "exec \\SFPU\\F2IN 0x40000000" "F2IN(2.0) -> 2"
}

run_batch() {
  local batch=""
  local i
  for i in "${!TEST_CMD[@]}"; do
    if [[ -n "$batch" ]]; then
      batch+="; "
    fi
    batch+="${TEST_CMD[$i]}"
  done

  local output
  if ! output="$("$ACPIEXEC_BIN" -dt -b "$batch" "$AML_FILE" 2>/dev/null)"; then
    die "acpiexec invocation failed"
  fi

  local -a results=()
  local line v
  while IFS= read -r line; do
    if [[ "$line" == "  [Integer] = "* ]]; then
      v="$(u64_hex_upper "${line##* = }")"
      [[ -n "$v" ]] || die "parsed empty integer result"
      results+=("$v")
    fi
  done <<<"$output"

  if [[ ${#results[@]} -ne ${#TEST_CMD[@]} ]]; then
    echo "$output" | tail -40 >&2
    die "expected ${#TEST_CMD[@]} results, got ${#results[@]}"
  fi

  local failures=0
  local kind expected actual name
  for i in "${!TEST_CMD[@]}"; do
    kind="${TEST_KIND[$i]}"
    expected="$(u64_hex_upper "${TEST_EXPECTED[$i]}")"
    actual="${results[$i]}"
    name="${TEST_NAME[$i]}"

    case "$kind" in
      nan)
        if is_nan_u64 "$actual"; then
          echo "PASS: $name (isnan)"
        else
          failures=$((failures + 1))
          echo "FAIL: $name (isnan)"
          echo "  expected result to be NaN"
          echo "  got:      $actual"
        fi
        ;;
      u32)
        expected="$(u32_to_u64hex "${TEST_EXPECTED[$i]}")"
        if [[ "$actual" == "$expected" ]]; then
          echo "PASS: $name"
        else
          failures=$((failures + 1))
          echo "FAIL: $name"
          echo "  expected: $expected"
          echo "  got:      $actual"
        fi
        ;;
      *)
        if [[ "$actual" == "$expected" ]]; then
          echo "PASS: $name"
        else
          failures=$((failures + 1))
          echo "FAIL: $name"
          echo "  expected: $expected"
          echo "  got:      $actual"
        fi
        ;;
    esac
  done

  echo
  echo "Executed ${#TEST_CMD[@]} checks, failures: $failures"
  if [[ "$failures" -ne 0 ]]; then
    exit 1
  fi
}

main() {
  require_cmd "$ACPIEXEC_BIN"
  require_file "$AML_FILE"
  define_tests
  run_batch
}

main "$@"

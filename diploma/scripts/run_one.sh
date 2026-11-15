#!/bin/bash
# Один запуск gem5.
#   scripts/run_one.sh <папка_результата> <бинарник> [параметры spmv_run.py ...]
# Если в папке уже есть завершённый запуск (в simout.txt есть @DONE), он
# пропускается -- поэтому серию можно прервать и перезапустить.
set -uo pipefail
cd "$(dirname "$0")/.."
GEM5=${GEM5:-../gem5/build/RISCV/gem5.opt}

out=$1; bin=$2; shift 2
if [ -f "$out/simout.txt" ] && grep -q "^@DONE" "$out/simout.txt" && [ -f "$out/stats.txt" ]; then
    echo "[skip] $out"
    exit 0
fi
rm -rf "$out"; mkdir -p "$out"
printf '%s\n' "$bin" "$@" > "$out/cmdline.txt"
t0=$(date +%s)
"$GEM5" -re --silent-redirect -d "$out" gem5/spmv_run.py --bin "$bin" "$@"
rc=$?
t1=$(date +%s)
echo "wall_seconds=$((t1 - t0)) rc=$rc" > "$out/wall.txt"
if [ $rc -ne 0 ] || ! grep -q "^@DONE" "$out/simout.txt" 2>/dev/null; then
    echo "[FAIL] $out (rc=$rc, см. $out/simerr.txt)"
    exit 1
fi
if grep -q "^@FAIL" "$out/simout.txt"; then
    echo "[VERIFY FAIL] $out: $(grep '^@FAIL' "$out/simout.txt" | tr '\n' ' ')"
    exit 1
fi
echo "[ok] $out  $((t1 - t0)) с"

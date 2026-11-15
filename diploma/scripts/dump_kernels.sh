#!/bin/bash
# Машинный код ядер SpMV из собранного бинарника (для анализа и листингов).
#   scripts/dump_kernels.sh nasa2910   ->  results/kernels_nasa2910.asm
cd "$(dirname "$0")/.."
m=$1
OBJDUMP=$(scripts/find_objdump.sh) || { echo "objdump не найден: ls ../toolchain/bin | grep objdump" >&2; exit 1; }
mkdir -p results
"$OBJDUMP" -d --no-show-raw-insn "build/spmv_$m" | awk '/^[0-9a-f]+ <spmv_/,/^$/' > "results/kernels_$m.asm"
echo "$OBJDUMP -> results/kernels_$m.asm ($(grep -c '>:$' "results/kernels_$m.asm") функций)"

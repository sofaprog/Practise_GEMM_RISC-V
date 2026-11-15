#!/bin/bash
# Печатает путь к objdump для RISC-V (или ничего).
#   scripts/find_objdump.sh [компилятор]
cd "$(dirname "$0")/.."
cc=${1:-rvv-gcc}
pre=${cc%gcc}; pre=${pre%g++}
for c in "${pre}objdump" ../toolchain/bin/riscv64-unknown-elf-objdump \
         ../toolchain/bin/riscv64-unknown-linux-gnu-objdump ../toolchain/bin/*objdump \
         riscv64-unknown-elf-objdump riscv64-linux-gnu-objdump llvm-objdump; do
    p=$(command -v "$c" 2>/dev/null) && [ -n "$p" ] && { echo "$p"; exit 0; }
done
exit 1

#!/bin/bash
# Сборка бенчмарка: заголовок матрицы + статический RISC-V бинарник.
#
#   scripts/build.sh nasa2910 [bcsstk13 crystm03 ...]
#
# Переменные окружения (необязательно):
#   CC       компилятор              (по умолчанию rvv-gcc из PATH или ../toolchain/bin)
#   MTX_DIR  папка с .mtx            (по умолчанию ../matrices)
#   WARMUP   прогревочных прогонов   (по умолчанию 1)
#   ITERS    измеряемых прогонов     (по умолчанию 2)
#   M5OPS    1 = маркеры gem5 (для gem5), 0 = без них (для QEMU)
#   ALIGN    выровнять массивы матрицы по ALIGN байт (опыт с размещением
#            данных); бинарник build/spmv_<матрица>_a<ALIGN>
set -euo pipefail
cd "$(dirname "$0")/.."                       # папка diploma/

MTX_DIR=${MTX_DIR:-../matrices}
WARMUP=${WARMUP:-1}
ITERS=${ITERS:-2}
M5OPS=${M5OPS:-1}

# Компилятор: $CC, иначе rvv-gcc из PATH, иначе ../toolchain/bin/rvv-gcc,
# иначе rvv-g++ в режиме C (-x c).
XLANG=""
if [ -z "${CC:-}" ]; then
    for c in rvv-gcc ../toolchain/bin/rvv-gcc; do
        if command -v "$c" >/dev/null; then CC=$c; break; fi
    done
fi
if [ -z "${CC:-}" ]; then
    for c in rvv-g++ ../toolchain/bin/rvv-g++; do
        if command -v "$c" >/dev/null; then CC=$c; XLANG="-x c"; break; fi
    done
fi
if [ -z "${CC:-}" ] || ! command -v "$CC" >/dev/null; then
    echo "Не найден компилятор rvv-gcc. Выполните из корня проекта: source compiler_vars.sh" >&2
    exit 1
fi
echo "Компилятор: $CC ($("$CC" --version | head -1))"
[ $# -ge 1 ] || { echo "Использование: $0 <матрица> [<матрица> ...]" >&2; exit 1; }

# Флаги одинаковые для всех ядер. -fno-tree-vectorize: скалярное ядро должно
# остаться скалярным (на RVV-интринсики флаг не влияет). -fno-stack-protector:
# у тулчейнов Ubuntu он включён по умолчанию, у rvv-gcc -- нет.
CFLAGS="-O2 -fno-tree-vectorize -fno-tree-slp-vectorize -fno-stack-protector \
        -march=rv64gcv -mabi=lp64d -static -I."
DEFS="-DWARMUP=$WARMUP -DITERS=$ITERS"
[ "$M5OPS" = 1 ] && DEFS="$DEFS -DUSE_M5OPS"
ALIGN=${ALIGN:-}
[ -n "$ALIGN" ] && DEFS="$DEFS -DARRAY_ATTR=__attribute__((aligned($ALIGN)))"

mkdir -p gen build
for name in "$@"; do
    hdr="gen/$name.h"
    if [ ! -f "$hdr" ] || [ "$MTX_DIR/$name.mtx" -nt "$hdr" ] || [ tools/gen_bench_header.py -nt "$hdr" ]; then
        python3 tools/gen_bench_header.py "$MTX_DIR/$name.mtx" "$hdr"
    fi
    suffix=""; [ -n "$ALIGN" ] && suffix="_a$ALIGN"; [ "$M5OPS" = 1 ] || suffix="${suffix}_qemu"
    out="build/spmv_${name}${suffix}"
    $CC $CFLAGS $DEFS -DMATRIX_HEADER="\"$hdr\"" $XLANG src/spmv_bench.c -x none -o "$out" -lm
    # контроль: в скалярном ядре не должно быть векторных инструкций
    OBJDUMP=$(scripts/find_objdump.sh "$CC" || true)
    if [ -n "$OBJDUMP" ]; then
        nvec=$("$OBJDUMP" -d "$out" 2>/dev/null | awk '/<spmv_csr_scalar>:/{f=1;next} f&&/^$/{f=0} f' \
               | grep -cE '\bv(set|le|se|lux|fm|fadd|fred)' || true)
        [ "$nvec" = 0 ] || { echo "ОШИБКА: в spmv_csr_scalar найдено $nvec векторных инструкций" >&2; exit 1; }
        echo "Проверка скалярного ядра ($OBJDUMP): векторных инструкций нет"
    else
        echo "ПРЕДУПРЕЖДЕНИЕ: objdump не найден, проверка скалярного ядра пропущена" >&2
    fi
    echo "OK: $out ($(du -h "$out" | cut -f1))"
done

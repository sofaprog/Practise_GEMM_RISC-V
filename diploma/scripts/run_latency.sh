#!/bin/bash
# Серия 2: латентности векторных операций -- когда векторный код перестаёт
# выигрывать у скалярного.
#   scripts/run_latency.sh <матрица>
# Для каждой группы классов операций (словарь GROUPS в gem5/spmv_run.py) латентность
# задаётся значениями из VALUES, остальное -- как в конфигурации лаборатории
# (включая SMS в L2). Скалярное ядро в каждом запуске служит контролем:
# его такты не должны меняться.
#
# Переменные: JOBS       (по умолчанию 2)
#             LAT_GROUPS (по умолчанию "gather vload vec_fp vec_red vec_misc vec_all")
#             VALUES     (по умолчанию "1 2 4 8 16 32 64 128")
#             EXTRA      дополнительные параметры spmv_run.py для всех запусков,
#                        например EXTRA="--l2-size 2MB"
#             TAG        суффикс серии, чтобы не смешать с основной, например
#                        TAG=_l2_2MB -> results/lat_l2_2MB/<матрица>/
set -uo pipefail
cd "$(dirname "$0")/.."
m=$1
JOBS=${JOBS:-2}
LAT_GROUPS=${LAT_GROUPS:-"gather vload vec_fp vec_red vec_misc vec_all"}
VALUES=${VALUES:-"1 2 4 8 16 32 64 128"}
EXTRA=${EXTRA:-}
TAG=${TAG:-}
if [ -n "$EXTRA" ] && [ -z "$TAG" ]; then
    echo "Задан EXTRA, но не задан TAG: результаты смешаются с основной серией" >&2; exit 1
fi
bin=build/spmv_$m
[ -x "$bin" ] || { echo "Нет $bin, сначала scripts/build.sh $m" >&2; exit 1; }
dir=results/lat$TAG/$m

cmds=("scripts/run_one.sh $dir/base $bin $EXTRA")
for g in $LAT_GROUPS; do
    for v in $VALUES; do
        cmds+=("scripts/run_one.sh $dir/${g}_$v $bin $EXTRA --lat $g=$v")
    done
done
printf '%s\n' "${cmds[@]}" | xargs -P "$JOBS" -I{} bash -c '{}'
python3 tools/parse_stats.py $dir/* -o results/lat${TAG}_$m.csv

#!/bin/bash
# Серия 1: влияние префетчера.
#   scripts/run_prefetchers.sh <матрица> [l1d|l2]
# Префетчер ставится в один уровень (по умолчанию L1D), второй уровень --
# без префетчера, чтобы эффект был только от исследуемого префетчера.
# Дополнительно: "lab" = конфигурация лаборатории без изменений (SMS в L2).
#
# Переменные: JOBS (параллельных gem5, по умолчанию 2),
#             PFS  (список, по умолчанию "none tagged stride ampm dcpt sms spp isb")
# bop и imp в gem5 v24.1 не работают (BOP не выдаёт ни одного запроса, IMP
# падает с panic). Их можно добавить в PFS только после патча
# gem5_patches/prefetch_bop_imp.patch (см. README, шаг 3б).
#             EXTRA (доп. параметры spmv_run.py для всех запусков, например
#                    EXTRA="--l1d-mshrs 16"), TAG (суффикс серии, например
#                    TAG=_mshr16 -> results/pf_l1d_mshr16/<матрица>/)
set -uo pipefail
cd "$(dirname "$0")/.."
m=$1; level=${2:-l1d}
JOBS=${JOBS:-2}
PFS=${PFS:-"none tagged stride ampm dcpt sms spp isb"}
EXTRA=${EXTRA:-}
TAG=${TAG:-}
if [ -n "$EXTRA" ] && [ -z "$TAG" ]; then
    echo "Задан EXTRA, но не задан TAG: результаты смешаются с основной серией" >&2; exit 1
fi
bin=build/spmv_$m
dir=results/pf_$level$TAG/$m
[ -x "$bin" ] || { echo "Нет $bin, сначала scripts/build.sh $m" >&2; exit 1; }

cmds=()
for pf in $PFS; do
    [ "$pf" = imp ] && [ "$level" = l2 ] && continue   # IMP только в L1D
    if [ "$level" = l1d ]; then a="--l1d-pf $pf --l2-pf none"; else a="--l1d-pf none --l2-pf $pf"; fi
    cmds+=("scripts/run_one.sh $dir/$pf $bin $EXTRA $a")
done
cmds+=("scripts/run_one.sh $dir/lab $bin $EXTRA")   # как binary_run.py (+ EXTRA)

printf '%s\n' "${cmds[@]}" | xargs -P "$JOBS" -I{} bash -c '{}'
python3 tools/parse_stats.py $dir/* -o results/pf_${level}${TAG}_$m.csv

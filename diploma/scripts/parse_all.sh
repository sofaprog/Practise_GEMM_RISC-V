#!/bin/bash
# Пересобрать все CSV из папок запусков: results/<серия>/<матрица>/<запуск>/
# -> results/<серия>_<матрица>.csv  (например, results/pf_l2_nasa2910.csv).
# gem5 заново не запускается, читаются только stats.txt и simout.txt.
cd "$(dirname "$0")/.."
for d in results/*/*/; do
    s=$(basename "$(dirname "$d")"); m=$(basename "$d")
    python3 tools/parse_stats.py "$d"* -o "results/${s}_${m}.csv" 2>&1 | head -1
done

#!/usr/bin/env python3
"""
Разбор результатов gem5 в CSV: одна строка = один регион (ядро + фаза).

  python3 tools/parse_stats.py results/pf_l1d/nasa2910/* -o results/pf_l1d_nasa2910.csv

В stats.txt блоки идут в порядке вызовов m5_dump_reset_stats:
  [0] старт программы, [1] регион 0, [2] промежуток, [3] регион 1, ...
Имена регионов берутся из строк "@REGION k имя:фаза" в simout.txt,
параметры запуска -- из cmdline.txt и строки "@GEM5CFG".
"""
import argparse
import csv
import math
import os
import re
import sys

STATS = {  # колонка CSV -> имя статистики gem5
    "cycles": "system.cpu.numCycles",
    "insts": "system.cpu.commitStats0.numInsts",
    "ops": "system.cpu.commitStats0.numOps",
    "l1d_accesses": "system.cpu.dcache.demandAccesses::total",
    "l1d_misses": "system.cpu.dcache.demandMisses::total",
    "l2_accesses": "system.l2cache.demandAccesses::total",
    "l2_misses": "system.l2cache.demandMisses::total",
    "dram_bytes_read": "system.mem_ctrl.dram.bytesRead::total",
    "l1d_pf_issued": "system.cpu.dcache.prefetcher.pfIssued",
    "l1d_pf_useful": "system.cpu.dcache.prefetcher.pfUseful",
    "l1d_pf_unused": "system.cpu.dcache.prefetcher.pfUnused",
    "l1d_pf_late": "system.cpu.dcache.prefetcher.pfLate",
    "l1d_pf_accuracy": "system.cpu.dcache.prefetcher.accuracy",
    "l1d_pf_coverage": "system.cpu.dcache.prefetcher.coverage",
    "l2_pf_issued": "system.l2cache.prefetcher.pfIssued",
    "l2_pf_useful": "system.l2cache.prefetcher.pfUseful",
    "l2_pf_unused": "system.l2cache.prefetcher.pfUnused",
    "l2_pf_late": "system.l2cache.prefetcher.pfLate",
    "l2_pf_accuracy": "system.l2cache.prefetcher.accuracy",
    "l2_pf_coverage": "system.l2cache.prefetcher.coverage",
    "clock_ps": "system.clk_domain.clock",
}


def num(s):
    try:
        return float(s)
    except ValueError:
        return math.nan


def read_blocks(path):
    blocks, cur = [], None
    with open(path) as f:
        for line in f:
            if line.startswith("---------- Begin Simulation Statistics"):
                cur = {}
            elif line.startswith("---------- End Simulation Statistics"):
                blocks.append(cur)
                cur = None
            elif cur is not None and line.strip():
                parts = line.split()
                if len(parts) >= 2:
                    cur[parts[0]] = num(parts[1])
    return blocks


def read_run(d):
    simout = os.path.join(d, "simout.txt")
    stats = os.path.join(d, "stats.txt")
    if not (os.path.isfile(simout) and os.path.isfile(stats)):
        return None, f"{d}: нет simout.txt/stats.txt"
    text = open(simout, encoding="utf-8", errors="replace").read()
    if "@DONE" not in text:
        return None, f"{d}: запуск не завершён"
    meta = {"run": os.path.basename(os.path.normpath(d)),
            "series": os.path.basename(os.path.dirname(os.path.dirname(os.path.normpath(d))))}
    m = re.search(r"@MATRIX (\S+) n=(\d+) m=(\d+) nnz=(\d+) sell_c=(\d+) sigma=(\d+) padded=(\d+)", text)
    meta.update(matrix=m.group(1), n=int(m.group(2)), nnz=int(m.group(4)),
                sell_padded=int(m.group(7)))
    m = re.search(r"@CONFIG warmup=(\d+) iters=(\d+)", text)
    warmup, iters = int(m.group(1)), int(m.group(2))
    m = re.search(r"@GEM5CFG l1d_pf=(\S+) l2_pf=(\S+) vlen=(\d+) l1d=(\S+) l2=(\S+) lat_overrides=(\S+)", text)
    if m:
        meta.update(l1d_pf=m.group(1), l2_pf=m.group(2), vlen=int(m.group(3)),
                    l1d=m.group(4), l2=m.group(5), lat=m.group(6))
    regions = re.findall(r"@REGION (\d+) (\S+):(\S+)", text)
    failed = set(re.findall(r"@FAIL (\S+)", text))
    blocks = read_blocks(stats)
    wall = ""
    wp = os.path.join(d, "wall.txt")
    if os.path.isfile(wp):
        wall = open(wp).read().split()[0].split("=")[1]

    rows = []
    for k, kernel, phase in regions:
        bi = 1 + 2 * int(k)
        if bi >= len(blocks):
            return None, f"{d}: в stats.txt меньше блоков, чем регионов"
        b = blocks[bi]
        r = dict(meta)
        r.update(kernel=kernel, phase=phase, verified=kernel not in failed,
                 iters=warmup if phase == "warm" else iters, wall_seconds=wall)
        for col, key in STATS.items():
            r[col] = b.get(key, math.nan)
        it = r["iters"]
        r["cycles_per_iter"] = r["cycles"] / it
        r["time_us_per_iter"] = r["cycles"] * r["clock_ps"] * 1e-6 / it
        r["gflops"] = 2.0 * r["nnz"] / (r["time_us_per_iter"] * 1e3)
        r["ipc"] = r["insts"] / r["cycles"] if r["cycles"] else math.nan
        r["l1d_miss_rate"] = r["l1d_misses"] / r["l1d_accesses"] if r["l1d_accesses"] else math.nan
        r["l2_miss_rate"] = r["l2_misses"] / r["l2_accesses"] if r["l2_accesses"] else math.nan
        rows.append(r)
    # ускорение относительно csr_scalar того же запуска (по фазе meas)
    base = {r["phase"]: r["cycles_per_iter"] for r in rows if r["kernel"] == "csr_scalar"}
    for r in rows:
        b = base.get(r["phase"])
        r["speedup_vs_scalar"] = b / r["cycles_per_iter"] if b else math.nan
    return rows, None


COLUMNS = ["series", "matrix", "run", "l1d_pf", "l2_pf", "lat", "vlen", "l1d", "l2",
           "kernel", "phase", "iters", "verified", "cycles", "cycles_per_iter",
           "time_us_per_iter", "gflops", "speedup_vs_scalar", "insts", "ops", "ipc",
           "l1d_accesses", "l1d_misses", "l1d_miss_rate", "l2_accesses", "l2_misses",
           "l2_miss_rate", "dram_bytes_read",
           "l1d_pf_issued", "l1d_pf_useful", "l1d_pf_unused", "l1d_pf_late",
           "l1d_pf_accuracy", "l1d_pf_coverage",
           "l2_pf_issued", "l2_pf_useful", "l2_pf_unused", "l2_pf_late",
           "l2_pf_accuracy", "l2_pf_coverage",
           "n", "nnz", "sell_padded", "clock_ps", "wall_seconds"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+", help="папки запусков")
    ap.add_argument("-o", "--out", help="CSV (по умолчанию stdout)")
    ap.add_argument("--all-phases", action="store_true",
                    help="включить и прогревочные регионы (по умолчанию только meas)")
    a = ap.parse_args()

    rows = []
    for d in a.runs:
        if not os.path.isdir(d):
            continue
        rr, err = read_run(d)
        if err:
            print("пропуск:", err, file=sys.stderr)
            continue
        rows.extend(r for r in rr if a.all_phases or r["phase"] == "meas")
    out = open(a.out, "w", newline="") if a.out else sys.stdout
    w = csv.DictWriter(out, fieldnames=COLUMNS, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow({k: (f"{v:.10g}" if isinstance(v, float) else v) for k, v in r.items()})
    if a.out:
        out.close()
        print(f"{len(rows)} строк -> {a.out}", file=sys.stderr)
        # короткая сводка в консоль
        print(f"{'run':<14}{'kernel':<16}{'такт/итер':>12}{'vs scalar':>10}{'L1D miss':>10}  проверка",
              file=sys.stderr)
        for r in rows:
            print(f"{r['run']:<14}{r['kernel']:<16}{r['cycles_per_iter']:>12.0f}"
                  f"{r['speedup_vs_scalar']:>10.2f}{r['l1d_miss_rate']:>10.3f}"
                  f"  {'ok' if r['verified'] else 'НЕВЕРНО'}", file=sys.stderr)


if __name__ == "__main__":
    main()

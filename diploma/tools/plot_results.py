#!/usr/bin/env python3
"""
Графики по CSV из parse_stats.py (нужен matplotlib: sudo apt install python3-matplotlib).

  python3 tools/plot_results.py pf  results/pf_l1d_nasa2910.csv  -o results/fig_pf_l1d_nasa2910.png
  python3 tools/plot_results.py lat results/lat_nasa2910.csv     -o results/fig_lat_nasa2910.png

pf  -- ускорение каждого ядра от префетчера относительно запуска "none".
lat -- такты на итерацию в зависимости от латентности группы операций;
       пунктир -- скалярное ядро; в консоль печатается точка пересечения.
"""
import argparse
import csv
import math
import sys
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Цвет закреплён за ядром (а не за позицией), маркер -- второй признак.
KERNELS = ["csr_scalar", "csr_rvv_red", "csr_rvv_acc", "sellcs_rvv",
           "csr_rvv_slide", "sellcs_rvv_mem"]
COLOR = dict(zip(KERNELS, ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#6250d6"]))
MARK = dict(zip(KERNELS, ["o", "s", "^", "D", "v", "P"]))
LABEL = {"csr_scalar": "CSR скаляр", "csr_rvv_red": "CSR RVV (редукция на порцию)",
         "csr_rvv_acc": "CSR RVV (накопление)", "sellcs_rvv": "SELL-C-σ RVV",
         "csr_rvv_slide": "CSR RVV (vslidedown)", "sellcs_rvv_mem": "SELL-C-σ RVV (через память)"}
PF_ORDER = ["none", "tagged", "stride", "ampm", "bop", "dcpt", "sms", "imp", "spp", "isb", "lab"]
INK, MUTED, GRID = "#1f1f1e", "#6b6a64", "#e4e3de"
# латентности групп в binary_run.py (для vec_fp: SimdFloatMult/MultAcc = 6, Add = 5)
LAB_LAT = {"gather": 7, "vload": 5, "vec_fp": 6, "vec_red": 7, "vec_misc": 12}
GROUP_DESC = {"gather": "vluxei32", "vload": "vle32", "vstore": "vse32, vsuxei32",
              "vec_fp": "vfmul, vfmacc, vfadd", "vec_red": "vfred*sum",
              "vec_misc": "vfmv, vslidedown", "vec_int": "vsll, vsetvli",
              "vec_mem": "все векторные загрузки/записи", "vec_all": "все векторные"}


def load(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def style(ax):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(MUTED)
    ax.tick_params(colors=MUTED, labelcolor=INK)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def plot_pf(rows, out, title):
    cyc = defaultdict(dict)
    for r in rows:
        cyc[r["kernel"]][r["run"]] = float(r["cycles_per_iter"])
    kernels = [k for k in KERNELS if k in cyc]
    pfs = [p for p in PF_ORDER if any(p in cyc[k] for k in kernels)]
    if "none" not in pfs:
        sys.exit("нужен запуск none (без префетчера)")
    shown = [p for p in pfs if p != "none"]
    tick = {"lab": "lab\n(SMS в L2)"}
    w = 0.8 / len(kernels)
    off = lambda i: (i - (len(kernels) - 1) / 2) * w
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(1.15 * len(pfs) + 3.2, 7.6))
    # (а) абсолютные такты: видно, какое ядро быстрее при каждом префетчере
    for i, k in enumerate(kernels):
        xs = [j + off(i) for j, p in enumerate(pfs) if p in cyc[k]]
        ys = [cyc[k][p] / 1e6 for p in pfs if p in cyc[k]]
        ax1.bar(xs, ys, width=w * 0.9, color=COLOR[k], label=LABEL[k],
                edgecolor="white", linewidth=1)
    ax1.set_xticks(range(len(pfs)))
    ax1.set_xticklabels([tick.get(p, p) for p in pfs])
    ax1.set_ylabel("млн тактов на итерацию\n(меньше -- лучше)", color=INK)
    ax1.set_title(title, color=INK, loc="left")
    style(ax1)
    ax1.legend(frameon=False, fontsize=8, loc="upper left", bbox_to_anchor=(1, 1))
    # (б) ускорение каждого ядра от префетчера
    for i, k in enumerate(kernels):
        xs, ys = [], []
        for j, p in enumerate(shown):
            if p in cyc[k]:
                xs.append(j + off(i))
                ys.append(cyc[k]["none"] / cyc[k][p])
        ax2.bar(xs, [y - 1 for y in ys], bottom=1, width=w * 0.9, color=COLOR[k],
                label=LABEL[k], edgecolor="white", linewidth=1)
    ax2.axhline(1, color=INK, linewidth=1)
    ax2.set_xticks(range(len(shown)))
    ax2.set_xticklabels([tick.get(p, p) for p in shown])
    ax2.set_ylabel("ускорение относительно\n«без префетчера»", color=INK)
    style(ax2)
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    print("таблица (такты на итерацию):")
    print(f"{'pf':<8}" + "".join(f"{k:>16}" for k in kernels))
    for p in pfs:
        print(f"{p:<8}" + "".join(f"{cyc[k].get(p, math.nan):>16.0f}" for k in kernels))


def plot_lat(rows, out, title):
    data = defaultdict(lambda: defaultdict(dict))  # group -> kernel -> lat -> cycles
    base = {}
    for r in rows:
        run = r["run"]
        c = float(r["cycles_per_iter"])
        if run == "base":
            base[r["kernel"]] = c
            continue
        g, v = run.rsplit("_", 1)
        data[g][r["kernel"]][int(v)] = c
    order = ["gather", "vload", "vstore", "vec_fp", "vec_red", "vec_misc", "vec_int",
             "vec_mem", "vec_all"]
    groups = [g for g in order if g in data] + sorted(g for g in data if g not in order)
    ncol = min(3, len(groups))
    nrow = math.ceil(len(groups) / ncol)
    fig, axes = plt.subplots(nrow, ncol, figsize=(4.2 * ncol, 3.4 * nrow), squeeze=False)
    print(f"{'группа':<10}{'ядро':<16}{'выигрыш до lat':>16}{'проигрыш с lat':>16}")
    for gi, g in enumerate(groups):
        ax = axes[gi // ncol][gi % ncol]
        scal = data[g].get("csr_scalar")
        sval = sum(scal.values()) / len(scal) if scal else base.get("csr_scalar")
        for k in KERNELS:
            if k == "csr_scalar" or k not in data[g]:
                continue
            lats = sorted(data[g][k])
            ys = [data[g][k][l] / 1e6 for l in lats]
            ax.plot(lats, ys, color=COLOR[k], marker=MARK[k], markersize=6,
                    linewidth=2, label=LABEL[k])
            win = [l for l in lats if data[g][k][l] < sval]
            lose = [l for l in lats if data[g][k][l] >= sval]
            print(f"{g:<10}{k:<16}{(max(win) if win else '-'):>16}{(min(lose) if lose else '-'):>16}")
        if sval:
            ax.axhline(sval / 1e6, color=INK, linestyle="--", linewidth=1.2,
                       label=LABEL["csr_scalar"])
        if g in LAB_LAT:  # значение в конфигурации лаборатории
            ax.axvline(LAB_LAT[g], color=MUTED, linestyle=":", linewidth=1.2,
                       label="латентность в конфиге лаборатории")
        ax.set_xscale("log", base=2)
        ax.set_xticks(sorted({l for k in data[g] for l in data[g][k]}))
        ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
        ax.set_title(f"{g}: {GROUP_DESC.get(g, '')}", color=INK, loc="left", fontsize=10)
        ax.set_xlabel("латентность, тактов", color=MUTED, fontsize=8)
        ax.set_ylabel("млн тактов на итерацию", color=MUTED, fontsize=8)
        style(ax)
    for gi in range(len(groups), nrow * ncol):
        axes[gi // ncol][gi % ncol].axis("off")
    hl = {}
    for ax in axes.flat:
        for h, l in zip(*ax.get_legend_handles_labels()):
            hl.setdefault(l, h)
    fig.legend(list(hl.values()), list(hl), frameon=False, fontsize=8,
               loc="lower center", ncol=len(hl))
    fig.suptitle(title, color=INK, x=0.01, ha="left")
    fig.tight_layout(rect=(0, 0.06, 1, 0.97))
    fig.savefig(out, dpi=200)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["pf", "lat"])
    ap.add_argument("csv")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    rows = [r for r in load(a.csv) if r["phase"] == "meas"]
    bad = [r for r in rows if r["verified"] != "True"]
    if bad:
        # Ядро посчитало неверно (VERIFY FAIL): такты такого запуска не
        # используются, точка на графике пропускается.
        print("ВНИМАНИЕ: исключены точки с неверным результатом (VERIFY FAIL):")
        for r in bad:
            print(f"   {r['run']:<14}{r['kernel']}")
        rows = [r for r in rows if r["verified"] == "True"]
    mat = rows[0]["matrix"] if rows else ""
    if a.kind == "pf":
        plot_pf(rows, a.out, a.title or f"Префетчеры, {mat}")
    else:
        plot_lat(rows, a.out, a.title or f"Латентности RVV, {mat}")
    print("->", a.out)


if __name__ == "__main__":
    main()

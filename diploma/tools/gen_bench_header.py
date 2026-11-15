#!/usr/bin/env python3
"""
Генератор заголовка для бенчмарка SpMV (одна матрица -> один .h).

Что кладётся в заголовок (всё const, попадает в .rodata, gem5 загружает это
вместе с бинарником -- в симуляторе на подготовку данных не тратится ни одной
инструкции):
  * CSR:          csr_row_ptr, csr_col_idx, csr_vals
  * SELL-C-sigma: sell_slice_ptr, sell_slice_len, sell_col_idx, sell_vals,
                  sell_row_perm   (column-major внутри слайса, как у Kreutzer et al.)
  * эталон:       y_ref (посчитан в double), y_tol (допуск на ошибку округления
                  для каждой строки)

Вектор x в программе задаётся как x[i] = (float)i * 0.001f -- здесь он
воспроизводится бит-в-бит, поэтому y_ref соответствует именно этому x.

Использование:
  python3 gen_bench_header.py matrices/nasa2910.mtx gen/nasa2910.h [--C 8] [--sigma 64]
"""
import argparse
import os
import struct
import sys

F32 = struct.Struct("<f")


def f32(v: float) -> float:
    """Округлить double до ближайшего float32 (как делает железо)."""
    return F32.unpack(F32.pack(v))[0]


def read_mtx(path):
    with open(path, "r") as f:
        header = f.readline().strip().lower().split()
        if len(header) < 5 or header[0] != "%%matrixmarket" or header[1] != "matrix":
            sys.exit(f"{path}: не MatrixMarket matrix")
        if header[2] != "coordinate":
            sys.exit(f"{path}: поддерживается только coordinate-формат")
        field, symm = header[3], header[4]
        if field not in ("real", "integer", "pattern"):
            sys.exit(f"{path}: тип поля {field} не поддерживается")
        if symm not in ("general", "symmetric"):
            sys.exit(f"{path}: симметрия {symm} не поддерживается")
        line = f.readline()
        while line.startswith("%"):
            line = f.readline()
        n, m, nnz_file = map(int, line.split())
        rows = [dict() for _ in range(n)]  # строка -> {столбец: значение}
        for _ in range(nnz_file):
            parts = f.readline().split()
            i, j = int(parts[0]) - 1, int(parts[1]) - 1
            v = 1.0 if field == "pattern" else float(parts[2])
            rows[i][j] = rows[i].get(j, 0.0) + v
            if symm == "symmetric" and i != j:
                rows[j][i] = rows[j].get(i, 0.0) + v
    return n, m, symm, rows


def build_csr(n, rows):
    row_ptr = [0]
    col_idx, vals = [], []
    for i in range(n):
        for j in sorted(rows[i]):
            col_idx.append(j)
            vals.append(f32(rows[i][j]))
        row_ptr.append(len(col_idx))
    return row_ptr, col_idx, vals


def build_sell(n, row_ptr, col_idx, vals, C, sigma):
    """SELL-C-sigma: сортировка строк по убыванию NNZ внутри окон sigma,
    слайсы по C строк, внутри слайса column-major (j-й элемент всех строк подряд).
    Сортировка устойчивая -> результат детерминирован."""
    row_nnz = [row_ptr[i + 1] - row_ptr[i] for i in range(n)]
    perm = []
    for w0 in range(0, n, sigma):
        w = list(range(w0, min(w0 + sigma, n)))
        w.sort(key=lambda r: -row_nnz[r])  # sort() в Python устойчивая
        perm.extend(w)
    slice_ptr, slice_len, s_col, s_val = [0], [], [], []
    nslices = (n + C - 1) // C
    for s in range(nslices):
        rs = perm[s * C: min((s + 1) * C, n)]
        L = max(row_nnz[r] for r in rs)
        slice_len.append(L)
        for j in range(L):
            for r in rs:
                if j < row_nnz[r]:
                    k = row_ptr[r] + j
                    s_col.append(col_idx[k])
                    s_val.append(vals[k])
                else:  # паддинг: 0 * x[0] = 0
                    s_col.append(0)
                    s_val.append(0.0)
        slice_ptr.append(len(s_col))
    return perm, slice_ptr, slice_len, s_col, s_val


def reference(n, m, row_ptr, col_idx, vals):
    x = [f32(f32(float(i)) * f32(0.001)) for i in range(m)]  # == (float)i * 0.001f
    eps = 2.0 ** -23
    y_ref, y_tol = [], []
    for i in range(n):
        s = 0.0
        a = 0.0
        for k in range(row_ptr[i], row_ptr[i + 1]):
            p = vals[k] * x[col_idx[k]]
            s += p
            a += abs(p)
        cnt = row_ptr[i + 1] - row_ptr[i]
        y_ref.append(f32(s))
        # граница ошибки суммирования float32 длины cnt: ~cnt*eps*sum|a_ij*x_j|
        y_tol.append(f32((cnt + 4) * eps * a + 1e-30))
    return y_ref, y_tol


def write_array(f, ctype, name, size_expr, data, per_line, fmt):
    f.write(f"static const {ctype} {name}[{size_expr}] ARRAY_ATTR = {{\n")
    for i in range(0, len(data), per_line):
        f.write(",".join(fmt(v) for v in data[i:i + per_line]))
        f.write(",\n" if i + per_line < len(data) else "\n")
    f.write("};\n\n")


def fl(v):
    s = "%.9g" % v
    if "." not in s and "e" not in s and "n" not in s:
        s += ".0"
    return s + "f"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mtx")
    ap.add_argument("out")
    ap.add_argument("--C", type=int, default=8, help="высота слайса (= VLMAX для e32m1 при VLEN=256)")
    ap.add_argument("--sigma", type=int, default=64, help="окно сортировки")
    a = ap.parse_args()

    name = os.path.basename(a.mtx).rsplit(".", 1)[0]
    n, m, symm, rows = read_mtx(a.mtx)
    row_ptr, col_idx, vals = build_csr(n, rows)
    del rows
    nnz = len(vals)
    sigma = min(a.sigma, n)
    if sigma % a.C != 0 and sigma != n:
        sys.exit("sigma должна делиться на C, иначе слайс попадёт в два окна")
    perm, sp, sl, sc, sv = build_sell(n, row_ptr, col_idx, vals, a.C, sigma)
    y_ref, y_tol = reference(n, m, row_ptr, col_idx, vals)

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    u = lambda v: "%du" % v
    with open(a.out, "w") as f:
        f.write("/* Сгенерировано tools/gen_bench_header.py из %s (%s). Не редактировать. */\n"
                % (os.path.basename(a.mtx), symm))
        f.write("#pragma once\n#include <stdint.h>\n\n")
        # ARRAY_ATTR задаёт build.sh (ALIGN=...) для опыта с размещением данных
        f.write("#ifndef ARRAY_ATTR\n#define ARRAY_ATTR\n#endif\n\n")
        f.write(f'#define MAT_NAME "{name}"\n')
        f.write(f"#define MAT_N {n}u\n#define MAT_M {m}u\n#define MAT_NNZ {nnz}u\n")
        f.write(f"#define SELL_C {a.C}u\n#define SELL_SIGMA {sigma}u\n")
        f.write(f"#define SELL_NSLICES {len(sl)}u\n#define SELL_NNZ_PADDED {len(sv)}u\n\n")
        write_array(f, "uint32_t", "csr_row_ptr", "MAT_N + 1", row_ptr, 16, u)
        write_array(f, "uint32_t", "csr_col_idx", "MAT_NNZ", col_idx, 16, u)
        write_array(f, "float", "csr_vals", "MAT_NNZ", vals, 8, fl)
        write_array(f, "uint32_t", "sell_slice_ptr", "SELL_NSLICES + 1", sp, 16, u)
        write_array(f, "uint32_t", "sell_slice_len", "SELL_NSLICES", sl, 16, u)
        write_array(f, "uint32_t", "sell_row_perm", "MAT_N", perm, 16, u)
        write_array(f, "uint32_t", "sell_col_idx", "SELL_NNZ_PADDED", sc, 16, u)
        write_array(f, "float", "sell_vals", "SELL_NNZ_PADDED", sv, 8, fl)
        write_array(f, "float", "y_ref", "MAT_N", y_ref, 8, fl)
        write_array(f, "float", "y_tol", "MAT_N", y_tol, 8, fl)

    data_kb = (nnz * 8 + (n + 1) * 4) / 1024
    print(f"{name}: n={n} m={m} nnz={nnz} nnz/row={nnz / n:.1f} | "
          f"SELL-{a.C}-{sigma}: slices={len(sl)} padded={len(sv)} overhead={len(sv) / nnz:.3f} | "
          f"CSR data={data_kb:.0f} KiB, x={m * 4 / 1024:.1f} KiB -> {a.out}")


if __name__ == "__main__":
    main()

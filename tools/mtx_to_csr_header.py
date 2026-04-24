import sys

def read_matrix_market(path):
    with open(path, "r") as f:
        header = f.readline().strip().lower()
        symmetric = "symmetric" in header

        line = f.readline()
        while line.startswith("%"):
            line = f.readline()

        n, m, nnz = map(int, line.split())

        entries = []
        for _ in range(nnz):
            i, j, val = f.readline().split()
            i = int(i) - 1
            j = int(j) - 1
            val = float(val)

            entries.append((i, j, val))
            if symmetric and i != j:
                entries.append((j, i, val))

    return n, m, entries

def coo_to_csr(n, m, entries):
    entries.sort(key=lambda x: (x[0], x[1]))

    row_ptr = [0] * (n + 1)
    col_idx = []
    vals = []

    for i, j, v in entries:
        row_ptr[i + 1] += 1
        col_idx.append(j)
        vals.append(v)

    for i in range(n):
        row_ptr[i + 1] += row_ptr[i]

    return row_ptr, col_idx, vals

def write_header(path, n, m, row_ptr, col_idx, vals):
    with open(path, "w") as f:
        f.write("#pragma once\n")
        f.write("#include <stdint.h>\n\n")
        f.write(f"#define CSR_N {n}u\n")
        f.write(f"#define CSR_M {m}u\n")
        f.write(f"#define CSR_NNZ {len(vals)}u\n\n")

        f.write("static uint32_t csr_row_ptr[CSR_N + 1] = {\n")
        for i, x in enumerate(row_ptr):
            f.write(f"{x}u")
            if i + 1 != len(row_ptr):
                f.write(",")
            if (i + 1) % 16 == 0:
                f.write("\n")
        f.write("\n};\n\n")

        f.write("static uint32_t csr_col_idx[CSR_NNZ] = {\n")
        for i, x in enumerate(col_idx):
            f.write(f"{x}u")
            if i + 1 != len(col_idx):
                f.write(",")
            if (i + 1) % 16 == 0:
                f.write("\n")
        f.write("\n};\n\n")

        f.write("static float csr_vals[CSR_NNZ] = {\n")
        for i, x in enumerate(vals):
            s = f"{float(x):.8e}"   # всегда scientific notation
            f.write(f"{s}f")
            if i + 1 != len(vals):
                f.write(",")
            if (i + 1) % 8 == 0:
                f.write("\n")
        f.write("\n};\n")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 mtx_to_csr_header.py input.mtx output.h")
        sys.exit(1)

    mtx_path = sys.argv[1]
    out_path = sys.argv[2]

    n, m, entries = read_matrix_market(mtx_path)
    row_ptr, col_idx, vals = coo_to_csr(n, m, entries)
    write_header(out_path, n, m, row_ptr, col_idx, vals)

    print(f"Done: n={n}, m={m}, nnz={len(vals)}")

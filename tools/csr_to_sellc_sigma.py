import sys
import numpy as np


def csr_to_sellc_sigma(row_ptr, col_idx, vals, C=8):
    """
    Конвертирует CSR в SELL-C-Sigma формат
    
    Parameters:
    - row_ptr, col_idx, vals: CSR формат
    - C: размер слайса (обычно 8, 16, или 32)
    
    Returns:
    - slice_ptr: границы слайсов
    - slice_lengths: макс nnz в каждом слайсе
    - slice_col_idx: индексы столбцов
    - slice_vals: значения
    """
    
    n = len(row_ptr) - 1
    num_slices = (n + C - 1) // C 
    
    slice_ptr = [0]
    slice_lengths = []
    slice_col_idx = []
    slice_vals = []
    
    for slice_id in range(num_slices):
        row_start = slice_id * C
        row_end = min((slice_id + 1) * C, n)
        
        max_nnz = 0
        for row in range(row_start, row_end):
            nnz_in_row = row_ptr[row + 1] - row_ptr[row]
            max_nnz = max(max_nnz, nnz_in_row)
        
        slice_lengths.append(max_nnz)
        
        slice_start_idx = len(slice_col_idx)
        
        for row in range(row_start, row_end):
            row_nnz_start = row_ptr[row]
            row_nnz_end = row_ptr[row + 1]
            
            for idx in range(row_nnz_start, row_nnz_end):
                slice_col_idx.append(col_idx[idx])
                slice_vals.append(vals[idx])
            
            nnz_in_row = row_nnz_end - row_nnz_start
            for _ in range(max_nnz - nnz_in_row):
                slice_col_idx.append(0)  # dummy index
                slice_vals.append(0.0)   # dummy value
        
        slice_ptr.append(len(slice_col_idx))
    
    return slice_ptr, slice_lengths, slice_col_idx, slice_vals, num_slices


def write_sellc_sigma_header(path, matrix_name, n, m, C, 
                              slice_ptr, slice_lengths, 
                              slice_col_idx, slice_vals, num_slices):
    """Генерирует C header файл с SELL-C-Sigma данными"""
    
    uname = matrix_name.upper()
    lname = matrix_name.lower()
    
    with open(path, "w") as f:
        f.write("#pragma once\n")
        f.write("#include <stdint.h>\n\n")
        
        f.write(f"#define {uname}_N {n}u\n")
        f.write(f"#define {uname}_M {m}u\n")
        f.write(f"#define {uname}_C {C}u\n")
        f.write(f"#define {uname}_NUM_SLICES {num_slices}u\n")
        f.write(f"#define {uname}_NNZ_PADDED {len(slice_vals)}u\n\n")
        
        # slice_ptr
        f.write(f"static uint32_t {lname}_slice_ptr[{uname}_NUM_SLICES + 1] = {{\n")
        for i, x in enumerate(slice_ptr):
            f.write(f"{x}u")
            if i + 1 != len(slice_ptr):
                f.write(",")
            if (i + 1) % 16 == 0:
                f.write("\n")
        f.write("\n};\n\n")
        
        # slice_lengths
        f.write(f"static uint32_t {lname}_slice_lengths[{uname}_NUM_SLICES] = {{\n")
        for i, x in enumerate(slice_lengths):
            f.write(f"{x}u")
            if i + 1 != len(slice_lengths):
                f.write(",")
            if (i + 1) % 16 == 0:
                f.write("\n")
        f.write("\n};\n\n")
        
        # slice_col_idx
        f.write(f"static uint32_t {lname}_slice_col_idx[{uname}_NNZ_PADDED] = {{\n")
        for i, x in enumerate(slice_col_idx):
            f.write(f"{x}u")
            if i + 1 != len(slice_col_idx):
                f.write(",")
            if (i + 1) % 16 == 0:
                f.write("\n")
        f.write("\n};\n\n")
        
        # slice_vals
        f.write(f"static float {lname}_slice_vals[{uname}_NNZ_PADDED] = {{\n")
        for i, x in enumerate(slice_vals):
            s = f"{float(x):.8e}"
            f.write(f"{s}f")
            if i + 1 != len(slice_vals):
                f.write(",")
            if (i + 1) % 8 == 0:
                f.write("\n")
        f.write("\n};\n")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 csr_to_sellc_sigma.py input_csr.h output.h [C=8]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    C = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    
    # Читай CSR из header файла (если уже есть)
    print(f"Converting to SELL-C-Sigma with C={C}...")
    print(f"Output: {output_file}")
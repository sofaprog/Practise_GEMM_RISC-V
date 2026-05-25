#include <riscv_vector.h>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <iomanip>
#include <string>
#include <vector>
#include <algorithm>

#include "../../generated/nasa2910.h"
#include "../../generated/bcsstk13.h"
#include "../../generated/ex5.h"
#include "../../generated/hood.h"
#include "../../generated/shipsec1.h"
#include "../../generated/raefsky3.h"
#include "../../generated/pwtk.h"
#include "../../generated/ecology2.h"
#include "../../generated/crystm03.h"
#include "../../generated/bcsstk18.h"


struct CSRf32 {
    uint32_t n{};
    uint32_t m{};
    uint32_t nnz{};

    std::vector<float> vals;
    std::vector<uint32_t> col_idx;
    std::vector<uint32_t> row_ptr;
};

struct SELLCSigma {
    uint32_t n;        
    uint32_t m;         
    uint32_t C;          
    uint32_t num_slices;
    uint32_t nnz_padded;
    
    std::vector<uint32_t> slice_ptr;  
    std::vector<uint32_t> slice_lengths; 
    std::vector<uint32_t> slice_col_idx; 
    std::vector<float> slice_vals;      
};

static volatile float sink[1];


CSRf32 make_matrix(
    uint32_t n,
    uint32_t m,
    uint32_t nnz,
    const float* vals,
    const uint32_t* col_idx,
    const uint32_t* row_ptr
) {
    CSRf32 A;
    A.n = n;
    A.m = m;
    A.nnz = nnz;

    A.vals.assign(vals, vals + nnz);
    A.col_idx.assign(col_idx, col_idx + nnz);
    A.row_ptr.assign(row_ptr, row_ptr + n + 1);

    return A;
}

SELLCSigma csr_to_sellc_sigma(const CSRf32& A_csr, uint32_t C = 8) {
    SELLCSigma A;
    A.n = A_csr.n;
    A.m = A_csr.m;
    A.C = C;
    A.num_slices = (A_csr.n + C - 1) / C;
    
    A.slice_ptr.resize(A.num_slices + 1);
    A.slice_lengths.resize(A.num_slices);
    
    A.slice_ptr[0] = 0;
    

    for (uint32_t sid = 0; sid < A.num_slices; ++sid) {
        uint32_t row_start = sid * C;
        uint32_t row_end = std::min((sid + 1) * C, A_csr.n);
        
        uint32_t max_nnz = 0;
        for (uint32_t row = row_start; row < row_end; ++row) {
            uint32_t nnz_in_row = A_csr.row_ptr[row + 1] - A_csr.row_ptr[row];
            max_nnz = std::max(max_nnz, nnz_in_row);
        }
        
        A.slice_lengths[sid] = max_nnz;
        
        for (uint32_t row = row_start; row < row_end; ++row) {
            uint32_t row_nnz_start = A_csr.row_ptr[row];
            uint32_t row_nnz_end = A_csr.row_ptr[row + 1];
            uint32_t nnz_in_row = row_nnz_end - row_nnz_start;
            
            for (uint32_t idx = row_nnz_start; idx < row_nnz_end; ++idx) {
                A.slice_col_idx.push_back(A_csr.col_idx[idx]);
                A.slice_vals.push_back(A_csr.vals[idx]);
            }
            
            for (uint32_t p = 0; p < max_nnz - nnz_in_row; ++p) {
                A.slice_col_idx.push_back(0);
                A.slice_vals.push_back(0.0f);
            }
        }
        
        A.slice_ptr[sid + 1] = A.slice_col_idx.size();
    }
    
    A.nnz_padded = A.slice_col_idx.size();
    return A;
}


void spmv_csr_scalar(const CSRf32& A, const float* x, float* y) {
    for (uint32_t r = 0; r < A.n; ++r) {
        float sum = 0.0f;
        for (uint32_t k = A.row_ptr[r]; k < A.row_ptr[r + 1]; ++k) {
            sum += A.vals[k] * x[A.col_idx[k]];
        }
        y[r] = sum;
    }
}

void spmv_csr_rvv(const CSRf32& A, const float* x, float* y) {
    for (uint32_t r = 0; r < A.n; ++r) {
        float sum = 0.0f;
        uint32_t row_start = A.row_ptr[r];
        uint32_t row_end = A.row_ptr[r + 1];
        uint32_t k = row_start;

        while (k < row_end) {
            size_t vl = __riscv_vsetvl_e32m1(row_end - k);

            vfloat32m1_t vvals = __riscv_vle32_v_f32m1(&A.vals[k], vl);
            vuint32m1_t vcols = __riscv_vle32_v_u32m1(&A.col_idx[k], vl);
            vuint32m1_t voff = __riscv_vsll_vx_u32m1(vcols, 2, vl);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(x, voff, vl);
            vfloat32m1_t vprod = __riscv_vfmul_vv_f32m1(vvals, vx, vl);

            vfloat32m1_t vzero = __riscv_vfmv_v_f_f32m1(0.0f, vl);
            vfloat32m1_t vred = __riscv_vfredosum_vs_f32m1_f32m1(vprod, vzero, vl);

            sum += __riscv_vfmv_f_s_f32m1_f32(vred);
            k += static_cast<uint32_t>(vl);
        }
        y[r] = sum;
    }
}


void spmv_sellc_sigma_scalar(const SELLCSigma& A, const float* x, float* y) {
    for (uint32_t sid = 0; sid < A.num_slices; ++sid) {
        uint32_t row_start = sid * A.C;
        uint32_t row_end = std::min((sid + 1) * A.C, A.n);
        uint32_t slice_len = A.slice_lengths[sid];
        uint32_t slice_idx = A.slice_ptr[sid];
        
        for (uint32_t row = row_start; row < row_end; ++row) {
            float sum = 0.0f;
            uint32_t local_row = row - row_start;
            
            for (uint32_t k = 0; k < slice_len; ++k) {
                uint32_t global_idx = slice_idx + local_row * slice_len + k;
                uint32_t col = A.slice_col_idx[global_idx];
                float val = A.slice_vals[global_idx];
                sum += val * x[col];
            }
            
            y[row] = sum;
        }
    }
}

void spmv_sellc_sigma_rvv(const SELLCSigma& A, const float* x, float* y) {
    for (uint32_t sid = 0; sid < A.num_slices; ++sid) {
        uint32_t row_start = sid * A.C;
        uint32_t row_end = std::min((sid + 1) * A.C, A.n);
        uint32_t slice_len = A.slice_lengths[sid];
        uint32_t slice_idx = A.slice_ptr[sid];
        
        for (uint32_t row = row_start; row < row_end; ++row) {
            float sum = 0.0f;
            uint32_t local_row = row - row_start;
            uint32_t k = 0;
            
            while (k < slice_len) {
                size_t vl = __riscv_vsetvl_e32m1(slice_len - k);
                
                uint32_t base_idx = slice_idx + local_row * slice_len + k;
                
                vuint32m1_t vcols = __riscv_vle32_v_u32m1(
                    &A.slice_col_idx[base_idx], vl);
                
                vfloat32m1_t vvals = __riscv_vle32_v_f32m1(
                    &A.slice_vals[base_idx], vl);
                
                vuint32m1_t voff = __riscv_vsll_vx_u32m1(vcols, 2, vl);
                vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(x, voff, vl);
                vfloat32m1_t vprod = __riscv_vfmul_vv_f32m1(vvals, vx, vl);
                
                vfloat32m1_t vzero = __riscv_vfmv_v_f_f32m1(0.0f, vl);
                vfloat32m1_t vred = __riscv_vfredosum_vs_f32m1_f32m1(vprod, vzero, vl);
                
                sum += __riscv_vfmv_f_s_f32m1_f32(vred);
                k += static_cast<uint32_t>(vl);
            }
            
            y[row] = sum;
        }
    }
}


bool verify_results(
    const std::vector<float>& ref,
    const std::vector<float>& test
) {
    for (size_t i = 0; i < ref.size(); ++i) {
        float diff = std::fabs(ref[i] - test[i]);
        float rel_tol = 1e-2f * std::fabs(ref[i]);
        float abs_tol = 1e-2f;
        float tol = std::max(abs_tol, rel_tol);

        if (diff > tol) {
            std::cout << "VERIFY FAIL at i=" << i
                      << " ref=" << ref[i]
                      << " got=" << test[i]
                      << " diff=" << diff
                      << " tol=" << tol << "\n";
            return false;
        }
    }
    return true;
}


int main() {
    std::vector<CSRf32> matrices;

    // Добавь все матрицы
    matrices.push_back(make_matrix(NASA2910_N, NASA2910_M, NASA2910_NNZ,
        nasa2910_vals, nasa2910_col_idx, nasa2910_row_ptr));
    matrices.push_back(make_matrix(BCSSTK13_N, BCSSTK13_M, BCSSTK13_NNZ,
        bcsstk13_vals, bcsstk13_col_idx, bcsstk13_row_ptr));
    matrices.push_back(make_matrix(SHIPSEC1_N, SHIPSEC1_M, SHIPSEC1_NNZ,
        shipsec1_vals, shipsec1_col_idx, shipsec1_row_ptr));
    matrices.push_back(make_matrix(RAEFSKY3_N, RAEFSKY3_M, RAEFSKY3_NNZ,
        raefsky3_vals, raefsky3_col_idx, raefsky3_row_ptr));
    matrices.push_back(make_matrix(PWTK_N, PWTK_M, PWTK_NNZ,
        pwtk_vals, pwtk_col_idx, pwtk_row_ptr));
    matrices.push_back(make_matrix(HOOD_N, HOOD_M, HOOD_NNZ,
        hood_vals, hood_col_idx, hood_row_ptr));
    matrices.push_back(make_matrix(EX5_N, EX5_M, EX5_NNZ,
        ex5_vals, ex5_col_idx, ex5_row_ptr));
    matrices.push_back(make_matrix(ECOLOGY2_N, ECOLOGY2_M, ECOLOGY2_NNZ,
        ecology2_vals, ecology2_col_idx, ecology2_row_ptr));
    matrices.push_back(make_matrix(CRYSTM03_N, CRYSTM03_M, CRYSTM03_NNZ,
        crystm03_vals, crystm03_col_idx, crystm03_row_ptr));
    matrices.push_back(make_matrix(BCSSTK18_N, BCSSTK18_M, BCSSTK18_NNZ,
        bcsstk18_vals, bcsstk18_col_idx, bcsstk18_row_ptr));

    std::cout << "\n" << std::string(90, '=') << "\n"
              << "SPARSE MATRIX-VECTOR MULTIPLICATION: CSR vs SELL-C-Sigma\n"
              << std::string(90, '=') << "\n\n";

    double total_csr_scalar = 0.0, total_csr_rvv = 0.0, total_sellc_rvv = 0.0;

    for (size_t mid = 0; mid < matrices.size(); ++mid) {
        CSRf32& A_csr = matrices[mid];

        std::cout << "MATRIX #" << mid << " | "
                  << "N=" << A_csr.n << " M=" << A_csr.m << " NNZ=" << A_csr.nnz;

        double sparsity = 100.0 * A_csr.nnz / (double)(A_csr.n * A_csr.m);
        std::cout << " | Sparsity=" << std::fixed << std::setprecision(2) 
                  << sparsity << "%\n";

        // Векторы
        std::vector<float> x(A_csr.m);
        std::vector<float> y_csr_scalar(A_csr.n, 0.0f);
        std::vector<float> y_csr_rvv(A_csr.n, 0.0f);
        std::vector<float> y_sellc_rvv(A_csr.n, 0.0f);

        for (uint32_t i = 0; i < A_csr.m; ++i) {
            x[i] = static_cast<float>(i) * 0.001f;
        }

        auto t1 = std::chrono::high_resolution_clock::now();
        spmv_csr_scalar(A_csr, x.data(), y_csr_scalar.data());
        auto t2 = std::chrono::high_resolution_clock::now();
        auto csr_scalar_us = std::chrono::duration_cast<std::chrono::microseconds>(t2 - t1).count();

        auto t3 = std::chrono::high_resolution_clock::now();
        spmv_csr_rvv(A_csr, x.data(), y_csr_rvv.data());
        auto t4 = std::chrono::high_resolution_clock::now();
        auto csr_rvv_us = std::chrono::duration_cast<std::chrono::microseconds>(t4 - t3).count();

        if (!verify_results(y_csr_scalar, y_csr_rvv)) {
            std::cerr << "CSR RVV verification failed!\n";
            return 1;
        }

        SELLCSigma A_sellc = csr_to_sellc_sigma(A_csr, 8);

        auto t5 = std::chrono::high_resolution_clock::now();
        spmv_sellc_sigma_rvv(A_sellc, x.data(), y_sellc_rvv.data());
        auto t6 = std::chrono::high_resolution_clock::now();
        auto sellc_rvv_us = std::chrono::duration_cast<std::chrono::microseconds>(t6 - t5).count();

        if (!verify_results(y_csr_scalar, y_sellc_rvv)) {
            std::cerr << "SELL-C-Sigma RVV verification failed!\n";
            return 1;
        }

        double csr_scalar_gflops = (2.0 * A_csr.nnz) / (csr_scalar_us * 1e-6) / 1e9;
        double csr_rvv_gflops = (2.0 * A_csr.nnz) / (csr_rvv_us * 1e-6) / 1e9;
        double sellc_rvv_gflops = (2.0 * A_csr.nnz) / (sellc_rvv_us * 1e-6) / 1e9;

        double csr_speedup = (double)csr_scalar_us / (double)csr_rvv_us;
        double sellc_vs_csr = (double)csr_rvv_us / (double)sellc_rvv_us;

        std::cout << std::fixed << std::setprecision(2)
                  << "  CSR Scalar:     " << std::setw(6) << csr_scalar_us << " µs | "
                  << std::setw(5) << csr_scalar_gflops << " GFLOP/s\n"
                  << "  CSR RVV:        " << std::setw(6) << csr_rvv_us << " µs | "
                  << std::setw(5) << csr_rvv_gflops << " GFLOP/s | "
                  << "Speedup: " << std::setw(5) << csr_speedup << "x\n"
                  << "  SELL-C Sigma:   " << std::setw(6) << sellc_rvv_us << " µs | "
                  << std::setw(5) << sellc_rvv_gflops << " GFLOP/s | "
                  << "vs CSR RVV: " << std::setw(5) << sellc_vs_csr << "x\n"
                  << "  Memory overhead (SELL-C): "
                  << (double)A_sellc.nnz_padded / (double)A_csr.nnz << "x\n\n";

        total_csr_scalar += csr_scalar_us;
        total_csr_rvv += csr_rvv_us;
        total_sellc_rvv += sellc_rvv_us;

        sink[0] = y_csr_rvv[0];
    }

    std::cout << std::string(90, '=') << "\n"
              << "TOTAL STATISTICS\n"
              << std::string(90, '=') << "\n";

    std::cout << std::fixed << std::setprecision(2)
              << "CSR Scalar Total:    " << total_csr_scalar << " µs\n"
              << "CSR RVV Total:       " << total_csr_rvv << " µs | "
              << "Speedup: " << (total_csr_scalar / total_csr_rvv) << "x\n"
              << "SELL-C Sigma Total:  " << total_sellc_rvv << " µs | "
              << "vs CSR RVV: " << (total_csr_rvv / total_sellc_rvv) << "x\n"
              << std::string(90, '=') << "\n";

    return 0;
}
#include "csr_common.h"
#include <riscv_vector.h>
#include <math.h>
#include <stdio.h>

#ifndef ITERS
#define ITERS 50
#endif

#ifndef VERIFY
#define VERIFY 0
#endif

#ifndef DBG
#define DBG 0
#endif

static void spmv_rvv(const CSRf32* A, const float* x, float* y) {
    for (uint32_t r = 0; r < A->n; ++r) {
        uint32_t start = A->row_ptr[r];
        uint32_t end   = A->row_ptr[r + 1];

        float sum = 0.0f;
        uint32_t i = start;

        while (i < end) {
            size_t vl = __riscv_vsetvl_e32m1((size_t)(end - i));

            vfloat32m1_t vvals = __riscv_vle32_v_f32m1(&A->vals[i], vl);
            vuint32m1_t  vcol  = __riscv_vle32_v_u32m1(&A->col_idx[i], vl);

            // vluxei32 expects BYTE offsets
            vuint32m1_t  voff  = __riscv_vsll_vx_u32m1(vcol, 2, vl);
            vfloat32m1_t vx    = __riscv_vluxei32_v_f32m1(x, voff, vl);

            vfloat32m1_t vprod = __riscv_vfmul_vv_f32m1(vvals, vx, vl);

            vfloat32m1_t zero = __riscv_vfmv_v_f_f32m1(0.0f, vl);
            vfloat32m1_t red  = __riscv_vfredosum_vs_f32m1_f32m1(vprod, zero, vl);
            sum += __riscv_vfmv_f_s_f32m1_f32(red);

            i += (uint32_t)vl;
        }

        y[r] = sum;
    }
}

#if VERIFY
static void spmv_scalar_ref(const CSRf32* A, const float* x, float* y) {
    for (uint32_t r = 0; r < A->n; ++r) {
        float sum = 0.0f;
        uint32_t start = A->row_ptr[r];
        uint32_t end   = A->row_ptr[r + 1];
        for (uint32_t i = start; i < end; ++i) {
            sum += A->vals[i] * x[A->col_idx[i]];
        }
        y[r] = sum;
    }
}
#endif

int main(void) {
    CSRf32 A = csr_generate();

    static float x[CSR_N];
    static float y[CSR_N];

#if VERIFY
    static float y_ref[CSR_N];
#endif

    for (uint32_t i = 0; i < A.n; ++i) {
        x[i] = (float)i * 0.001f;
        y[i] = 0.0f;
#if VERIFY
        y_ref[i] = 0.0f;
#endif
    }

#if DBG
    printf("CSR n=%u m=%u nnz=%u row0=[%u,%u)\n",
           A.n, A.m, A.nnz, A.row_ptr[0], A.row_ptr[1]);
#endif

#if VERIFY
    spmv_scalar_ref(&A, x, y_ref);
    spmv_rvv(&A, x, y);

    for (uint32_t i = 0; i < A.n; ++i) {
        float diff = fabsf(y_ref[i] - y[i]);
        float tol  = 1e-4f * fmaxf(1.0f, fabsf(y_ref[i]));
        if (diff > tol) {
            printf("VERIFY FAIL at i=%u ref=%f got=%f diff=%f\n",
                   i, y_ref[i], y[i], diff);
            return 1;
        }
    }
    printf("VERIFY OK\n");

    for (uint32_t i = 0; i < A.n; ++i) y[i] = 0.0f;
#endif

    for (int it = 0; it < ITERS; ++it) {
        spmv_rvv(&A, x, y);
    }

    *sink_ptr() = y[0];
    return 0;
}

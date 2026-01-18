#include "csr_common.h"

#ifndef ITERS
#define ITERS 50
#endif

static void spmv_scalar(const CSRf32* A, const float* x, float* y) {
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

int main(void) {
    CSRf32 A = csr_generate();

    static float x[CSR_N];
    static float y[CSR_N];

    for (uint32_t i = 0; i < A.n; ++i) {
        x[i] = (float)i * 0.001f;
        y[i] = 0.0f;
    }

    for (int it = 0; it < ITERS; ++it) {
        spmv_scalar(&A, x, y);
    }

    *sink_ptr() = y[0];
    return 0;
}

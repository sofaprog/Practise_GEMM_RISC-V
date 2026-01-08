#include "csr_common.h"

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
    CSRf32 A = csr_test_4x4();
    static float x[4] = {1.f, 2.f, 3.f, 4.f};
    static float y[4] = {0};

    spmv_scalar(&A, x, y);

    *sink_ptr() = y[0];
    return 0;
}

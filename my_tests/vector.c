#include "csr_common.h"
#include <riscv_vector.h>

static float hsum_f32m1(vfloat32m1_t v, size_t vl) {
    vfloat32m1_t zero = __riscv_vfmv_v_f_f32m1(0.0f, vl);
    vfloat32m1_t red  = __riscv_vfredosum_vs_f32m1_f32m1(v, zero, vl);
    return __riscv_vfmv_f_s_f32m1_f32(red);
}

static void spmv_rvv(const CSRf32* A, const float* x, float* y) {
    for (uint32_t r = 0; r < A->n; ++r) {
        uint32_t start = A->row_ptr[r];
        uint32_t end   = A->row_ptr[r + 1];

        float sum = 0.0f;
        uint32_t i = start;

        while (i < end) {
            size_t vl = __riscv_vsetvl_e32m1((size_t)(end - i));

            vfloat32m1_t vvals = __riscv_vle32_v_f32m1(&A->vals[i], vl);
            vuint32m1_t vcol = __riscv_vle32_v_u32m1(&A->col_idx[i], vl);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(x, vcol, vl);
            vfloat32m1_t vprod = __riscv_vfmul_vv_f32m1(vvals, vx, vl);
            sum += hsum_f32m1(vprod, vl);

            i += (uint32_t)vl;
        }

        y[r] = sum;
    }
}

int main(void) {
    CSRf32 A = csr_test_4x4();
    static float x[4] = {1.f, 2.f, 3.f, 4.f};
    static float y[4] = {0};

    spmv_rvv(&A, x, y);

    *sink_ptr() = y[0];
    return 0;
}

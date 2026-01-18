#include <riscv_vector.h>
#include <stdio.h>

int main() {
    static float a[16];
    for (int i = 0; i < 16; ++i) a[i] = (float)(i + 1);

    size_t vl = __riscv_vsetvl_e32m1(16);
    vfloat32m1_t v = __riscv_vle32_v_f32m1(a, vl);

    float lane0 = __riscv_vfmv_f_s_f32m1_f32(v);
    printf("a0=%f lane0=%f vl=%zu\n", a[0], lane0, vl);
    return 0;
}

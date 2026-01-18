#include <riscv_vector.h>
#include <stdio.h>

int main() {
    static const float a[16] = {
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    };

    size_t vl = __riscv_vsetvl_e32m1(16);
    vfloat32m1_t v = __riscv_vle32_v_f32m1(a, vl);

    float lane0 = __riscv_vfmv_f_s_f32m1_f32(v);
    printf("const a0=%f lane0=%f vl=%zu\n", a[0], lane0, vl);
    return 0;
}

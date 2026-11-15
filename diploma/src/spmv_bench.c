/*
 * SpMV-бенчмарк для gem5 SE: CSR (скаляр, RVV) и SELL-C-sigma (RVV).
 *
 * Одна матрица на бинарник: заголовок генерирует tools/gen_bench_header.py,
 * путь передаётся через -DMATRIX_HEADER='"gen/nasa2910.h"'.
 *
 * Каждое ядро запускается в двух регионах:
 *   <kernel>:warm  -- WARMUP прогонов (прогрев кэшей, обучение префетчера);
 *                     после него проверяется корректность результата;
 *   <kernel>:meas  -- ITERS прогонов, это и есть измерение.
 * На границах регионов вызывается m5_dump_reset_stats, поэтому в stats.txt
 * для каждого региона есть отдельный блок статистики (такты, промахи кэшей,
 * счётчики префетчера). Порядок блоков в stats.txt:
 *   [0] запуск ... первый регион
 *   [1] регион 0, [2] промежуток, [3] регион 1, [4] промежуток, ...
 * Имена регионов печатаются в stdout строками "@REGION <k> <имя>".
 *
 * Аргументы командной строки (необязательно): список ядер, например
 *   spmv_nasa2910 csr_scalar sellcs_rvv
 * По умолчанию: csr_scalar csr_rvv_red csr_rvv_acc sellcs_rvv.
 *
 * Сборка (см. scripts/build.sh):
 *   rvv-gcc -O2 -fno-tree-vectorize -fno-tree-slp-vectorize -march=rv64gcv
 *           -mabi=lp64d -static -DUSE_M5OPS -DMATRIX_HEADER='"gen/x.h"' ...
 * -fno-tree-vectorize нужен, чтобы компилятор сам не векторизовал скалярное
 * ядро: интринсики RVV от этого флага не зависят.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <riscv_vector.h>

#ifndef MATRIX_HEADER
#error "Задайте -DMATRIX_HEADER='\"gen/<matrix>.h\"'"
#endif
#include MATRIX_HEADER

#ifndef WARMUP
#define WARMUP 1
#endif
#ifndef ITERS
#define ITERS 2
#endif

/* ---------- m5ops (псевдо-инструкция gem5, opcode custom-3) ---------- */
#ifdef USE_M5OPS
static inline void m5_dump_reset_stats(void)
{
    register uint64_t a0 __asm__("a0") = 0; /* delay  */
    register uint64_t a1 __asm__("a1") = 0; /* period */
    __asm__ volatile(".long 0x0000007b | (0x42 << 25)"
                     : "+r"(a0) : "r"(a1) : "memory");
}
#else
static inline void m5_dump_reset_stats(void) {} /* для запуска в QEMU */
#endif

static int g_region = 0;
static void region_begin(const char *kernel, const char *phase)
{
    printf("@REGION %d %s:%s\n", g_region++, kernel, phase);
    fflush(stdout);
    m5_dump_reset_stats(); /* закрыли промежуток, начали регион */
}
static void region_end(void)
{
    m5_dump_reset_stats(); /* закрыли регион */
}

static float x[MAT_M];
static float y[MAT_N];

/* =====================================================================
 * 1. CSR, скалярная версия (эталон производительности)
 * ===================================================================== */
__attribute__((noinline)) static void
spmv_csr_scalar(const float *restrict xv, float *restrict yv)
{
    for (uint32_t r = 0; r < MAT_N; ++r) {
        float sum = 0.0f;
        for (uint32_t k = csr_row_ptr[r]; k < csr_row_ptr[r + 1]; ++k)
            sum += csr_vals[k] * xv[csr_col_idx[k]];
        yv[r] = sum;
    }
}

/* =====================================================================
 * 2. CSR + RVV, редукция vfredosum на каждой порции из vl элементов
 *    (алгоритм отчёта прошлого семестра, vector.c)
 * ===================================================================== */
__attribute__((noinline)) static void
spmv_csr_rvv_red(const float *restrict xv, float *restrict yv)
{
    for (uint32_t r = 0; r < MAT_N; ++r) {
        uint32_t k = csr_row_ptr[r], end = csr_row_ptr[r + 1];
        float sum = 0.0f;
        while (k < end) {
            size_t vl = __riscv_vsetvl_e32m1(end - k);
            vfloat32m1_t vv = __riscv_vle32_v_f32m1(&csr_vals[k], vl);
            vuint32m1_t vc = __riscv_vle32_v_u32m1(&csr_col_idx[k], vl);
            vuint32m1_t vo = __riscv_vsll_vx_u32m1(vc, 2, vl); /* байтовые смещения */
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(xv, vo, vl);
            vfloat32m1_t vp = __riscv_vfmul_vv_f32m1(vv, vx, vl);
            vfloat32m1_t vz = __riscv_vfmv_v_f_f32m1(0.0f, vl);
            vfloat32m1_t vs = __riscv_vfredosum_vs_f32m1_f32m1(vp, vz, vl);
            sum += __riscv_vfmv_f_s_f32m1_f32(vs);
            k += (uint32_t)vl;
        }
        yv[r] = sum;
    }
}

/* =====================================================================
 * 3. CSR + RVV, накопление в векторном регистре (vfmacc) по полным порциям
 *    из VLMAX элементов и не больше двух редукций на строку.
 *    Хвост строки (< VLMAX элементов) сворачивается отдельной редукцией,
 *    её результат подаётся начальным значением в основную. Так ядро не
 *    зависит от политики хвоста (tu/ta): GCC 13 для vfmacc_..._tu выдаёт
 *    vsetvli с "ta", и на это полагаться нельзя.
 * ===================================================================== */
__attribute__((noinline)) static void
spmv_csr_rvv_acc(const float *restrict xv, float *restrict yv)
{
    const size_t vlmax = __riscv_vsetvlmax_e32m1();
    const vfloat32m1_t vzero = __riscv_vfmv_v_f_f32m1(0.0f, vlmax);
    for (uint32_t r = 0; r < MAT_N; ++r) {
        uint32_t k = csr_row_ptr[r];
        const uint32_t end = csr_row_ptr[r + 1];
        vfloat32m1_t acc = vzero;
        for (; k + vlmax <= end; k += (uint32_t)vlmax) {
            vfloat32m1_t vv = __riscv_vle32_v_f32m1(&csr_vals[k], vlmax);
            vuint32m1_t vc = __riscv_vle32_v_u32m1(&csr_col_idx[k], vlmax);
            vuint32m1_t vo = __riscv_vsll_vx_u32m1(vc, 2, vlmax);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(xv, vo, vlmax);
            acc = __riscv_vfmacc_vv_f32m1(acc, vv, vx, vlmax);
        }
        vfloat32m1_t init = vzero;
        if (k < end) {
            size_t vl = __riscv_vsetvl_e32m1(end - k);
            vfloat32m1_t vv = __riscv_vle32_v_f32m1(&csr_vals[k], vl);
            vuint32m1_t vc = __riscv_vle32_v_u32m1(&csr_col_idx[k], vl);
            vuint32m1_t vo = __riscv_vsll_vx_u32m1(vc, 2, vl);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(xv, vo, vl);
            vfloat32m1_t vp = __riscv_vfmul_vv_f32m1(vv, vx, vl);
            init = __riscv_vfredusum_vs_f32m1_f32m1(vp, vzero, vl);
        }
        vfloat32m1_t vs = __riscv_vfredusum_vs_f32m1_f32m1(acc, init, vlmax);
        yv[r] = __riscv_vfmv_f_s_f32m1_f32(vs);
    }
}

/* =====================================================================
 * 4. SELL-C-sigma + RVV: C строк слайса = элементы вектора, накопление
 *    в регистре (vfmacc), редукций нет; результат раскладывается в исходный
 *    порядок строк одной indexed-store (vsuxei32) по sell_row_perm
 *    (как в Listing 1 у Gomez et al. 2020).
 * ===================================================================== */
__attribute__((noinline)) static void
spmv_sellcs_rvv(const float *restrict xv, float *restrict yv)
{
    for (uint32_t s = 0; s < SELL_NSLICES; ++s) {
        const uint32_t r0 = s * SELL_C;
        const uint32_t rows = (MAT_N - r0 < SELL_C) ? (MAT_N - r0) : SELL_C;
        const uint32_t base = sell_slice_ptr[s];
        const uint32_t len = sell_slice_len[s];
        for (uint32_t rr = 0; rr < rows;) { /* при VLEN>=256 ровно один проход */
            size_t vl = __riscv_vsetvl_e32m1(rows - rr);
            const float *pv = &sell_vals[base + rr];
            const uint32_t *pc = &sell_col_idx[base + rr];
            vfloat32m1_t acc = __riscv_vfmv_v_f_f32m1(0.0f, vl);
            for (uint32_t j = 0; j < len; ++j) {
                vfloat32m1_t vv = __riscv_vle32_v_f32m1(pv, vl);
                vuint32m1_t vc = __riscv_vle32_v_u32m1(pc, vl);
                vuint32m1_t vo = __riscv_vsll_vx_u32m1(vc, 2, vl);
                vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(xv, vo, vl);
                acc = __riscv_vfmacc_vv_f32m1(acc, vv, vx, vl);
                pv += rows;
                pc += rows;
            }
            vuint32m1_t vp = __riscv_vle32_v_u32m1(&sell_row_perm[r0 + rr], vl);
            __riscv_vsuxei32_v_f32m1(yv, __riscv_vsll_vx_u32m1(vp, 2, vl), acc, vl);
            rr += (uint32_t)vl;
        }
    }
}

/* =====================================================================
 * Необязательные ядра: реализации из весеннего/летнего main.cpp, чтобы
 * можно было воспроизвести старые замеры при -O2 (по умолчанию не запускаются).
 * ===================================================================== */
/* 5. CSR + RVV, извлечение каждого произведения через vslidedown + vfmv.f.s */
__attribute__((noinline)) static void
spmv_csr_rvv_slide(const float *restrict xv, float *restrict yv)
{
    for (uint32_t r = 0; r < MAT_N; ++r) {
        uint32_t k = csr_row_ptr[r], end = csr_row_ptr[r + 1];
        float sum = 0.0f;
        while (k < end) {
            size_t vl = __riscv_vsetvl_e32m1(end - k);
            vfloat32m1_t vv = __riscv_vle32_v_f32m1(&csr_vals[k], vl);
            vuint32m1_t vc = __riscv_vle32_v_u32m1(&csr_col_idx[k], vl);
            vuint32m1_t vo = __riscv_vsll_vx_u32m1(vc, 2, vl);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(xv, vo, vl);
            vfloat32m1_t vp = __riscv_vfmul_vv_f32m1(vv, vx, vl);
            for (size_t i = 0; i < vl; ++i)
                sum += __riscv_vfmv_f_s_f32m1_f32(
                    __riscv_vslidedown_vx_f32m1(vp, i, vl));
            k += (uint32_t)vl;
        }
        yv[r] = sum;
    }
}

/* 6. SELL-C-sigma + RVV с накоплением через память (vle32 y / vfadd / vse32
 *    на каждом шаге j) и отдельным проходом обратной перестановки */
static float y_perm[MAT_N];
__attribute__((noinline)) static void
spmv_sellcs_rvv_mem(const float *restrict xv, float *restrict yv)
{
    memset(y_perm, 0, sizeof(y_perm));
    for (uint32_t s = 0; s < SELL_NSLICES; ++s) {
        const uint32_t r0 = s * SELL_C;
        const uint32_t rows = (MAT_N - r0 < SELL_C) ? (MAT_N - r0) : SELL_C;
        const uint32_t base = sell_slice_ptr[s];
        const uint32_t len = sell_slice_len[s];
        for (uint32_t j = 0; j < len; ++j) {
            uint32_t idx = base + j * rows;
            size_t vl = __riscv_vsetvl_e32m1(rows);
            vuint32m1_t vc = __riscv_vle32_v_u32m1(&sell_col_idx[idx], vl);
            vfloat32m1_t vv = __riscv_vle32_v_f32m1(&sell_vals[idx], vl);
            vuint32m1_t vo = __riscv_vsll_vx_u32m1(vc, 2, vl);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(xv, vo, vl);
            vfloat32m1_t vp = __riscv_vfmul_vv_f32m1(vv, vx, vl);
            vfloat32m1_t vy = __riscv_vle32_v_f32m1(&y_perm[r0], vl);
            __riscv_vse32_v_f32m1(&y_perm[r0], __riscv_vfadd_vv_f32m1(vy, vp, vl), vl);
        }
    }
    for (uint32_t i = 0; i < MAT_N; ++i)
        yv[sell_row_perm[i]] = y_perm[i];
}

/* ===================================================================== */
typedef void (*kernel_fn)(const float *restrict, float *restrict);
static const struct { const char *name; kernel_fn fn; int by_default; } KERNELS[] = {
    {"csr_scalar",     spmv_csr_scalar,     1},
    {"csr_rvv_red",    spmv_csr_rvv_red,    1},
    {"csr_rvv_acc",    spmv_csr_rvv_acc,    1},
    {"sellcs_rvv",     spmv_sellcs_rvv,     1},
    {"csr_rvv_slide",  spmv_csr_rvv_slide,  0},
    {"sellcs_rvv_mem", spmv_sellcs_rvv_mem, 0},
};
#define NKERNELS ((int)(sizeof(KERNELS) / sizeof(KERNELS[0])))

static int verify(const char *name)
{
    uint32_t bad = 0, first = 0;
    for (uint32_t i = 0; i < MAT_N; ++i) {
        if (!(fabsf(y[i] - y_ref[i]) <= y_tol[i])) { /* NaN тоже ловим */
            if (!bad) first = i;
            ++bad;
        }
    }
    if (bad) {
        printf("VERIFY FAIL %s: %u строк, первая i=%u ref=%.9g got=%.9g tol=%.3g\n",
               name, bad, first, y_ref[first], y[first], y_tol[first]);
        return 1;
    }
    printf("VERIFY OK %s\n", name);
    return 0;
}

static void run_kernel(int id)
{
    const char *name = KERNELS[id].name;
    memset(y, 0, sizeof(y));
    region_begin(name, "warm");
    for (int it = 0; it < WARMUP; ++it)
        KERNELS[id].fn(x, y);
    region_end();
    int fail = verify(name);
    memset(y, 0, sizeof(y));
    region_begin(name, "meas");
    for (int it = 0; it < ITERS; ++it)
        KERNELS[id].fn(x, y);
    region_end();
    fail |= verify(name);
    if (fail)
        printf("@FAIL %s\n", name);
}

int main(int argc, char **argv)
{
    for (uint32_t i = 0; i < MAT_M; ++i)
        x[i] = (float)i * 0.001f;

    printf("@MATRIX %s n=%u m=%u nnz=%u sell_c=%u sigma=%u padded=%u\n",
           MAT_NAME, MAT_N, MAT_M, MAT_NNZ, SELL_C, SELL_SIGMA, SELL_NNZ_PADDED);
    printf("@CONFIG warmup=%d iters=%d vlmax_e32m1=%u\n",
           WARMUP, ITERS, (unsigned)__riscv_vsetvlmax_e32m1());

    if (argc <= 1) {
        for (int k = 0; k < NKERNELS; ++k)
            if (KERNELS[k].by_default)
                run_kernel(k);
    } else {
        for (int a = 1; a < argc; ++a) {
            int found = -1;
            for (int k = 0; k < NKERNELS; ++k)
                if (strcmp(argv[a], KERNELS[k].name) == 0)
                    found = k;
            if (found < 0) {
                printf("unknown kernel: %s\n", argv[a]);
                return 2;
            }
            run_kernel(found);
        }
    }
    printf("@DONE\n");
    return 0;
}

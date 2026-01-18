#pragma once
#include <stddef.h>
#include <stdint.h>

#ifndef CSR_N
#define CSR_N 1024u
#endif

#ifndef CSR_NNZ_PER_ROW
#define CSR_NNZ_PER_ROW 16u
#endif

#define CSR_NNZ (CSR_N * CSR_NNZ_PER_ROW)

typedef struct {
    uint32_t n;
    uint32_t m;
    uint32_t nnz;
    float*    vals;
    uint32_t* col_idx;
    uint32_t* row_ptr;
} CSRf32;

static inline CSRf32 csr_generate(void) {
    static float    vals[CSR_NNZ];
    static uint32_t col [CSR_NNZ];
    static uint32_t row [CSR_N + 1];

    uint32_t idx = 0;
    row[0] = 0;

    for (uint32_t r = 0; r < CSR_N; ++r) {
        for (uint32_t t = 0; t < CSR_NNZ_PER_ROW; ++t) {
            uint32_t c = (r + 17u * t) % CSR_N;

            col[idx]  = c;
            vals[idx] = 1.0f / (1.0f + (float)t);
            ++idx;
        }
        row[r + 1] = idx;
    }

    CSRf32 A;
    A.n = CSR_N;
    A.m = CSR_N;
    A.nnz = CSR_NNZ;
    A.vals = vals;
    A.col_idx = col;
    A.row_ptr = row;
    return A;
}

static inline volatile float* sink_ptr(void) {
    static volatile float sink[1];
    return sink;
}

#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t n;  
    uint32_t m;   
    uint32_t nnz; 
    const float* vals; 
    const uint32_t* col_idx;
    const uint32_t* row_ptr;
} CSRf32;

static inline CSRf32 csr_test_4x4(void) {
    static const float vals[] = { 10.f, 2.f, 3.f, 9.f, 7.f, 8.f, 6.f };
    static const uint32_t col[] = { 0,   3,  0,  1,  1,  2,  3 };
    static const uint32_t row[] = { 0,   2,  4,  6,  7 }; 
    CSRf32 A = { 4, 4, 7, vals, col, row };
    return A;
}

static inline volatile float* sink_ptr(void) {
    static volatile float sink[1];
    return sink;
}

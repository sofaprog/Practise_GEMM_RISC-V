#include <riscv_vector.h>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <algorithm>

struct CSRf32 {
    uint32_t n{};
    uint32_t m{};
    uint32_t nnz{};
    std::vector<float> vals;
    std::vector<uint32_t> col_idx;
    std::vector<uint32_t> row_ptr;
};

static volatile float sink[1];

struct Entry {
    uint32_t r;
    uint32_t c;
    float v;
};

CSRf32 read_matrix_market_to_csr(const std::string& path) {

    std::ifstream fin(path);
    if (!fin) {
        throw std::runtime_error("Cannot open file: " + path);
    }

    std::string line;
    bool symmetric = false;

    if (!std::getline(fin, line)) {
        throw std::runtime_error("Empty file");
    }

    if (line.find("symmetric") != std::string::npos ||
        line.find("SYMMETRIC") != std::string::npos) {
        symmetric = true;
    }

    do {
        if (!std::getline(fin, line)) {
            throw std::runtime_error("Unexpected end of file while reading header");
        }
    } while (!line.empty() && line[0] == '%');

    std::istringstream dims(line);
    uint32_t n, m, nnz_file;
    dims >> n >> m >> nnz_file;


    std::vector<Entry> entries;
    entries.reserve(symmetric ? nnz_file * 2 : nnz_file);

    for (uint32_t k = 0; k < nnz_file; ++k) {
        uint32_t i, j;
        float val;
        fin >> i >> j >> val;

        --i;
        --j;

        entries.push_back({i, j, val});
        if (symmetric && i != j) {
            entries.push_back({j, i, val});
        }

    }

    std::sort(entries.begin(), entries.end(), [](const Entry& a, const Entry& b) {
        if (a.r != b.r) return a.r < b.r;
        return a.c < b.c;
    });

    CSRf32 A;
    A.n = n;
    A.m = m;
    A.nnz = static_cast<uint32_t>(entries.size());
    A.vals.resize(A.nnz);
    A.col_idx.resize(A.nnz);
    A.row_ptr.assign(n + 1, 0);

    for (const auto& e : entries) {
        A.row_ptr[e.r + 1]++;
    }

    for (uint32_t i = 0; i < n; ++i) {
        A.row_ptr[i + 1] += A.row_ptr[i];
    }


    std::vector<uint32_t> offset = A.row_ptr;


    for (const auto& e : entries) {
        uint32_t pos = offset[e.r]++;
        A.vals[pos] = e.v;
        A.col_idx[pos] = e.c;
    }

    return A;
}

void spmv_scalar(const CSRf32& A, const float* x, float* y) {
    for (uint32_t r = 0; r < A.n; ++r) {
        float sum = 0.0f;
        for (uint32_t k = A.row_ptr[r]; k < A.row_ptr[r + 1]; ++k) {
            sum += A.vals[k] * x[A.col_idx[k]];
        }
        y[r] = sum;
    }
}

void spmv_rvv(const CSRf32& A, const float* x, float* y) {
    for (uint32_t r = 0; r < A.n; ++r) {
        float sum = 0.0f;
        uint32_t k = A.row_ptr[r];

        while (k < A.row_ptr[r + 1]) {
            size_t vl = __riscv_vsetvl_e32m1(A.row_ptr[r + 1] - k);

            vfloat32m1_t vvals = __riscv_vle32_v_f32m1(&A.vals[k], vl);
            vuint32m1_t  vcol  = __riscv_vle32_v_u32m1(&A.col_idx[k], vl);

            vuint32m1_t voff = __riscv_vsll_vx_u32m1(vcol, 2, vl);
            vfloat32m1_t vx = __riscv_vluxei32_v_f32m1(x, voff, vl);

            vfloat32m1_t vprod = __riscv_vfmul_vv_f32m1(vvals, vx, vl);
            vfloat32m1_t zero  = __riscv_vfmv_v_f_f32m1(0.0f, vl);
            vfloat32m1_t red   = __riscv_vfredosum_vs_f32m1_f32m1(vprod, zero, vl);

            sum += __riscv_vfmv_f_s_f32m1_f32(red);
            k += static_cast<uint32_t>(vl);
        }

        y[r] = sum;
    }
}

bool verify_results(const std::vector<float>& ref, const std::vector<float>& test) {
    for (size_t i = 0; i < ref.size(); ++i) {
        float diff = std::fabs(ref[i] - test[i]);
        float tol  = std::max(1e-4f, 1e-3f * std::fabs(ref[i]));

        if (diff > tol) {
            std::cout << "VERIFY FAIL1 at i=" << i
                      << " ref=" << ref[i]
                      << " got=" << test[i]
                      << " diff=" << diff
                      << " tol=" << tol << "\n";
            return false;
        }
    }
    std::cout << "VERIFY OK\n";
    return true;
}

int main() {

    const std::string path = "matrices/nasa2910.mtx";

    CSRf32 A = read_matrix_market_to_csr(path);

    std::vector<float> x(A.m), y_scalar(A.n, 0.0f), y_rvv(A.n, 0.0f);


    for (uint32_t i = 0; i < A.m; ++i) {
        x[i] = static_cast<float>(i) * 0.001f;
    }


    auto t1 = std::chrono::high_resolution_clock::now();
    spmv_scalar(A, x.data(), y_scalar.data());
    auto t2 = std::chrono::high_resolution_clock::now();


    auto scalar_us =
        std::chrono::duration_cast<std::chrono::microseconds>(t2 - t1).count();

    auto t3 = std::chrono::high_resolution_clock::now();
    spmv_rvv(A, x.data(), y_rvv.data());
    auto t4 = std::chrono::high_resolution_clock::now();


    auto rvv_us =
        std::chrono::duration_cast<std::chrono::microseconds>(t4 - t3).count();

    if (!verify_results(y_scalar, y_rvv)) {
        return 1;
    }

    std::cout << "scalar_us=" << scalar_us << "\n";
    std::cout << "rvv_us=" << rvv_us << "\n";

    sink[0] = y_rvv[0];
    return 0;
}
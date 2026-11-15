# RVV-cross-ext
This repository is designed to explore the cross product instruction based on gem5.

## Gem5
For our work, we use gem5. This repository contains a submodule with the modified [gem5](https://github.com/gem5/gem5) version 23.1. gem5 requires additional packages that can be installed using the following command line:

```shell
sudo apt install build-essential git m4 scons zlib1g zlib1g-dev libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev python3-dev libboost-all-dev pkg-config python3-tk
```
You may also need to install additional Python libraries that are required by gem5 (```pip install -r requirements.txt```).

gem5 itself can be built using the standard instructions of this package. We recommend using the suggested script (the built package will be located in ./gem5_bin/RISCV):

```shell
sh build_gem5.sh
```

## RISC-V Toolchain
To compile programs, we use a modified version of GCC from the [risc-v-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain) repository. Before compiling the required version of the compiler, you also need to install additional programs:

```shell
sudo apt-get install autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev
```

Changes in the corresponding submodule are contained in patches. Therefore, for correct assembly, we recommend using the build script:

```shell
sh build_toolchain.sh
```

If you used a script, then the environment variables can be configured by the script:

```shell
source compiler_vars.sh
```

After completing all the steps, the compilers will be accessible under the names ```rvv-gcc``` and ```rvv-g++```. If you have not used the scripts we recommended, then the names and paths to the compiler may differ.

## Example core

In our experiments, we employ our proposed RVV-enabled version of the RISC-V core configuration. Expert users can tailor their own settings.

Additionally, in the gem5_board folder, we provide a script that allows the binary to run on certain standard boards in system call mode:

```shell
<path_to_gem5_dir>/RISCV/gem5.opt binary_run.py <your_binary>
```

## Simple example

The code_example folder contains code showing the operation of the proposed instruction

## Usage
Intrinsic list:
```shell
vfloat32m1_t __riscv_vfcross_vv_f32m1(vfloat32m1_t, vfloat32m1_t, size_t)
vfloat32m2_t __riscv_vfcross_vv_f32m2(vfloat32m2_t, vfloat32m2_t, size_t)
vfloat32m4_t __riscv_vfcross_vv_f32m4(vfloat32m4_t, vfloat32m4_t, size_t)
vfloat32m8_t __riscv_vfcross_vv_f32m8(vfloat32m8_t, vfloat32m8_t, size_t)

vfloat64m1_t __riscv_vfcross_vv_f64m1(vfloat64m1_t, vfloat64m1_t, size_t)
vfloat64m2_t __riscv_vfcross_vv_f64m2(vfloat64m2_t, vfloat64m2_t, size_t)
vfloat64m4_t __riscv_vfcross_vv_f64m4(vfloat64m4_t, vfloat64m4_t, size_t)
vfloat64m8_t __riscv_vfcross_vv_f64m8(vfloat64m8_t, vfloat64m8_t, size_t)
```
## Дипломная работа: SpMV (CSR, SELL-C-σ) на RVV в gem5

Эксперименты с префетчерами и латентностями векторных операций лежат в папке
[`diploma/`](diploma/README.md): код бенчмарка, конфигурация gem5, скрипты
запусков и результаты (CSV, машинный код ядер).
Папка `my_tests/` содержит более ранние версии кода (январь–сентябрь 2026).

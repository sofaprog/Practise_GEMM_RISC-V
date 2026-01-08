#!/bin/sh

rvv-gcc -O2 -march=rv64gcv rvv_cross.c -static -lm -o cross
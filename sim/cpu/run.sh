#!/bin/bash
# T80 DAA test against the Z80 reference
set -e
cd "$(dirname "$0")"
mkdir -p out
verilator --cc --exe --build -j "$(nproc)" -O2 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
  --top-module daa_tb -Mdir out/obj ../../rtl/t80/T80s.v daa_tb.v "$PWD/daa_main.cpp" \
  > out/build.log 2>&1 || { grep -E "%Error|error:" out/build.log | head; exit 1; }
out/obj/Vdaa_tb

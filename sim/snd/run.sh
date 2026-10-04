#!/bin/bash
# Sound board NMI stress test. Usage: sim/snd/run.sh [commands] [cpu.v]
set -e
cd "$(dirname "$0")"
CPU=${2:-../../rtl/cpu6502/cpu.v}
mkdir -p out
python3 ../mkroms.py "${FT_ROMS:-$HOME/jt/firetrap/roms}" out firetrap > /dev/null
verilator --cc --exe --build -j "$(nproc)" -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
  -Wno-PINMISSING -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-IMPLICIT -Wno-CASEX -Wno-CASEOVERLAP \
  --top-module snd_tb -DSIMULATION -Mdir out/obj \
  ../../rtl/cpu6502/ALU.v "$CPU" ../../rtl/jt5205/*.v \
  $(ls ../../rtl/jtopl/jtopl.v ../../rtl/jtopl/jtopl_*.v) \
  ../../rtl/dpram.v ../../rtl/ft_sound.v snd_tb.v "$PWD/snd_main.cpp" > out/build.log 2>&1 \
  || { grep %Error out/build.log | head; exit 1; }
out/obj/Vsnd_tb out/rom.bin "${1:-20000}"

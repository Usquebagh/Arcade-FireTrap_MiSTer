#!/bin/bash
# Build and run the Verilator simulation.
#   sim/run.sh [frames] [dump_every]
# ROMs are read from $FT_ROMS (default ~/jt/firetrap/roms), set $FT_SET (default firetrap);
# output goes to sim/out/. The ROM image is loaded through the core's download port.
set -e
cd "$(dirname "$0")"
ROMS=${FT_ROMS:-$HOME/jt/firetrap/roms}
mkdir -p out/roms
python3 mkroms.py "$ROMS" out/roms "${FT_SET:-firetrap}" > /dev/null
mkdir -p out/rtl/jt8051
cp ../rtl/jt8051/jt8051.uc out/rtl/jt8051/   # jt8051 microcode, $readmemb'd relative to the project root

SRC="../rtl/t80/T80s.v
  ../rtl/jt8051/jt8051.v ../rtl/jt8051/jt8051_alu.v ../rtl/jt8051/jt8051_ctrl.v
  ../rtl/jt8051/jt8051_periph.v ../rtl/jt8051/jt8051_regs.v ../rtl/jt8051/jt8051_serial.v
  ../rtl/cpu6502/ALU.v ../rtl/cpu6502/cpu.v ../rtl/jt5205/*.v
  $(ls ../rtl/jtopl/jtopl.v ../rtl/jtopl/jtopl_*.v)
  ../rtl/dpram.v ../rtl/ft_mcu.v ../rtl/ft_sound.v ../rtl/ft_render.v ../rtl/ft_video.v ../rtl/ft_core.v
  sim_top.v"

# Rebuild only when sources changed
if [ ! -x obj_dir/Vsim_top ] || [ -n "$(find ../rtl sim_top.v sim_main.cpp run.sh -newer obj_dir/Vsim_top -name '*.*' | head -1)" ] \
   || [ "$(cat obj_dir/params 2>/dev/null)" != "${VRAM_WAIT}${FT_TRACE_IO}${GFX_SKEW}" ]; then
verilator --cc --exe --build -j "$(nproc)" -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
  -Wno-PINMISSING -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-IMPLICIT \
  --top-module sim_top -DSIMULATION -I../rtl/jt8051 \
  ${VRAM_WAIT:+-GVRAM_WAIT=$VRAM_WAIT} ${GFX_SKEW:+-GGFX_SKEW=$GFX_SKEW} \
  -Mdir obj_dir ${FT_TRACE_IO:+-DFT_TRACE_IO} $SRC sim_main.cpp > out/build.log 2>&1 || { grep -E "%Error" out/build.log | head -30; tail -5 out/build.log; exit 1; }
echo "${VRAM_WAIT}${FT_TRACE_IO}${GFX_SKEW}" > obj_dir/params
grep -E "%Warning" out/build.log | grep -v -E "t80/|jt8051" | head -20 || true
fi

cd out
rm -f frame_*.ppm frame_*.png
time ../obj_dir/Vsim_top "${1:-60}" "${2:-10}"
python3 - <<'EOF'
import glob
from PIL import Image
for f in sorted(glob.glob("frame_*.ppm")):
    Image.open(f).save(f[:-4] + ".png")
EOF
ls frame_*.png 2>/dev/null | tail -3

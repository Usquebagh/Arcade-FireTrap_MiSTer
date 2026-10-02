#!/bin/bash
# Build and run the Verilator simulation.
#   sim/run.sh [frames] [dump_every]
# ROMs are read from $FT_ROMS (default ~/jt/firetrap/roms), set $FT_SET (default firetrap);
# output goes to sim/out/.
set -e
cd "$(dirname "$0")"
ROMS=${FT_ROMS:-$HOME/jt/firetrap/roms}
mkdir -p out/roms
python3 mkroms.py "$ROMS" out/roms "${FT_SET:-firetrap}" > /dev/null
cp ../rtl/jt8051/jt8051.uc out/      # jt8051 microcode, $readmemb'd from the working directory

verilator --cc --exe --build -j "$(nproc)" -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
  -Wno-PINMISSING -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-IMPLICIT \
  --top-module ft_core -DSIMULATION -I../rtl/jt8051 \
  -GMAIN_ROM_INIT='"roms/main.hex"' -GMCU_ROM_INIT='"roms/mcu.hex"' \
  -GCHR_INIT='"roms/chr.hex"' -GPROM_INIT='"roms/prom.hex"' \
  ${VRAM_WAIT:+-GVRAM_WAIT=$VRAM_WAIT} \
  -Mdir obj_dir ${FT_TRACE:+-DFT_TRACE} \
  ../rtl/t80/T80s.v \
  ../rtl/jt8051/jt8051.v ../rtl/jt8051/jt8051_alu.v ../rtl/jt8051/jt8051_ctrl.v \
  ../rtl/jt8051/jt8051_periph.v ../rtl/jt8051/jt8051_regs.v ../rtl/jt8051/jt8051_serial.v \
  ../rtl/dpram.v ../rtl/ft_mcu.v ../rtl/ft_video.v ../rtl/ft_core.v \
  sim_main.cpp > out/build.log 2>&1 || { grep -E "%Error" out/build.log | head -30; tail -5 out/build.log; exit 1; }
grep -E "%Warning" out/build.log | grep -v -E "t80/|jt8051" | head -20 || true

cd out
rm -f frame_*.ppm frame_*.png
time ../obj_dir/Vft_core "${1:-60}" "${2:-10}"
python3 - <<'EOF'
import glob
from PIL import Image
for f in sorted(glob.glob("frame_*.ppm")):
    Image.open(f).save(f[:-4] + ".png")
EOF
ls frame_*.png 2>/dev/null | tail -3

# Fire Trap (Wood Place / Data East USA, 1986) — hardware spec for the FPGA core

Sources, in priority order:
1. **Schematics** in the Data East *Firetrap Installation & Service Manual* (PDF pages 17–48,
   sheet page numbers 15–43; DE-0246-1 top board, DE-0247-2 bottom board). Ground truth for
   structure. Several gates are crossed out by hand ("61.9.22" / "61.9.3" revisions = Showa 61,
   1986); the crossed-out versions are ignored below unless stated.
2. **MAME 0.289** `src/mame/dataeast/firetrap.cpp` (Nicola Salmoria, Stephane Humbert) —
   functional model: memory maps, gfx layouts, ROM loading, DIPs.
3. **PCB measurements** quoted in the MAME driver: XTAL 11.9911 MHz, HSync 15.6137 kHz,
   VSync 57.4034 Hz.

"Sheet N" below means the page number printed on the schematic (PDF page = N + 2).

## Board set

| Board | Contents |
|---|---|
| DE-0246 (top, sheets 15–28) | Z80B, program ROMs/RAM, i8751 + 8 MHz crystal, FG (text) layer, BG1 + BG2 scrolling layers, I/O decode |
| DE-0247 (bottom, sheets 29–43) | 12 MHz crystal, DECO customs HMC20 (H counter), VSC30 (V counter), TC15G032AY "DSPC-10" (sprites + sync), sprite RAM/ROMs, priority + palette PROMs, 6502, YM3526 + YM3014, MSM5205, inputs/DIPs |

## Clocks (sheet 37)

| Signal | Derivation | Frequency |
|---|---|---|
| `*12M` | X1 crystal (MAME: 12.000; PCB measured 11.9911 MHz) | 12 MHz |
| `HCLK` (pixel clock) | HMC20 ÷2 | 6 MHz |
| Z80 φ (`*CPU6M`, sheet 17) | = `HCLK` via 16 (LS38) | 6 MHz |
| `M1H` → YM3526 φM (sheet 43) | ÷4 | 3 MHz |
| `*M2H` → 6502 φ0 (sheet 41) | ÷8 | 1.5 MHz |
| `M8H` (inverted) → MSM5205 XT (sheet 43) | ÷32 | 375 kHz |
| i8751 | own 8 MHz crystal (sheet 26) | 8 MHz, asynchronous to the rest |

FPGA plan: 48 MHz master clock (= 4 × 12 MHz) with clock enables for everything on the 12 MHz
tree; the 8751 gets an enable from a fractional accumulator (8 / 48 = 1/6 exactly, so a plain ÷6).
The 11.9911 MHz measurement is 0.07 % slow — ignore it (57.40 Hz vs 57.44 Hz).

## Video timing

- **384 clocks/line × 272 lines**, both confirmed by the PCB measurements:
  11.9911 MHz / 2 / 15613.7 Hz = 384.0; 15613.7 / 57.4034 = 272.0. MAME's `set_raw(…, 384, 0,
  256, 272, 8, 248)` matches.
- H counter is inside **HMC20** (16A), V counter inside **VSC30** (18A); sync and VBLK come from
  the **DSPC-10** (11C, sheet 34). None of the three customs is documented, so blanking/sync edge
  positions come from MAME: visible **H 0–255**, **V 8–247** (240 lines). HBLK is derived from
  `*M8H` by 18J/18K flip-flops (sheet 38), i.e. on an 8-pixel boundary, consistent with 256
  visible pixels.
- **Display is ROT90** (vertical monitor). Native output is 256 × 240 landscape; rotation is
  done by MiSTer's screen-rotate (`video_freak`/`screen_rotate`) as in other vertical cores.
- **Flip / cocktail**: register F003 (`1P/2P SEL`, latch 4C sheet 17) produces `1P/2P` and
  `*1P/2P`, which XOR the H/V positions on every layer (sheets 20, 21, 37) and make the sprite
  V counter count down (LS669 4D/4C, sheet 31).
- **VBLANK edge for interrupts**: the Z80 NMI flip-flop (5C) is clocked by `VBLK` rising, i.e. at
  the *start* of vertical blank (line 248). MAME instead raises NMI and the MCU INT1 at line 0
  (`configure_scanline(…, 0, 1)`), 24 lines later. Simulation should use the schematic timing;
  frame comparisons against MAME must allow for this.

## Main CPU — Z80B @ 6 MHz

### Memory map (decode sheets 16, 30; agrees with MAME)

| Address | R/W | Function | Decode |
|---|---|---|---|
| 0000–7FFF | R | ROM `di-02.4a` (27256) | 1B |
| 8000–BFFF | R | Banked ROM, 4 × 16 KB: `di-01.3a` (banks 0,1), `di-00-a.2a` (banks 2,3) | 1B + bank latch |
| C000–CFFF | RW | Work RAM (HM6264 6A, 4 KB used) | 2B Y0/Y1 |
| D000–D7FF | RW | BG1 RAM (6116 9E): code/attribute pages alternate every 0x100 | 2B Y2 `*BACK1 EQU` |
| D800–DFFF | RW | BG2 RAM (6116) | 2B Y3 |
| E000–E3FF / E400–E7FF | RW | FG codes / attributes (6116 13B) | 2B Y4 `*FIX EQU` |
| E800–E97F | RW | Sprite RAM (TMM2018 6E, sheet 31; 384 bytes used = 96 × 4) | 2B Y5 `*OBJ SEL` |
| F000 | W | IRQ acknowledge (`*INT CLR`) | 6B Y0 |
| F001 | W | Sound latch + 6502 NMI (`*SOUND SEL`) | 6B Y1 |
| F002 | W | ROM bank, D1:D0 (4B LS74 ×2) | 6B Y2 |
| F003 | W | Flip screen, D0 (`*1P/2P SEL`) | 6B Y3 |
| F004 | W | NMI enable/disable (`*NMI CLR`), D0 = 1 disables | 6B Y4 |
| F005 | W | Data to 8751 P2 (latch 16E) + set 8751 INT0 (`*WR51`) | 6B Y5 |
| F008–F009 / F00A–F00B | W | BG1 X scroll (9 bits) / Y scroll (9 bits) (`*BACK1 POS`) | 5B |
| F00C–F00F | W | BG2 X / Y scroll (`*BACK2 POS`) | 5B |
| F010–F012 | R | IN0, IN1, IN2 | 11H Y0–2 |
| F013–F014 | R | DSW0 (SW1), DSW1 (SW2) | 11H Y3–4 |
| F015 | R | 8751 P3.0 (the IRQ line) on one data bit (`*IRQ EQU`, 15H). Not in MAME's map | 11H Y5 |
| F016 | R | 8751 P1 (`*RD51`, LS245) | 11H Y6 |

### Interrupts (sheet 15)

- **IRQ**: 5C (LS74) set by a *rising* edge of `*IRQ51` = 8751 P3.0, cleared by a write to F000;
  Q̄ drives `/INT` directly. (The coin input and the 6C gate that once ORed into `/INT` are crossed
  out.) MAME asserts on the *falling* edge of P3.0. Which edge matters only if the MCU holds P3.0
  low for a long time; check the MCU code (look at what it does around `CLR P3.0` / `SETB P3.0`).
- **NMI**: VBLK-clocked flip-flop gated by the F004 enable. Working model (= MAME's behaviour):
  NMI goes active at VBLANK start if enabled; writing F004 with D0 = 1 disables and clears it.
  The Z80 NMI is edge-triggered, so it must be released before the next frame (it is released
  at the end of VBLANK).
- **Wait states (`*WAIT`, sheet 17, not in MAME)**: 3C (F74) samples `VRAM` (CPU address in
  D000–E7FF, generated on sheet 15 by 2C/6F) on `*HCLK`; its Q̄ drives `/WAIT`, and its Q gates
  the CPU's chip selects to BG1/BG2/FIX RAM (1C). Its reset comes from 6C (`*HBLK`, `*VBLK`).
  Working model: **the Z80 only gets the tile RAMs during blanking**. An access during active
  display waits until the next HBLANK or VBLANK. Sprite RAM (E800) is not included. The 6C gate
  is drawn as a NOR, which taken literally does not give a sensible function. Before
  implementing, measure how often the game touches D000–E7FF outside VBLANK (Z80 trace in
  MAME). If it never does, the wait logic is irrelevant to timing and can be a simple model.

## Protection MCU — i8751H @ 8 MHz (sheet 26)

| Pin | Direction | Connection |
|---|---|---|
| P0.0 | in | Coin flip-flop 4F Q̄: set by `COIN` (diode-OR of Service/Coin1/Coin2 through RC, sheet 29), reset by P3.4 |
| P0.1 | in | `*SERVICE` |
| P0.2 | in | `*COIN1` |
| P0.3 | in | `*COIN2` |
| P1 | out | → Z80 via LS245, read at F016 |
| P2 | in | ← latch 16E, written by Z80 at F005 |
| P3.0 | out | `*IRQ51` → Z80 IRQ flip-flop; also readable at F015 |
| P3.1 | out | Reset (level) of the INT0 flip-flop 15J |
| P3.2 (INT0) | in | 15J Q̄: set by Z80 write to F005 |
| P3.3 (INT1) | in | `*VBLK` directly (level: low during VBLANK) |
| P3.4 (T0) | out | Reset of the coin flip-flop 4F |

Differences from MAME's model (MAME needs `set_perfect_quantum`; on the FPGA both CPUs simply run
concurrently):
- MAME clears INT0 on a *falling edge* of P3.1. On the board, P3.1 is the flip-flop's **reset
  level**: while P3.1 is low, a Z80 write to F005 cannot set INT0.
- MAME pulses INT1 for one scanline at line 0. On the board, INT1 = `*VBLK` (low for the whole of
  VBLANK, from line 248). Whether this matters depends on IT1 (edge vs level) in TCON; check the
  MCU code.
- MAME models P0.0 as "all coins released" logic; the board has a real flip-flop that the MCU
  must clear with P3.4. Model the flip-flop.

The MCU ROM is in the set (`di-12.16h` US, `fi-13.16h` JP), so no simulation of the protection
is needed: the jt8051 core runs it.

## Video

Draw order (low → high): **BG2, BG1, sprites, FG**, modified by the priority PROM (below).

### FG ("FIX") layer (sheets 18, 19)
- 32 × 32 tiles of 8 × 8, 2 bpp, 512 codes. RAM: code at E000+n, attribute at E400+n.
  Attribute bit 0 = code bit 8; bits 7:4 = colour (16 palettes × 4 colours, palette 0x00–0x3F).
- Memory order: `offset = (row ^ 0x1F) + (col << 5)` (MAME mapper; vertical-first, matching
  the rotated monitor).
- Char ROM `di-03.17c` (2764): A2:0 = VPOS2:0, A10:3 = code 7:0, A11 = code 8, A12 = DHPOS0
  (left/right half of the tile). Each byte = 4 pixels × 2 planes (MAME `charlayout`).
- Pen 0 is transparent.

### BG1 / BG2 layers (sheets 20–25)
- Each: 32 × 32 tiles of 16 × 16, 4 bpp, 1024 codes; 2 KB RAM.
  Byte at `offset` = code 7:0, byte at `offset + 0x100` = attribute:
  bits 1:0 = code 9:8, bit 2 = flip X, bit 3 = flip Y, bits 5:4 = palette (4 × 16 colours).
- Memory order (MAME): `((row & 0xF) ^ 0xF) | ((col & 0xF) << 4) | ((row & 0x10) << 5) |
  ((col & 0x10) << 6)` — bit 8 is the code/attribute select ("hole").
- Scroll: 9-bit X (F008/F009, added to DHPOS by 13C/13D) and 9-bit Y (F00A/F00B, added to VPOS
  by 12C/12D) per layer (sheet 20). MAME negates Y (`set_scrolly(0, -scroll)`).
- ROMs: 4 × 27256 per layer (BG1: `di-06.3e`, `di-04.2e`, `di-07.6e`, `di-05.4e`; BG2: `di-09.3j`,
  `di-08.2j`, `di-11.6j`, `di-10.4j`). Two chips are read at once (one pair per CS bit), feeding
  four LS194 shift registers = 4 pixels × 4 planes per fetch. MAME's `ROM_CONTINUE` shuffle
  (8 KB chunks) reproduces this wiring; the core will instead address the raw chips
  the way the board does, and verify against MAME's decoded tiles.
- BG1 pen 0 is transparent (via the priority PROM); BG2 is opaque.
- Palette: BG1 0x80–0xBF, BG2 0xC0–0xFF.

### Sprites (sheets 31–36, DSPC-10)
- 96 sprites × 4 bytes at E800–E97F: `[0]` Y, `[1]` attributes, `[2]` X, `[3]` code 7:0.
  Attributes: bits 7:6 = code 9:8, bit 4 = double height (two 16 × 16 cells), bit 2 = flip X,
  bit 1 = flip Y, bits 3 and 0 = colour (palette 0x40–0x7F, 4 × 16). One attribute bit also feeds
  `PRIOTY`/`PRO` (latch 12E, sheet 33) → priority PROM; which bit is still to be identified.
- X wraps (MAME draws every sprite twice, at X and X−256).
- Hardware: per-line sprite list. During each line the DSPC-10 scans sprite RAM (`HPOS` addresses,
  Y compare via 5E/4E LS283 adders, sheet 32), writes matches into a list (`MAT` RAM, 7-bit
  counter 17E/18E), then draws them into **two TMM2018 line buffers** (2F/2C, swapped by `E/D`,
  sheet 33). So there is a per-line sprite limit set by the time available; MAME has none. Find
  the limit from the counter width and the line timing during implementation.
- Sprite ROMs: 4 × 27256, one per bit plane (`di-16.17h`, `di-13.13h`, `di-14.14h`, `di-15.15h`),
  read at the same time (`*CG1–3`, sheet 35) → 8 pixels per fetch.

### Priority and palette (sheets 39, 40)
- **`firetrap.1a` (82S129, 256 × 4) is the priority PROM** (MAME marks it "?"). Inputs:
  A7:6 = FG pixel, A5 = sprite `PRO` bit, A4 = sprite transparent (7425 NOR of the 4 sprite
  bits), A3:0 = BG1 pixel. Outputs O1:O0 = layer select = palette index bits 7:6
  (0 = FG, 1 = sprites, 2 = BG1, 3 = BG2). Contents:

  | FG ≠ 0 | PRO | sprite opaque | BG1 ≠ 0 | layer shown |
  |---|---|---|---|---|
  | yes | x | x | x | FG |
  | no | 0 | yes | x | sprite |
  | no | 1 | yes | no | sprite |
  | no | 1 | yes | yes | **BG1 (sprite behind BG1)** |
  | no | x | no | yes | BG1 |
  | no | x | no | no | BG2 |

  With PRO = 0 this is MAME's fixed order. PRO = 1 (sprite behind BG1) is not in MAME. Implement
  it through the PROM and check whether the game uses it.
- Palette index = {layer select (2), palette bits, pixel bits} selected by LS153 muxes 5A/4A/3A.
- `firetrap.3b` (MB7118, 256 × 8): bits 3:0 red, 7:4 green. `firetrap.4b` (MB7114, 256 × 4): blue.
  Latched on `*HCLK` (2B, 5B), cleared by `*RGBBL`. DAC weights as MAME (220/470/1k/2.2k Ω):
  level = 0x0E·b0 + 0x1F·b1 + 0x43·b2 + 0x8F·b3.

## Sound — 6502 @ 1.5 MHz (sheets 41–43)

| Address | R/W | Function |
|---|---|---|
| 0000–07FF | RW | RAM (6116 9J) |
| 1000–1001 | W | YM3526 (`*OPL`), A0 = register/data |
| 2000 | W | ADPCM data latch (`*VOICE`, 6J), also clears the 6502 IRQ |
| 2400 | W | bit 0: MSM5205 reset (0 = reset), bit 1: IRQ enable (4H flip-flops, `*ADPCM`) |
| 2800 | W | ROM bank, D0 (10F) |
| 3400 | R | Sound latch (`*COM RD`, 13J), also clears the NMI flip-flop 11F |
| 4000–7FFF | R | Banked: `di-18.12j` half 0/1 |
| 8000–FFFF | R | `di-17.10j` |

- **NMI**: 11F set by Z80 write to F001, cleared by the 6502 reading 3400 (= MAME's
  `generic_latch_8` data-pending behaviour).
- **IRQ**: from MSM5205 VCK via 3H flip-flops: the LS157 6K selects high/low nibble of the 2000
  latch, toggled every VCK; IRQ every other VCK, gated by 2400 bit 1, cleared by writing 2000.
  The YM3526 IRQ is crossed out (not connected).
- **YM3526** @ 3 MHz → YM3014 DAC. **MSM5205** @ 375 kHz, S1 = 1 via jumper J1 open (÷48 →
  7.8125 kHz; closing J1 gives 4 kHz). Mixed by MC3403 op-amps; MAME levels: OPL 1.0, ADPCM 0.30.
- Cores: jtopl (YM3526 mode) and jt5205.

## Inputs (sheet 29)

The board's own labels are a joystick (`U D L R`) plus `SW1`–`SW5` and `SEL` (start) per player.
The US kit wires SW1–4 to a second (right) joystick and SW5 to the PUSH 1 button (manual p. 10).

| Port | Bits (active low) |
|---|---|
| IN0 (F010) | 0–3: P1 left stick U D L R; 4–7: P1 right stick U D L R (SW1–4) |
| IN1 (F011) | same for P2 (cocktail) |
| IN2 (F012) | 0: P1 button (SW5), 1: Start 1, 2: P2 button, 3: Start 2, 4–6: unused (coins crossed out, now on the MCU), 7: VBLK (active high) |
| DSW0 (F013), DSW1 (F014) | DIP banks SW1, SW2 (see MAME / manual p. 4) |

Gameplay notes: climbing = both sticks pushed the same way; water is aimed with the right stick and
fired with the button. One owner reports the stick-only firing method ("moving joysticks away from
each other and back together") printed on their bezel. MAME has no single-stick option. Planned
OSD option: **Single stick** (one joystick drives both sticks, button fires) vs **Twin stick**
(right stick on the pad's right analog stick or face buttons). Verify in MAME that a full game is
playable with both sticks bound to the same input before relying on it.

### DIP switches (MAME defaults; manual differences noted)
- SW1: Coin A (1–3), Coin B (4–5), Cabinet (6: OFF = table/cocktail, ON = upright; MAME
  default upright), Demo sound (7), Flip (8).
- SW2: Difficulty (1–2), Lives (3–4; "2" per MAME, "Infinite" per manual), Bonus (5–6; table
  differs between US and JP), Continue (7), Test mode (8).
- MAME notes the manual lists 1C_5C where the game gives 1C_6C.

## ROM set and memory plan

| Region | Files (US rev A) | Size | Storage |
|---|---|---|---|
| Main | `di-02.4a`, `di-01.3a`, `di-00-a.2a` | 96 KB | BRAM |
| Sound | `di-17.10j`, `di-18.12j` | 64 KB | BRAM |
| MCU | `di-12.16h` | 4 KB | BRAM |
| FG chars | `di-03.17c` | 8 KB | BRAM |
| PROMs | `firetrap.3b`, `firetrap.4b`, `firetrap.1a` | 768 B | BRAM |
| BG1 tiles | `di-06/04/07/05` | 128 KB | **SDRAM** |
| BG2 tiles | `di-09/08/11/10` | 128 KB | **SDRAM** |
| Sprites | `di-16/13/14/15` | 128 KB | **SDRAM** |

BRAM total ≈ 173 KB ROM + ≈ 16 KB RAM, well inside the DE10-nano's ~550 KB of M10K at byte width;
all 556 KB would not fit alongside the framework.

**SDRAM layout**: the MRA interleaves the chips that the board reads at the same time, so each
board fetch is one SDRAM word (BG: 2 chips → 16 bits) or one 2-word burst (sprites: 4 chips →
32 bits). Bandwidth: two BG layers need a 16-bit word every 4 pixels each (3 M words/s), and
sprites at most one 32-bit fetch per 8 pixels into the line buffer. With SDRAM at 96 MHz (one
random 16-bit access ≈ 8 cycles), ≈ 12 M accesses/s is available, so plain time-slotting per
pixel phase works, without caches.

**Download layout (ioctl index 0)** — proposal:

| Offset | Content |
|---|---|
| 0x00000 | Main ROM 0x18000 (di-02, di-01, di-00-a) |
| 0x18000 | Sound ROM 0x10000 (di-17, di-18) |
| 0x28000 | MCU 0x1000 |
| 0x29000 | FG chars 0x2000 |
| 0x2B000 | PROMs 3B, 4B, 1A (0x300), padded to 0x2C000 |
| 0x2C000 | BG1 0x20000 (interleaved) → SDRAM |
| 0x4C000 | BG2 0x20000 (interleaved) → SDRAM |
| 0x6C000 | Sprites 0x20000 (interleaved) → SDRAM |

Total 0x8C000 = 573,440 bytes.

## Third-party cores

| Function | Core | Licence |
|---|---|---|
| Z80 | T80 (jtframe copy, VHDL → Verilog via GHDL/Yosys for Verilator) | BSD-style |
| i8751 | jt8051 (jotego) | GPL-3.0 |
| 6502 | Arlet Ottens' verilog-6502 (as in the Jedi core) | free |
| YM3526 | jtopl (jotego) | GPL-3.0 |
| MSM5205 | jt5205 (jotego) | GPL-3.0 |

## Open items

1. Exact polarity of the Z80 VRAM wait logic (6C); measure how much it matters with a MAME trace.
2. Which sprite attribute bit is `PRO` (priority), and whether the game sets it.
3. Per-line sprite limit of the DSPC-10.
4. HBLANK/HSYNC/VSYNC edge positions inside the DECO customs (use MAME's 0–255 / 8–247 visible
   area; sync positions chosen for a standard 15 kHz picture).
5. MCU INT1 edge/level mode and the IRQ edge (rising per schematic vs falling per MAME) —
   read the MCU code.
6. Single-stick cabinet behaviour (needs a MAME test; no documentation found yet).

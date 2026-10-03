# Fire Trap (Arcade, 1986) for MiSTer FPGA

An FPGA implementation of Wood Place's **Fire Trap** (licensed in the US by Data East) for the
[MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

Climb burning skyscrapers as a firefighter, dodging falling debris and putting out fires with
your hose. Each hand gets its own joystick: one climbs, the other aims the water.

> **Early build, not yet tested on hardware.** Feedback and bug reports are welcome via
> [Issues](https://github.com/Usquebagh/Arcade-FireTrap_MiSTer/issues).

---

## Original Hardware

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main CPU** | Zilog Z80B @ 6 MHz | T80 |
| **Protection MCU** | Intel 8751 @ 8 MHz | jt8051 (Jose Tejada) |
| **Sound CPU** | MOS 6502 @ 1.5 MHz | Arlet Ottens' verilog-6502 |
| **Sound** | Yamaha YM3526 + OKI MSM5205 ADPCM | jtopl, jt5205 (Jose Tejada) |
| **Video** | Text layer, two scrolling 16×16 tile layers, 96 sprites, priority and palette PROMs | `ft_video.v`, `ft_render.v`, from the schematics |
| **Display** | 256×240, vertical (ROT90), 57.4 Hz | Rotated via the MiSTer framebuffer |

Notes on the hardware and design decisions are in [docs/hardware.md](docs/hardware.md).

---

## Controls

Each player has two 4-way joysticks, one per hand. As in Crazy Climber, you climb hand over
hand: alternate *left up + right down* and *left down + right up*. Pushing both sticks left or
right moves sideways.

| Input | Function |
|---|---|
| **D-Pad / Left Analog** | Left stick |
| **Right Analog**, or **X / B / Y / A** | Right stick (up / down / left / right) |
| **R** | Fire (also needed to enter high-score initials) |
| **Start / Select** | Start / Coin |

**Joysticks** in the OSD: *Twin Stick* (default) or *Single Stick*. In Single Stick mode one
stick does everything: hold **up** to climb (the core alternates the hands for you; *Single Stick
Climb* sets the pace, 32 frames per hand by default), left/right/down go to both sticks.
**4-Way Filter** keeps diagonals out, as the original 4-way sticks did.

MiSTer's *Define joystick buttons* only asks for the d-pad and the buttons; the left analog stick
always works as the left stick, and the right analog stick as the right one.

**Cheats** (OSD *Cheats*): infinite lives, infinite time and the 3-way power-up, from the MAME
cheat file. Like MAME's, they are written into RAM once per frame.

**Service Mode:** set *Service Mode* in the DIP switches page and reset.

---

## ROMs

MAME sets `firetrap` (US, rev A), `firetrapa` (US) and `firetrapj` (Japan). Place
`firetrap.zip` (merged, MAME 0.289) in `games/mame`; the MRA files are in [releases](releases).
The bootleg `firetrapbl` is not supported.

---

## Advanced OSD options

- **Z80 VRAM Wait:** the board makes the Z80 wait for blanking when it touches tile RAM
  (`On`, default). `Off` behaves like MAME. See docs/hardware.md.
- **SDRAM Read Phase:** for testing only; leave at `2.5`.

---

## Credits

- Core: Usquebagh, with Claude (Anthropic)
- T80: Daniel Wallner and contributors; jt8051, jtopl, jt5205: Jose Tejada (jotego)
- 6502: Arlet Ottens; SDRAM controller and MiSTer framework: Sorgelig and the MiSTer-devel team
- MAME's `firetrap` driver (Nicola Salmoria, Stephane Humbert) as reference

## License

GPL-3.0. See [LICENSE](LICENSE).

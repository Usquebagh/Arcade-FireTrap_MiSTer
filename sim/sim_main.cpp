// Verilator testbench for Fire Trap (sim_top = ft_core + SDRAM model).
// Downloads roms/rom.bin through the ROM download port, then runs N frames and dumps
// selected frames as PPM.
// Usage: Vsim_top <frames> <dump_every>
// Environment:
//   DUMP_FROM=n          also dump every frame from n on
//   INPUTS=f:v,f:v,...   from frame f, drive inputs with hex v:
//                        bits 7:0 IN0, 15:8 IN1, 19:16 IN2, 22:20 {coin2, coin1, service}
//                        (all active low; idle = 7fffff)
//   DSW=hhhh             DSW1:DSW0 (default ffdf = MAME defaults)
//   LAYERS=h             layer enables {BG2, BG1, sprites, FG} (default f)
//   PC_FROM=f PC_TO=g    print Z80 opcode fetch addresses for frames [f, g)
//   RAMDUMP=f            write ram_*.hex (C000, D000, D800, E000, E800) at frame f
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vsim_top.h"
#include "verilated.h"

static const int W = 256, H = 240;
static Vsim_top *top;

static void tick() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }

static void write_ppm(const char *name, const std::vector<uint8_t> &fb) {
    FILE *f = fopen(name, "wb");
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    fwrite(fb.data(), 1, fb.size(), f);
    fclose(f);
}

static void set_inputs(unsigned v) {
    top->in0  = v & 0xff;
    top->in1  = (v >> 8) & 0xff;
    top->in2  = (v >> 16) & 0xf;
    top->coin = (v >> 20) & 0x7;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int frames = argc > 1 ? atoi(argv[1]) : 60;
    int every  = argc > 2 ? atoi(argv[2]) : 10;
    int from   = getenv("DUMP_FROM") ? atoi(getenv("DUMP_FROM")) : 1 << 30;
    int pc_from = getenv("PC_FROM") ? atoi(getenv("PC_FROM")) : -1;
    int pc_to   = getenv("PC_TO") ? atoi(getenv("PC_TO")) : -1;
    unsigned dsw = getenv("DSW") ? strtoul(getenv("DSW"), nullptr, 16) : 0xffdf;

    top = new Vsim_top;
    set_inputs(0x7fffff);
    top->dsw0 = dsw & 0xff;
    top->dsw1 = (dsw >> 8) & 0xff;
    top->layer_en = getenv("LAYERS") ? strtoul(getenv("LAYERS"), nullptr, 16) : 0xf;

    std::vector<std::pair<int, unsigned>> script;
    if (const char *s = getenv("INPUTS")) {
        int f, n;
        unsigned v;
        while (sscanf(s, "%d:%x%n", &f, &v, &n) == 2) {
            script.push_back({f, v});
            s += n;
            if (*s == ',') s++;
        }
    }
    size_t next_input = 0;

    // ROM download, as hps_io: one byte per write strobe, honouring dl_wait
    FILE *rf = fopen("roms/rom.bin", "rb");
    if (!rf) { fprintf(stderr, "roms/rom.bin missing\n"); return 1; }
    std::vector<uint8_t> rom;
    { uint8_t buf[4096]; size_t n; while ((n = fread(buf, 1, sizeof buf, rf)) > 0) rom.insert(rom.end(), buf, buf + n); }
    fclose(rf);
    top->reset = 1;
    top->dl_wr = 0;
    for (int i = 0; i < 16; i++) tick();
    for (size_t a = 0; a < rom.size(); a++) {
        top->dl_addr = a;
        top->dl_data = rom[a];
        top->dl_wr = 1;
        tick();
        top->dl_wr = 0;
        tick();
        while (top->dl_wait) tick();
    }
    for (int i = 0; i < 200; i++) tick();
    top->reset = 0;

    std::vector<uint8_t> fb(W * H * 3, 0);
    int frame = 0;
    bool last_vblank = false, last_m1 = false, overrun_reported = false;
    uint64_t cycles = 0;

    while (frame < frames) {
        tick();
        cycles++;

        if (frame >= pc_from && frame < pc_to) {
            if (top->dbg_m1 && !last_m1) printf("PC %04x\n", top->dbg_addr);
            last_m1 = top->dbg_m1;
        }
        if (top->dbg_overrun && !overrun_reported) {
            printf("RENDER OVERRUN in frame %d\n", frame);
            overrun_reported = true;
        }

        if (!top->ce_pix) continue;
        if (!top->hblank && !top->vblank && top->vid_h < W && top->vid_v >= 8 && top->vid_v < 8 + H) {
            uint8_t *p = &fb[((top->vid_v - 8) * W + top->vid_h) * 3];
            p[0] = top->red; p[1] = top->green; p[2] = top->blue;
        }
        if (top->vblank && !last_vblank) {
            frame++;
            while (next_input < script.size() && script[next_input].first <= frame)
                set_inputs(script[next_input++].second);
            if (frame % 50 == 0) printf("frame %4d  addr %04x\n", frame, top->dbg_addr);
            if (getenv("RAMDUMP") && frame == atoi(getenv("RAMDUMP"))) {
                top->dbg_dump = 1; tick(); top->dbg_dump = 0;
                printf("RAM dumped at frame %d\n", frame);
            }
            if (frame % every == 0 || frame >= from) {
                char name[64];
                snprintf(name, sizeof name, "frame_%04d.ppm", frame);
                write_ppm(name, fb);
            }
        }
        last_vblank = top->vblank;
    }

    printf("%llu clocks, %.2f s emulated\n", (unsigned long long)cycles, cycles / 48e6);
    delete top;
    return 0;
}

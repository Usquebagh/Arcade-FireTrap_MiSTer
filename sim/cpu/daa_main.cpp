// Compare T80's DAA against the Z80 reference (as implemented in MAME's z80 core).
#include <cstdio>
#include "Vdaa_tb.h"
#include "verilated.h"

static int parity(int v) { v ^= v >> 4; v ^= v >> 2; v ^= v >> 1; return !(v & 1); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vdaa_tb *t = new Vdaa_tb;
    auto tick = [&]() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); };
    t->reset_n = 0;
    for (int i = 0; i < 10; i++) tick();
    t->reset_n = 1;
    long n = 0;
    while (!t->halted && n < 20000000) { tick(); n++; }
    printf("program %s after %ld clocks\n", t->halted ? "halted" : "DID NOT HALT", n);

    const int flags[8] = {0x00, 0x01, 0x02, 0x03, 0x10, 0x11, 0x12, 0x13};
    int bad_a = 0, bad_f = 0, bad_f_doc = 0, shown = 0;
    for (int a = 0; a < 256; a++)
        for (int k = 0; k < 8; k++) {
            int f = flags[k];
            int r = a;
            if (f & 0x02) {
                if ((f & 0x10) || (a & 0x0f) > 9) r = (r - 6) & 0xff;
                if ((f & 0x01) || a > 0x99) r = (r - 0x60) & 0xff;
            } else {
                if ((f & 0x10) || (a & 0x0f) > 9) r = (r + 6) & 0xff;
                if ((f & 0x01) || a > 0x99) r = (r + 0x60) & 0xff;
            }
            int rf = (f & 0x03) | (a > 0x99 ? 1 : 0) | ((a ^ r) & 0x10) |
                     (r & 0xa8) | (r == 0 ? 0x40 : 0) | (parity(r) ? 0x04 : 0);
            int addr = 0x9000 + (a * 8 + k) * 2;
            t->peek_addr = addr;     t->eval(); int ga = t->peek_data;
            t->peek_addr = addr + 1; t->eval(); int gf = t->peek_data;
            if (ga != r) bad_a++;
            if (gf != rf) bad_f++;
            if ((gf & 0xd7) != (rf & 0xd7)) bad_f_doc++;   // ignore undocumented bits 5 and 3
            if ((ga != r || (gf & 0xd7) != (rf & 0xd7)) && shown < 20) {
                printf("A=%02x F=%02x: T80 A=%02x F=%02x, Z80 A=%02x F=%02x\n", a, f, ga, gf, r, rf);
                shown++;
            }
        }
    printf("2048 cases: A wrong %d, F wrong %d (documented flags wrong %d)\n", bad_a, bad_f, bad_f_doc);
    delete t;
    return 0;
}

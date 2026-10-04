// Sound board stress test: write N sound commands at random intervals and check that the
// 6502 takes an NMI and reads the latch for every one of them.
// Usage: Vsnd_tb <rom.bin> [commands]
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "Vsnd_tb.h"
#include "verilated.h"

static Vsnd_tb *t;
static void tick() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    t = new Vsnd_tb;
    FILE *f = fopen(argv[1], "rb");
    std::vector<uint8_t> rom(0x8c000);
    fread(rom.data(), 1, rom.size(), f);
    fclose(f);
    int n = argc > 2 ? atoi(argv[2]) : 20000;

    t->reset = 1;
    for (int a = 0; a < 0x10000; a++) {          // sound ROM is at 0x18000 in the image
        t->rom_waddr = a; t->rom_wdata = rom[0x18000 + a]; t->rom_we = 1; tick();
    }
    t->rom_we = 0;
    for (int i = 0; i < 1000; i++) tick();
    t->reset = 0;
    for (int i = 0; i < 4000000; i++) tick();     // let the driver initialise

    uint32_t base_reads = t->reads, base_nmis = t->nmis;
    srand(1234);
    for (int c = 0; c < n; c++) {
        // Command 0x01 (coin sound); spacing 3000-15000 clocks (60-300 us), longer than the
        // NMI handler, so each command should be read before the next arrives
        t->cmd = 0x01; t->cmd_wr = 1; tick(); t->cmd_wr = 0;
        int gap = 3000 + rand() % 12000;
        for (int i = 0; i < gap; i++) tick();
    }
    for (int i = 0; i < 100000; i++) tick();
    uint32_t reads = t->reads - base_reads, nmis = t->nmis - base_nmis;
    printf("commands %d  NMIs taken %u  latch reads %u  lost %d\n", n, nmis, reads, n - (int)reads);
    delete t;
    return 0;
}

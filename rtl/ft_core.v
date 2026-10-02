// Fire Trap (Wood Place / Data East, 1986) — core.
// Master clock 48 MHz; everything else runs on clock enables. See docs/hardware.md.
//
// Milestone 2: Z80 + memory map + 8751 + video timing + FG layer.
module ft_core #(
    parameter MAIN_ROM_INIT = "",
    parameter MCU_ROM_INIT  = "",
    parameter CHR_INIT      = "",
    parameter PROM_INIT     = "",
    parameter VRAM_WAIT     = 1        // Z80 waits for blanking on tile-RAM access (not in MAME)
) (
    input             clk,             // 48 MHz
    input             reset,

    // ROM download (MRA layout, docs/hardware.md)
    input      [19:0] dl_addr,
    input       [7:0] dl_data,
    input             dl_wr,

    // Inputs, active low as on the board
    input       [7:0] in0,             // P1 left stick UDLR, right stick UDLR
    input       [7:0] in1,             // P2 (cocktail)
    input       [3:0] in2,             // P1 button, start 1, P2 button, start 2
    input       [2:0] coin,            // {coin 2, coin 1, service}
    input       [7:0] dsw0,
    input       [7:0] dsw1,

    // Video
    output            ce_pix,
    output      [7:0] red,
    output      [7:0] green,
    output      [7:0] blue,
    output            hblank,
    output            vblank,
    output            hs,
    output            vs,
    output      [8:0] vid_h,
    output      [8:0] vid_v,

    // Debug
    output     [15:0] dbg_addr,
    output            dbg_m1
);

// ---------------------------------------------------------------- clock enables
reg [2:0] ph;                 // pixel slot phase: 6 MHz = 48 / 8
reg [2:0] mcu_div;            // 8 MHz = 48 / 6
always @(posedge clk) begin
    ph      <= ph + 3'd1;
    mcu_div <= (mcu_div == 3'd5) ? 3'd0 : mcu_div + 3'd1;
end
wire cen_z80 = (ph == 3'd7);  // Z80 clock = HCLK, in phase with the pixel counter
wire cen_mcu = (mcu_div == 3'd0);

// ---------------------------------------------------------------- Z80
wire [15:0] A;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;
wire        mreq_n, rd_n, wr_n, m1_n, rfsh_n, iorq_n;
wire        int_n, nmi_n, wait_n;

T80s u_z80 (
    .RESET_n ( ~reset   ),
    .CLK     ( clk      ),
    .CEN     ( cen_z80  ),
    .WAIT_n  ( wait_n   ),
    .INT_n   ( int_n    ),
    .NMI_n   ( nmi_n    ),
    .BUSRQ_n ( 1'b1     ),
    .M1_n    ( m1_n     ),
    .MREQ_n  ( mreq_n   ),
    .IORQ_n  ( iorq_n   ),
    .RD_n    ( rd_n     ),
    .WR_n    ( wr_n     ),
    .RFSH_n  ( rfsh_n   ),
    .HALT_n  (          ),
    .BUSAK_n (          ),
    .OUT0    ( 1'b0     ),
    .A       ( A        ),
    .DI      ( cpu_din  ),
    .DOUT    ( cpu_dout )
);

assign dbg_addr = A;
assign dbg_m1   = ~m1_n;

// ---------------------------------------------------------------- address decode (sheets 16, 30)
wire mem    = ~mreq_n & rfsh_n;
wire rom_cs = mem & ~A[15];                         // 0000-7FFF
wire bnk_cs = mem & (A[15:14] == 2'b10);            // 8000-BFFF
wire ram_cs = mem & (A[15:12] == 4'hC);             // C000-CFFF
wire bg1_cs = mem & (A[15:11] == 5'b11010);         // D000-D7FF
wire bg2_cs = mem & (A[15:11] == 5'b11011);         // D800-DFFF
wire fg_cs  = mem & (A[15:11] == 5'b11100);         // E000-E7FF
wire obj_cs = mem & (A[15:11] == 5'b11101);         // E800-EFFF (512 bytes, mirrored)
wire io_cs  = mem & (A[15:11] == 5'b11110);         // F000-F7FF
wire io_wr  = io_cs & ~wr_n & ~A[4];                // F000-F00F
wire io_rd  = io_cs & ~rd_n &  A[4];                // F010-F017

// ---------------------------------------------------------------- VRAM wait (sheet 17)
// Tile RAM (D000-E7FF) is only available to the Z80 during blanking. An access that starts
// in the active display waits; one that has been granted completes.
wire hblank_now, vblank_now;
wire vram_acc = bg1_cs | bg2_cs | fg_cs;
reg  vram_grant;
always @(posedge clk)
    vram_grant <= vram_acc & (vram_grant | hblank_now | vblank_now | (VRAM_WAIT == 0));
assign wait_n = ~(vram_acc & ~vram_grant & (VRAM_WAIT != 0));
wire vram_wr = ~wr_n & (vram_grant | (VRAM_WAIT == 0));

// ---------------------------------------------------------------- download decode
wire dl_main = dl_wr & (dl_addr < 20'h18000);
wire dl_mcu  = dl_wr & (dl_addr[19:12] == 8'h28);
wire dl_chr  = dl_wr & (dl_addr >= 20'h29000) & (dl_addr < 20'h2B000);
wire dl_prom = dl_wr & (dl_addr >= 20'h2B000) & (dl_addr < 20'h2B300);
wire [19:0] dl_chr_a  = dl_addr - 20'h29000;
wire [19:0] dl_prom_a = dl_addr - 20'h2B000;

// ---------------------------------------------------------------- memories
reg  [1:0] bank;
// Main ROM: 0x00000-0x07FFF fixed, 0x08000-0x17FFF banks 0-3 (di-01: 0,1; di-00-a: 2,3)
wire [16:0] rom_addr = A[15] ? (17'h08000 + {1'b0, bank, A[13:0]}) : {2'b00, A[14:0]};
wire  [7:0] rom_q;
dpram #(.AW(17), .DEPTH(17'h18000), .INIT(MAIN_ROM_INIT)) u_main_rom (
    .clk(clk),
    .a_addr(dl_addr[16:0]), .a_din(dl_data), .a_we(dl_main), .a_dout(),
    .b_addr(rom_addr), .b_din(8'h00), .b_we(1'b0), .b_dout(rom_q)
);

wire [7:0] ram_q;
dpram #(.AW(12)) u_ram (
    .clk(clk),
    .a_addr(A[11:0]), .a_din(cpu_dout), .a_we(ram_cs & ~wr_n), .a_dout(ram_q),
    .b_addr(12'd0), .b_din(8'h00), .b_we(1'b0), .b_dout()
);

wire [10:0] fg_vaddr;
wire  [7:0] fg_q, fg_vq;
dpram #(.AW(11)) u_fg_ram (
    .clk(clk),
    .a_addr(A[10:0]), .a_din(cpu_dout), .a_we(fg_cs & vram_wr), .a_dout(fg_q),
    .b_addr(fg_vaddr), .b_din(8'h00), .b_we(1'b0), .b_dout(fg_vq)
);

wire [7:0] bg1_q, bg2_q, obj_q;
dpram #(.AW(11)) u_bg1_ram (
    .clk(clk),
    .a_addr(A[10:0]), .a_din(cpu_dout), .a_we(bg1_cs & vram_wr), .a_dout(bg1_q),
    .b_addr(11'd0), .b_din(8'h00), .b_we(1'b0), .b_dout()
);
dpram #(.AW(11)) u_bg2_ram (
    .clk(clk),
    .a_addr(A[10:0]), .a_din(cpu_dout), .a_we(bg2_cs & vram_wr), .a_dout(bg2_q),
    .b_addr(11'd0), .b_din(8'h00), .b_we(1'b0), .b_dout()
);
dpram #(.AW(9)) u_obj_ram (
    .clk(clk),
    .a_addr(A[8:0]), .a_din(cpu_dout), .a_we(obj_cs & ~wr_n), .a_dout(obj_q),
    .b_addr(9'd0), .b_din(8'h00), .b_we(1'b0), .b_dout()
);

// ---------------------------------------------------------------- I/O writes (sheet 16)
// Board latches clock on the rising (trailing) edge of the decoded write strobe.
reg        io_wr_l;
reg  [3:0] io_a_l;
reg  [7:0] io_d_l;
reg        flip, nmi_en;
reg  [7:0] sound_latch, mcu_latch;
reg  [8:0] scroll [0:3];          // BG1 X, BG1 Y, BG2 X, BG2 Y
reg        int0_set;
wire       io_end = io_wr_l & ~io_wr;

always @(posedge clk) begin
    io_wr_l  <= io_wr;
    int0_set <= 1'b0;
    if (io_wr) begin
        io_a_l <= A[3:0];
        io_d_l <= cpu_dout;
    end
    if (reset) begin
        bank   <= 0;
        flip   <= 0;
        nmi_en <= 0;
    end else if (io_end) begin
        case (io_a_l)
        4'h1: sound_latch <= io_d_l;
        4'h2: bank        <= io_d_l[1:0];
        4'h3: flip        <= io_d_l[0];
        4'h4: nmi_en      <= ~io_d_l[0];
        4'h5: begin mcu_latch <= io_d_l; int0_set <= 1'b1; end
        4'h8: scroll[0][7:0] <= io_d_l;
        4'h9: scroll[0][8]   <= io_d_l[0];
        4'hA: scroll[1][7:0] <= io_d_l;
        4'hB: scroll[1][8]   <= io_d_l[0];
        4'hC: scroll[2][7:0] <= io_d_l;
        4'hD: scroll[2][8]   <= io_d_l[0];
        4'hE: scroll[3][7:0] <= io_d_l;
        4'hF: scroll[3][8]   <= io_d_l[0];
        default: ;
        endcase
    end
end

// ---------------------------------------------------------------- interrupts (sheet 15)
// NMI: the enable is latched at the start of VBLANK; NMI is held for the rest of VBLANK.
// IRQ: set by a rising edge of 8751 P3.0, cleared by a write to F000.
wire [7:0] mcu_p0_o, mcu_p1_o, mcu_p2_o, mcu_p3_o;
reg        vbl_l, nmi_ff, irq_ff, p30_l;
always @(posedge clk) begin
    vbl_l <= vblank_now;
    p30_l <= mcu_p3_o[0];
    if (reset) begin
        nmi_ff <= 0;
        irq_ff <= 0;
    end else begin
        if (vblank_now & ~vbl_l) nmi_ff <= nmi_en;
        if (io_wr & (A[3:0] == 4'h0)) irq_ff <= 0;
        else if (mcu_p3_o[0] & ~p30_l) irq_ff <= 1;
    end
end
assign nmi_n = ~(nmi_ff & vblank_now);
assign int_n = ~irq_ff;

// ---------------------------------------------------------------- 8751 (sheet 26)
// INT0 flip-flop: set by a write to F005, held reset while P3.1 is low.
// Coin flip-flop: set when a coin switch closes, held reset while P3.4 is low.
reg  int0_ff, coin_ff;
reg  [2:0] coin_l;
always @(posedge clk) begin
    coin_l <= coin;
    if (reset) begin
        int0_ff <= 0;
        coin_ff <= 0;
    end else begin
        if (~mcu_p3_o[1]) int0_ff <= 0;
        else if (int0_set) int0_ff <= 1;
        if (~mcu_p3_o[4]) coin_ff <= 0;
        else if (&coin_l & ~&coin) coin_ff <= 1;
    end
end

ft_mcu #(.ROM_INIT(MCU_ROM_INIT)) u_mcu (
    .clk       ( clk        ),
    .rst       ( reset      ),
    .cen       ( cen_mcu    ),
    .int0n     ( ~int0_ff   ),
    .int1n     ( ~vblank_now ),
    .p0_i      ( {4'b0000, coin, ~coin_ff} ),
    .p1_i      ( mcu_p1_o   ),
    .p2_i      ( mcu_latch  ),
    .p3_i      ( {3'b111, mcu_p3_o[4], ~vblank_now, ~int0_ff, mcu_p3_o[1:0]} ),
    .p0_o      ( mcu_p0_o   ),
    .p1_o      ( mcu_p1_o   ),
    .p2_o      ( mcu_p2_o   ),
    .p3_o      ( mcu_p3_o   ),
    .rom_waddr ( dl_addr[11:0] ),
    .rom_wdata ( dl_data    ),
    .rom_we    ( dl_mcu     )
);

// ---------------------------------------------------------------- CPU read mux
always @(*) begin
    cpu_din = 8'hff;
    if (rom_cs | bnk_cs) cpu_din = rom_q;
    else if (ram_cs)     cpu_din = ram_q;
    else if (bg1_cs)     cpu_din = bg1_q;
    else if (bg2_cs)     cpu_din = bg2_q;
    else if (fg_cs)      cpu_din = fg_q;
    else if (obj_cs)     cpu_din = obj_q;
    else if (io_rd) begin
        case (A[2:0])
        3'd0: cpu_din = in0;
        3'd1: cpu_din = in1;
        3'd2: cpu_din = {vblank_now, 3'b111, in2};
        3'd3: cpu_din = dsw0;
        3'd4: cpu_din = dsw1;
        3'd5: cpu_din = {5'b11111, mcu_p3_o[0], 2'b11};  // F015: P3.0 (bit position unverified)
        3'd6: cpu_din = mcu_p1_o;
        default: cpu_din = 8'hff;
        endcase
    end
end

// ---------------------------------------------------------------- video
ft_video #(.CHR_INIT(CHR_INIT), .PROM_INIT(PROM_INIT)) u_video (
    .clk        ( clk        ),
    .rst        ( reset      ),
    .ph         ( ph         ),
    .flip       ( flip       ),
    .hc         (            ),
    .vc         (            ),
    .hblank_now ( hblank_now ),
    .vblank_now ( vblank_now ),
    .fg_addr    ( fg_vaddr   ),
    .fg_q       ( fg_vq      ),
    .chr_waddr  ( dl_chr_a[12:0]  ),
    .chr_wdata  ( dl_data    ),
    .chr_we     ( dl_chr     ),
    .prom_waddr ( dl_prom_a[9:0]  ),
    .prom_wdata ( dl_data    ),
    .prom_we    ( dl_prom    ),
    .ce_pix     ( ce_pix     ),
    .red        ( red        ),
    .green      ( green      ),
    .blue       ( blue       ),
    .hblank     ( hblank     ),
    .vblank     ( vblank     ),
    .hs         ( hs         ),
    .vs         ( vs         ),
    .vid_h      ( vid_h      ),
    .vid_v      ( vid_v      )
);

endmodule

// Fire Trap sound board (sheets 41-43): 6502 @ 1.5 MHz, YM3526 @ 3 MHz, MSM5205 @ 375 kHz.
//
// 6502 map: 0000-0FFF RAM (2 KB, mirrored), 1000-1FFF YM3526 (A0), 2000 ADPCM data (clears IRQ),
// 2400 b0 = MSM5205 run (0 = reset), b1 = IRQ enable, 2800 b0 = ROM bank, 3400 read sound latch
// (clears NMI), 4000-7FFF banked di-18, 8000-FFFF di-17.
// NMI: set by the Z80 writing F001, cleared by reading 3400.
// IRQ: every other MSM5205 VCK. The LS157 6K feeds the MSM the high nibble of the 2000 latch,
// then the low one, toggling on each VCK (MAME: adpcm_int / ls157).
module ft_sound (
    input             clk,          // 48 MHz
    input             reset,

    input       [7:0] latch_data,   // Z80 F001
    input             latch_wr,     // one-clock pulse at the end of the Z80 write

    // Sound ROM download: 0x0000-0x7FFF di-17 (8000-FFFF), 0x8000-0xFFFF di-18 (banks)
    input      [15:0] rom_waddr,
    input       [7:0] rom_wdata,
    input             rom_we,

    output reg signed [15:0] audio
);

// ---------------------------------------------------------------- clock enables
reg  [6:0] sdiv;
always @(posedge clk) sdiv <= sdiv + 7'd1;
wire ce_cpu = sdiv[4:0] == 5'd31;    // 1.5 MHz
wire ce_opl = sdiv[3:0] == 4'd15;    // 3 MHz
wire ce_msm = sdiv == 7'd127;        // 375 kHz

// ---------------------------------------------------------------- 6502 (Arlet Ottens)
wire [15:0] ab;
wire  [7:0] dout;
wire        we;
reg   [7:0] din = 0;
reg         nmi_ff, irq_ff;

cpu u_cpu (
    .clk(clk), .reset(reset),
    .AB(ab), .DI(din), .DO(dout), .WE(we),
    .IRQ(irq_ff), .NMI(nmi_ff), .RDY(ce_cpu)
);

wire wr = ce_cpu & we;
wire rd = ce_cpu & ~we;

wire sel_ram  = ab[15:12] == 4'h0;
wire sel_opl  = ab[15:12] == 4'h1;
wire sel_wr2  = ab[15:12] == 4'h2;          // 2000/2400/2800 by A11:A10
wire sel_rd3  = ab[15:12] == 4'h3;          // 3400 latch (A11:A10 = 01)
wire sel_bank = ab[15:14] == 2'b01;
wire sel_rom  = ab[15];

reg        bank;
reg  [7:0] adpcm_data;
reg        msm_run, irq_en;

wire [7:0] ram_q, rom_q, opl_q;
dpram #(.AW(11)) u_ram (
    .clk(clk),
    .a_addr(ab[10:0]), .a_din(dout), .a_we(wr & sel_ram), .a_dout(ram_q),
    .b_addr(11'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
);
wire [15:0] rom_a = ab[15] ? {1'b0, ab[14:0]} : {1'b1, bank, ab[13:0]};
dpram #(.AW(16)) u_rom (
    .clk(clk),
    .a_addr(rom_a), .a_din(8'd0), .a_we(1'b0), .a_dout(rom_q),
    .b_addr(rom_waddr), .b_din(rom_wdata), .b_we(rom_we), .b_dout()
);

wire [7:0] bus_q =
    sel_ram              ? ram_q :
    sel_opl              ? opl_q :
    sel_rd3              ? (ab[11:10] == 2'b01 ? latch_data : 8'hff) :
    (sel_bank | sel_rom) ? rom_q : 8'hff;

always @(posedge clk) if (ce_cpu) din <= bus_q;

// ---------------------------------------------------------------- MSM5205 + LS157
reg        nib_sel;          // LS157 select: 1 = high nibble
wire       vck;              // one-clock pulse per sample (VCK edge)
wire signed [11:0] msm_snd;
wire [3:0] msm_din = ~nib_sel ? adpcm_data[7:4] : adpcm_data[3:0];  // nibble after the toggle

jt5205 #(.INTERPOL(0)) u_msm (
    .rst    ( reset | ~msm_run ),
    .clk    ( clk       ),
    .cen    ( ce_msm    ),
    .sel    ( 2'd2      ),   // S1 = 1, S2 = 0: 375 kHz / 48 = 7.8125 kHz
    .din    ( msm_din   ),
    .sound  ( msm_snd   ),
    .sample (           ),
    .irq    ( vck       ),
    .vclk_o (           )
);

// ---------------------------------------------------------------- registers, NMI, IRQ
always @(posedge clk) begin
    if (reset) begin
        bank    <= 0;
        msm_run <= 0;
        irq_en  <= 0;
        nmi_ff  <= 0;
        irq_ff  <= 0;
        nib_sel <= 0;
    end else begin
        if (latch_wr) nmi_ff <= 1;
        if (rd & sel_rd3 & (ab[11:10] == 2'b01)) nmi_ff <= 0;

        if (vck) begin
            nib_sel <= ~nib_sel;
            if (irq_en & ~nib_sel) irq_ff <= 1;
        end

        if (wr & sel_wr2) case (ab[11:10])
            2'b00: begin adpcm_data <= dout; irq_ff <= 0; end
            2'b01: begin msm_run <= dout[0]; irq_en <= dout[1]; if (~dout[1]) irq_ff <= 0; end
            2'b10: bank <= dout[0];
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------- YM3526
wire signed [15:0] opl_snd;
jtopl #(.OPL_TYPE(1)) u_opl (
    .rst    ( reset     ),
    .clk    ( clk       ),
    .cen    ( ce_opl    ),
    .din    ( dout      ),
    .addr   ( ab[0]     ),
    .cs_n   ( ~(sel_opl & ce_cpu) ),
    .wr_n   ( ~we       ),
    .dout   ( opl_q     ),
    .irq_n  (           ),   // not connected on the board
    .snd    ( opl_snd   ),
    .sample (           )
);

// ---------------------------------------------------------------- mix (MAME: OPL 1.0, MSM 0.30)
wire signed [17:0] mix = opl_snd + ((msm_snd * 18'sd77) >>> 4);   // 12-bit x 16 x 0.30
always @(posedge clk)
    audio <= (mix > 18'sd32767) ? 16'sd32767 : (mix < -18'sd32768) ? -16'sd32768 : mix[15:0];

endmodule

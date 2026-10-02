// i8751 protection MCU: jt8051 with its 4 KB program ROM and 128-byte internal RAM.
// Follows jtframe_8751mcu: memories are read only on cen pulses (the core expects
// that latency), internal RAM is cleared during reset.
module ft_mcu #(
    parameter ROM_INIT = ""
) (
    input            clk,
    input            rst,
    input            cen,        // oscillator-period enable (8 MHz); needs an idle clock between pulses

    input            int0n,
    input            int1n,
    input      [7:0] p0_i,
    input      [7:0] p1_i,
    input      [7:0] p2_i,
    input      [7:0] p3_i,
    output     [7:0] p0_o,
    output     [7:0] p1_o,
    output     [7:0] p2_o,
    output     [7:0] p3_o,

    // ROM download
    input     [11:0] rom_waddr,
    input      [7:0] rom_wdata,
    input            rom_we
);

wire [15:0] rom_addr_c;
reg  [11:0] rom_addr;
reg  [ 7:0] rom_q;
reg  [ 7:0] rom [0:4095];

wire [ 6:0] ram_addr;
wire [ 7:0] ram_dout;
wire        ram_we;
reg  [ 7:0] ram_q;
reg  [ 7:0] ram [0:127];
reg  [ 6:0] clr_addr;
reg         clr;

initial if (ROM_INIT != "") $readmemh(ROM_INIT, rom);

always @(posedge clk) begin
    if (rom_we) rom[rom_waddr] <= rom_wdata;
    rom_addr <= rom_addr_c[11:0];
    if (cen) rom_q <= rom[rom_addr];
end

// Internal RAM, cleared while in reset (as jtframe_ram_rst does)
always @(posedge clk) begin
    clr <= rst;
    if (clr) clr_addr <= clr_addr + 7'd1;
    if (clr) ram[clr_addr] <= 8'd0;
    else if (cen) begin
        if (ram_we) ram[ram_addr] <= ram_dout;
        ram_q <= ram[ram_addr];
    end
end

jt8051 u_mcu (
    .rst      ( rst        ),
    .clk      ( clk        ),
    .cen      ( cen        ),
    .int0n    ( int0n      ),
    .int1n    ( int1n      ),
    .p0_i     ( p0_i       ),
    .p1_i     ( p1_i       ),
    .p2_i     ( p2_i       ),
    .p3_i     ( p3_i       ),
    .p0_o     ( p0_o       ),
    .p1_o     ( p1_o       ),
    .p2_o     ( p2_o       ),
    .p3_o     ( p3_o       ),
    .rom_data ( rom_q      ),
    .rom_addr ( rom_addr_c ),
    .ram_din  ( ram_q      ),
    .ram_dout ( ram_dout   ),
    .ram_addr ( ram_addr   ),
    .ram_we   ( ram_we     ),
    .x_din    ( 8'hff      ),
    .x_dout   (            ),
    .x_addr   (            ),
    .x_wr     (            ),
    .x_acc    (            )
);

endmodule

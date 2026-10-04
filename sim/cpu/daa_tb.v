// T80 DAA test: runs a small program that executes DAA for every A with each combination of
// the C, N and H flags and stores A and F to 9000-9FFF; the C++ side checks the results.
module daa_tb (
    input        clk,
    input        reset_n,
    output       halted,
    input [15:0] peek_addr,
    output [7:0] peek_data
);

reg  [7:0] mem [0:65535];
wire [15:0] A;
wire  [7:0] dout;
wire        mreq_n, wr_n, halt_n;

T80s u_cpu (
    .RESET_n(reset_n), .CLK(clk), .CEN(1'b1), .WAIT_n(1'b1), .INT_n(1'b1), .NMI_n(1'b1),
    .BUSRQ_n(1'b1), .M1_n(), .MREQ_n(mreq_n), .IORQ_n(), .RD_n(), .WR_n(wr_n), .RFSH_n(),
    .HALT_n(halt_n), .BUSAK_n(), .OUT0(1'b0), .A(A), .DI(mem[A]), .DOUT(dout)
);

always @(posedge clk) if (~mreq_n & ~wr_n) mem[A] <= dout;

assign halted    = ~halt_n;
assign peek_data = mem[peek_addr];

integer i;
initial begin
    for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
    // 0000 ld sp,8000 / ld hl,9000 / ld d,0
    mem[16'h00] = 8'h31; mem[16'h01] = 8'h00; mem[16'h02] = 8'h80;
    mem[16'h03] = 8'h21; mem[16'h04] = 8'h00; mem[16'h05] = 8'h90;
    mem[16'h06] = 8'h16; mem[16'h07] = 8'h00;
    // 0008 outer: ld ix,0100 / ld c,8
    mem[16'h08] = 8'hdd; mem[16'h09] = 8'h21; mem[16'h0a] = 8'h00; mem[16'h0b] = 8'h01;
    mem[16'h0c] = 8'h0e; mem[16'h0d] = 8'h08;
    // 000E inner: ld e,(ix+0) / push de / pop af / daa / ld (hl),a / inc hl
    mem[16'h0e] = 8'hdd; mem[16'h0f] = 8'h5e; mem[16'h10] = 8'h00;
    mem[16'h11] = 8'hd5; mem[16'h12] = 8'hf1; mem[16'h13] = 8'h27;
    mem[16'h14] = 8'h77; mem[16'h15] = 8'h23;
    // push af / ld a,(7ffe) / ld (hl),a / inc hl / pop af
    mem[16'h16] = 8'hf5; mem[16'h17] = 8'h3a; mem[16'h18] = 8'hfe; mem[16'h19] = 8'h7f;
    mem[16'h1a] = 8'h77; mem[16'h1b] = 8'h23; mem[16'h1c] = 8'hf1;
    // inc ix / dec c / jr nz,inner / inc d / jr nz,outer / halt
    mem[16'h1d] = 8'hdd; mem[16'h1e] = 8'h23; mem[16'h1f] = 8'h0d;
    mem[16'h20] = 8'h20; mem[16'h21] = 8'hec;
    mem[16'h22] = 8'h14; mem[16'h23] = 8'h20; mem[16'h24] = 8'he3;
    mem[16'h25] = 8'h76;
    // flag combinations (F = ---H --NC)
    mem[16'h100] = 8'h00; mem[16'h101] = 8'h01; mem[16'h102] = 8'h02; mem[16'h103] = 8'h03;
    mem[16'h104] = 8'h10; mem[16'h105] = 8'h11; mem[16'h106] = 8'h12; mem[16'h107] = 8'h13;
end

endmodule

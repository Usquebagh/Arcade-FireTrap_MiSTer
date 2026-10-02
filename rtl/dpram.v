// Generic true dual-port synchronous RAM/ROM (infers M10K block RAM on Cyclone V).
// Both ports: registered read, write-first not required. Optional $readmemh init (simulation).
module dpram #(
    parameter AW    = 10,
    parameter DW    = 8,
    parameter DEPTH = (1 << AW),
    parameter INIT  = ""
) (
    input               clk,

    input      [AW-1:0] a_addr,
    input      [DW-1:0] a_din,
    input               a_we,
    output reg [DW-1:0] a_dout,

    input      [AW-1:0] b_addr,
    input      [DW-1:0] b_din,
    input               b_we,
    output reg [DW-1:0] b_dout
);

reg [DW-1:0] mem [0:DEPTH-1];

initial if (INIT != "") $readmemh(INIT, mem);

always @(posedge clk) begin
    if (a_we) mem[a_addr] <= a_din;
    a_dout <= mem[a_addr];
end

always @(posedge clk) begin
    if (b_we) mem[b_addr] <= b_din;
    b_dout <= mem[b_addr];
end

endmodule

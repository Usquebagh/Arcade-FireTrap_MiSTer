// Generic true dual-port synchronous RAM/ROM (infers M10K block RAM on Cyclone V).
// Both ports: registered read; a port that writes returns the written data (the Altera
// true-dual-port template - "old data" read-during-write cannot be inferred when both ports
// write). Optional $readmemh init (simulation).
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
    if (a_we) begin
        mem[a_addr] <= a_din;
        a_dout <= a_din;
    end else
        a_dout <= mem[a_addr];
end

always @(posedge clk) begin
    if (b_we) begin
        mem[b_addr] <= b_din;
        b_dout <= b_din;
    end else
        b_dout <= mem[b_addr];
end

endmodule

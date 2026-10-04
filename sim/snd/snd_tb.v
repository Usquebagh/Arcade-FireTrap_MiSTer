// Sound board stress test: commands written at random moments; counts how many the 6502 reads.
module snd_tb (
    input         clk,
    input         reset,
    input  [15:0] rom_waddr,
    input   [7:0] rom_wdata,
    input         rom_we,
    input   [7:0] cmd,
    input         cmd_wr,
    output reg [31:0] reads,
    output reg [31:0] nmis
);

wire signed [15:0] audio;
ft_sound u_snd (
    .clk(clk), .reset(reset),
    .latch_data(cmd), .latch_wr(cmd_wr),
    .rom_waddr(rom_waddr), .rom_wdata(rom_wdata), .rom_we(rom_we),
    .audio(audio)
);

`ifdef NMI_DEBUG
// Timeline of NMI handling for the first commands after `NMI_DEBUG` clocks
reg [31:0] clocks = 0;
reg  [5:0] st_l;
reg        edge_l, nmi_l;
always @(posedge clk) begin
    clocks <= clocks + 1;
    st_l   <= u_snd.u_cpu.state;
    edge_l <= u_snd.u_cpu.NMI_edge;
    nmi_l  <= u_snd.nmi_ff;
    if (clocks > `NMI_DEBUG && clocks < `NMI_DEBUG + 60000) begin
        if (u_snd.nmi_ff != nmi_l) $display("%0d nmi_ff=%0d", clocks, u_snd.nmi_ff);
        if (u_snd.u_cpu.NMI_edge != edge_l) $display("%0d NMI_edge=%0d state=%0d RDY=%0d", clocks, u_snd.u_cpu.NMI_edge, u_snd.u_cpu.state, u_snd.ce_cpu);
        if (u_snd.u_cpu.state != st_l && (u_snd.u_cpu.state >= 8 && u_snd.u_cpu.state <= 11))
            $display("%0d state %0d -> %0d AB=%04x", clocks, st_l, u_snd.u_cpu.state, u_snd.ab);
    end
end
`endif

// Count 6502 reads of the sound latch (3400) and NMI vector fetches (FFFA)
always @(posedge clk) begin
    if (reset) begin
        reads <= 0;
        nmis  <= 0;
    end else if (u_snd.ce_cpu & ~u_snd.we) begin
        if (u_snd.ab == 16'h3400) reads <= reads + 1;
        if (u_snd.ab == 16'hfffa) nmis  <= nmis + 1;
    end
end

endmodule

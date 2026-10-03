// Simulation top: ft_core + a behavioural model of the SDRAM controller's channels
// (same request/ready handshake as rtl/sdram.sv: one-clock request pulse, ready pulse).
module sim_top #(
    parameter VRAM_WAIT = 1,
    parameter GFX_LAT   = 10,     // clocks from request to data, as the 48 MHz controller
    parameter GFX_SKEW  = 0       // debug: 1 = burst captured one word late, 2 = one word early
) (
    input         clk,
    input         reset,
    input  [19:0] dl_addr,
    input   [7:0] dl_data,
    input         dl_wr,
    output        dl_wait,
    input   [7:0] in0,
    input   [7:0] in1,
    input   [3:0] in2,
    input   [2:0] coin,
    input   [7:0] dsw0,
    input   [7:0] dsw1,
    input   [3:0] layer_en,
    output        ce_pix,
    output  [7:0] red,
    output  [7:0] green,
    output  [7:0] blue,
    output        hblank,
    output        vblank,
    output        hs,
    output        vs,
    output  [8:0] vid_h,
    output  [8:0] vid_v,
    output signed [15:0] audio,
    output [15:0] dbg_addr,
    output        dbg_m1,
    output        dbg_overrun,
    input         dbg_dump,
    input         single,         // P1 single-stick mode (rtl/ft_inputs.v), left stick = in0[3:0]
    input [128:0] cheat_code,
    input         cheat_reset
);

// Single-stick mode as in the MiSTer top level (32 frames per hand swap)
reg  vbl_l;
always @(posedge clk) vbl_l <= vblank;
wire [3:0] sl_in = ~{in0[0], in0[1], in0[2], in0[3]};   // {up, down, left, right}
wire [3:0] sl_l, sl_r;
ft_single u_single (.clk(clk), .frame(vblank & ~vbl_l), .n(6'd32), .single(single),
                    .l_in(sl_in), .r_in(~{in0[4], in0[5], in0[6], in0[7]}),
                    .l_out(sl_l), .r_out(sl_r));
wire [7:0] in0_eff = ~{sl_r[0], sl_r[1], sl_r[2], sl_r[3], sl_l[0], sl_l[1], sl_l[2], sl_l[3]};

wire [22:0] gfx_addr, sdw_addr;
wire        gfx_req, sdw_req;
reg         gfx_ready, sdw_ready;
reg  [63:0] gfx_data;
wire [15:0] sdw_data;
wire  [1:0] sdw_be;

ft_core u_core (
    .clk(clk), .reset(reset), .vram_wait(VRAM_WAIT != 0),
    .dl_addr(dl_addr), .dl_data(dl_data), .dl_wr(dl_wr), .dl_wait(dl_wait),
    .gfx_addr(gfx_addr), .gfx_req(gfx_req), .gfx_ready(gfx_ready), .gfx_data(gfx_data),
    .sdw_addr(sdw_addr), .sdw_data(sdw_data), .sdw_be(sdw_be), .sdw_req(sdw_req), .sdw_ready(sdw_ready),
    .layer_en(layer_en), .cheat_code(cheat_code), .cheat_reset(cheat_reset),
    .in0(in0_eff), .in1(in1), .in2(in2), .coin(coin), .dsw0(dsw0), .dsw1(dsw1),
    .ce_pix(ce_pix), .red(red), .green(green), .blue(blue),
    .hblank(hblank), .vblank(vblank), .hs(hs), .vs(vs), .vid_h(vid_h), .vid_v(vid_v),
    .audio(audio),
    .dbg_addr(dbg_addr), .dbg_m1(dbg_m1), .dbg_overrun(dbg_overrun), .dbg_dump(dbg_dump)
);

reg [15:0] mem [0:196607];     // 3 x 64K words: BG1, BG2, sprites
reg  [4:0] rd_cnt, wr_cnt;
reg [22:0] rd_a;

always @(posedge clk) begin
    gfx_ready <= 0;
    sdw_ready <= 0;
    if (gfx_req) begin
        rd_a   <= {gfx_addr[22:2], 2'b00};
        rd_cnt <= GFX_LAT[4:0];
    end else if (rd_cnt != 0) begin
        rd_cnt <= rd_cnt - 5'd1;
        if (rd_cnt == 5'd1) begin
            if (GFX_SKEW == 1)       // late: word n gets word n+1, the last one the bus after the burst
                gfx_data <= {16'hffff, mem[rd_a + 3], mem[rd_a + 2], mem[rd_a + 1]};
            else if (GFX_SKEW == 2)  // early: word 0 gets whatever was on the bus before
                gfx_data <= {mem[rd_a + 2], mem[rd_a + 1], mem[rd_a], 16'hffff};
            else
                gfx_data <= {mem[rd_a + 3], mem[rd_a + 2], mem[rd_a + 1], mem[rd_a]};
            gfx_ready <= 1;
        end
    end
    if (sdw_req) wr_cnt <= 5'd4;
    else if (wr_cnt != 0) begin
        wr_cnt <= wr_cnt - 5'd1;
        if (wr_cnt == 5'd1) begin
            if (sdw_be[0]) mem[sdw_addr][7:0]  <= sdw_data[7:0];
            if (sdw_be[1]) mem[sdw_addr][15:8] <= sdw_data[15:8];
            sdw_ready <= 1;
        end
    end
end

endmodule

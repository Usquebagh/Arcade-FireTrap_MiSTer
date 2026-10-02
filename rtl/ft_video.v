// Fire Trap video: timing, FG (text) layer, BG1/BG2/sprite line buffers (ft_render),
// priority PROM and palette.
//
// Timing (docs/hardware.md): 6 MHz pixel clock, 384 clocks x 272 lines.
// Visible area as MAME: H 0-255, V 8-247. Each pixel slot is 8 master clocks (48 MHz);
// 'ph' is the slot phase and the counters advance at the end of phase 7.
// The colour for a slot's pixel is computed during that slot and output in the next one.
module ft_video #(
    parameter CHR_INIT  = "",
    parameter PROM_INIT = ""          // 768 bytes: 3B (R/G), 4B (B), 1A (priority)
) (
    input             clk,
    input             rst,
    input       [2:0] ph,
    input             flip,
    input       [8:0] bg1_sx, bg1_sy, bg2_sx, bg2_sy,

    // Timing
    output reg  [8:0] hc,
    output reg  [8:0] vc,
    output            hblank_now,     // undelayed blanking, for the Z80 wait logic
    output            vblank_now,

    // Video-side RAM read ports (registered BRAM)
    output reg [10:0] fg_addr,
    input       [7:0] fg_q,
    output     [10:0] bg1_addr,
    input       [7:0] bg1_q,
    output     [10:0] bg2_addr,
    input       [7:0] bg2_q,
    output      [8:0] obj_addr,
    input       [7:0] obj_q,

    // Graphics ROM (SDRAM)
    output     [22:0] gfx_addr,
    output            gfx_req,
    input             gfx_ready,
    input      [63:0] gfx_data,

    // ROM/PROM download
    input      [12:0] chr_waddr,
    input       [7:0] chr_wdata,
    input             chr_we,
    input       [9:0] prom_waddr,
    input       [7:0] prom_wdata,
    input             prom_we,

    // Layer enables (debug / OSD): FG, sprites, BG1, BG2
    input       [3:0] layer_en,

    // Output (one slot behind hc/vc)
    output reg        ce_pix,
    output reg  [7:0] red,
    output reg  [7:0] green,
    output reg  [7:0] blue,
    output reg        hblank,
    output reg        vblank,
    output reg        hs,
    output reg        vs,
    output reg  [8:0] vid_h,
    output reg  [8:0] vid_v,
    output            render_overrun
);

localparam H_TOTAL = 384, V_TOTAL = 272;
localparam HS_START = 9'd296, HS_END = 9'd328;   // sync positions are not documented
localparam VS_START = 9'd252, VS_END = 9'd255;

// ---------------------------------------------------------------- timing
always @(posedge clk) begin
    if (rst) begin
        hc <= 0;
        vc <= 0;
    end else if (ph == 3'd7) begin
        if (hc == H_TOTAL - 1) begin
            hc <= 0;
            vc <= (vc == V_TOTAL - 1) ? 9'd0 : vc + 9'd1;
        end else
            hc <= hc + 9'd1;
    end
end

assign hblank_now = hc[8];                         // 256-383
assign vblank_now = (vc < 9'd8) || (vc >= 9'd248);
wire line_start = (hc == 9'd0) && (ph == 3'd0);

// ---------------------------------------------------------------- ROMs / PROMs
reg [7:0] chr_rom [0:8191];
reg [7:0] prom    [0:767];
initial begin
    if (CHR_INIT != "")  $readmemh(CHR_INIT, chr_rom);
    if (PROM_INIT != "") $readmemh(PROM_INIT, prom);
end

reg [12:0] chr_addr;
reg  [7:0] chr_q;
always @(posedge clk) begin
    if (chr_we) chr_rom[chr_waddr] <= chr_wdata;
    chr_q <= chr_rom[chr_addr];
end

reg  [9:0] prom_addr_a, prom_addr_b;
reg  [7:0] prom_qa, prom_qb;
always @(posedge clk) begin
    if (prom_we) prom[prom_waddr] <= prom_wdata;
    prom_qa <= prom[prom_addr_a];
    prom_qb <= prom[prom_addr_b];
end

// ---------------------------------------------------------------- BG / sprite renderer
wire  [8:0] lb_waddr;
wire  [6:0] lb_wdata;
wire        lb_we_bg1, lb_we_bg2, lb_we_obj;

ft_render u_render (
    .clk        ( clk        ),
    .rst        ( rst        ),
    .line_start ( line_start ),
    .vc         ( vc         ),
    .flip       ( flip       ),
    .bg1_sx     ( bg1_sx     ),
    .bg1_sy     ( bg1_sy     ),
    .bg2_sx     ( bg2_sx     ),
    .bg2_sy     ( bg2_sy     ),
    .bg1_addr   ( bg1_addr   ),
    .bg1_q      ( bg1_q      ),
    .bg2_addr   ( bg2_addr   ),
    .bg2_q      ( bg2_q      ),
    .obj_addr   ( obj_addr   ),
    .obj_q      ( obj_q      ),
    .gfx_addr   ( gfx_addr   ),
    .gfx_req    ( gfx_req    ),
    .gfx_ready  ( gfx_ready  ),
    .gfx_data   ( gfx_data   ),
    .lb_addr    ( lb_waddr   ),
    .lb_data    ( lb_wdata   ),
    .lb_we_bg1  ( lb_we_bg1  ),
    .lb_we_bg2  ( lb_we_bg2  ),
    .lb_we_obj  ( lb_we_obj  ),
    .busy       (            ),
    .overrun    ( render_overrun )
);

// Line buffers: port A = renderer, port B = display (sprites are cleared after reading)
reg  [8:0] lb_raddr;
reg        obj_clr;
wire [6:0] bg1_lb, bg2_lb, obj_lb;
dpram #(.AW(9), .DW(7)) u_lb_bg1 (
    .clk(clk), .a_addr(lb_waddr), .a_din(lb_wdata), .a_we(lb_we_bg1), .a_dout(),
    .b_addr(lb_raddr), .b_din(7'd0), .b_we(1'b0), .b_dout(bg1_lb)
);
dpram #(.AW(9), .DW(7)) u_lb_bg2 (
    .clk(clk), .a_addr(lb_waddr), .a_din(lb_wdata), .a_we(lb_we_bg2), .a_dout(),
    .b_addr(lb_raddr), .b_din(7'd0), .b_we(1'b0), .b_dout(bg2_lb)
);
dpram #(.AW(9), .DW(7)) u_lb_obj (
    .clk(clk), .a_addr(lb_waddr), .a_din(lb_wdata), .a_we(lb_we_obj), .a_dout(),
    .b_addr(lb_raddr), .b_din(7'd0), .b_we(obj_clr), .b_dout(obj_lb)
);

// ---------------------------------------------------------------- FG layer + mixer
// Screen position as seen by the FG tilemap (MAME flips the whole 256x256 map)
wire [7:0] x = flip ? ~hc[7:0] : hc[7:0];
wire [7:0] y = flip ? ~vc[7:0] : vc[7:0];
reg  [7:0] code_l, attr_l;
reg  [1:0] fg_pix;
reg  [3:0] fg_col;
reg  [6:0] bg1_l, bg2_l, obj_l;
wire [1:0] px = x[1:0];

// FG character ROM: pixels 0-3 in the first 4 KB, 4-7 in the second; rows stored bottom-up.
// Pixel p of a byte: plane 0 (MSB) = bit 4+p, plane 1 = bit p.
wire [1:0] fg_p    = layer_en[0] ? {chr_q[4 + px], chr_q[px]} : 2'd0;
wire [6:0] obj_m   = layer_en[1] ? obj_l : 7'd0;
wire [6:0] bg1_m   = layer_en[2] ? bg1_l : 7'd0;
wire [6:0] bg2_m   = layer_en[3] ? bg2_l : 7'd0;

reg  [7:0] pal_idx;

function [7:0] level(input [3:0] b);
    level = 8'h0e * b[0] + 8'h1f * b[1] + 8'h43 * b[2] + 8'h8f * b[3];
endfunction

always @(posedge clk) begin
    obj_clr <= 0;
    case (ph)
    3'd0: begin
        fg_addr  <= {1'b0, x[7:3], ~y[7:3]};              // code
        lb_raddr <= {vc[0], hc[7:0]};
    end
    3'd1: fg_addr <= {1'b1, x[7:3], ~y[7:3]};             // attribute
    3'd2: begin
        code_l <= fg_q;
        bg1_l  <= bg1_lb;
        bg2_l  <= bg2_lb;
        obj_l  <= obj_lb;
        obj_clr <= ~hc[8];                                // clear the sprite pixel once shown
    end
    3'd3: begin
        attr_l   <= fg_q;
        chr_addr <= {x[2], fg_q[0], code_l, ~y[2:0]};
    end
    3'd5: begin
        fg_pix <= fg_p;
        fg_col <= attr_l[7:4];
        // Priority PROM 1A: A7:6 FG pixel, A5 sprite priority, A4 sprite transparent,
        // A3:0 BG1 pixel
        prom_addr_a <= {2'b10, fg_p, obj_m[6], obj_m[3:0] == 4'd0, bg1_m[3:0]};
    end
    3'd7: begin
        // prom_qa holds the layer select (read at the ph6 edge)
        case (prom_qa[1:0])
        2'd0:    pal_idx <= {2'b00, fg_col, fg_pix};
        2'd1:    pal_idx <= {2'b01, obj_m[5:0]};
        2'd2:    pal_idx <= {2'b10, bg1_m[5:0]};
        default: pal_idx <= {2'b11, bg2_m[5:0]};
        endcase
    end
    default: ;
    endcase
    // Palette PROMs for the previous slot's pixel: address at ph0, data valid at the ph2 edge
    if (ph == 3'd0) begin
        prom_addr_a <= {2'b00, pal_idx};
        prom_addr_b <= {2'b01, pal_idx};
    end
end

// ---------------------------------------------------------------- output
// The pixel computed in slot n (hc = H) is output at the ph2 edge of slot n+1, when hc
// has already advanced to H+1; blanking and sync are derived from that position.
wire [8:0] oh = (hc == 0) ? H_TOTAL - 1 : hc - 9'd1;
wire [8:0] ov = (hc == 0) ? ((vc == 0) ? V_TOTAL - 1 : vc - 9'd1) : vc;

always @(posedge clk) begin
    ce_pix <= (ph == 3'd2);
    if (ph == 3'd2) begin
        vid_h  <= oh;
        vid_v  <= ov;
        hblank <= oh[8];
        vblank <= (ov < 9'd8) || (ov >= 9'd248);
        hs     <= (oh >= HS_START) && (oh < HS_END);
        vs     <= (ov >= VS_START) && (ov < VS_END);
        if (oh[8] || ov < 9'd8 || ov >= 9'd248) begin
            red <= 0; green <= 0; blue <= 0;
        end else begin
            red   <= level(prom_qa[3:0]);
            green <= level(prom_qa[7:4]);
            blue  <= level(prom_qb[3:0]);
        end
    end
end

endmodule

// Line renderer for the two BG layers and the sprites.
// During line L it draws line L+1 into line buffers (indexed by the line's LSB), which the
// mixer in ft_video reads while line L+1 is displayed. The board does the same for sprites
// (DSPC-10 + two line buffers); the BG layers are fetched ahead here for convenience, which
// gives identical pixels as long as scroll and tile RAM do not change mid-line (tile RAM is
// only writable in blanking).
//
// Graphics come from SDRAM in 64-bit bursts = one 16-pixel tile row (see ft_core for the
// download permutation):
//   BG:      word 0 = {Q1,Q0} pixels 0-7, word 1 = {Q3,Q2} pixels 0-7, words 2/3 = pixels 8-15.
//            Pixels 0-3 use Q0/Q2, 4-7 use Q1/Q3; pixel p (0-3) = {Qk[4+p], Qk[p], Qk+2[4+p], Qk+2[p]}.
//   Sprites: word 0 = {P1,P0}, word 1 = {P3,P2} for pixels 0-7, words 2/3 for 8-15;
//            pixel p (0-7) = {P0[p], P1[p], P2[p], P3[p]}.
// Layer conventions follow MAME firetrap.cpp (tilemap mappers, scroll signs, sprite rules).
module ft_render #(
    parameter [22:0] BG1_BASE = 23'h000000,  // 16-bit word addresses
    parameter [22:0] BG2_BASE = 23'h010000,
    parameter [22:0] OBJ_BASE = 23'h020000
) (
    input             clk,
    input             rst,
    input             line_start,       // pulse at the start of each line
    input       [8:0] vc,               // line being displayed
    input             flip,
    input       [8:0] bg1_sx, bg1_sy, bg2_sx, bg2_sy,

    // Tile/sprite RAM read ports (registered BRAM, 1 clock latency)
    output reg [10:0] bg1_addr,
    input       [7:0] bg1_q,
    output reg [10:0] bg2_addr,
    input       [7:0] bg2_q,
    output reg  [8:0] obj_addr,
    input       [7:0] obj_q,

    // Graphics ROM (SDRAM), 64-bit burst reads; req is a one-clock pulse
    output reg [22:0] gfx_addr,
    output reg        gfx_req,
    input             gfx_ready,
    input      [63:0] gfx_data,

    // Line buffer writes: {line LSB, x}
    output reg  [8:0] lb_addr,
    output reg  [6:0] lb_data,          // BG: {1'b0, pal[1:0], pix[3:0]}; OBJ: {pro, col[1:0], pix[3:0]}
    output reg        lb_we_bg1,
    output reg        lb_we_bg2,
    output reg        lb_we_obj,

    output reg        busy,
    output reg        overrun           // debug: rendering did not finish within the line
);

// ---------------------------------------------------------------- fetch engine
localparam S_IDLE = 0, S_BG_CODE = 1, S_BG_ATTR = 2, S_BG_WAIT = 3, S_BG_REQ = 4, S_BG_DATA = 5,
           S_OBJ_RD = 6, S_OBJ_CHK = 7, S_OBJ_REQ = 8, S_OBJ_DATA = 9, S_DONE = 10;

reg  [3:0] st;
reg  [8:0] Y;
reg        layer;        // 0 = BG1, 1 = BG2
reg  [4:0] t;            // tile column within the line (0-16)
reg  [6:0] s;            // sprite number
reg  [2:0] k;            // byte counter for sprite RAM reads
reg  [7:0] code_l;
reg  [7:0] spr [0:3];

wire [8:0] sx = layer ? bg2_sx : bg1_sx;
wire [8:0] sy = layer ? bg2_sy : bg1_sy;
// Flip screen: MAME flips tilemaps around the visible area (256 x 256 incl. the 8-line top
// border), i.e. the map is read at (255 - x, 255 - y); the writer mirrors x.
wire [8:0] Yb = flip ? 9'd255 - Y : Y;
wire [8:0] ty = Yb - sy;                 // MAME: scrolly = -register
wire [4:0] trow = ty[8:4];
wire [4:0] tcol = sx[8:4] + t;
// MAME get_bg_memory_offset: ((row & 0xF) ^ 0xF) | (col & 0xF) << 4 | (row & 0x10) << 5 | (col & 0x10) << 6
wire [10:0] bg_off = {tcol[4], trow[4], 1'b0, tcol[3:0], ~trow[3:0]};

// Sprite geometry (MAME draw_sprites)
wire [7:0] s_y0   = spr[0];
wire [7:0] s_attr = spr[1];
wire [7:0] s_x0   = spr[2];
wire [9:0] s_code = {s_attr[7:6], spr[3]};
wire       s_dbl  = s_attr[4];
wire [8:0] s_y    = flip ? (9'd240 - s_y0 - (s_dbl ? 9'd16 : 9'd0)) : {1'b0, s_y0};
wire [7:0] s_x    = flip ? 8'd240 - s_x0 : s_x0;
wire       s_fx   = s_attr[2] ^ flip;
wire       s_fy   = s_attr[1] ^ flip;
wire [8:0] s_dy   = Y - s_y;                         // row relative to the sprite top
wire       s_hit  = s_dbl ? (s_dy < 9'd32) : (s_dy < 9'd16);
// Double height: upper cell = code|1 (code&~1 when flipped in Y)
wire [9:0] s_cell = s_dbl ? {s_code[9:1], s_dy[4] ^ ~s_fy} : s_code;
wire [3:0] s_r    = s_fy ? ~s_dy[3:0] : s_dy[3:0];
wire [1:0] s_col  = {s_attr[3], s_attr[0]};
wire       s_pro  = s_attr[5];                       // priority bit: assumed unused attr bit 5

// ---------------------------------------------------------------- pixel writer (16 pixels)
reg        w_busy;
reg  [3:0] w_i;
reg [63:0] w_data;
reg  [9:0] w_x;          // x of pixel 0 (may be negative for BG: 10-bit two's complement)
reg        w_fx, w_obj, w_layer, w_pro;
reg  [1:0] w_pal;

reg        load;          // fetch engine has a tile row ready for the writer
wire       take = load & ~w_busy;
reg [63:0] l_data;
reg  [9:0] l_x;
reg        l_fx, l_obj, l_layer, l_pro;
reg  [1:0] l_pal;

wire [3:0] wp   = w_fx ? ~w_i : w_i;                 // pixel within the tile row
wire [15:0] wlo = w_data[{wp[3], 1'b0, 4'd0} +: 16];  // word 0 or 2
wire [15:0] whi = w_data[{wp[3], 1'b1, 4'd0} +: 16];  // word 1 or 3
wire [7:0] qk   = wp[2] ? wlo[15:8] : wlo[7:0];
wire [7:0] qk2  = wp[2] ? whi[15:8] : whi[7:0];
wire [3:0] bg_pix  = {qk[{1'b1, wp[1:0]}], qk[{1'b0, wp[1:0]}], qk2[{1'b1, wp[1:0]}], qk2[{1'b0, wp[1:0]}]};
wire [3:0] obj_pix = {wlo[wp[2:0]], wlo[{1'b1, wp[2:0]}], whi[wp[2:0]], whi[{1'b1, wp[2:0]}]};
wire [9:0] wx = w_x + w_i;

always @(posedge clk) begin
    lb_we_bg1 <= 0;
    lb_we_bg2 <= 0;
    lb_we_obj <= 0;
    if (rst) begin
        w_busy <= 0;
    end else if (w_busy) begin
        lb_addr <= {Y[0], (flip & ~w_obj) ? ~wx[7:0] : wx[7:0]};
        if (w_obj) begin
            lb_data   <= {w_pro, w_pal, obj_pix};
            lb_we_obj <= obj_pix != 4'd0;             // sprite X wraps (MAME draws at x and x-256)
        end else begin
            lb_data   <= {1'b0, w_pal, bg_pix};
            lb_we_bg1 <= ~w_layer & ~wx[9] & ~wx[8];
            lb_we_bg2 <=  w_layer & ~wx[9] & ~wx[8];
        end
        w_i <= w_i + 4'd1;
        if (w_i == 4'd15) w_busy <= 0;
    end else if (take) begin
        w_busy  <= 1;
        w_i     <= 0;
        w_data  <= l_data;
        w_x     <= l_x;
        w_fx    <= l_fx;
        w_obj   <= l_obj;
        w_layer <= l_layer;
        w_pal   <= l_pal;
        w_pro   <= l_pro;
    end
end
// A new fetch may only be issued once the previous tile row has been handed to the writer
wire can_fetch = ~load | take;

// ---------------------------------------------------------------- fetch state machine
reg [11:0] clocks;
always @(posedge clk) begin
    gfx_req <= 0;
    if (take) load <= 0;
    clocks <= clocks + 12'd1;

    if (rst) begin
        st      <= S_IDLE;
        busy    <= 0;
        load    <= 0;
        overrun <= 0;
    end else begin
        if (line_start) begin
            if (busy) overrun <= 1;
            st     <= S_BG_CODE;
            busy   <= 1;
            Y      <= (vc == 9'd271) ? 9'd0 : vc + 9'd1;
            layer  <= 0;
            t      <= 0;
            k      <= 0;
            clocks <= 0;
        end else case (st)
        S_IDLE: ;
        // -------- BG layers: 17 tiles each
        S_BG_CODE: begin
            bg1_addr <= bg_off;
            bg2_addr <= bg_off;
            st <= S_BG_ATTR;
        end
        S_BG_ATTR: begin
            bg1_addr <= bg_off | 11'h100;
            bg2_addr <= bg_off | 11'h100;
            st <= S_BG_WAIT;
        end
        S_BG_WAIT: begin
            code_l <= layer ? bg2_q : bg1_q;             // code (addressed two clocks ago)
            st <= S_BG_REQ;
        end
        S_BG_REQ: if (can_fetch) begin
            // attribute is on q now. Bit 3 flips X and bit 2 flips Y in screen (native)
            // orientation: MAME's TILE_FLIPXY((attr & 0x0c) >> 2) ends up this way, and the
            // game's mirrored building halves (attr bit 2 set) only join up like this.
            l_fx    <= layer ? bg2_q[3] : bg1_q[3];
            l_pal   <= layer ? bg2_q[5:4] : bg1_q[5:4];
            l_layer <= layer;
            l_obj   <= 0;
            l_pro   <= 0;
            l_x     <= {1'b0, t, 4'd0} - {6'd0, sx[3:0]};
            gfx_addr <= (layer ? BG2_BASE : BG1_BASE) +
                        {9'd0, (layer ? bg2_q[1:0] : bg1_q[1:0]), code_l,
                         ((layer ? bg2_q[2] : bg1_q[2]) ? ty[3:0] : ~ty[3:0]), 2'b00};
            gfx_req <= 1;
            st <= S_BG_DATA;
        end
        S_BG_DATA: if (gfx_ready) begin
            l_data <= gfx_data;
            load   <= 1;
            if (t == 5'd16) begin
                t <= 0;
                if (layer) begin
                    s  <= 0;
                    k  <= 0;
                    st <= S_OBJ_RD;
                end else begin
                    layer <= 1;
                    st <= S_BG_CODE;
                end
            end else begin
                t  <= t + 5'd1;
                st <= S_BG_CODE;
            end
        end
        // -------- sprites: 96 x 4 bytes
        S_OBJ_RD: begin
            // address byte k, data for byte k-2 arrives (registered RAM + address register)
            obj_addr <= {s[6:0], k[1:0]};
            if (k >= 3'd2) spr[k - 3'd2] <= obj_q;
            k <= k + 3'd1;
            if (k == 3'd5) st <= S_OBJ_CHK;
        end
        S_OBJ_CHK: if (can_fetch) begin
            if (s_hit) begin
                l_fx    <= s_fx;
                l_pal   <= s_col;
                l_pro   <= s_pro;
                l_obj   <= 1;
                l_layer <= 0;
                l_x     <= {2'b00, s_x};
                gfx_addr <= OBJ_BASE + {9'd0, s_cell, ~s_r, 2'b00};
                gfx_req <= 1;
                st <= S_OBJ_DATA;
            end else
                st <= S_OBJ_REQ;
        end
        S_OBJ_DATA: if (gfx_ready) begin
            l_data <= gfx_data;
            load   <= 1;
            st     <= S_OBJ_REQ;
        end
        S_OBJ_REQ: begin                                // next sprite
            k <= 0;
            if (s == 7'd95) st <= S_DONE;
            else begin
                s  <= s + 7'd1;
                st <= S_OBJ_RD;
            end
        end
        S_DONE: if (~load & ~w_busy & ~take) begin
            busy <= 0;
            st   <= S_IDLE;
        end
        endcase
    end
end

endmodule

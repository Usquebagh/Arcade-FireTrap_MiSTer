// Cheat engine for the Z80 (8-bit data bus).
//
// Adapted from the Irem M92 core's cheatengine_32_16 (Martin Donlon, GPL-2.0+), which is
// based on Kitrinx's MiSTer cheat code handling. Same 16-byte code format as MiSTer MRA
// <cheat> entries, e.g. "000000 10 0000C143 00000000 00000008":
//
//   [127:96] flags: bit 96 = compare enable, [102:100] = width (1 = byte),
//                   [105:104] = method (0 replace, 1 OR, 2 AND)
//   [95:64]  address (low 16 bits used)
//   [63:32]  compare value (low byte used)
//   [31:0]   replacement value (low byte used)
//
// Codes for work RAM (C000-CFFF) are applied the way MAME's cheat scripts are: the value is
// written into RAM once per frame (start of VBLANK), so the game still sees its own writes in
// between. Substituting every read instead breaks Fire Trap (the timer cheat makes the game
// reset itself at the start of a stage). Codes for other addresses replace the data on Z80
// reads.
module ft_cheats #(
    parameter MAX_CODES = 16
) (
    input            clk,
    input            reset,      // on the first byte of a new code download
    input    [128:0] code,       // bit 128 = strobe (rising edge loads one code)
    input     [15:0] addr,
    input      [7:0] din,
    output reg [7:0] dout,

    // Work RAM pokes (second RAM port)
    input            frame,      // one pulse per frame
    output reg [11:0] poke_addr,
    output reg  [7:0] poke_data,
    output reg        poke_we,
    input       [7:0] poke_q     // RAM read data for OR/AND/compare codes (1-clock latency)
);

reg        valid  [0:MAX_CODES-1];
reg [15:0] c_addr [0:MAX_CODES-1];
reg  [7:0] c_cmp  [0:MAX_CODES-1];
reg        c_cmpe [0:MAX_CODES-1];
reg  [7:0] c_val  [0:MAX_CODES-1];
reg  [1:0] c_meth [0:MAX_CODES-1];

reg  [4:0] next_index = 0;
reg        strobe_last = 0;
integer    k;
initial for (k = 0; k < MAX_CODES; k = k + 1) valid[k] = 0;

always @(posedge clk) begin
    strobe_last <= code[128];
    if (reset) begin
        next_index <= 0;
        for (k = 0; k < MAX_CODES; k = k + 1) valid[k] <= 0;
    end else if (code[128] && !strobe_last && next_index < MAX_CODES) begin
        valid [next_index] <= code[102:100] == 3'd1;   // byte codes only
        c_addr[next_index] <= code[79:64];
        c_cmp [next_index] <= code[39:32];
        c_cmpe[next_index] <= code[96];
        c_val [next_index] <= code[7:0];
        c_meth[next_index] <= code[105:104];
        next_index <= next_index + 5'd1;
    end
end

function is_ram(input [15:0] a);
    is_ram = a[15:12] == 4'hC;
endfunction

// Read substitution for codes outside work RAM
integer x;
always @* begin
    dout = din;
    for (x = 0; x < MAX_CODES; x = x + 1)
        if (valid[x] && !is_ram(c_addr[x]) && c_addr[x] == addr && (!c_cmpe[x] || c_cmp[x] == din))
            case (c_meth[x])
                2'd1:    dout = c_val[x] | din;
                2'd2:    dout = c_val[x] & din;
                default: dout = c_val[x];
            endcase
end

// Once per frame: for each RAM code, read the byte, then write the new value
reg  [4:0] pi;          // code index being poked
reg  [1:0] pst;         // 0 idle, 1 address, 2 wait, 3 write
wire [3:0] pk = pi[3:0];
always @(posedge clk) begin
    poke_we <= 0;
    if (reset) begin
        pst <= 0;
    end else case (pst)
    2'd0: if (frame) begin pi <= 0; pst <= 2'd1; end
    2'd1: begin
        if (pi == MAX_CODES) pst <= 2'd0;
        else if (valid[pk] && is_ram(c_addr[pk])) begin
            poke_addr <= c_addr[pk][11:0];
            pst <= 2'd2;
        end else
            pi <= pi + 5'd1;
    end
    2'd2: pst <= 2'd3;                                   // RAM read latency
    2'd3: begin
        if (!c_cmpe[pk] || c_cmp[pk] == poke_q) begin
            case (c_meth[pk])
                2'd1:    poke_data <= c_val[pk] | poke_q;
                2'd2:    poke_data <= c_val[pk] & poke_q;
                default: poke_data <= c_val[pk];
            endcase
            poke_we <= 1;
        end
        pi  <= pi + 5'd1;
        pst <= 2'd1;
    end
    endcase
end

endmodule

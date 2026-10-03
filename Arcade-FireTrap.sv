//============================================================================
//  Arcade: Fire Trap (Wood Place / Data East USA, 1986)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];
wire       no_rotate = status[2] | direct_video;

assign VIDEO_ARX = (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"FireTrap;;",
	"-;",
	"O[2],Orientation,Vertical,Horizontal;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O[8],Joysticks,Twin Stick,Single Stick;",
	"O[14:13],Single Stick Climb,24 Frames,16 Frames,32 Frames,40 Frames;",
	"O[9],4-Way Filter,On,Off;",
	"-;",
	"DIP;",
	"-;",
	"C,Cheats;",
	"-;",
	"P1,Advanced;",
	"P1-;",
	"P1O[10],Z80 VRAM Wait,On (Board),Off (MAME);",
	"P1O[12:11],SDRAM Read Phase,2.5,2.0,3.0,3.5;",
	"-;",
	"R[0],Reset;",
	"J1,Fire,R-Stick Up,R-Stick Down,R-Stick Left,R-Stick Right,Start,Coin;",
	"jn,R,X,B,Y,A,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;   // 48 MHz = 4 x 12 MHz
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

wire         ioctl_download;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire  [15:0] ioctl_index;
wire         ioctl_wait;

wire  [31:0] joy0, joy1;
wire  [15:0] joy_l0, joy_l1, joy_r0, joy_r1;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),

	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_l_analog_0(joy_l0),
	.joystick_l_analog_1(joy_l1),
	.joystick_r_analog_0(joy_r0),
	.joystick_r_analog_1(joy_r1)
);

wire rom_download  = ioctl_download && ioctl_index == 0;
wire code_download = ioctl_download && ioctl_index == 255;

// Cheat codes from the MRA <cheats> section: 16 bytes per code, shifted in MSB first;
// bit 128 strobes each complete code into the engine (as in the Jedi and Irem M92 cores).
reg [128:0] cheat_code = 0;
always @(posedge clk_sys) begin
	cheat_code[128] <= 1'b0;
	if (code_download & ioctl_wr) begin
		cheat_code[127:0] <= {cheat_code[119:0], ioctl_dout};
		cheat_code[128]   <= &ioctl_addr[3:0];
	end
end
wire cheat_reset = code_download && ioctl_wr && ioctl_addr == 0;
wire reset = RESET | status[0] | buttons[1] | rom_download | ~pll_locked;

// DIP switches from the MRA (ioctl index 254): byte 0 = SW1 (DSW0), byte 1 = SW2 (DSW1)
reg [7:0] sw[2];
always @(posedge clk_sys)
	if (ioctl_wr && ioctl_index == 254 && !ioctl_addr[24:1]) sw[ioctl_addr[0]] <= ioctl_dout;

wire [7:0] r, g, b;
wire       hs, vs, hbl, vbl, ce_pix, flip_screen;

////////////////////   INPUTS   ///////////////////
// Each player has two 4-way sticks and one button. Climbing is hand over hand, as in Crazy
// Climber: alternate (left up, right down) and (left down, right up); both sticks left/right
// move sideways. Left stick: d-pad or left analog stick. Right stick: right analog stick or the
// buttons mapped to R-Stick Up/Down/Left/Right.
// "Single Stick": one joystick drives both. Holding up alternates the hands automatically every
// N frames (MAME test: the climb speed levels off at about 40 frames per swap); other
// directions go to both sticks.

// Analog stick -> {up, down, left, right} with a threshold of half deflection
function [3:0] analog_dirs(input [15:0] a);
	analog_dirs = { $signed(a[15:8]) < -8'sd64, $signed(a[15:8]) > 8'sd64,
	                $signed(a[7:0])  < -8'sd64, $signed(a[7:0])  > 8'sd64 };
endfunction

// MiSTer joystick bits [3:0] = up, down, left, right
wire [3:0] p1_l = joy0[3:0] | analog_dirs(joy_l0);
wire [3:0] p2_l = joy1[3:0] | analog_dirs(joy_l1);
wire [3:0] p1_r = {joy0[5], joy0[6], joy0[7], joy0[8]} | analog_dirs(joy_r0);
wire [3:0] p2_r = {joy1[5], joy1[6], joy1[7], joy1[8]} | analog_dirs(joy_r1);

wire single = status[8];
wire [3:0] p1_lf, p2_lf, p1_rf, p2_rf, p1_l4, p2_l4, p1_r4, p2_r4;
ft_4way f1l (.clk(clk_sys), .enable(~status[9]), .in(p1_l), .out(p1_lf));
ft_4way f2l (.clk(clk_sys), .enable(~status[9]), .in(p2_l), .out(p2_lf));
ft_4way f1r (.clk(clk_sys), .enable(~status[9]), .in(p1_r), .out(p1_rf));
ft_4way f2r (.clk(clk_sys), .enable(~status[9]), .in(p2_r), .out(p2_rf));

// Single-stick climbing: swap hands every 24 (default), 16, 32 or 40 frames
wire [5:0] climb_n = status[14:13] == 2'd1 ? 6'd16 : status[14:13] == 2'd2 ? 6'd32 :
                     status[14:13] == 2'd3 ? 6'd40 : 6'd24;
reg vbl_l;
always @(posedge clk_sys) vbl_l <= vbl;
wire frame = vbl & ~vbl_l;

ft_single s1 (.clk(clk_sys), .frame(frame), .n(climb_n), .single(single),
              .l_in(p1_lf), .r_in(p1_rf), .l_out(p1_l4), .r_out(p1_r4));
ft_single s2 (.clk(clk_sys), .frame(frame), .n(climb_n), .single(single),
              .l_in(p2_lf), .r_in(p2_rf), .l_out(p2_l4), .r_out(p2_r4));

// IN0/IN1 bits 0-3 = left stick up, down, left, right; 4-7 = right stick (all active low)
function [7:0] stick_port(input [3:0] l, input [3:0] r);
	stick_port = ~{r[0], r[1], r[2], r[3], l[0], l[1], l[2], l[3]};
endfunction

wire [7:0] in0 = stick_port(p1_l4, p1_r4);
wire [7:0] in1 = stick_port(p2_l4, p2_r4);
wire [3:0] in2 = ~{joy1[9], joy1[4], joy0[9], joy0[4]};      // start 2, P2 fire, start 1, P1 fire
wire coin1, coin2;
ft_coin c1 (.clk(clk_sys), .frame(frame), .button(joy0[10]), .coin(coin1));
ft_coin c2 (.clk(clk_sys), .frame(frame), .button(joy1[10]), .coin(coin2));
wire [2:0] coin = ~{coin2, coin1, 1'b0};                     // coin 2, coin 1, service

////////////////////   CORE   ///////////////////

wire signed [15:0] audio;

wire [22:0] gfx_addr, sdw_addr;
wire        gfx_req, gfx_ready, sdw_req, sdw_ready;
wire [63:0] gfx_data;
wire [15:0] sdw_data;
wire  [1:0] sdw_be;

ft_core core
(
	.clk(clk_sys),
	.reset(reset),
	.vram_wait(~status[10]),

	.dl_addr(ioctl_addr[19:0]),
	.dl_data(ioctl_dout),
	.dl_wr(ioctl_wr & rom_download),
	.dl_wait(ioctl_wait),

	.gfx_addr(gfx_addr),
	.gfx_req(gfx_req),
	.gfx_ready(gfx_ready),
	.gfx_data(gfx_data),
	.sdw_addr(sdw_addr),
	.sdw_data(sdw_data),
	.sdw_be(sdw_be),
	.sdw_req(sdw_req),
	.sdw_ready(sdw_ready),

	.layer_en(4'hf),
	.cheat_code(cheat_code),
	.cheat_reset(cheat_reset),

	.in0(in0),
	.in1(in1),
	.in2(in2),
	.coin(coin),
	.dsw0(sw[0]),
	.dsw1(sw[1]),

	.ce_pix(ce_pix),
	.red(r),
	.green(g),
	.blue(b),
	.hblank(hbl),
	.vblank(vbl),
	.hs(hs),
	.vs(vs),
	.vid_h(),
	.vid_v(),
	.flip_screen(flip_screen),

	.audio(audio),

	.dbg_addr(),
	.dbg_m1(),
	.dbg_overrun(),
	.dbg_dump(1'b0)
);

////////////////////   SDRAM   ///////////////////
// Graphics ROMs (3 x 128 KB). Channel 2: 64-bit burst reads, channel 3: download writes.

sdram sdram
(
	.init(~pll_locked),
	.clk(clk_sys),
	// OSD order 2.5 (default), 2.0, 3.0, 3.5 clocks -> controller phase 1, 0, 2, 3
	.rd_phase(status[12:11] == 2'd0 ? 2'd1 : status[12:11] == 2'd1 ? 2'd0 : status[12:11]),
	.doRefresh(1'b0),

	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_CLK(SDRAM_CLK),

	.ch1_addr(26'd0),
	.ch1_dout(),
	.ch1_req(1'b0),
	.ch1_ready(),

	.ch2_addr({3'd0, gfx_addr}),
	.ch2_dout(gfx_data),
	.ch2_req(gfx_req),
	.ch2_ready(gfx_ready),

	.ch3_addr({3'd0, sdw_addr}),
	.ch3_dout(),
	.ch3_din(sdw_data),
	.ch3_be(sdw_be),
	.ch3_req(sdw_req),
	.ch3_rnw(1'b0),
	.ch3_ready(sdw_ready),

	.ch4_addr(26'd0),
	.ch4_dout(),
	.ch4_req(1'b0),
	.ch4_ready()
);

////////////////////   VIDEO / AUDIO   ///////////////////

arcade_video #(256, 24) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(ce_pix),

	.RGB_in({r, g, b}),
	.HBlank(hbl),
	.VBlank(vbl),
	.HSync(hs),
	.VSync(vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),

	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// ROT90 (MAME): rotate clockwise. When the game flips the picture (Flip Screen DIP, or
// player 2 in cocktail mode) rotate the other way so it stays upright on a single monitor.
screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),

	.rotate_ccw(flip_screen),
	.no_rotate(no_rotate),
	.flip(1'b0),
	.video_rotated(),

	.FB_EN(FB_EN),
	.FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH),
	.FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE),
	.FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),

	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),
	.DDRAM_RD(DDRAM_RD)
);

assign AUDIO_L   = audio;
assign AUDIO_R   = audio;
assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_USER = ioctl_download;

endmodule

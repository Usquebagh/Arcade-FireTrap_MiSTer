// Fire Trap input helpers for the MiSTer top level (also used by the simulation).

// Coin switch: the 8751 only credits a coin whose switch opens again within 24 frames
// (longer = jammed coin, ignored). A pad button is easily held longer, so each press becomes
// a 6-frame pulse, like a real coin mech.
module ft_coin
(
	input      clk,
	input      frame,     // one pulse per video frame
	input      button,    // active high
	output     coin       // active high, 6 frames per press
);

reg       btn_l;
reg [2:0] cnt;
always @(posedge clk) begin
	btn_l <= button;
	if (button & ~btn_l)
		cnt <= 3'd6;
	else if (frame && cnt != 0)
		cnt <= cnt - 3'd1;
end
assign coin = cnt != 0;

endmodule

// Single-stick mode for one player: the left (only) stick drives both sticks; holding up
// alternates the hands every n frames so the player climbs.
module ft_single
(
	input            clk,
	input            frame,   // one pulse per video frame
	input      [5:0] n,
	input            single,
	input      [3:0] l_in,    // up, down, left, right
	input      [3:0] r_in,
	output     [3:0] l_out,
	output     [3:0] r_out
);

reg       phase;
reg [5:0] cnt;
wire      up = l_in == 4'b1000;

always @(posedge clk) begin
	if (!up) begin
		phase <= 0;
		cnt   <= 0;
	end else if (frame) begin
		if (cnt == n - 6'd1) begin
			cnt   <= 0;
			phase <= ~phase;
		end else
			cnt <= cnt + 6'd1;
	end
end

assign l_out = !single ? l_in : up ? (phase ? 4'b0100 : 4'b1000) : l_in;
assign r_out = !single ? r_in : up ? (phase ? 4'b1000 : 4'b0100) : l_in;

endmodule

// 4-way joystick filter (MAME PORT_4WAY): when two directions are held, the one pressed
// most recently wins.
module ft_4way
(
	input            clk,
	input            enable,
	input      [3:0] in,      // up, down, left, right
	output     [3:0] out
);

reg [3:0] in_l, out_r;
wire [3:0] newly = in & ~in_l;
wire onehot_in  = (in    != 0) && ((in    & (in    - 4'd1)) == 0);
wire onehot_new = (newly != 0) && ((newly & (newly - 4'd1)) == 0);

always @(posedge clk) begin
	in_l <= in;
	if (in == 0)                 out_r <= 0;
	else if (onehot_in)          out_r <= in;
	else if (onehot_new)         out_r <= newly;
	else if ((out_r & in) == 0)  out_r <= in[3] ? 4'b1000 : in[2] ? 4'b0100 : in[1] ? 4'b0010 : 4'b0001;
end

assign out = enable ? out_r : in;

endmodule

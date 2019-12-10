// 
// c1541_track
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
/////////////////////////////////////////////////////////////////////////

module c1541_track
(
	input         clk,
	input         reset,

	input         sd_clk,
	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         disk_change,
	input   [1:0] stp,
	input         mtr,
	input         act,
	output        tr00_sense_n,
	input  [12:0] buff_addr,
	output  [7:0] buff_dout,
	input   [7:0] buff_din,
	input         buff_we,
	output  [1:0] buff_speed_zone,
	output reg    busy
);

always @(posedge sd_clk) begin
	reg wr1,rd1;
	
	wr1 <= wr;
	rd1 <= rd;
	
	sd_wr <= wr1;
	sd_rd <= rd1;
end

reg sd_buff_phase;
assign sd_buff_din = sd_buff_phase ? speed_buffer_din : buffer_din;

wire [7:0] buffer_din;
wire sd_b_ack = sd_ack & busy;
trk_dpram buffer
(
	.clock_a(sd_clk),
	.address_a({sd_buff_base, sd_buff_addr}),
	.data_a(sd_buff_dout),
	.wren_a(sd_b_ack & sd_buff_wr & ~sd_buff_phase),
	.q_a(buffer_din),

	.clock_b(clk),
	.address_b(buff_addr),
	.data_b(buff_din),
	.wren_b(buff_we),
	.q_b(buff_dout)
);

wire [7:0] speed_buffer_din;
// XXX: ADDRWIDTH 7 would be enough with one speed per byte, and 5 with 4 speeds per byte,
// but both require extra logic and there does not seem to be a need to save memory so much.
trk_dpram #(.ADDRWIDTH(9)) speed_buffer
(
	.clock_a(sd_clk),
	.address_a(sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_b_ack & sd_buff_wr & sd_buff_phase),
	.q_a(speed_buffer_din),

	.clock_b(clk),
	.address_b({2'b0, cur_half_track}),
	.data_b(), // XXX: no drive-side write support.
	.wren_b(1'b0),
	.q_b({6'bx, buff_speed_zone})
);

reg [3:0] sd_buff_base;
reg [6:0] cur_half_track;
reg [6:0] lba_half_track;
assign sd_lba = {sd_buff_phase, lba_half_track, sd_buff_base};
reg rd,wr;

always @(posedge clk) begin
	reg ack1,ack2,ack;
	reg old_ack;
	reg old_disk_change, ready = 0;
	reg saving = 0;

	old_disk_change <= disk_change;
	if (~old_disk_change && disk_change) ready <= 1;
	
	ack1 <= sd_b_ack;
	ack2 <= ack1;
	if(ack2 == ack1) ack <= ack1;

	old_ack <= ack;
	if(ack) {rd,wr} <= 0;

	if(reset) begin
		cur_half_track <= 0;
		lba_half_track <= 0;
		busy  <= 0;
		rd <= 0;
		wr <= 0;
		saving<= 0;
		sd_buff_phase <= 0;
	end
	else
	if(busy) begin
		if(old_ack && ~ack) begin
			if(sd_buff_phase == 0 && sd_buff_base != 4'b1111) begin
				sd_buff_base <= sd_buff_base + 4'b1;
				if(saving) wr <= 1;
					else rd <= 1;
			end
			else
			if(sd_buff_phase == 0) begin // XXX: reading once on disk change would be enough
				sd_buff_base <= 0;
				sd_buff_phase <= 1;
				lba_half_track <= 0; // Speed block LBA is track-independent.
				if(saving) wr <= 1;
					else rd <= 1;
			end
			else
			if(saving && (cur_half_track != half_track)) begin
				saving <= 0;
				sd_buff_phase <= 0;
				cur_half_track <= half_track;
				lba_half_track <= half_track;
				sd_buff_base <= 0;
				rd <= 1;
			end
			else
			begin
				busy <= 0;
			end
		end
	end
	else
	if(ready) begin
		if(save_track) begin
			saving <= 1;
			sd_buff_phase <= 0;
			sd_buff_base <= 0;
			wr <= 1;
			busy <= 1;
		end
		else
		if (
			(cur_half_track != half_track) ||
			(old_disk_change && ~disk_change)
		) begin
			saving <= 0;
			sd_buff_phase <= 0;
			cur_half_track <= half_track;
			lba_half_track <= half_track;
			sd_buff_base <= 0;
			rd <= 1;
			busy <= 1;
		end
	end
end

reg [6:0] half_track;
reg       save_track;
always @(posedge clk) begin
	reg       track_modified;
	reg [1:0] stp_r;
	reg       act_r;

	tr00_sense_n <= |half_track;
	stp_r <= stp;
	act_r <= act;
	save_track <= 0;

	if (buff_we) track_modified <= 1;
	if (disk_change) track_modified <= 0;

	if (reset) begin
		half_track <= 36;
		track_modified <= 0;
	end else begin
		if (mtr) begin
			if ((stp_r == 0 && stp == 1)
				|| (stp_r == 1 && stp == 2)
				|| (stp_r == 2 && stp == 3)
				|| (stp_r == 3 && stp == 0)) begin
				if (half_track < 83) half_track <= half_track + 7'b1;
				save_track <= track_modified;
				track_modified <= 0;
			end

			if ((stp_r == 0 && stp == 3)
				|| (stp_r == 3 && stp == 2)
				|| (stp_r == 2 && stp == 1)
				|| (stp_r == 1 && stp == 0)) begin
				if (half_track) half_track <= half_track - 7'b1;
				save_track <= track_modified;
				track_modified <= 0;
			end
		end

		if (act_r && ~act) begin		// stopping activity
			save_track <= track_modified;
			track_modified <= 0;
		end
	end
end
endmodule

module trk_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=13)
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

logic [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always_ff@(posedge clock_a) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always_ff@(posedge clock_b) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule

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
	input         side,
	input   [1:0] stp,
	input         mtr,
	output        tr00_sense_n,
	input  [12:0] buff_addr,
	output  [7:0] buff_dout,
	input   [7:0] buff_din,
	input         buff_we,
	output reg    busy
);

always @(posedge sd_clk) begin
	reg wr1,rd1;
	
	wr1 <= wr;
	rd1 <= rd;
	
	sd_wr <= wr1;
	sd_rd <= rd1;
end

wire sd_b_ack = sd_ack && busy;
trk_dpram buffer
(
	.clock_a(sd_clk),
	.address_a({sd_buff_base, sd_buff_addr}),
	.data_a(sd_buff_dout),
	.wren_a(sd_b_ack && sd_buff_wr),
	.q_a(sd_buff_din),

	.clock_b(clk),
	.address_b(buff_addr),
	.data_b(buff_din),
	.wren_b(buff_we),
	.q_b(buff_dout)
);

reg rd, wr;
// Actual tracks are composed of 7692, 7142, 6666, or 6250 GCR bytes
// (depending on physical track length).
// The largest is 0x1e0c. As a simplification, use 0x2000-bytes tracks
// in the file format, or 16 LBA blocks of 512 bytes.
// sd_buff_base is the LBA block index in the track, from 0 to 15.
// It also directly maps as the most significant bits in "buffer", which
// contains an entire track.
// cur_half_track is the track index in the file, from 0 to 83.
// cur_side is the diskette side, 0 for single-sided diskettes.
reg [3:0] sd_buff_base;
reg [6:0] cur_half_track;
reg       cur_side;
assign sd_lba = {20'b0, cur_side, cur_half_track, sd_buff_base};

always @(posedge clk) begin
	reg ack1, ack2, ack;
	reg old_ack;
	reg old_disk_change, ready = 1'b0;
	reg saving = 1'b0;

	old_disk_change <= disk_change;
	if (~old_disk_change && disk_change) ready <= 1'b1;
	
	ack1 <= sd_b_ack;
	ack2 <= ack1;
	if (ack2 == ack1) ack <= ack1;

	old_ack <= ack;
	if (ack) {rd, wr} <= 2'b0;

	if (reset) begin
		cur_half_track <= 7'b0;
		cur_side <= 1'b0;
		busy <= 1'b0;
		rd <= 1'b0;
		wr <= 1'b0;
		saving <= 1'b0;
	end else if (busy) begin
		if (old_ack && ~ack) begin
			if (sd_buff_base != 4'b1111) begin
				// read or write next block
				sd_buff_base <= sd_buff_base + 4'b1;
				if(saving) wr <= 1'b1;
				else rd <= 1'b1;
			end else if(saving && (cur_half_track != half_track || cur_side != side)) begin
				// done writing and was changing track ? start reading new track.
				saving <= 1'b0;
				cur_half_track <= half_track;
				cur_side <= side;
				sd_buff_base <= 4'b0;
				rd <= 1'b1;
			end else begin
				// done reading or writing
				busy <= 1'b0;
			end
		end
	end else if (ready) begin
		if (save_track) begin
			// start writing track buffer back to sdcard
			saving <= 1'b1;
			sd_buff_base <= 4'b0;
			wr <= 1'b1;
			busy <= 1'b1;
		end else if (
			(cur_half_track != half_track) ||
			(cur_side != side) ||
			(old_disk_change && ~disk_change)
		) begin
			// start reading sdcard to track buffer
			saving <= 1'b0;
			cur_half_track <= half_track;
			cur_side <= side;
			sd_buff_base <= 4'b0;
			rd <= 1'b1;
			busy <= 1'b1;
		end
	end
end

reg [6:0] half_track;
reg       save_track;
always @(posedge clk) begin
	reg       track_modified;
	reg [1:0] stp_r;
	reg       mtr_r;

        tr00_sense_n <= |half_track;
	stp_r <= stp;
	mtr_r <= mtr;
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

		if (mtr_r && ~mtr) begin		// stopping activity
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

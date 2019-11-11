// 
// c1571_track
// Copyright (c) 2016 Sorgelig
// Copyright (C) 2019 Vincent Pelletier
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

module c1571_track
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

	input         save_track,
	input         change,
	input         side,
	input   [5:0] track,
	input   [4:0] sector,
	input   [7:0] buff_addr,
	output  [7:0] buff_dout,
	input   [7:0] buff_din,
	input         buff_we,
	output reg    busy
);

assign sd_lba = lba;

always @(posedge sd_clk) begin
	reg wr1,rd1;
	
	wr1 <= wr;
	rd1 <= rd;
	
	sd_wr <= wr1;
	sd_rd <= rd1;
end

wire sd_b_ack = sd_ack & busy;
c1571_trk_dpram buffer
(
	.clock_a(sd_clk),
	.address_a(sd_buff_base + base_fix + sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_b_ack & sd_buff_wr),
	.q_a(sd_buff_din),

	.clock_b(clk),
	.address_b({sector, buff_addr}),
	.data_b(buff_din),
	.wren_b(buff_we),
	.q_b(buff_dout)
);

// TODO: support error bytes
// Tracks 1 to 17 have 21 sectors
// Tracks 18 to 24 have 19 sectors
// Tracks 25 to 30 have 18 sectors
// Tracks 31 to 35 have 17 sectors
wire [10:0] start_sectors[2][36] = '{
  '{   0,
       0,  21,  42,  63,  84, 105, 126, 147, 168, 189, 210, 231, 252, 273, 294, 315, 336,
     357, 376, 395, 414, 433, 452, 471,
     490, 508, 526, 544, 562, 580,
     598, 615, 632, 649, 666
  }, '{
       0,
     683, 704, 725, 746, 767, 788, 809, 830, 851, 872, 893, 914, 935, 956, 977, 998,1019,
    1040,1059,1078,1097,1116,1135,1154,
    1173,1191,1209,1227,1245,1263,
    1281,1298,1315,1332,1349
  }
};
reg [31:0] lba;
reg [12:0] base_fix;
reg [12:0] sd_buff_base;
reg rd,wr;

always @(posedge clk) begin
	reg ack1,ack2,ack;
	reg old_ack;
	reg [5:0] cur_track = 0;
	reg old_change, ready = 0;
	reg saving = 0;

	old_change <= change;
	if(~old_change & change) ready <= 1;
	
	ack1 <= sd_b_ack;
	ack2 <= ack1;
	if(ack2 == ack1) ack <= ack1;

	old_ack <= ack;
	if(ack) {rd,wr} <= 0;

	if(reset) begin
		cur_track <= 'b111111;
		busy  <= 0;
		rd <= 0;
		wr <= 0;
		saving<= 0;
	end
	else
	if(busy) begin
		if(old_ack && ~ack) begin
			if(sd_buff_base < 'h1800) begin
				sd_buff_base <= sd_buff_base + 13'd512;
				lba <= lba + 1'd1;
				if(saving) wr <= 1;
					else rd <= 1;
			end
			else
			if(saving && (cur_track != track)) begin
				saving <= 0;
				cur_track <= track;
				sd_buff_base <= 0;
				base_fix <= start_sectors[side][track][0] ? 13'h1F00 : 13'h0000;
				lba <= start_sectors[side][track][10:1];
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
		if(save_track && cur_track != 'b111111) begin
			saving <= 1;
			sd_buff_base <= 0;
			lba <= start_sectors[side][cur_track][9:1];
			wr <= 1;
			busy <= 1;
		end
		else
		if((cur_track != track) || (old_change && ~change)) begin
			saving <= 0;
			cur_track <= track;
			sd_buff_base <= 0;
			base_fix <= start_sectors[side][track][0] ? 13'h1F00 : 13'h0000;
			lba <= start_sectors[side][track][9:1];
			rd <= 1;
			busy <= 1;
		end
	end
end

endmodule

module c1571_trk_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=13)
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

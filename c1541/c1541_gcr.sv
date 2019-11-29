//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
// Commodore 1541 gcr floppy (read/write) by Dar (darfpga@aol.fr) 23-May-2017
// http://darfpga.blogspot.fr
//
// produces GCR data, byte(ready) and sync signal to feed c1541_logic from current
// track buffer ram which contains D64 data
//
// gets GCR data from c1541_logic, while producing byte(ready) signal. Data feed
// track buffer ram after conversion
//
// Input clk 32MHz
//
//-------------------------------------------------------------------------------

module c1541_gcr
(
   input            clk32,

   output     [7:0] dout,		// data from ram to 1541 logic
   input      [7:0] din,		// data from 1541 logic to ram
   input            mode,		// read/write
   input            mtr,		// spindle motor on/off
   output           sync_n,		// reading SYNC bytes
   output reg       byte_n,		// byte ready

   input      [6:0] half_track,
   input      [1:0] speed_zone,

   output    [12:0] byte_addr,
   input      [7:0] ram_do,
   output reg [7:0] ram_di,
   output reg       ram_we,

   input            ram_ready
);

reg bit_clock;
reg [7:0] bit_clk_cnt;
reg [15:0] bit_addr;
//reg [2:0] bit_count;
reg [9:0] read_shift_register;
assign sync_n = ~&{mode, read_shift_register};
assign byte_addr = bit_addr[15:3];
assign dout = read_shift_register[7:0];
//wire whole_byte = bit_count == 3'b111;
// XXX: this is not strictly correct: a track is a bit stream, not a byte stream.
// Fixing this requires changing trk_dpram.
wire whole_byte = sync_n || (bit_addr[2:0] == 3'b111);
//wire [15:0] bit_addr_max = (half_track < {6'd17, 1'd0}) ? 16'd61538: // 30.769 kHz / 5Hz (spindle rotation)
//			   (half_track < {6'd24, 1'd0}) ? 16'd57143: // 28.571 kHz / 5Hz
//			   (half_track < {6'd30, 1'd0}) ? 16'd53333: // 26.666 kHz / 5Hz
//							  16'd50000; // 25.000 kHz / 5Hz
wire [7:0] clk32_speed_zone_ratio[4] = '{
	128 - 1, // speed zone 0: 25.000 kHz (from spec)
	120 - 1, // speed zone 1: 26.666 kHz (from spec)
	112 - 1, // speed zone 2: 28.571 kHz (from spec)
	104 - 1  // speed zone 3: 30.769 kHz (from spec)
};
// XXX: Simulating perfect magnetic resolution: if non-standard speed zone is
// requested, shorter tracks will still be able to fit as many bits as longer
// tracks.
wire [15:0] bit_addr_max[4] = '{
	16'd50000 - 1, // 25.000 kHz / 5Hz
	16'd53333 - 1, // 26.666 kHz / 5Hz
	16'd57143 - 1, // 28.571 kHz / 5Hz
	16'd61538 - 1  // 30.769 kHz / 5Hz
};
always @(posedge clk32) begin
	bit_clock <= 0;
	if (mtr && ram_ready) begin
		if (bit_clk_cnt >= clk32_speed_zone_ratio[speed_zone]) begin
//			bit_clk_cnt <= bit_clk_cnt - clk32_speed_zone_ratio[speed_zone];
			bit_clk_cnt <= 0;
			bit_clock <= 1;
		end else
			bit_clk_cnt <= bit_clk_cnt + 8'b1;
	end
end

always @(posedge clk32) begin
	if (bit_clock) begin
		bit_addr <= bit_addr < bit_addr_max[speed_zone] ? bit_addr + 16'b1 : 16'b0;
		// TODO: check the speed at which data was written and decide how to read it if read speed does not match
		read_shift_register <= {read_shift_register[8:0], ram_do[3'b111 - bit_addr[2:0]]};
//		bit_count <= sync_n ? bit_count + 3'b1 : 3'b0;
		ram_we <= ~mode && whole_byte;
		// XXX: what is UF4 QA ?
		if (whole_byte) begin
			// TODO: save writing speed
			ram_di <= din;
		end
	end else begin
		// XXX: soe is added in _logic
		byte_n <= ~whole_byte;
	end
end

endmodule

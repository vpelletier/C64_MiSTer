//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
// Reworked into a 1571 replica by Vincent Pelletier (2019)
//
// Commodore 1541 to SD card by Dar (darfpga@aol.fr)
// http://darfpga.blogspot.fr
//
// c1541_logic    from : Mark McDougall
// via6522        from : Gideon Zweijtzer  <gideon.zweijtzer@gmail.com>
// c1541_track    from : Sorgelig@MiSTer
//
// c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
//                             : remove iec internal OR wired
//                             : synched atn_in (sometime no IRQ with real c64)
//
// Input clk 32MHz
//
//-------------------------------------------------------------------------------

module c1571_sd
(
	input         clk,

	input         disk_change,
	input         disk_readonly,
	input   [1:0] drive_num,
	output        led,

	input         iec_reset_i,
	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	input         iec_fast_clk_i,
	output        iec_data_o,
	output        iec_clk_o,
	output        iec_fast_clk_o,

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,
	output        sd_busy

);

assign led = act | sd_busy;

// Force reload as disk may have changed
// Track number (0-34)
// Note: this is the head-position, physical cylinder number.
// So side=1 track=0 means DOS track 36, side=1 track=34 means DOS track 70.
// Sector number (0-20)

reg reset;
always @(posedge clk) begin
	reg reset_r;
	reset_r <= iec_reset_i;
	reset <= reset_r;
end

reg readonly = 0;
reg ch_state;
always @(posedge clk) begin
	integer ch_timeout;
	reg     prev_change;

	prev_change <= disk_change;
	if (ch_timeout > 0) begin
		ch_timeout <= ch_timeout - 1;
		ch_state <= 1;
	end else ch_state <= 0;
	if (~prev_change && disk_change) begin
		ch_timeout <= 15000000;
		readonly <= disk_readonly;
	end
end

wire       mode; // read/write
wire [1:0] stp;
wire       mtr;
wire       act;
wire       soe;
wire       side;
wire [1:0] speed_zone;
wire       wps_n = ~readonly ^ ch_state;
wire       tr00_sense_n;

c1571_logic drive_logic
(
	.clk32(clk),
	.reset(reset),

	// serial bus
	.sb_clk_in(iec_clk_i),
	.sb_data_in(iec_data_i),
	.sb_atn_in(iec_atn_i),
	.sb_fast_clk_in(iec_fast_clk_i),
	.sb_clk_out(iec_clk_o),
	.sb_data_out(iec_data_o),
	.sb_fast_clk_out(iec_fast_clk_o),

	// drive-side interface
	.din(gcr_do),
	.dout(gcr_di),
	.mode(mode),
	.stp(stp),
	.mtr(mtr),
	.soe(soe),
	.speed_zone(speed_zone),
	.side(side),
	.sync_n(sync_n),
	.byte_n(byte_n),
	.wps_n(wps_n),
	.tr00_sense_n(tr00_sense_n),

	.ds(drive_num),
	.act(act)
);

wire [7:0] buff_dout;
wire [7:0] buff_din;
wire       buff_we;
wire [7:0] gcr_do;
wire [7:0] gcr_di;
wire       sync_n;
wire       byte_n;
wire [12:0] byte_addr;

c1541_gcr gcr
(
	.clk32(clk),

	.dout(gcr_do),
	.din(gcr_di),
	.mode(mode),
	.mtr(mtr),
	.soe(soe),
	.wps_n(wps_n),
	.sync_n(sync_n),
	.byte_n(byte_n),

	.speed_zone(speed_zone),

	.byte_addr(byte_addr),
	.ram_do(buff_dout),
	.ram_di(buff_din),
	.ram_we(buff_we),

	.ram_ready(~sd_busy)
);

c1541_track track
(
	.sd_clk(clk_sys),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.buff_addr(byte_addr),
	.buff_dout(buff_dout),
	.buff_din(buff_din),
	.buff_we(buff_we),

	.disk_change(disk_change),
	.side(side),
	.stp(stp),
	.mtr(mtr),
	.tr00_sense_n(tr00_sense_n),

	.clk(clk),
	.reset(reset),
	.busy(sd_busy)
);
endmodule

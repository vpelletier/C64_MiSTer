//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
// Reworked into a 1571 replica by Vincent Pelletier (2019)
//
//-------------------------------------------------------------------------------

//
// Model 1571
//
module c1571_logic
(
   // system signals
   input        clk32,
   input        reset,

   // serial bus
   input        sb_clk_in,
   input        sb_data_in,
   input        sb_atn_in,
   input        sb_fast_clk_in,
   output       sb_clk_out,
   output       sb_data_out,
   output       sb_fast_clk_out,

   // floppy-side interface
   input  [7:0] din,            // disk read data
   output [7:0] dout,           // disk write data
   output       mode,           // 1=read, 0=write
   output [1:0] stp,            // stepper motor control
   output       mtr,            // spindle motor on/off
   output       soe,            // serial output enable
   output [1:0] speed_zone,     // bit clock adjustment for track density
   output       side,           // disk side
   input        sync_n,         // reading SYNC bytes
   input        byte_n,         // byte ready
   input        wps_n,          // write-protect sense
   input        tr00_sense_n,   // track 0 sense

   // human-side interface
   input  [1:0] ds,             // device select
   output       act             // activity LED
);

assign sb_data_out = ~(uc9_pb_o[1] | uc9_pb_oe_n[1]) & (uc20_sb_fast_data_out | ~fast_serial_dir_out);
assign sb_clk_out  = ~(uc9_pb_o[3] | uc9_pb_oe_n[3]);
assign sb_fast_clk_out = (uc20_sb_fast_clk_out | ~fast_serial_dir_out);

assign dout = uc4_pa_o | uc4_pa_oe_n;
assign soe  = uc4_ca2_o | uc4_ca2_oe_n;
assign mode = uc4_cb2_o | uc4_cb2_oe_n;

// XXX: U6 input is different, but U4 stp also goes directly to U7 and U22
assign stp        = uc4_pb_o[1:0] | uc4_pb_oe_n[1:0];
assign mtr        = uc4_pb_o[2] | uc4_pb_oe_n[2];
assign act        = uc4_pb_o[3] | uc4_pb_oe_n[3];
assign speed_zone = uc4_pb_o[6:5] | uc4_pb_oe_n[6:5];
assign side       = uc9_pa_o[2] | uc9_pa_oe_n[2];

reg iec_atn;
reg iec_data;
reg iec_clk;
reg iec_fast_clk;
always @(posedge clk32) begin
	reg iec_atn_d1, iec_data_d1, iec_clk_d1, iec_fast_clk_d1;
	reg iec_atn_d2, iec_data_d2, iec_clk_d2, iec_fast_clk_d2;

	iec_atn_d1 <= sb_atn_in;
	iec_atn_d2 <= iec_atn_d1;
	if(iec_atn_d1 == iec_atn_d2) iec_atn <= iec_atn_d2;

	iec_data_d1 <= sb_data_in;
	iec_data_d2 <= iec_data_d1;
	if(iec_data_d1 == iec_data_d2) iec_data <= iec_data_d2;

	iec_clk_d1 <= sb_clk_in;
	iec_clk_d2 <= iec_clk_d1;
	if(iec_clk_d1 == iec_clk_d2) iec_clk <= iec_clk_d2;

	iec_fast_clk_d1 <= sb_fast_clk_in;
	iec_fast_clk_d2 <= iec_fast_clk_d1;
	if(iec_fast_clk_d1 == iec_fast_clk_d2) iec_fast_clk <= iec_fast_clk_d2;
end

reg p2_h_r;
reg p2_h_f;
`ifdef ENABLE_WD1770
reg clk8_r;
`endif
always @(posedge clk32) begin
	reg [4:0] div;
	div <= div + 1'd1;

`ifdef ENABLE_WD1770
	clk8_r <= div[1:0] == 2'b10;
`endif
	// uc18_3q is ACCL signal: 0 for 1MHz clock, 1 for 2MHz clock
	p2_h_r <= uc18_3q ? (div[3:0] == 4'b0000) : (div[4:0] == 5'b00000);
	p2_h_f <= uc18_3q ? (div[3:0] == 4'b1000) : (div[4:0] == 5'b10000);
end

// U5 (64H157) address decoder
// Receives {cpu_a[15:12], cpu_a[10]}.
// cpu_a[11] goes directly to U9 and U4 CS1, so include them here.
// Memory map from "1571 service manual preliminary October 1986 - PN-314002-04",
// except RAM does not stop at 0x7FF as cpu_a[11] is connected to neither U3 nor U5.
wire ram_cs  = cpu_a[15:12] == 4'b0000__; // RAME: U3  $0000-$0FFF (2KB + mirror)
wire uc9_cs  = cpu_a[15:10] == 6'b000110; // IO2 : U9  $1800-$1BFF (16B + mirrors)
wire uc4_cs  = cpu_a[15:10] == 6'b000111; // IO1 : U4  $1C00-$1FFF (16B + mirrors)
// XXX: real hardware OR's this with PHI_1
wire uc11_cs = cpu_a[15:13] == 3'b001___; // CS1 : U11 $2000-$3FFF (4B + mirrors)
wire uc20_cs = cpu_a[15:14] == 2'b01____; // CS2 : U20 $4000-$7FFF (16B + mirrors)
wire rom_cs  = cpu_a[15];

// U1 (6502)
wire  [7:0] cpu_di = (
	!cpu_rw ? cpu_do :
	ram_cs  ? ram_do :
	uc9_cs  ? uc9_do :
	uc4_cs  ? uc4_do :
	uc11_cs ? uc11_do :
	uc20_cs ? uc20_do :
	rom_cs ? rom_do :
        8'hFF
);

wire [15:0] cpu_a;
wire  [7:0] cpu_do;
wire        cpu_rw;
wire        cpu_irq_n = uc4_irq_n & uc9_irq_n & uc20_irq_n;
// so_n comes from U6 _BYTE_RDY
// _BYTE_RDY is:
// - byte_n | ~soe in C1541 mode
// - byte_n        in C1571 mode ?
// Mode is selected using U6 TED input, which is:
//   U18 _4Q | (U4 _CS2 | PHI_1(trailing))
// PHI_1 being ~PHI_2, but only keep the edge, so PHI_2(raising)
//wire        byte_n = |{byte_n, ~uc18_4q, ~uc4_cs, p2_h_r};

T65 cpu
(
	.mode(2'b00),
	.res_n(~reset),
	.enable(p2_h_f),
	.clk(clk32),
	.rdy(1'b1),
	.abort_n(1'b1),
	.irq_n(cpu_irq_n),
	.nmi_n(1'b1),
	.so_n(byte_n),
	.r_w_n(cpu_rw),
	.sync(),
	.ef(),
	.mf(),
	.xf(),
	.ml_n(),
	.vp_n(),
	.vda(),
	.vpa(),
	.a({8'h00,cpu_a}),
	.di(cpu_di),
	.do(cpu_do),
	.debug(),
	.nmi_ack()
);

// U2 (23256)
reg [7:0] rom_do;
(* ram_init_file = "c1571/c1571_rom.mif" *) reg [7:0] rom[32768];
always @(posedge clk32) rom_do <= rom[cpu_a[14:0]];

// U3 (2016)
reg [7:0] ram[2048];
reg [7:0] ram_do;
wire      ram_wr = ram_cs & ~cpu_rw;
always @(posedge clk32) if (ram_wr) ram[cpu_a[10:0]] <= cpu_do;
always @(posedge clk32) ram_do <= ram[cpu_a[10:0]];

// U9 (VIA6522)
wire [7:0] uc9_do;
wire       uc9_irq_n;
wire [7:0] uc9_pa_o;
wire [7:0] uc9_pa_oe_n;
wire [7:0] uc9_pb_o;
wire [7:0] uc9_pb_oe_n;
wire fast_serial_dir_out = uc9_pa_o[1] | uc9_pa_oe_n[1];

c1541_via6522 uc9
(
	.addr(cpu_a[3:0]),
	.data_in(cpu_do),
	.data_out(uc9_do),

	.phi2_ref(),

	.ren(cpu_rw & uc9_cs),
	.wen(~cpu_rw & uc9_cs),

	.irq_l(uc9_irq_n),

	// port a
	.ca1_i(~iec_atn),
	.ca2_i(wps_n),
	.ca2_o(),
	.ca2_t_l(),

	.port_a_i({byte_n, 6'd0, tr00_sense_n}),
	.port_a_o(uc9_pa_o),
	.port_a_t_l(uc9_pa_oe_n),

	// port b
	.cb1_i(1'b0),
	.cb1_o(),
	.cb1_t_l(),
	.cb2_i(1'b0),
	.cb2_o(),
	.cb2_t_l(),

	.port_b_i({~iec_atn, ds, 2'b00, ~(iec_clk & sb_clk_out), 1'b0, ~(iec_data & sb_data_out)}),
	.port_b_o(uc9_pb_o),
	.port_b_t_l(uc9_pb_oe_n),

	.reset(reset),
	.clock(clk32),
	.rising(p2_h_r),
	.falling(p2_h_f)
);

// U4 (VIA6522)
wire [7:0] uc4_do;
wire       uc4_irq_n;
wire       uc4_ca2_o;
wire       uc4_ca2_oe_n;
wire [7:0] uc4_pa_o;
wire       uc4_cb2_o;
wire       uc4_cb2_oe_n;
wire [7:0] uc4_pa_oe_n;
wire [7:0] uc4_pb_o;
wire [7:0] uc4_pb_oe_n;

c1541_via6522 uc4
(
	.addr(cpu_a[3:0]),
	.data_in(cpu_do),
	.data_out(uc4_do),

	.phi2_ref(),

	.ren(cpu_rw & uc4_cs),
	.wen(~cpu_rw & uc4_cs),

	.irq_l(uc4_irq_n),

	// port a
	.ca1_i(byte_n),
	.ca2_i(1'b0),
	.ca2_o(uc4_ca2_o),
	.ca2_t_l(uc4_ca2_oe_n),

	.port_a_i(din),
	.port_a_o(uc4_pa_o),
	.port_a_t_l(uc4_pa_oe_n),

	// port b
	.cb1_i(1'b0),
	.cb1_o(),
	.cb1_t_l(),
	.cb2_i(1'b0),
	.cb2_o(uc4_cb2_o),
	.cb2_t_l(uc4_cb2_oe_n),

	.port_b_i({sync_n, 2'b11, wps_n, 4'b1111}),
	.port_b_o(uc4_pb_o),
	.port_b_t_l(uc4_pb_oe_n),

	.reset(reset),
	.clock(clk32),
	.rising(p2_h_r),
	.falling(p2_h_f)
);

// U6 (64H156): out of scope
// U7 (SIL): out of scope
// U8 (7406): trivial

// U10 (74LS74A): trivial
// U11 (WD1770)
// TODO: implement WD1770-00
`ifdef ENABLE_WD1770
wire [7:0] uc11_do;
// XXX: write not supported in ram mode ?
wd1793 #(0, 0) uc11
(
	.clk_sys(clk32),
	.ce(clk8_r),
	.reset(reset),
	.io_en(uc11_cs),
	.rd(cpu_rw),
	.wr(~cpu_rw),
	.addr(cpu_a[1:0]),
	.din(cpu_do),
	.dout(uc11_do),
	//.drq(),
	//.intrq(),
	//.busy(),

	.wp(wps_n),

	.size_code(3'd1), // TODO
	.layout(0), // TODO
	.side(0),
	.ready(1), // TODO

	.img_mounted(0),
	.img_size(0),
	.sd_ack(0),
	.sd_buff_addr(0),
	.sd_buff_dout(0),
	.sd_buff_wr(0),

	.input_active(), // TODO
	.input_addr(),   // TODO
	.input_data(din),
	.input_wr(0),
	//.buff_addr(),  // TODO ?
	//.buff_read(),  // TODO ?
	.buff_din()      // TODO
);
`else
reg [7:0] uc11_do = 8'hff;
`endif

// U12 (74F32): trivial
// U13 (74LS266): trivial
// U14 (7407): trivial
// U15 (74LS14): trivial
// U16 (7486): trivial
// U17 (74LS14): trivial

// U18 (74LS175) clock transition sequencer
reg uc18_2q;
reg uc18_3q;
reg uc18_4q;
always @(posedge clk32) begin
	if (p2_h_r) begin
	    uc18_2q <= uc9_pa_o[5] | uc9_pa_oe_n[5];
	    uc18_3q <= uc18_2q;
	    uc18_4q <= uc18_3q;
	end
end

// U19 (74LS241): trivial

// U20 (6526)
wire [7:0] uc20_do;
wire       uc20_irq_n;
wire       uc20_sb_fast_clk_out;
wire       uc20_sb_fast_data_out;
mos6526 uc20
(
	.mode(1'b0),
	.clk(clk32),
	.phi2_p(p2_h_r),
	.phi2_n(p2_h_f),
	.res_n(~reset),
	.cs_n(~uc20_cs),
	.rw(cpu_rw),

	.rs(cpu_a[3:0]),
	.db_in(cpu_do),
	.db_out(uc20_do),

	// floating
	.pa_in(8'hff),
	.pa_out(),
	.pb_in(8'hff),
	.pb_out(),

	.flag_n(1'b1),
	.pc_n(),

	.tod(1'b1),

	.sp_in(fast_serial_dir_out | iec_data),
	.sp_out(uc20_sb_fast_data_out),

	.cnt_in(fast_serial_dir_out | iec_fast_clk),
	.cnt_out(uc20_sb_fast_clk_out),

	.irq_n(uc20_irq_n)
);

// U21 (PST 520C/D): analog

// U22 (74LS123)
// TODO ?

endmodule

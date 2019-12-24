//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
//-------------------------------------------------------------------------------

//
// Model 1541B
//
module c1541_logic
(
   input        clk32,
   input        reset,

   // serial bus
   input        sb_clk_in,
   input        sb_data_in,
   input        sb_atn_in,
   output       sb_clk_out,
   output       sb_data_out,

   input        c1541rom_clk,
   input [13:0] c1541rom_addr,
   input [7:0]  c1541rom_data,
   input        c1541rom_wr,
   input        c1541stdrom_wr,
   input        c1541std,

   // drive-side interface
   input [1:0]  ds,			// device select
   input [7:0]  din,			// disk read data
   output [7:0] dout,		// disk write data
   output       mode,		// 1=read, 0=write
   output [1:0] stp,			// stepper motor control
   output       mtr,			// spindle motor on/off
   output       soe,			// serial output enable
   output [1:0] speed_zone,	// bit clock adjustment for track density
   input        sync_n,		// reading SYNC bytes
   input        byte_n,		// byte ready
   input        wps_n,		// write-protect sense
   input        tr00_sense_n,	// track 0 sense (unused?)
   output       act			// activity LED
);

assign sb_data_out = ~uc1_pb_o[1] & ~(uc1_pb_o[4] ^ ~sb_atn_in);
assign sb_clk_out  = ~uc1_pb_o[3];

assign dout = uc3_pa_o;
assign soe  = uc3_ca2_o;
assign mode = uc3_cb2_o;

assign stp        = uc3_pb_o[1:0];
assign mtr        = uc3_pb_o[2];
assign act        = uc3_pb_o[3];
assign speed_zone = uc3_pb_o[6:5];


reg iec_atn;
reg iec_data;
reg iec_clk;
always @(posedge clk32) begin
	reg iec_atn_d1, iec_data_d1, iec_clk_d1;
	reg iec_atn_d2, iec_data_d2, iec_clk_d2;

	iec_atn_d1 <= sb_atn_in;
	iec_atn_d2 <= iec_atn_d1;
	if(iec_atn_d1 == iec_atn_d2) iec_atn <= iec_atn_d2;

	iec_data_d1 <= sb_data_in;
	iec_data_d2 <= iec_data_d1;
	if(iec_data_d1 == iec_data_d2) iec_data <= iec_data_d2;

	iec_clk_d1 <= sb_clk_in;
	iec_clk_d2 <= iec_clk_d1;
	if(iec_clk_d1 == iec_clk_d2) iec_clk <= iec_clk_d2;
end

reg p2_h_r;
reg p2_h_f;
always @(posedge clk32) begin
	reg [4:0] div;
	div <= div + 1'd1;

	p2_h_r <= !div[4] && !div[3:0];
	p2_h_f <=  div[4] && !div[3:0];
end

// The address decoder only sees A15 A12 A11 and A10, which means the
// 0x0000-0x1FFF address map repeats 4 times (A14 & A13).
// Also, it means the smallest chip addressing space is
// 0x400-addresses-long (A9 to A0).
// Above that, cpu_a[15] is set, which selects the ROM.
wire ram_cs =(({cpu_a[15], cpu_a[12]   } == 2'b0__0__) ||
	      ({cpu_a[15], cpu_a[12:11]} == 3'b0__10_));// RAM $0000-$17FF (2KB + mirrors)
wire uc1_cs = ({cpu_a[15], cpu_a[12:10]} == 4'b0__110); // UC1 $1800-$1BFF (16B + mirrors)
wire uc3_cs = ({cpu_a[15], cpu_a[12:10]} == 4'b0__111); // UC3 $1C00-$1FFF (16B + mirrors)

wire  [7:0] cpu_di = (
	!cpu_rw ? cpu_do :
	ram_cs ? ram_do :
	uc1_cs ? uc1_do :
	uc3_cs ? uc3_do :
	(c1541std ? romstd_do : rom_do)
);

wire [15:0] cpu_a;
wire  [7:0] cpu_do;
wire        cpu_rw;
wire        cpu_irq_n = ~(uc1_irq | uc3_irq);

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

reg [7:0] rom_do;
(* ram_init_file = "c1541/c1541_rom.mif" *) reg [7:0] rom[16384];
always @(posedge c1541rom_clk) if (c1541rom_wr) rom[c1541rom_addr] <= c1541rom_data;
always @(posedge clk32) rom_do <= rom[cpu_a[13:0]];

reg [7:0] romstd_do;
(* ram_init_file = "c1541/c1541_rom.mif" *) reg [7:0] romstd[16384];
always @(posedge c1541rom_clk) if (c1541stdrom_wr) romstd[c1541rom_addr] <= c1541rom_data;
always @(posedge clk32) romstd_do <= romstd[cpu_a[13:0]];

reg [7:0] ram[2048];
reg [7:0] ram_do;
wire      ram_wr = ram_cs & ~cpu_rw;
always @(posedge clk32) if (ram_wr) ram[cpu_a[10:0]] <= cpu_do;
always @(posedge clk32) ram_do <= ram[cpu_a[10:0]];


// UC1 (VIA6522) signals
wire [7:0] uc1_do;
wire       uc1_irq;
wire [7:0] uc1_pb_o;

via6522 uc1
(
	.data_out(uc1_do),
	.data_in(cpu_do),
	.addr(cpu_a[3:0]),
	.strobe(uc1_cs),
	.we(~cpu_rw),
	.irq(uc1_irq),

	.porta_in({7'h7f, tr00_sense_n}),
	.porta_out(),
	.portb_in({~iec_atn, ds, 2'b11, ~(iec_clk & sb_clk_out), 1'b1, ~(iec_data & sb_data_out)}),
	.portb_out(uc1_pb_o),

	.ca1_in(~iec_atn),
	.ca2_out(),
	.ca2_in(1'b1),
	.cb1_out(),
	.cb1_in(1'b1),
	.cb2_out(),
	.cb2_in(1'b1),

	.ce(p2_h_r), // ???
	.clk(clk32),
	.reset(reset)
);


// UC3 (VIA6522) signals
wire [7:0] uc3_do;
wire       uc3_irq;
wire       uc3_ca2_o;
wire [7:0] uc3_pa_o;
wire       uc3_cb2_o;
wire [7:0] uc3_pb_o;

via6522 uc3
(
	.data_out(uc3_do),
	.data_in(cpu_do),
	.addr(cpu_a[3:0]),
	.strobe(uc3_cs),
	.we(~cpu_rw),
	.irq(uc3_irq),

	.porta_in(din),
	.porta_out(uc3_pa_o),
	.portb_in({sync_n, 2'b11, wps_n, 4'b1111}),
	.portb_out(uc3_pb_o),

	.ca1_in(byte_n),
	.ca2_out(uc3_ca2_o),
	.ca2_in(1'b1),
	.cb1_out(),
	.cb1_in(1'b1),
	.cb2_out(uc3_cb2_o),
	.cb2_in(1'b1),

	.ce(p2_h_r), // ???
	.clk(clk32),
	.reset(reset)
);

endmodule

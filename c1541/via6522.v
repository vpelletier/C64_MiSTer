`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
//
// Engineer:	Thomas Skibo
//
// Create Date:	Sep 24, 2011
//
// Module Name: via6522
//
// Description:
//
//	A simple implementation of the 6522 Versatile Interface Adapter (VIA).
//	Tri-state lines aren't used.  Instead,  All PIA I/O signals have
//	seperate "in" and "out" signals.  Wire or ignore appropriately.
//
//	A seperate "slow clock" (a synchronous pulse) runs the timers.
//	Typically, it's 1Mhz.
//
/////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2011, Thomas Skibo.  All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// * Redistributions of source code must retain the above copyright
//   notice, this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
// * The names of contributors may not be used to endorse or promote products
//   derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL Thomas Skibo OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//
//////////////////////////////////////////////////////////////////////////////

module via6522
(
	output reg [7:0] data_out,	// cpu interface
	input      [7:0] data_in,
	input      [3:0] addr,
	input            strobe,
	input            we,

	output           irq,

	output     [7:0] porta_out,
	input      [7:0] porta_in,
	output     [7:0] portb_out,
	input      [7:0] portb_in,

	input            ca1_in,
	output reg       ca2_out,
	input            ca2_in,
	output reg       cb1_out,
	input            cb1_in,
	output reg       cb2_out,
	input            cb2_in,

	input            phi2_rising,
	input            phi2_falling,
	input            clk,
	output reg       phi2,
	input            reset
);

// Register address offsets
parameter [3:0]
	ADDR_PORTB     = 4'h0,
	ADDR_PORTA     = 4'h1,
	ADDR_DDRB      = 4'h2,
	ADDR_DDRA      = 4'h3,
	ADDR_TIMER1_LO = 4'h4,
	ADDR_TIMER1_HI = 4'h5,
	ADDR_TIMER1_LATCH_LO = 4'h6,
	ADDR_TIMER1_LATCH_HI = 4'h7,
	ADDR_TIMER2_LO = 4'h8,
	ADDR_TIMER2_HI = 4'h9,
	ADDR_SR        = 4'ha,
	ADDR_ACR       = 4'hb,
	ADDR_PCR       = 4'hc,
	ADDR_IFR       = 4'hd,
	ADDR_IER       = 4'he,
	ADDR_PORTA_NH  = 4'hf;

wire	wr_strobe = strobe && we;
wire	rd_strobe = strobe && !we;

///////////////////////////////////////////////////
// PHI2 - Mostly because it helps reading test bench result
always @(posedge clk) begin
	if (phi2_rising) phi2 <= 1'b1;
	else if (phi2_falling) phi2 <= 1'b0;
end

///////////////////////////////////////////////////
// IER - Interrupt Enable Register
reg [6:0] 	ier;

always @(posedge clk) begin
	if (reset) ier <= 7'd0;
	else if (wr_strobe && addr == ADDR_IER && phi2_falling) ier <= data_in[7] ? (ier | data_in[6:0]) : (ier & ~data_in[6:0]);
end

////////////////////////////////////////////////////
// PCR - Peripheral Control Register
reg [7:0] 	pcr;

always @(posedge clk) begin
	if (reset) pcr <= 8'h00;
	else if (wr_strobe && addr == ADDR_PCR && phi2_falling) pcr <= data_in;
end

//////////////////////////////////////////////////////
// ACR - Auxiliary Control Register
reg [7:0] 	acr;

always @(posedge clk) begin
	if (reset) acr <= 8'h00;
	else if (wr_strobe && addr == ADDR_ACR && phi2_falling) acr <= data_in;
end

/////////////////////////////////////////////////////
// PORTs and DDRs
reg [7:0] 	ddra;
reg [7:0] 	ddrb;
reg [7:0] 	ora;
reg [7:0] 	orb;

// Implement PORTA (out) and PORTB (out) pins
assign porta_out = ora | ~ddra;
assign portb_out = (orb | ~ddrb) ^ {acr[7] & pb7_invert, 7'b0};

// Implement PORTA (out)
always @(posedge clk) begin
	if (reset) ora <= 8'h00;
	else if (wr_strobe && (addr == ADDR_PORTA || addr == ADDR_PORTA_NH) && phi2_falling) ora <= data_in;
end

// Implement DDRA
always @(posedge clk) begin
	if (reset) ddra <= 8'h00;
	else if (wr_strobe && addr == ADDR_DDRA && phi2_falling) ddra <= data_in;
end

// Implement PORTB (out).
always @(posedge clk) begin
	if (reset) orb <= 8'h00;
	else if (wr_strobe && addr == ADDR_PORTB && phi2_falling) orb <= data_in;
end

// Implement DDRB
always @(posedge clk) begin
	if (reset) ddrb <= 8'h00;
	else if (wr_strobe && addr == ADDR_DDRB && phi2_falling) ddrb <= data_in;
end

////////////////////////////////////////////////////////
// CA interrupt logic
reg irq_ca1;
reg irq_ca2;

// CA1 and CA2 transition logic.
reg ca1_in_1;
reg ca2_in_1;
always @(posedge clk) begin
	ca1_in_1 <= ca1_in;
	ca2_in_1 <= ca2_in;
end

// detect "active" transitions.
wire	ca1_act_trans = ((ca1_in && !ca1_in_1 && pcr[0]) ||
                        (!ca1_in && ca1_in_1 && !pcr[0]));
wire 	ca2_act_trans = ((ca2_in && !ca2_in_1 && pcr[2]) ||
                        (!ca2_in && ca2_in_1 && !pcr[2])) && !pcr[3];

// logic for clearing CA1 and CA2 interrupt bits.
wire 	irq_ca1_clr = ((strobe && addr == ADDR_PORTA) ||
                    (wr_strobe && addr == ADDR_IFR && data_in[1])) && phi2_falling;
wire 	irq_ca2_clr = ((strobe && addr == ADDR_PORTA && (pcr[3] || !pcr[1])) ||
                    (wr_strobe && addr == ADDR_IFR && data_in[0])) && phi2_falling;

always @(posedge clk) begin
	if (reset || (irq_ca1_clr && !ca1_act_trans)) irq_ca1 <= 1'b0;
	else if (ca1_act_trans) irq_ca1 <= 1'b1;
end

always @(posedge clk) begin
	if (reset || (irq_ca2_clr && !ca2_act_trans)) irq_ca2 <= 1'b0;
	else if (ca2_act_trans) irq_ca2 <= 1'b1;
end


////////////////////////////////////////////////////////
// CB interrupt logic
reg irq_cb1;
reg irq_cb2;

// CB1 and CB2 transition logic
reg cb1_in_1;
reg cb2_in_1;
always @(posedge clk) begin
	cb1_in_1 <= cb1_in;
	cb2_in_1 <= cb2_in;
end

// detect "active" transitions.
wire cb1_act_trans = ((cb1_in && !cb1_in_1 && pcr[4]) ||
                     (!cb1_in && cb1_in_1 && !pcr[4]));
wire cb2_act_trans = ((cb2_in && !cb2_in_1 && pcr[6]) ||
                     (!cb2_in && cb2_in_1 && !pcr[6])) && !pcr[7];

// logic for clearing CB1 and CB2 interrupt bits.
wire irq_cb1_clr = ((strobe && addr == ADDR_PORTB) ||
                 (wr_strobe && addr == ADDR_IFR && data_in[4])) && phi2_falling;
wire irq_cb2_clr = ((strobe && addr == ADDR_PORTB && (pcr[7] || !pcr[5])) ||
                 (wr_strobe && addr == ADDR_IFR && data_in[3])) && phi2_falling;

always @(posedge clk) begin
	if (reset || (irq_cb1_clr && !cb1_act_trans)) irq_cb1 <= 1'b0;
	else if (cb1_act_trans) irq_cb1 <= 1'b1;
end

always @(posedge clk) begin
	if (reset || (irq_cb2_clr && !cb2_act_trans)) irq_cb2 <= 1'b0;
	else if (cb2_act_trans) irq_cb2 <= 1'b1;
end

///////////////////////////////////////////////////
// CA2/CB2 output modes
wire porta_rd_strobe = rd_strobe && addr == ADDR_PORTA;

// CA2 write handshake is delayed by half a cycle
reg  porta_wr_strobe_r;
always @(posedge clk) begin
	if (phi2_falling) porta_wr_strobe_r <= wr_strobe && addr == ADDR_PORTA;
end

always @(posedge clk) begin
	case ({reset, pcr[3:1]})
		4'b0100: begin
			if ((porta_rd_strobe || porta_wr_strobe_r) && phi2_rising) ca2_out <= 1'b0;
			else if (ca1_act_trans) ca2_out <= 1'b1;
		end
		4'b0101: begin
			if ((porta_rd_strobe || porta_wr_strobe_r) && phi2_rising) ca2_out <= 1'b0;
			else if (phi2_rising) ca2_out <= 1'b1;
		end
		4'b0110: ca2_out <= 1'b0;
		default: ca2_out <= 1'b1;
	endcase
end

// CB2 write handshake is delayed by half a cycle
reg  portb_wr_strobe_r;
always @(posedge clk) begin
	if (phi2_falling) portb_wr_strobe_r <= wr_strobe && addr == ADDR_PORTB;
end

wire cb2_sr_out;
always @(posedge clk) begin
	if (acr[4]) cb2_out <= cb2_sr_out;
	else begin
		case ({reset, pcr[7:5]})
			4'b0100: begin
				if (portb_wr_strobe_r && phi2_rising) cb2_out <= 1'b0;
				else if (cb1_act_trans) cb2_out <= 1'b1;
			end
			4'b0101: begin
				if (portb_wr_strobe_r && phi2_rising) cb2_out <= 1'b0;
				else if (phi2_rising) cb2_out <= 1'b1;
			end
			4'b0110:  cb2_out <= 1'b0;
			default: cb2_out <= 1'b1;
		endcase
	end
end

//////////////////////////////////////////////////////////
// Implement PORTA (in) latch
reg [7:0] porta_in_r;
always @(posedge clk) begin
	if (!acr[0] || ca1_act_trans) porta_in_r <= porta_in;
end

// Implement PORTB (in) latch
reg [7:0] portb_in_r;
always @(posedge clk) begin
	if (!acr[1] || cb1_act_trans) portb_in_r <= portb_in;
end

// Detect negative pulses on PORTB.6
reg portb6_1;
reg portb6_2;
wire portb6_negedge = portb6_2 && !portb6_1;
always @(posedge clk) begin
	if (phi2_rising) begin
		portb6_1 <= portb_in[6];
		portb6_2 <= portb6_1;
	end
end

///////////////////////////////////////////////////
// Timers
reg [15:0] timer1 = 16'h0105;
reg        timer1_decremented_from_zero = 1'b0;
reg        timer1_may_interrupt = 1'b0;
reg [7:0]  timer1_latch_lo = 8'h05; // from VICE's testsuite...
reg [7:0]  timer1_latch_hi = 8'h01; // ..."default" program

reg [15:0] timer2 = 16'h0000;
reg        timer2_decremented_from_zero = 1'b0;
reg        timer2_may_interrupt = 1'b0;
reg [7:0]  timer2_latch_lo;

reg        irq_t1;
reg        irq_t2;

// TIMER1
always @(posedge clk) begin
	if (wr_strobe && addr == ADDR_TIMER1_HI && phi2_falling) begin
		timer1 <= {data_in, timer1_latch_lo};
		timer1_may_interrupt <= 1'b1;
		timer1_decremented_from_zero <= 1'b0;
	end else if (timer1_decremented_from_zero && phi2_falling) begin
		timer1 <= {timer1_latch_hi, timer1_latch_lo};
		timer1_may_interrupt <= timer1_may_interrupt && acr[6];
		timer1_decremented_from_zero <= 1'b0;
	end else if (phi2_falling) begin
		timer1 <= timer1 - 1'b1;
		timer1_decremented_from_zero <= timer1 == 16'h0000;
	end
end

// T1 latch lo
always @(posedge clk) begin
	if (wr_strobe && (addr == ADDR_TIMER1_LO || addr == ADDR_TIMER1_LATCH_LO) && phi2_falling) timer1_latch_lo <= data_in;
end

// T1 latch hi
always @(posedge clk) begin
	if (wr_strobe && (addr == ADDR_TIMER1_HI || addr == ADDR_TIMER1_LATCH_HI) && phi2_falling) timer1_latch_hi <= data_in;
end

// T1 interrupt set and clear logic
wire irq_t1_set = (timer1_decremented_from_zero && timer1_may_interrupt && phi2_rising);
wire irq_t1_clr = ((wr_strobe && addr == ADDR_TIMER1_HI) ||
                   (rd_strobe && addr == ADDR_TIMER1_LO) ||
                   (wr_strobe && addr == ADDR_TIMER1_LATCH_HI) ||
                   (rd_strobe && addr == ADDR_TIMER1_LATCH_LO) ||
                   (wr_strobe && addr == ADDR_IFR && data_in[6])) && phi2_falling;

// T1 IRQ
always @(posedge clk) begin
	if (reset || irq_t1_clr) irq_t1 <= 1'b0;
	else if (irq_t1_set) irq_t1 <= 1'b1;
end

// T1 overflow inverts PB7 polarity
reg 	pb7_invert = 1'b0;
always @(posedge clk) begin
	if (reset) pb7_invert <= 1'b0;
	else if (wr_strobe && addr == ADDR_TIMER1_HI && phi2_falling) pb7_invert <= 1'b1;
	else if (irq_t1_set) pb7_invert <= !pb7_invert;
end

// TIMER2
always @(posedge clk) begin
	if (wr_strobe && addr == ADDR_TIMER2_HI && phi2_falling) begin
		timer2 <= {data_in, timer2_latch_lo};
		timer2_may_interrupt <= 1'b1;
		timer2_decremented_from_zero <= 1'b0;
	end else if ((!acr[5] || portb6_negedge) && phi2_falling) begin
		timer2 <= timer2 - 1'b1;
		timer2_may_interrupt <= timer2_may_interrupt && !timer2_decremented_from_zero;
		timer2_decremented_from_zero <= timer2 == 16'h0000;
	end
end

// T2 latch lo (i.e. writes to T2L)
always @(posedge clk) begin
	if (reset) timer2_latch_lo <= 8'hff;
	else if (wr_strobe && addr == ADDR_TIMER2_LO && phi2_falling) timer2_latch_lo <= data_in;
end

// T2 IRQ set and clear logic
wire irq_t2_set = (timer2_decremented_from_zero && timer2_may_interrupt && phi2_rising);
wire irq_t2_clr = ((wr_strobe && addr == ADDR_TIMER2_HI) ||
                   (rd_strobe && addr == ADDR_TIMER2_LO) ||
                   (wr_strobe && addr == ADDR_IFR && data_in[5])) && phi2_falling;

// T2 IRQ
always @(posedge clk) begin
	if (reset || irq_t2_clr) irq_t2 <= 1'b0;
	else if (irq_t2_set) irq_t2 <= 1'b1;
end


////////////////////////////////////////////////////////
// SR - shift register
reg [7:0] sr = 8'h00;
reg [2:0] sr_cntr;
reg [7:0] sr_clk_div_ctr;
reg       sr_clk_div;
reg       irq_sr;
reg       sr_go;
reg       do_shift;

// Update serial register
always @(posedge clk) begin
	if (wr_strobe && addr == ADDR_SR && phi2_falling) sr <= data_in;
	else if (do_shift) sr <= { sr[6:0], (acr[4] ? sr[7] : cb2_in) };
end

assign cb2_sr_out = sr[7];

always @(posedge clk) begin
	if (reset) sr_clk_div_ctr <= 8'd0;
	else if (phi2_falling && sr_clk_div_ctr == 8'd0) sr_clk_div_ctr <= timer2_latch_lo;
	else if (phi2_falling) sr_clk_div_ctr <= sr_clk_div_ctr - 1'b1;
end

always @(posedge clk) begin
	if (reset) sr_clk_div <= 1'b0;
	else sr_clk_div <= (phi2_falling && sr_clk_div_ctr == 8'd0);
end

always @(posedge clk) begin
	if (reset || (strobe && addr == ADDR_SR && phi2_falling)) sr_cntr <= 3'd7;
	else if (do_shift) sr_cntr <= sr_cntr - 1'b1;
end

// SR IRQ set and clr logic
wire irq_sr_set = do_shift && sr_cntr == 3'b000;
wire irq_sr_clr = ((strobe && addr == ADDR_SR) || (wr_strobe && addr == ADDR_IFR && data_in[2])) && phi2_falling;

// SR IRQ
always @(posedge clk) begin
	if (reset || (irq_sr_clr && !irq_sr_set)) irq_sr <= 1'b0;
	else if (irq_sr_set) irq_sr <= 1'b1;
end

always @(posedge clk) begin
	if (reset) sr_go <= 1'b0;
	else if (strobe && addr == ADDR_SR && phi2_falling) sr_go <= 1'b1;
	else if (irq_sr_set) sr_go <= 1'b0;
end

// cominatorial logic for do_shift signal.
always @(sr_clk_div or phi2_falling or cb1_act_trans or sr_go or acr) begin
	case (acr[4:2])
		3'b000: do_shift <= 1'b0;
		3'b100: do_shift <= sr_clk_div;
		3'b001,
		3'b101: do_shift <= (sr_go && sr_clk_div);
		3'b010,
		3'b110: do_shift <= (sr_go && phi2_falling);
		3'b011,
		3'b111: do_shift <= cb1_act_trans;
	endcase
end

always @(posedge clk) begin
	if (reset) cb1_out <= 1'b1;
	else if (do_shift) cb1_out <= !cb1_out;
end

////////////////////////////////////////////////////////
// IRQ and enable logic.
//

// IFR register (not including bit 7)
wire [6:0] ifr = { irq_t1, irq_t2, irq_cb1, irq_cb2, irq_sr, irq_ca1, irq_ca2 };

// IRQ output
assign irq = ~reset && |(ifr & ier);

///////////////////////////////////////////////////
// Read data mux
wire [7:0] porta = porta_out & porta_in_r;
wire [7:0] portb = ((orb & ddrb) | (portb_in_r & ~ddrb)) ^ {acr[7] & pb7_invert, 7'b0};

always @(posedge clk) begin
	case (addr)
		ADDR_PORTB:           data_out <= portb;
		ADDR_PORTA:           data_out <= porta;
		ADDR_DDRB:            data_out <= ddrb;
		ADDR_DDRA:            data_out <= ddra;
		ADDR_TIMER1_LO:       data_out <= timer1[7:0];
		ADDR_TIMER1_HI:       data_out <= timer1[15:8];
		ADDR_TIMER1_LATCH_LO: data_out <= timer1_latch_lo;
		ADDR_TIMER1_LATCH_HI: data_out <= timer1_latch_hi;
		ADDR_TIMER2_LO:       data_out <= timer2[7:0];
		ADDR_TIMER2_HI:       data_out <= timer2[15:8];
		ADDR_SR:              data_out <= sr;
		ADDR_ACR:             data_out <= acr;
		ADDR_PCR:             data_out <= pcr;
		ADDR_IFR:             data_out <= {irq, ifr};
		ADDR_IER:             data_out <= {1'b1, ier};
		ADDR_PORTA_NH:        data_out <= porta;
		default:              data_out <= 8'hXX;
	endcase
end

endmodule // via6522

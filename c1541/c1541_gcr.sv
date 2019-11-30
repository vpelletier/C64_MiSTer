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

module sn74ls193 (
    input            clk,

    input            up,
    input            down,
    input      [3:0] data_in,
    input            clr,
    input            load_n,

    output reg       carry_n,
    output reg       borrow_n,
    output reg [3:0] data_out
);
always @(posedge clk) begin
    reg up1, down1;
    up1 <= up;
    down1 <= down;
    borrow_n <= |{down, data_out};
    carry_n <= ~&{data_out, ~up};
    if (clr) data_out <= 4'b0;
    else if (~load_n) data_out <= data_in;
    else if (up1 && ~up) data_out <= data_out + 4'b1;
    else if (down1 && ~down) data_out <= data_out - 4'b1;
    // else, no change
end
endmodule

module c1541_gcr
(
    input               clk32,

    output        [7:0] dout,           // data from ram to 1541 logic
    input         [7:0] din,            // data from 1541 logic to ram
    input               mode,           // read/write
    input               mtr,            // spindle motor on/off
    input               soe,            // serial output enable
    input               wps_n,          // write-protect
    output              sync_n,         // reading SYNC bytes
    output reg          byte_n,         // byte ready

//    input         [6:0] half_track,
    input         [1:0] speed_zone,

    output reg   [12:0] byte_addr,
    input         [7:0] ram_do,
    output reg    [7:0] ram_di,
    output reg          ram_we,
    input               ram_ready
);

reg clk16; // c1541 internal crystal
always @(posedge clk32) clk16 <= clk16 + 1'b1;

wire raw_bit_clock;
sn74ls193 raw_bit_clock_ic(
    .clk(clk32),
    .up(clk16),
    .down(1'b1),
    .data_in({2'b0, speed_zone}),
    .clr(1'b0),
    .load_n(raw_bit_clock & ram_ready & mtr),

    .carry_n(raw_bit_clock),
    .borrow_n(), // (n/c)
    .data_out()  // (n/c)
);

// state counter:
// state[0] clocks parallel input on byte boundary and high state[1]
// state[1] clocks bit counter, bit shifters, and when low clocks byte ready
//          and (in real hardware) is mixed with serial output
// ~|state[3:2] is the serial bit input, which we do not need as we control bit address
wire [1:0] state;
sn74ls193 state_counter_ic(
    .clk(clk32),
    .up(~raw_bit_clock),
    .down(1'b1),
    .data_in(4'b0),
    .clr(~(ram_ready & mtr)),
    .load_n(1'b1),

    .carry_n(), // (n/c)
    .borrow_n(), // (n/c)
    .data_out({2'bx, state})
);

reg parallel_to_serial_load_edge;
reg bit_clock_posedge;
reg bit_clock_negedge;
always @(posedge clk32) begin
    reg parallel_to_serial_load1;
    reg bit_clock1;
    bit_clock1 <= state[1];
    bit_clock_negedge <= bit_clock1 && !state[1];
    bit_clock_posedge <= !bit_clock1 && state[1];
    parallel_to_serial_load1 <= parallel_to_serial_load;
    parallel_to_serial_load_edge <= !parallel_to_serial_load1 && parallel_to_serial_load;
end

reg [2:0] bit_count;
wire whole_byte = &bit_count;
wire parallel_to_serial_load = &{whole_byte, state[1], state[0]};
reg [9:0] read_shift_register;
assign sync_n = ~&{mode, read_shift_register};

assign dout = read_shift_register[7:0];
// XXX: Simulating perfect magnetic resolution: if non-standard speed zone is
// requested, shorter tracks will still be able to fit as many bits as longer
// tracks.
wire [15:0] bit_addr_max[4] = '{
    16'd50000 - 1, // 25.000 kHz / 5Hz (spindle rotation)
    16'd53336 - 1, // 26.666 kHz / 5Hz, rounded to nearest whole byte (+3 bits)
    16'd57144 - 1, // 28.571 kHz / 5Hz, rounded to nearest whole byte (+1 bit)
    16'd61536 - 1  // 30.769 kHz / 5Hz, rounded to nearest whole byte (-2 bits)
};

reg [15:0] bit_addr;
assign byte_addr = bit_addr[15:3];
always @(posedge clk32) begin
    if (bit_clock_posedge) begin
        bit_count <= sync_n ? bit_count + 3'b1 : 3'b0;
        // TODO: check the speed at which data was written and decide how to read it if read speed does not match
        read_shift_register <= {read_shift_register[8:0], ram_do[3'b111 - bit_addr[2:0]]};
        ram_we <= (~mode && wps_n);
    end
    if (bit_clock_negedge) begin
        bit_addr <= (
            bit_addr < bit_addr_max[speed_zone] ?
            bit_addr + 16'b1 :
            16'b0
        );
        byte_n <= ~&{whole_byte, soe};
    end
    if (parallel_to_serial_load_edge) begin
        // TODO: save writing speed
        ram_di <= din;
    end
end

endmodule

/*
for REF in .../testprogs/drive/viavarious/via*ref.bin; do \
    dd if="$REF" bs=1 skip=2 | hexdump -ve '16/1 "%02x " "\n"' > "$(basename "$REF").hex"; \
done
iverilog -o via6522_tb -l../via6522.v via6522_tb.v && vvp -n via6522_tb
*/

`timescale 10 ns / 1 ns
module via6522_tb;
integer failed;
integer failed_step;
integer x;
integer y;
reg [32:0] test_name;
reg [7:0] reference_data[0:256 * 32 - 1];
reg [7:0] test_index;

reg [7:0] cpu_in;
always @(posedge clk) begin
    if (phi2_falling) cpu_in <= data_out;
end

wire [7:0] data_out;
reg  [7:0] data_in      = 8'hxx;
reg  [3:0] addr         = 4'hx;
reg        strobe       = 1'b0;
reg        we           = 1'bx;
wire       irq;
wire [7:0] porta_out;
reg  [7:0] porta_in     = 8'hff;
wire [7:0] portb_out;
reg  [7:0] portb_in     = 8'hff;
reg        ca1_in       = 1'b1;
wire       ca2_out;
reg        ca2_in       = 1'b1;
wire       cb1_out;
reg        cb1_in       = 1'b1;
wire       cb2_out;
reg        cb2_in       = 1'b1;
reg        phi2_rising  = 1'b0;
reg        phi2_falling = 1'b0;
reg        clk          = 1'b0;
reg        reset        = 1'b0;
via6522 via6522 (
    .data_out(data_out),
    .data_in(data_in),
    .addr(addr),
    .strobe(strobe),
    .we(we),

    .irq(irq),

    .porta_out(porta_out),
    .porta_in(porta_in),
    .portb_out(portb_out),
    .portb_in(portb_in),

    .ca1_in(ca1_in),
    .ca2_out(ca2_out),
    .ca2_in(ca2_in),
    .cb1_out(cb1_out),
    .cb1_in(cb1_in),
    .cb2_out(cb2_out),
    .cb2_in(cb2_in),

    .phi2_rising(phi2_rising),
    .phi2_falling(phi2_falling),
    .phi2(),
    .clk(clk),
    .reset(reset)
);

initial begin
    $dumpfile("via6522_tb.vcd");
    $dumpvars(0, via6522);
    $dumpvars(1, cpu_in);

    `define assertEqual(VALUE_A, VALUE_B)       \
        if (VALUE_A !== VALUE_B) begin          \
            $display(                           \
                "%9d %s:%0d: %s !== %s, %02x",  \
                $time,                          \
                `__FILE__,                      \
                `__LINE__,                      \
                `"VALUE_A`",                    \
                `"VALUE_B`",                    \
                VALUE_A                         \
            );                                  \
        end

    `define assertRegisterEqual(ADDR, VALUE_B)  \
        `read(ADDR);                            \
        `assertEqual(cpu_in, VALUE_B);

    `define clktic  \
        #1 clk = 1; \
        #1 clk = 0;


    `define phi2_rise       \
        phi2_rising = 1;    \
        `clktic;            \
        phi2_rising = 0;    \
        `clktic;

    `define phi2_fall       \
        phi2_falling = 1;   \
        `clktic;            \
        phi2_falling = 0;   \
        `clktic;

    `define phi2_tic(COUNT)             \
        for (y=0; y<COUNT; y=y+1) begin \
            `phi2_rise;                 \
            `phi2_fall;                 \
        end

    `define write(ADDR, VAL)    \
        addr = ADDR;            \
        we = 1'b1;              \
        strobe = 1'b1;          \
        `phi2_rise;             \
        data_in = VAL;          \
        `phi2_fall;             \
        data_in = 8'hxx;        \
        strobe = 1'b0;          \
        we = 1'bx;

    `define read(ADDR)  \
        addr = ADDR;    \
        we = 1'b0;      \
        strobe = 1'b1;  \
        `phi2_tic(1);   \
        strobe = 1'b0;  \
        we = 1'bx;

    // sta, absolute: 4 cycles.
    `define sta(ADDR, VAL)  \
        `phi2_tic(3);       \
        `write(ADDR, VAL);

    // lda, absolute: 4 cycles.
    `define lda(ADDR)       \
        `phi2_tic(3);       \
        `read(ADDR);

    `define setdefaults                         \
        `sta(`ADDR_ACR, 8'b00100000);           \
        `sta(`ADDR_PCR, 8'h00);                 \
        `sta(`ADDR_SR,  8'ha5);                 \
        `sta(`ADDR_IER, 8'h7f);                 \
        `lda(`ADDR_IFR);                        \
        `sta(`ADDR_IFR, cpu_in);                \
        /* from this point, be cycle exact*/    \
        for (x=0; x<2/*56*/; x=x+1) begin           \
            `sta(`ADDR_TIMER1_LO, 8'h00);       \
            `sta(`ADDR_TIMER1_HI, 8'h00);       \
            `sta(`ADDR_TIMER1_LATCH_LO, 8'h00); \
            `sta(`ADDR_TIMER1_LATCH_HI, 8'h00); \
            `sta(`ADDR_TIMER2_LO, 8'h00);       \
            `sta(`ADDR_TIMER2_HI, 8'h00);       \
            `phi2_tic(5); /* dey + bne */       \
        end                                     \
        `phi2_tic(12); /* rts + jsr snd_init */ \
        `phi2_tic(2); /* lda */                 \
        `sta(`ADDR_DDRB, 8'b01111010);          \
        `phi2_tic(2); /* lda */                 \
        `sta(`ADDR_PORTB, 8'b00000000);         \
        `phi2_tic(12); /* rts + jsr ddotest */

    `define test(TEST_NAME)                                             \
        test_name = TEST_NAME;                                          \
        $readmemh({"via", TEST_NAME, "ref.bin.hex"}, reference_data);   \
        failed_step = 0;

    `define end_test        \
        if (failed_step)    \
            $finish;

    `define init_step(STEP_NAME)        \
        test_index = STEP_NAME - "A";   \
        failed = 0;                     \
        `setdefaults;

    `define do_step                     \
        `phi2_tic(2); /* ldx */         \
        for (x=0; x<256; x=x+1) begin

    `define checkCPUIn                                                      \
            if (cpu_in !== reference_data[test_index * 256 + x]) begin      \
                `ifdef VERBOSE                                              \
                $display(                                                   \
                    "%9d %s.%c: %c[31mERROR%c[0m at %3d got %02x, expected %02x, difference %3d, xor %02x", \
                    $time,                                                  \
                    test_name,                                              \
                    "A" + test_index,                                       \
                    8'h1b,                                                  \
                    8'h1b,                                                  \
                    x,                                                      \
                    cpu_in,                                                 \
                    reference_data[test_index * 256 + x],                   \
                    cpu_in - reference_data[test_index * 256 + x],          \
                    cpu_in ^ reference_data[test_index * 256 + x]           \
                );                                                          \
                `endif                                                      \
                failed = failed + 1;                                        \
            end else if (failed) begin                                      \
                `ifdef VERBOSE                                              \
                $display(                                                   \
                    "%9d %s.%c: %c[32mOK%c[0m    at %3d got %02x",          \
                    $time,                                                  \
                    test_name,                                              \
                    "A" + test_index,                                       \
                    8'h1b,                                                  \
                    8'h1b,                                                  \
                    x,                                                      \
                    cpu_in                                                  \
                );                                                          \
                `endif                                                      \
            end                                                             \
            `phi2_tic(5);

    `define end_step                                \
            `phi2_tic(5);                           \
        end                                         \
        if (failed) begin                           \
            failed_step = failed_step + 1;          \
            $display(                               \
                "%9d %s.%c: FAILED (%3d errors)",   \
                $time,                              \
                test_name,                          \
                "A" + test_index,                   \
                failed                              \
            );                                      \
        end

    `define ADDR_PORTB              4'h0
    `define ADDR_PORTA              4'h1
    `define ADDR_DDRB               4'h2
    `define ADDR_DDRA               4'h3
    `define ADDR_TIMER1_LO          4'h4
    `define ADDR_TIMER1_HI          4'h5
    `define ADDR_TIMER1_LATCH_LO    4'h6
    `define ADDR_TIMER1_LATCH_HI    4'h7
    `define ADDR_TIMER2_LO          4'h8
    `define ADDR_TIMER2_HI          4'h9
    `define ADDR_SR                 4'ha
    `define ADDR_ACR                4'hb
    `define ADDR_PCR                4'hc
    `define ADDR_IFR                4'hd
    `define ADDR_IER                4'he
    `define ADDR_PORTA_NH           4'hf

    `define VIAPORTS

    `ifdef VIAPORTS
    // PORTA tests
    // pin control
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    porta_in =                              8'b11111111;
    `assertEqual(porta_out,                 8'b11111111);
    `write(`ADDR_DDRA,                      8'b11110000);
    `assertEqual(porta_out,                 8'b00001111);
    `write(`ADDR_PORTA,                     8'b11001100);
    `assertEqual(porta_out,                 8'b11001111);
    `assertRegisterEqual(`ADDR_PORTA,       8'b11001111);
    `assertRegisterEqual(`ADDR_PORTA_NH,    8'b11001111);
    porta_in =                              8'b10101010;
    `assertRegisterEqual(`ADDR_PORTA,       8'b10001010);
    `assertRegisterEqual(`ADDR_PORTA_NH,    8'b10001010);
    // CA2 input functions
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    `write(`ADDR_IER, 8'b10000001); // enable CA2 interrupt
    `write(`ADDR_PCR, 8'b00000000); // negative edge input on CA2
    `assertEqual(irq, 1'b0);
    ca2_in = 1'b1; `clktic; `assertEqual(irq, 1'b0);
    ca2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTA); `assertEqual(irq, 1'b0);
    ca2_in = 1'b1; `clktic; ca2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTA, 8'h00); `assertEqual(irq, 1'b0);
    `write(`ADDR_PCR, 8'b00000010); // negative edge input on CA2, no clear on PORTA access
    `assertEqual(irq, 1'b0);
    ca2_in = 1'b1; `clktic; `assertEqual(irq, 1'b0);
    ca2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTA); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00000001); `assertEqual(irq, 1'b0);
    ca2_in = 1'b1; `clktic; ca2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTA, 8'h00); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00000001); `assertEqual(irq, 1'b0);
    `write(`ADDR_PCR, 8'b00000100); // positive edge input on CA2
    `assertEqual(irq, 1'b0);
    ca2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTA); `assertEqual(irq, 1'b0);
    ca2_in = 1'b0; `clktic; ca2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTA, 8'h00); `assertEqual(irq, 1'b0);
    `write(`ADDR_PCR, 8'b00000110); // positive edge input on CA2, no clear on PORTA access
    `assertEqual(irq, 1'b0);
    ca2_in = 1'b0; `clktic; `assertEqual(irq, 1'b0);
    ca2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTA); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00000001); `assertEqual(irq, 1'b0);
    ca2_in = 1'b0; `clktic; ca2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTA, 8'h00); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00000001); `assertEqual(irq, 1'b0);
    // read handshake
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    `write(`ADDR_IER, 8'b10000010); // enable PORTA interrupt
    `write(`ADDR_PCR, 8'b00001000); // negative CA1 edge, handshake output on CA2
    `assertEqual(ca2_out, 1'b1);
    porta_in = 8'h00;
    `assertRegisterEqual(`ADDR_PORTA_NH, 8'h00);
    `write(`ADDR_ACR, 8'b00000001); // enable latched operation
    porta_in = 8'h55;
    `assertRegisterEqual(`ADDR_PORTA_NH, 8'h00); // Not latched yet
    ca1_in = 1'b0;
    `assertEqual(irq, 1'b0);
    `assertEqual(ca2_out, 1'b1);
    `clktic;
    `assertEqual(irq, 1'b1); // IRQ reacts even outside of phi2 edges
    `assertEqual(ca2_out, 1'b1);
    ca1_in = 1'b1;
    `assertRegisterEqual(`ADDR_PORTA_NH, 8'h55); // Latched
    `assertEqual(irq, 1'b1);     // NH did not clear interrupt...
    `assertEqual(ca2_out, 1'b1); // ...nor trigger handshake...
    `assertRegisterEqual(`ADDR_PORTA, 8'h55);
    `assertEqual(irq, 1'b0);     // ...but normal read does.
    `assertEqual(ca2_out, 1'b0);
    porta_in = 8'haa;
    `phi2_tic(2);
    ca1_in = 1'b0;
    `assertEqual(irq, 1'b0);
    `assertEqual(ca2_out, 1'b0); // CA2 stays low until next incomming byte
    `clktic;
    `assertEqual(irq, 1'b1);
    `assertEqual(ca2_out, 1'b1);
    `assertRegisterEqual(`ADDR_PORTA_NH, 8'haa);
    // read strobe
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    `write(`ADDR_IER, 8'b10000010); // enable PORTA interrupt
    `write(`ADDR_PCR, 8'b00001011); // positive CA1 edge, strobe output on CA2
    `write(`ADDR_ACR, 8'b00000001); // enable latched operation
    ca1_in = 1'b0;
    `clktic;
    `assertEqual(ca2_out, 1'b1);
    porta_in = 8'h00;
    `assertRegisterEqual(`ADDR_PORTA_NH, 8'haa); // Not latched yet
    ca1_in = 1'b1;
    `assertEqual(irq, 1'b0);
    `assertEqual(ca2_out, 1'b1);
    `clktic;
    `assertEqual(irq, 1'b1); // IRQ reacts even outside of phi2 edges
    `assertEqual(ca2_out, 1'b1);
    ca1_in = 1'b0;
    `assertRegisterEqual(`ADDR_PORTA, 8'h00);
    `assertEqual(irq, 1'b0);
    `assertEqual(ca2_out, 1'b0);
    `clktic;
    `clktic;
    `assertEqual(ca2_out, 1'b0); // phi2 cycle is needed for ca2 to become 1 again...
    `phi2_tic(1);
    `assertEqual(ca2_out, 1'b1); // ...done
    // write handshake
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    porta_in = 8'hff;
    ca1_in = 1'b1;
    `write(`ADDR_IER, 8'b10000010); // enable PORTA interrupt
    `write(`ADDR_DDRA, 8'hff); // drive all porta_out pins from ORA
    `write(`ADDR_PCR, 8'b00001000); // negative CA1 edge, handshake output on CA2
    `assertEqual(ca2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    `write(`ADDR_PORTA, 8'hff);
    `assertEqual(ca2_out, 1'b1); // CA2 gets low on next phi2 positive edge
    `assertEqual(irq, 1'b0);
    `phi2_rise;
    `assertEqual(ca2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    `phi2_fall;
    `phi2_tic(2); // CA2 stays low
    `assertEqual(ca2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    ca1_in = 1'b0;
    `clktic;
    `assertEqual(irq, 1'b1); // IRQ reacts even outside of phi2 edges
    `assertEqual(ca2_out, 1'b1);
    ca1_in = 1'b1;
    `clktic;
    `assertEqual(ca2_out, 1'b1);
    `write(`ADDR_PORTA, 8'hff);
    `assertEqual(irq, 1'b0);
    `assertEqual(ca2_out, 1'b1);
    `phi2_tic(1);
    `assertEqual(ca2_out, 1'b0);
    // write strobe
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    porta_in = 8'hff;
    ca1_in = 1'b1;
    `write(`ADDR_IER, 8'b10000010); // enable PORTA interrupt
    `write(`ADDR_DDRA, 8'hff); // drive all porta_out pins from ORA
    `write(`ADDR_PCR, 8'b00001010); // negative CA1 edge, pulse output on CA2
    `assertEqual(ca2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    `write(`ADDR_PORTA, 8'hff);
    `assertEqual(ca2_out, 1'b1); // CA2 gets low on next phi2 positive edge
    `assertEqual(irq, 1'b0);
    `phi2_rise;
    `assertEqual(ca2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    `phi2_fall;
    `assertEqual(ca2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    `phi2_rise;
    `assertEqual(ca2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    `phi2_fall;
    `assertEqual(ca2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    ca1_in = 1'b0;
    `clktic;
    `assertEqual(irq, 1'b1); // IRQ reacts even outside of phi2 edges
    `assertEqual(ca2_out, 1'b1);
    ca1_in = 1'b1;
    `clktic;
    `assertEqual(ca2_out, 1'b1);
    `write(`ADDR_PORTA, 8'hff);
    `assertEqual(irq, 1'b0);
    `assertEqual(ca2_out, 1'b1);
    `phi2_tic(1);
    `assertEqual(ca2_out, 1'b0);

    // PORTB tests
    // pin control
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    portb_in =                              8'b11111111;
    `assertEqual(portb_out,                 8'b11111111);
    `write(`ADDR_DDRB,                      8'b11110000);
    `assertEqual(portb_out,                 8'b00001111);
    `write(`ADDR_PORTB,                     8'b11001100);
    `assertEqual(portb_out,                 8'b11001111);
    `assertRegisterEqual(`ADDR_PORTB,       8'b11001111);
    portb_in =                              8'b10101010;
    `assertRegisterEqual(`ADDR_PORTB,       8'b11001010);
    // CB2 input functions
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    `write(`ADDR_IER, 8'b10001000); // enable CB2 interrupt
    `write(`ADDR_PCR, 8'b00000000); // negative edge input on CB2
    `assertEqual(irq, 1'b0);
    cb2_in = 1'b1; `clktic; `assertEqual(irq, 1'b0);
    cb2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTB); `assertEqual(irq, 1'b0);
    cb2_in = 1'b1; `clktic; cb2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTB, 8'h00); `assertEqual(irq, 1'b0);
    `write(`ADDR_PCR, 8'b00100000); // negative edge input on CB2, no clear on PORTA access
    `assertEqual(irq, 1'b0);
    cb2_in = 1'b1; `clktic; `assertEqual(irq, 1'b0);
    cb2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTB); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00001000); `assertEqual(irq, 1'b0);
    cb2_in = 1'b1; `clktic; cb2_in = 1'b0; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTB, 8'h00); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00001000); `assertEqual(irq, 1'b0);
    `write(`ADDR_PCR, 8'b01000000); // positive edge input on CB2
    `assertEqual(irq, 1'b0);
    cb2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTB); `assertEqual(irq, 1'b0);
    cb2_in = 1'b0; `clktic; cb2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTB, 8'h00); `assertEqual(irq, 1'b0);
    `write(`ADDR_PCR, 8'b01100000); // positive edge input on CB2, no clear on PORTA access
    `assertEqual(irq, 1'b0);
    cb2_in = 1'b0; `clktic; `assertEqual(irq, 1'b0);
    cb2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `read(`ADDR_PORTB); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00001000); `assertEqual(irq, 1'b0);
    cb2_in = 1'b0; `clktic; cb2_in = 1'b1; `clktic; `assertEqual(irq, 1'b1);
    `write(`ADDR_PORTB, 8'h00); `assertEqual(irq, 1'b1);
    `write(`ADDR_IFR, 8'b00001000); `assertEqual(irq, 1'b0);
    // write handshake
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    portb_in = 8'hff;
    cb1_in = 1'b1;
    `write(`ADDR_IER, 8'b10010000); // enable PORTB interrupt
    `write(`ADDR_DDRB, 8'hff); // drive all portb_out pins from ORB
    `write(`ADDR_PCR, 8'b10000000); // negative CB1 edge, handshake output on CB2
    `assertEqual(cb2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    `write(`ADDR_PORTB, 8'hff);
    `assertEqual(cb2_out, 1'b1); // CB2 gets low on next phi2 positive edge
    `assertEqual(irq, 1'b0);
    `phi2_rise;
    `assertEqual(cb2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    `phi2_fall;
    `phi2_tic(2); // CB2 stays low
    `assertEqual(cb2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    cb1_in = 1'b0;
    `clktic;
    `assertEqual(irq, 1'b1); // IRQ reacts even outside of phi2 edges
    `assertEqual(cb2_out, 1'b1);
    cb1_in = 1'b1;
    `clktic;
    `assertEqual(cb2_out, 1'b1);
    `write(`ADDR_PORTB, 8'hff);
    `assertEqual(irq, 1'b0);
    `assertEqual(cb2_out, 1'b1);
    `phi2_tic(1);
    `assertEqual(cb2_out, 1'b0);
    // write strobe
    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    portb_in = 8'hff;
    cb1_in = 1'b1;
    `write(`ADDR_IER, 8'b10010000); // enable PORTB interrupt
    `write(`ADDR_DDRB, 8'hff); // drive all portb_out pins from ORB
    `write(`ADDR_PCR, 8'b10100000); // negative CB1 edge, pulse output on CB2
    `assertEqual(cb2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    `write(`ADDR_PORTB, 8'hff);
    `assertEqual(cb2_out, 1'b1); // CB2 gets low on next phi2 positive edge
    `assertEqual(irq, 1'b0);
    `phi2_rise;
    `assertEqual(cb2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    `phi2_fall;
    `assertEqual(cb2_out, 1'b0);
    `assertEqual(irq, 1'b0);
    `phi2_rise;
    `assertEqual(cb2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    `phi2_fall;
    `assertEqual(cb2_out, 1'b1);
    `assertEqual(irq, 1'b0);
    cb1_in = 1'b0;
    `clktic;
    `assertEqual(irq, 1'b1); // IRQ reacts even outside of phi2 edges
    `assertEqual(cb2_out, 1'b1);
    cb1_in = 1'b1;
    `clktic;
    `assertEqual(cb2_out, 1'b1);
    `write(`ADDR_PORTB, 8'hff);
    `assertEqual(irq, 1'b0);
    `assertEqual(cb2_out, 1'b1);
    `phi2_tic(1);
    `assertEqual(cb2_out, 1'b0);
    `endif

    `define VERBOSE
    `define VIA1
    `define VIA2
    `define VIA3
    `define VIA3A
    `define VIA4
    `define VIA5
    `define VIA9
    `define VIA10
    `define VIA11
    `define VIA12
    `define VIA13

    reset = 1; `phi2_tic(1); reset = 0; `phi2_tic(1);
    `ifdef VIA1
    `test("1");
    `init_step("A");                                             `do_step; `lda(`ADDR_TIMER1_LO      ); `checkCPUIn; `end_step;
    `init_step("B");                                             `do_step; `lda(`ADDR_TIMER1_HI      ); `checkCPUIn; `end_step;
    `init_step("C");                                             `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `end_step;
    `init_step("D");                                             `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `end_step;
    `init_step("E");                                             `do_step; `lda(`ADDR_TIMER2_LO      ); `checkCPUIn; `end_step;
    `init_step("F");                                             `do_step; `lda(`ADDR_TIMER2_HI      ); `checkCPUIn; `end_step;
    `init_step("G"); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_TIMER2_LO      ); `checkCPUIn; `end_step;
    `init_step("H"); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_TIMER2_HI      ); `checkCPUIn; `end_step;
    `end_test;
    `endif

    `ifdef VIA2
    `test("2");
    `init_step("A"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_LO      ); `checkCPUIn; `end_step;
    `init_step("B"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_HI      ); `checkCPUIn; `end_step;
    `init_step("C"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `end_step;
    `init_step("D"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `end_step;
    `init_step("E"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_LO      ); `checkCPUIn; `end_step;
    `init_step("F"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_HI      ); `checkCPUIn; `end_step;
    `init_step("G"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `end_step;
    `init_step("H"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1);                                             `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `end_step;
    `init_step("I"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_TIMER2_LO      ); `checkCPUIn; `end_step;
    `init_step("J"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_TIMER2_HI      ); `checkCPUIn; `end_step;
    `init_step("K"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_TIMER2_LO      ); `checkCPUIn; `end_step;
    `init_step("L"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_TIMER2_HI      ); `checkCPUIn; `end_step;
    `end_test;
    `endif

    `ifdef VIA3
    `test("3");
    `init_step("A"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("B"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("C"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("D"); `phi2_tic(2); `sta(`ADDR_TIMER1_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("E"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("F"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("G"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("H"); `phi2_tic(2); `sta(`ADDR_TIMER1_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("I"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("J"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("K"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("L"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `end_test;
    `endif

    `ifdef VIA3A
    `test("3a");
    `init_step("A"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("B"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("C"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("D"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("E"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("F"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("G"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `init_step("H"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000); `do_step; `lda(`ADDR_IFR); `checkCPUIn; `end_step;
    `end_test;
    `endif

    `ifdef VIA4
    `test("4");
    `init_step("A"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("B"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("C"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("D"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("E"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("F"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    // --
    `init_step("G"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("H"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("I"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("J"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("K"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("L"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b01000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    // --
    `init_step("M"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("N"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("O"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("P"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("Q"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("R"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b10000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    // --
    `init_step("S"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("T"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("U"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("V"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000);
        `do_step; `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("W"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `init_step("X"); `phi2_tic(2); `sta(`ADDR_TIMER1_LATCH_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b11000000);
        `do_step; `lda(`ADDR_IFR            ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'b01000000); `end_step;
    `end_test;
    `endif

    `ifdef VIA5
    `test("5");
    `init_step("A"); `do_step; `sta(`ADDR_TIMER1_LO, x); `lda(`ADDR_TIMER1_LO); `checkCPUIn; `end_step;
    `init_step("B"); `do_step; `sta(`ADDR_TIMER1_LO, x); `lda(`ADDR_TIMER1_HI); `checkCPUIn; `end_step;
    `init_step("C"); `do_step; `sta(`ADDR_TIMER1_HI, x); `lda(`ADDR_TIMER1_LO); `checkCPUIn; `end_step;
    `init_step("D"); `do_step; `sta(`ADDR_TIMER1_HI, x); `lda(`ADDR_TIMER1_HI); `checkCPUIn; `end_step;
    `init_step("E"); `do_step; `sta(`ADDR_TIMER1_LO, x); `lda(`ADDR_IFR      ); `checkCPUIn; `end_step;
    `init_step("F"); `do_step; `sta(`ADDR_TIMER1_HI, x); `lda(`ADDR_IFR      ); `checkCPUIn; `end_step;
    // --
    `init_step("G"); `do_step; `sta(`ADDR_TIMER1_LATCH_LO, x); `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `end_step;
    `init_step("H"); `do_step; `sta(`ADDR_TIMER1_LATCH_LO, x); `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `end_step;
    `init_step("I"); `do_step; `sta(`ADDR_TIMER1_LATCH_HI, x); `lda(`ADDR_TIMER1_LATCH_LO); `checkCPUIn; `end_step;
    `init_step("J"); `do_step; `sta(`ADDR_TIMER1_LATCH_HI, x); `lda(`ADDR_TIMER1_LATCH_HI); `checkCPUIn; `end_step;
    `init_step("K"); `do_step; `sta(`ADDR_TIMER1_LATCH_LO, x); `lda(`ADDR_IFR            ); `checkCPUIn; `end_step;
    `init_step("L"); `do_step; `sta(`ADDR_TIMER1_LATCH_HI, x); `lda(`ADDR_IFR            ); `checkCPUIn; `end_step;
    // --
    `init_step("M"); `do_step; `sta(`ADDR_TIMER2_LO, x); `lda(`ADDR_TIMER2_LO); `checkCPUIn; `end_step;
    `init_step("N"); `do_step; `sta(`ADDR_TIMER2_LO, x); `lda(`ADDR_TIMER2_HI); `checkCPUIn; `end_step;
    `init_step("O"); `do_step; `sta(`ADDR_TIMER2_HI, x); `lda(`ADDR_TIMER2_LO); `checkCPUIn; `end_step;
    `init_step("P"); `do_step; `sta(`ADDR_TIMER2_HI, x); `lda(`ADDR_TIMER2_HI); `checkCPUIn; `end_step;
    `init_step("Q"); `do_step; `sta(`ADDR_TIMER2_LO, x); `lda(`ADDR_IFR      ); `checkCPUIn; `end_step;
    `init_step("R"); `do_step; `sta(`ADDR_TIMER2_HI, x); `lda(`ADDR_IFR      ); `checkCPUIn; `end_step;
    `end_test;
    `endif

    `ifdef VIA9
    `test("9");
    `init_step("A"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER2_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("B"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER2_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("C"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_IFR      ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    // --
    `init_step("D"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER2_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("E"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_TIMER2_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("F"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00000000);
        `do_step; `lda(`ADDR_IFR      ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    // --
    `init_step("G"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000);
        `do_step; `lda(`ADDR_TIMER2_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("H"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000);
        `do_step; `lda(`ADDR_TIMER2_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("I"); `phi2_tic(2); `sta(`ADDR_TIMER2_LO, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000);
        `do_step; `lda(`ADDR_IFR      ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    // --
    `init_step("J"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000);
        `do_step; `lda(`ADDR_TIMER2_LO); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("K"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000);
        `do_step; `lda(`ADDR_TIMER2_HI); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `init_step("L"); `phi2_tic(2); `sta(`ADDR_TIMER2_HI, 8'h1); `phi2_tic(2); `sta(`ADDR_ACR, 8'b00100000);
        `do_step; `lda(`ADDR_IFR      ); `checkCPUIn; `lda(`ADDR_ACR); `phi2_tic(2); `sta(`ADDR_ACR, cpu_in ^ 8'h20); `end_step;
    `end_test;
    `endif

    `define via1x(DDRB, PRB, CR, TIMER, THIFL)                      \
        `phi2_tic(2); `sta(`ADDR_DDRB, DDRB);                       \
        `phi2_tic(2); `sta(`ADDR_PORTB, PRB);                       \
        `phi2_tic(2); `sta(`ADDR_TIMER1_LO + TIMER * 4 + THIFL, 1); \
        `phi2_tic(2); `sta(`ADDR_ACR + TIMER, CR);                  \
        `do_step; `lda(`ADDR_PORTB); `checkCPUIn;

    // ADDR_PORTB = ((ORB & DDRB) | (portb_in_r & ~DDRB)) ^ {acr[7] & pb7_invert, 7'b0}
    `ifdef VIA10
    portb_in = 8'h1f;
    `test("10");
    `init_step("A"); `via1x(8'h00, 8'h00, 8'h00, 0, 0); `end_step;              // 0            in , 0, one shot & no out, LO <- portb_in[7] (0)              (1 ?)
    `init_step("B"); `via1x(8'h00, 8'h00, 8'h00, 0, 1); `end_step;              // 0            in , 0, one shot & no out, HI <- portb_in[7] (0)              (0 ?)
    `init_step("C"); `via1x(8'h00, 8'h00, 8'h80, 0, 0); `end_step;              // 1            in , 0, one shot &    out, LO <- portb_in[7] (0) ^ pb7_invert (1)
    `init_step("D"); `via1x(8'h00, 8'h00, 8'h80, 0, 1); `end_step;              // 0            in , 0, one shot &    out, HI <- portb_in[7] (0) ^ pb7_invert (0)
    `init_step("E"); `via1x(8'h00, 8'h00, 8'h40, 0, 0); `end_step;              // 0            in , 0, cont     & no out, LO <- portb_in[7] (0)              (1 ?)
    `init_step("F"); `via1x(8'h00, 8'h00, 8'h40, 0, 1); `end_step;              // 0            in , 0, cont     & no out, HI <- portb_in[7] (0)              (pulse ?)
    `init_step("G"); `via1x(8'h00, 8'h00, 8'hc0, 0, 0); `end_step;              // 1            in , 0, cont     &    out, LO <- portb_in[7] (0) ^ pb7_invert (1)
    `init_step("H"); `via1x(8'h00, 8'h00, 8'hc0, 0, 1); `end_step;              // 1 (pulsed)   in , 0, cont     &    out, HI <- portb_in[7] (0) ^ pb7_invert (pulse)
    `end_test;
    `endif

    `ifdef VIA11
    portb_in = 8'h1f;
    `test("11");
    `init_step("A"); `via1x(8'h80, 8'h00, 8'h00, 0, 0); `end_step;              // 0            out, 0, one shot & no out, LO <- orb[7] (0)
    `init_step("B"); `via1x(8'h80, 8'h00, 8'h00, 0, 1); `end_step;              // 0            out, 0, one shot & no out, HI <- orb[7] (0)
    `init_step("C"); `via1x(8'h80, 8'h00, 8'h80, 0, 0); `end_step;              // 1            out, 0, one shot &    out, LO <- orb[7] (0) ^ pb7_invert (1)
    `init_step("D"); `via1x(8'h80, 8'h00, 8'h80, 0, 1); `end_step;              // 0            out, 0, one shot &    out, HI <- orb[7] (0) ^ pb7_invert (0)
    `init_step("E"); `via1x(8'h80, 8'h00, 8'h40, 0, 0); `end_step;              // 0            out, 0, cont     & no out, LO <- orb[7] (0)
    `init_step("F"); `via1x(8'h80, 8'h00, 8'h40, 0, 1); `end_step;              // 0            out, 0, cont     & no out, HI <- orb[7] (0)
    `init_step("G"); `via1x(8'h80, 8'h00, 8'hc0, 0, 0); `end_step;              // 1            out, 0, cont     &    out, LO <- orb[7] (0) ^ pb7_invert (1)
    `init_step("H"); `via1x(8'h80, 8'h00, 8'hc0, 0, 1); `end_step;              // 1 (pulsed)   out, 0, cont     &    out, HI <- orb[7] (0) ^ pb7_invert (pulse)
    `end_test;
    `endif

    `ifdef VIA12
    portb_in = 8'h1f;
    `test("12");
    `init_step("A"); `via1x(8'h00, 8'h80, 8'h00, 0, 0); `end_step;              // 0            in, 1, one shot & no out, LO <- portb_in[7] (0)
    `init_step("B"); `via1x(8'h00, 8'h80, 8'h00, 0, 1); `end_step;              // 0            in, 1, one shot & no out, HI <- portb_in[7] (0)
    `init_step("C"); `via1x(8'h00, 8'h80, 8'h80, 0, 0); `end_step;              // 1            in, 1, one shot &    out, LO <- portb_in[7] (0) ^ pb7_invert (1)
    `init_step("D"); `via1x(8'h00, 8'h80, 8'h80, 0, 1); `end_step;              // 0            in, 1, one shot &    out, HI <- portb_in[7] (0) ^ pb7_invert (0)
    `init_step("E"); `via1x(8'h00, 8'h80, 8'h40, 0, 0); `end_step;              // 0            in, 1, cont     & no out, LO <- portb_in[7] (0)
    `init_step("F"); `via1x(8'h00, 8'h80, 8'h40, 0, 1); `end_step;              // 0            in, 1, cont     & no out, HI <- portb_in[7] (0)
    `init_step("G"); `via1x(8'h00, 8'h80, 8'hc0, 0, 0); `end_step;              // 1            in, 1, cont     &    out, LO <- portb_in[7] (0) ^ pb7_invert (1)
    `init_step("H"); `via1x(8'h00, 8'h80, 8'hc0, 0, 1); `end_step;              // 1 (pulsed)   in, 1, cont     &    out, HI <- portb_in[7] (0) ^ pb7_invert (pulse)
    `end_test;
    `endif

    `ifdef VIA13
    portb_in = 8'h1f;
    `test("13");
    `init_step("A"); `via1x(8'h80, 8'h80, 8'h00, 0, 0); `end_step;              // 1            out, 1, one shot & no out, LO <- orb[7] (1)
    `init_step("B"); `via1x(8'h80, 8'h80, 8'h00, 0, 1); `end_step;              // 1            out, 1, one shot & no out, HI <- orb[7] (1)
    `init_step("C"); `via1x(8'h80, 8'h80, 8'h80, 0, 0); `end_step;              // 1            out, 1, one shot &    out, LO <- orb[7] (1) ^ pb7_invert (1)
    `init_step("D"); `via1x(8'h80, 8'h80, 8'h80, 0, 1); `end_step;              // 0            out, 1, one shot &    out, HI <- orb[7] (1) ^ pb7_invert (0)
    `init_step("E"); `via1x(8'h80, 8'h80, 8'h40, 0, 0); `end_step;              // 1            out, 1, cont     & no out, LO <- orb[7] (1)
    `init_step("F"); `via1x(8'h80, 8'h80, 8'h40, 0, 1); `end_step;              // 1            out, 1, cont     & no out, HI <- orb[7] (1)
    `init_step("G"); `via1x(8'h80, 8'h80, 8'hc0, 0, 0); `end_step;              // 1            out, 1, cont     &    out, LO <- orb[7] (1) ^ pb7_invert (1)
    `init_step("H"); `via1x(8'h80, 8'h80, 8'hc0, 0, 1); `end_step;              // 1 (pulsed)   out, 1, cont     &    out, HI <- orb[7] (1) ^ pb7_invert (pulse)
    `end_test;
    `endif

    $finish;
end

endmodule

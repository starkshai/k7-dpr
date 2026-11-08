// Multi-burst testbench for spi_flash_reader.
//
// Purpose: the hardware ILA window is 655 us = exactly one 256-beat burst, so
// the burst boundary (ST_DATA -> ST_DONE -> ST_IDLE -> next AR handshake) has
// never been observed on the board. This TB drives back-to-back AXI read bursts
// against a behavioural SPI flash and checks that every beat of every burst
// arrives, that rlast lands only on the final beat, that the FSM passes through
// ST_DONE between bursts, and that burst N+1 actually starts.
//
// Run with NUM_BURSTS=4 / BURST_LEN=256 for a fast smoke test, then
// NUM_BURSTS=472 / LAST_BEATS=131 to replay the real rm_shift_left load
// (482828 bytes).
`timescale 1ns / 1ps

module tb_spi_flash_reader;

    // Runtime knobs (plusargs) because the Windows xelab.bat mangles
    // -generic_top NAME=VALUE. Defaults replay one rm_shift_left burst pair.
    integer       NUM_BURSTS;
    integer       BURST_LEN;
    integer       LAST_BEATS;
    reg   [31:0]  BASE_ADDR;
    integer       STRESS_RREADY;
    integer       IDLE_GAPS;
    reg           cfg_ready = 1'b0;

    parameter [23:0] MEM_BASE = 24'hAE0000;

    initial begin
        NUM_BURSTS    = 4;
        BURST_LEN     = 256;
        LAST_BEATS    = 0;
        BASE_ADDR     = 32'h00AEA000;
        STRESS_RREADY = 0;
        IDLE_GAPS     = 0;
        if ($value$plusargs("NUM_BURSTS=%d",    NUM_BURSTS))    ;
        if ($value$plusargs("BURST_LEN=%d",     BURST_LEN))     ;
        if ($value$plusargs("LAST_BEATS=%d",    LAST_BEATS))    ;
        if ($value$plusargs("BASE_ADDR=%h",     BASE_ADDR))     ;
        if ($value$plusargs("STRESS_RREADY=%d", STRESS_RREADY)) ;
        if ($value$plusargs("IDLE_GAPS=%d",     IDLE_GAPS))     ;
        $display("CFG: NUM_BURSTS=%0d BURST_LEN=%0d LAST_BEATS=%0d BASE_ADDR=%08h STRESS=%0d GAPS=%0d",
                 NUM_BURSTS, BURST_LEN, LAST_BEATS, BASE_ADDR, STRESS_RREADY, IDLE_GAPS);
        cfg_ready = 1'b1;
    end

    localparam integer ST_IDLE       = 0;
    localparam integer ST_CMD_SETUP  = 1;
    localparam integer ST_CMD        = 2;
    localparam integer ST_ADDR_SETUP = 3;
    localparam integer ST_ADDR       = 4;
    localparam integer ST_DATA_SETUP = 5;
    localparam integer ST_DATA       = 6;
    localparam integer ST_DONE       = 7;

    // ---------------------------------------------------------------- clocks
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;

    // ------------------------------------------------------------------ DUT
    reg  [31:0] araddr;
    reg  [7:0]  arlen;
    reg  [2:0]  arsize;
    reg  [1:0]  arburst;
    reg  [3:0]  arcache;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready;

    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rlast;
    wire        rvalid;
    reg         rready;

    wire        spi_clk_o, spi_clk_ts, spi_ce_b, spi_d0_o;
    wire        spi_d1_i;
    wire [3:0]  dbg_state, dbg_seq;

    spi_flash_reader dut (
        .clk            (clk),
        .rst            (rst),
        .s_axi_araddr   (araddr),
        .s_axi_arlen    (arlen),
        .s_axi_arsize   (arsize),
        .s_axi_arburst  (arburst),
        .s_axi_arcache  (arcache),
        .s_axi_arprot   (arprot),
        .s_axi_arvalid  (arvalid),
        .s_axi_arready  (arready),
        .s_axi_rdata    (rdata),
        .s_axi_rresp    (rresp),
        .s_axi_rlast    (rlast),
        .s_axi_rvalid   (rvalid),
        .s_axi_rready   (rready),
        .spi_clk_o      (spi_clk_o),
        .spi_clk_ts     (spi_clk_ts),
        .spi_ce_b       (spi_ce_b),
        .spi_d0_o       (spi_d0_o),
        .spi_d1_i       (spi_d1_i),
        .dbg_state      (dbg_state),
        .dbg_seq        (dbg_seq)
    );

    spi_flash_model #(.MEM_BASE(MEM_BASE)) flash (
        .sclk (spi_clk_o),
        .ce_b (spi_ce_b),
        .mosi (spi_d0_o),
        .miso (spi_d1_i)
    );

    // ------------------------------------------------------- expected bytes
    function [7:0] mem_pattern;
        input integer idx;
        begin
            mem_pattern = ((idx * 7 + (idx >> 8) * 13 + 32'h5A) & 32'hFF);
        end
    endfunction

    function [7:0] flash_byte;
        input [31:0] abs_addr;
        integer idx;
        begin
            idx = abs_addr - {8'd0, MEM_BASE};
            flash_byte = mem_pattern(idx);
        end
    endfunction

    // ------------------------------------------------- passive instrumentation
    integer cycle         = 0;
    integer ar_handshakes = 0;
    integer done_edges    = 0;
    integer prev_done     = 0;
    integer prev_ce       = 1;
    integer ce_high_run   = 0;
    integer ce_high_min   = 1000000;
    integer ce_gaps       = 0;

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (!rst) begin
            if (arvalid && arready) ar_handshakes <= ar_handshakes + 1;
            if (dbg_state == ST_DONE && prev_done == 0) done_edges <= done_edges + 1;
        end
        prev_done <= (dbg_state == ST_DONE) ? 1 : 0;
        if (!spi_ce_b && prev_ce == 1) begin
            // end of a CE-high gap: record how long it lasted
            ce_gaps <= ce_gaps + 1;
            if (ce_high_run < ce_high_min) ce_high_min <= ce_high_run;
        end
        ce_high_run <= spi_ce_b ? (ce_high_run + 1) : 0;
        prev_ce     <= spi_ce_b;
    end

    // ---------------------------------------------------------- AXI master
    integer errors      = 0;
    integer total_beats = 0;
    integer b, n, len, guard;
    integer t_start, idle_wait;
    reg [31:0] burst_base, word_addr, exp_word;

    task wait_beats;
        input integer want;
        input integer burst_no;
        input [31:0]  base;
        integer got;
        begin
            got = 0;
            guard = 0;
            while (got < want) begin
                @(posedge clk);
                guard = guard + 1;
                if (rvalid && rready) begin
                    word_addr = base + (got * 4);
                    exp_word  = { flash_byte(word_addr + 3),
                                  flash_byte(word_addr + 2),
                                  flash_byte(word_addr + 1),
                                  flash_byte(word_addr + 0) };
                    if (rdata !== exp_word) begin
                        errors = errors + 1;
                        if (errors < 25)
                            $display("ERROR data  burst=%0d beat=%0d addr=%08h got=%08h exp=%08h cycle=%0d",
                                     burst_no, got, word_addr, rdata, exp_word, cycle);
                    end
                    if (rlast !== ((got + 1) == want)) begin
                        errors = errors + 1;
                        if (errors < 25)
                            $display("ERROR rlast burst=%0d beat=%0d of %0d rlast=%b cycle=%0d",
                                     burst_no, got, want, rlast, cycle);
                    end
                    got = got + 1;
                end
                if (guard > 500000) begin
                    $display("FATAL   burst=%0d timed out: %0d/%0d beats, state=%0d seq=%0d cycle=%0d",
                             burst_no, got, want, dbg_state, dbg_seq, cycle);
                    errors = errors + 1;
                    got = want;
                end
            end
            total_beats = total_beats + got;
        end
    endtask

    initial begin
        wait (cfg_ready);
        araddr  = 0; arlen = 0; arsize = 3'd2; arburst = 2'b01;
        arcache = 4'd3; arprot = 3'd0; arvalid = 0; rready = 1'b1;
        rst = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        for (b = 0; b < NUM_BURSTS; b = b + 1) begin
            len        = ((LAST_BEATS != 0) && (b == NUM_BURSTS - 1)) ? LAST_BEATS : BURST_LEN;
            burst_base = BASE_ADDR + (b * BURST_LEN * 4);

            if (IDLE_GAPS != 0) repeat (IDLE_GAPS) @(posedge clk);

            araddr  = burst_base;
            arlen   = len - 1;
            arvalid = 1'b1;
            t_start = cycle;

            @(posedge clk);
            idle_wait = 0;
            while (!(arvalid && arready)) begin
                @(posedge clk);
                idle_wait = idle_wait + 1;
                if (idle_wait > 100000) begin
                    $display("FATAL   burst=%0d AR never accepted (state=%0d seq=%0d)",
                             b, dbg_state, dbg_seq);
                    errors = errors + 1;
                    b = NUM_BURSTS;
                    idle_wait = 100001;
                end
            end
            arvalid = 1'b0;

            if (b < 4 || b == NUM_BURSTS - 1)
                $display("burst %0d: AR addr=%08h len=%0d accepted at cycle %0d after %0d idle cycles",
                         b, burst_base, len, cycle, idle_wait);

            wait_beats(len, b, burst_base);

            if (b < 4 || b == NUM_BURSTS - 1)
                $display("burst %0d: done, %0d beats, %0d cycles total", b, len, cycle - t_start);
        end

        repeat (500) @(posedge clk);
        $display("");
        $display("==================== SUMMARY ====================");
        $display("bursts requested   : %0d", NUM_BURSTS);
        $display("AR handshakes seen : %0d", ar_handshakes);
        $display("ST_DONE edges seen : %0d", done_edges);
        $display("total R beats      : %0d", total_beats);
        $display("data/rlast errors  : %0d", errors);
        $display("CE-high gaps       : %0d, min %0d cycles (%0d ns)",
                 ce_gaps, ce_high_min, ce_high_min * 10);
        if (errors == 0 && ar_handshakes == NUM_BURSTS && done_edges == NUM_BURSTS)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $display("=================================================");
        $finish;
    end

    // random rready stall stress
    always @(posedge clk) begin
        if (STRESS_RREADY && !rst) rready <= (($random % 4) != 0);
    end

    // global watchdog
    initial begin
        #2000000000;
        $display("FATAL: global watchdog at cycle %0d, state=%0d, beats=%0d",
                 cycle, dbg_state, total_beats);
        $finish;
    end

endmodule

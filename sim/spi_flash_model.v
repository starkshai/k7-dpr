// Behavioural SPI flash for the spi_flash_reader testbench.
// Standard read (0x03), Mode 0, 24-bit address, auto-increment read.
// Address space is MEM_BASE .. MEM_BASE+(1<<20)-1.
//
// MISO is registered off the falling SCLK edge with a non-blocking assignment so
// it is stable across the whole following high phase, and so that a DUT which
// samples on the same simulation instant as the falling edge still sees the
// previous bit (no active-region race).
`timescale 1ns / 1ps

module spi_flash_model #(
    parameter [23:0] MEM_BASE = 24'hAE0000
) (
    input  wire sclk,
    input  wire ce_b,
    input  wire mosi,
    output reg  miso
);

    localparam integer MEM_SIZE = 1 << 20;

    reg [7:0]  mem [0:MEM_SIZE-1];
    reg [31:0] sh32;         // {cmd, addr} shifted in over the first 32 edges
    reg [23:0] base_addr_r;  // address latched once the header is complete
    reg [31:0] cnt;          // number of rising SCLK edges already sampled
    reg [31:0] next_didx;
    reg [31:0] next_addr;
    reg        trace;

    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1)
            mem[i] = mem_pattern(i);
        sh32        = 32'd0;
        base_addr_r = 24'd0;
        cnt         = 32'd0;
        miso        = 1'b0;
        trace       = $test$plusargs("trace");
    end

    function [7:0] mem_pattern;
        input integer idx;
        begin
            mem_pattern = ((idx * 7 + (idx >> 8) * 13 + 32'h5A) & 32'hFF);
        end
    endfunction

    // Sample MOSI on every rising SCLK edge; the first 32 bits are {cmd, addr}.
    always @(posedge sclk or posedge ce_b) begin
        if (ce_b) sh32 <= 32'd0;
        else      sh32 <= {sh32[30:0], mosi};
    end

    // On each falling edge, present the bit that the next rising edge will sample.
    always @(negedge sclk or posedge ce_b) begin
        if (ce_b) begin
            cnt         = 32'd0;
            base_addr_r = 24'd0;
            miso       <= 1'b0;
        end else begin
            cnt = cnt + 32'd1;
            if (cnt == 32'd32) begin
                // header just completed: latch the address, then stream data
                base_addr_r = sh32[23:0];
                if (trace)
                    $display("MODEL t=%0t latch cmd=%02h addr=%06h",
                             $time, sh32[31:24], sh32[23:0]);
            end
            if (cnt >= 32'd32) begin
                next_didx = cnt - 32'd32;
                next_addr = ({8'd0, base_addr_r} - {8'd0, MEM_BASE}) + (next_didx >> 3);
                if (next_addr < MEM_SIZE)
                    miso <= mem[next_addr[19:0]][3'd7 - next_didx[2:0]];
                else
                    miso <= 1'b0;
                if (trace && next_didx < 32'd16)
                    $display("MODEL t=%0t didx=%0d addr=%0d byte=%02h bit=%b",
                             $time, next_didx, next_addr,
                             mem[next_addr[19:0]],
                             mem[next_addr[19:0]][3'd7 - next_didx[2:0]]);
            end else begin
                miso <= 1'b0;
            end
        end
    end

endmodule

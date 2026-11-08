module debouncer #(
    parameter C_WIDTH = 10
) (
    input  wire clk,
    input  wire input_to_debounce,
    output reg  debounced_signal = 1'b0
);

    reg input_to_debounce_d1 = 1'b0;
    reg [C_WIDTH-1:0] us_count_value;

    always @(posedge clk) begin
        input_to_debounce_d1 <= input_to_debounce;

        if (input_to_debounce != input_to_debounce_d1)
            us_count_value = 0;
        else if (!us_count_value[C_WIDTH-1])
            us_count_value = us_count_value + 1;

        if (us_count_value[C_WIDTH-1])
            debounced_signal <= input_to_debounce_d1;
    end

endmodule

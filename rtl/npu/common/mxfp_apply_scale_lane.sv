`timescale 1ns/1ps
`default_nettype none

// Applies an E8M0 block scale while retaining an FP32-shaped value.  Keeping
// this step explicit lets high-throughput users register the scale adjustment
// before the FP8/FP4 rounding network.
module mxfp_apply_scale_lane (
    input  logic [31:0]                  data_i,
    input  mxfp_pkg::mxfp_scale_t       scale_i,
    output logic [31:0]                  data_o
);

    logic signed [10:0] scaled_exponent;

    always_comb begin
        data_o = data_i;
        scaled_exponent = $signed({3'd0, data_i[30:23]}) -
            $signed({3'd0, scale_i}) + 11'sd127;
        if ((data_i[30:23] != 8'h00) && (data_i[30:23] != 8'hff)) begin
            if (scaled_exponent >= 11'sd255) begin
                data_o[30:23] = 8'hfe;
                data_o[22:0] = 23'h7fffff;
            end else if (scaled_exponent <= 11'sd0) begin
                data_o[30:0] = 31'd0;
            end else begin
                data_o[30:23] = scaled_exponent[7:0];
            end
        end
    end

endmodule

`default_nettype wire

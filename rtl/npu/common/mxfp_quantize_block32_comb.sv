`timescale 1ns/1ps
`default_nettype none

// Combinational MX block quantizer. One E8M0 scale is selected from all 32
// FP32 elements before the individual MXFP4/MXFP8 encoders are evaluated.
module mxfp_quantize_block32_comb (
    input  logic [1023:0]                  block_data_i,
    input  mxfp_pkg::mxfp_format_e        format_i,
    output logic [255:0]                   block_data_o,
    output mxfp_pkg::mxfp_scale_t         scale_o,
    output logic [31:0]                    overflow_o,
    output logic [31:0]                    inexact_o
);

    logic [7:0] quantized_lane [0:31];

    always_comb begin
        block_data_o = '0;
        for (integer lane = 0; lane < 32; lane++) begin
            if (format_i == mxfp_pkg::MXFP4_E2M1) begin
                block_data_o[lane*4 +: 4] = quantized_lane[lane][3:0];
            end else begin
                block_data_o[lane*8 +: 8] = quantized_lane[lane];
            end
        end
    end

    mxfp_scale_block32 u_scale (
        .block_data_i(block_data_i),
        .format_i(format_i),
        .scale_o(scale_o)
    );

    generate
        for (genvar lane = 0; lane < 32; lane++) begin : g_lane
            mxfp_quantize_lane u_quantize_lane (
                .data_i(block_data_i[lane*32 +: 32]),
                .format_i(format_i),
                .scale_i(scale_o),
                .data_o(quantized_lane[lane]),
                .overflow_o(overflow_o[lane]),
                .inexact_o(inexact_o[lane])
            );
        end
    endgenerate

endmodule

`default_nettype wire

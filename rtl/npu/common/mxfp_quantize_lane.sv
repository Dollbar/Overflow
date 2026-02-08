`timescale 1ns/1ps
`default_nettype none

// Quantizes one FP32 value using an externally selected E8M0 block scale.
module mxfp_quantize_lane (
    input  logic [31:0]                  data_i,
    input  mxfp_pkg::mxfp_format_e      format_i,
    input  mxfp_pkg::mxfp_scale_t       scale_i,
    output logic [7:0]                   data_o,
    output logic                         overflow_o,
    output logic                         inexact_o
);

    logic [31:0] scaled_data;
    logic [7:0] fp8_data;
    logic fp8_overflow;
    logic fp8_inexact;
    logic [2:0] fp4_main;
    logic [3:0] fp4_rounded;
    logic fp4_guard;
    logic fp4_sticky;
    logic fp4_increment;
    logic fp4_overflow;
    logic signed [10:0] fp4_exponent;

    mxfp_apply_scale_lane u_apply_scale (
        .data_i(data_i),
        .scale_i(scale_i),
        .data_o(scaled_data)
    );

    fp32_to_fp8 u_fp8_quantizer (
        .data_i(scaled_data),
        .data_o(fp8_data),
        .overflow_o(fp8_overflow), .inexact_o(fp8_inexact)
    );

    always_comb begin
        fp4_main = 3'd0;
        fp4_guard = 1'b0;
        fp4_sticky = 1'b0;
        fp4_overflow = 1'b0;
        fp4_exponent = $signed({3'd0, scaled_data[30:23]}) - 11'sd127;
        if ((scaled_data[30:23] != 8'h00) &&
            (scaled_data[30:23] != 8'hff)) begin
            if (fp4_exponent > 11'sd2) begin
                fp4_main = 3'b111;
                fp4_sticky = 1'b1;
                fp4_overflow = 1'b1;
            end else if (fp4_exponent == 11'sd2) begin
                fp4_main = {2'b11, scaled_data[22]};
                fp4_guard = scaled_data[21];
                fp4_sticky = |scaled_data[20:0];
                fp4_overflow = scaled_data[22:0] > 23'h400000;
            end else if (fp4_exponent == 11'sd1) begin
                fp4_main = {2'b10, scaled_data[22]};
                fp4_guard = scaled_data[21];
                fp4_sticky = |scaled_data[20:0];
            end else if (fp4_exponent >= 11'sd0) begin
                fp4_main = {2'b01, scaled_data[22]};
                fp4_guard = scaled_data[21];
                fp4_sticky = |scaled_data[20:0];
            end else if (fp4_exponent == -11'sd1) begin
                fp4_main = 3'b001;
                fp4_guard = scaled_data[22];
                fp4_sticky = |scaled_data[21:0];
            end else if (fp4_exponent == -11'sd2) begin
                fp4_main = 3'b000;
                fp4_guard = 1'b1;
                fp4_sticky = |scaled_data[22:0];
            end else begin
                fp4_main = 3'b000;
                fp4_guard = 1'b0;
                fp4_sticky = |scaled_data[30:0];
            end
        end
        fp4_increment = fp4_guard && (fp4_sticky || fp4_main[0]);
        fp4_rounded = {1'b0, fp4_main} + fp4_increment;
        data_o = fp8_data;
        overflow_o = fp8_overflow;
        inexact_o = fp8_inexact;
        if (format_i == mxfp_pkg::MXFP4_E2M1) begin
            data_o = {4'd0, scaled_data[31],
                fp4_rounded[3] ? 3'b111 : fp4_rounded[2:0]};
            overflow_o = fp4_overflow || fp4_rounded[3];
            inexact_o = fp4_guard || fp4_sticky || fp4_overflow;
            if ((scaled_data[30:23] == 8'h00) &&
                (scaled_data[22:0] == 23'd0)) begin
                data_o = {4'd0, scaled_data[31], 3'b000};
                overflow_o = 1'b0;
                inexact_o = 1'b0;
            end else if ((scaled_data[30:23] == 8'hff) &&
                         (scaled_data[22:0] == 23'd0)) begin
                data_o = {4'd0, scaled_data[31], 3'b111};
                overflow_o = 1'b1;
                inexact_o = 1'b0;
            end
        end
        if ((scaled_data[30:23] == 8'hff) &&
            (scaled_data[22:0] != 23'd0)) begin
            data_o = (format_i == mxfp_pkg::MXFP4_E2M1) ? 8'h07 : fp8_data;
        end
        if ((format_i != mxfp_pkg::MXFP4_E2M1) &&
            (format_i != mxfp_pkg::MXFP8_E4M3)) begin
            data_o = 8'h7f;
            overflow_o = 1'b0;
            inexact_o = 1'b0;
        end
    end

endmodule

`default_nettype wire

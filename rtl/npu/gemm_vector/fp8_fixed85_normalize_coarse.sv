`timescale 1ns/1ps
`default_nettype none

module fp8_fixed85_normalize_coarse (
    input  logic        [84:0] magnitude_i,
    input  logic         [6:0] msb_index_i,
    input  logic               nonzero_i,
    output logic        [84:0] coarse_magnitude_o,
    output logic         [2:0] fine_shift_o,
    output logic               shift_right_o,
    output logic               sticky_o,
    output logic signed [10:0] exponent_o
);

    logic [6:0] total_shift;
    logic [3:0] coarse_group;

    always_comb begin
        coarse_magnitude_o = 85'd0;
        fine_shift_o = 3'd0;
        shift_right_o = 1'b0;
        sticky_o = 1'b0;
        exponent_o = 11'sd0;
        total_shift = 7'd0;
        coarse_group = 4'd0;

        if (nonzero_i) begin
            exponent_o = $signed({4'b0000, msb_index_i}) - 11'sd32;
            if (msb_index_i >= 7'd26) begin
                shift_right_o = 1'b1;
                total_shift = msb_index_i - 7'd26;
                fine_shift_o = total_shift[2:0];
                coarse_group = total_shift[6:3];
                case (coarse_group)
                    4'd0: begin
                        coarse_magnitude_o = magnitude_i;
                        sticky_o = 1'b0;
                    end
                    4'd1: begin
                        coarse_magnitude_o = magnitude_i >> 8;
                        sticky_o = |magnitude_i[7:0];
                    end
                    4'd2: begin
                        coarse_magnitude_o = magnitude_i >> 16;
                        sticky_o = |magnitude_i[15:0];
                    end
                    4'd3: begin
                        coarse_magnitude_o = magnitude_i >> 24;
                        sticky_o = |magnitude_i[23:0];
                    end
                    4'd4: begin
                        coarse_magnitude_o = magnitude_i >> 32;
                        sticky_o = |magnitude_i[31:0];
                    end
                    4'd5: begin
                        coarse_magnitude_o = magnitude_i >> 40;
                        sticky_o = |magnitude_i[39:0];
                    end
                    4'd6: begin
                        coarse_magnitude_o = magnitude_i >> 48;
                        sticky_o = |magnitude_i[47:0];
                    end
                    4'd7: begin
                        coarse_magnitude_o = magnitude_i >> 56;
                        sticky_o = |magnitude_i[55:0];
                    end
                    default: begin
                        coarse_magnitude_o = 85'd0;
                        sticky_o = |magnitude_i;
                    end
                endcase
            end else begin
                total_shift = 7'd26 - msb_index_i;
                fine_shift_o = total_shift[2:0];
                coarse_group = total_shift[6:3];
                case (coarse_group)
                    4'd0: coarse_magnitude_o = magnitude_i;
                    4'd1: coarse_magnitude_o = magnitude_i << 8;
                    4'd2: coarse_magnitude_o = magnitude_i << 16;
                    4'd3: coarse_magnitude_o = magnitude_i << 24;
                    default: coarse_magnitude_o = 85'd0;
                endcase
            end
        end
    end

endmodule

`default_nettype wire

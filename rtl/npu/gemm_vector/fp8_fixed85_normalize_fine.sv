`timescale 1ns/1ps
`default_nettype none

module fp8_fixed85_normalize_fine (
    input  logic [84:0] coarse_magnitude_i,
    input  logic  [2:0] fine_shift_i,
    input  logic        shift_right_i,
    input  logic        sticky_i,
    output logic [26:0] significand_o
);

    /* verilator lint_off UNUSEDSIGNAL */
    logic [84:0] shifted_magnitude;
    /* verilator lint_on UNUSEDSIGNAL */
    logic fine_sticky;

    always_comb begin
        shifted_magnitude = 85'd0;
        fine_sticky = sticky_i;
        significand_o = 27'd0;
        if (shift_right_i) begin
            shifted_magnitude = coarse_magnitude_i >> fine_shift_i;
            case (fine_shift_i)
                3'd0: fine_sticky = sticky_i;
                3'd1: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[0:0]);
                3'd2: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[1:0]);
                3'd3: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[2:0]);
                3'd4: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[3:0]);
                3'd5: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[4:0]);
                3'd6: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[5:0]);
                3'd7: fine_sticky = sticky_i ||
                                         (|coarse_magnitude_i[6:0]);
                default: fine_sticky = sticky_i;
            endcase
            significand_o = shifted_magnitude[26:0];
            significand_o[0] = shifted_magnitude[0] | fine_sticky;
        end else begin
            shifted_magnitude = coarse_magnitude_i << fine_shift_i;
            significand_o = shifted_magnitude[26:0];
        end
    end

endmodule

`default_nettype wire

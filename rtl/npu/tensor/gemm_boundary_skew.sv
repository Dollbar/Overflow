`timescale 1ns/1ps
`default_nettype none

// Converts a dense, lane-parallel stream into the diagonal wavefront required
// at a systolic-array boundary. Lane n is delayed by exactly n cycles. The
// payload delay is coupled to the valid delay so back-to-back matrices can use
// the boundary every cycle without inserting a bubble.
module gemm_boundary_skew #(
    parameter int unsigned LANES = 256,
    parameter int unsigned PAYLOAD_WIDTH = 32
) (
    input  logic                           clk_i,
    input  logic                           rst_i,
    input  logic                           clear_i,
    input  logic             [LANES-1:0]   valid_i,
    input  logic [LANES*PAYLOAD_WIDTH-1:0] payload_i,
    output logic             [LANES-1:0]   valid_o,
    output logic [LANES*PAYLOAD_WIDTH-1:0] payload_o
);

    generate
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane_delay
            if (lane == 0) begin : g_no_delay
                always_comb begin
                    valid_o[lane] = valid_i[lane];
                    payload_o[lane*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                        payload_i[lane*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
                end
            end else begin : g_delay
                logic [lane-1:0] valid_q;
                logic [PAYLOAD_WIDTH-1:0] payload_q [0:lane-1];

                always_ff @(posedge clk_i) begin
                    if (rst_i || clear_i) begin
                        valid_q <= '0;
                    end else begin
                        valid_q[0] <= valid_i[lane];
                        payload_q[0] <=
                            payload_i[lane*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
                        for (integer stage = 1; stage < lane; stage++) begin
                            valid_q[stage] <= valid_q[stage-1];
                            payload_q[stage] <= payload_q[stage-1];
                        end
                    end
                end

                always_comb begin
                    valid_o[lane] = valid_q[lane-1];
                    payload_o[lane*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                        payload_q[lane-1];
                end
            end
        end
    endgenerate

    initial begin
        assert (LANES > 0)
            else $error("gemm_boundary_skew LANES must be positive");
        assert (PAYLOAD_WIDTH > 0)
            else $error("gemm_boundary_skew PAYLOAD_WIDTH must be positive");
    end

endmodule

`default_nettype wire

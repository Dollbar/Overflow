`timescale 1ns/1ps
`default_nettype none

// Equal-depth registered distribution tree for synchronous array controls.
// A control value crosses root, branch, and leaf registers before reaching every
// consumer.  NODE_COUNT need not be an integer multiple of BRANCH_FANOUT.
module gemm_control_tree #(
    parameter integer NODE_COUNT = 256,
    parameter integer BRANCH_FANOUT = 16
) (
    input  logic                  clk_i,
    input  logic                  control_i,
    output logic [NODE_COUNT-1:0] control_o
);

    localparam integer BRANCH_COUNT =
        (NODE_COUNT + BRANCH_FANOUT - 1) / BRANCH_FANOUT;

    logic root_q;
    logic [BRANCH_COUNT-1:0] branch_q;
    logic [NODE_COUNT-1:0] leaf_q;

    assign control_o = leaf_q;

    (* keep = "true", dont_touch = "true" *)
    gemm_control_tree_register #(
        .REGISTER_ID (0)
    ) u_root_register (
        .clk_i  (clk_i),
        .data_i (control_i),
        .data_o (root_q)
    );

    generate
        for (genvar branch_index = 0; branch_index < BRANCH_COUNT;
             branch_index = branch_index + 1) begin : gen_branch
            (* keep = "true", dont_touch = "true" *)
            gemm_control_tree_register #(
                .REGISTER_ID (1 + branch_index)
            ) u_branch_register (
                .clk_i  (clk_i),
                .data_i (root_q),
                .data_o (branch_q[branch_index])
            );
        end

        for (genvar leaf_index = 0; leaf_index < NODE_COUNT;
             leaf_index = leaf_index + 1) begin : gen_leaf
            localparam integer PARENT_BRANCH = leaf_index / BRANCH_FANOUT;

            (* keep = "true", dont_touch = "true" *)
            gemm_control_tree_register #(
                .REGISTER_ID (1 + BRANCH_COUNT + leaf_index)
            ) u_leaf_register (
                .clk_i  (clk_i),
                .data_i (branch_q[PARENT_BRANCH]),
                .data_o (leaf_q[leaf_index])
            );
        end
    endgenerate

endmodule

`default_nettype wire

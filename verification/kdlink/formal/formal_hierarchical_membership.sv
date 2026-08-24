`include "kdlink_defs.vh"
module formal_hierarchical_membership;
    (* gclk *) reg clk;
    (* anyconst *) reg [2:0] opcode;
    (* anyseq *) reg command_ready;
    reg past_valid;
    reg [4:0] cycle_q;
    wire rst_n;
    wire descriptor_valid;
    wire command_valid;
    wire [1:0] command_phase;
    wire [7:0] command_destination;
    wire descriptor_error;
    wire opcode_valid;
    reg [1:0] observed_phase_q;
    initial begin
        past_valid = 1'b0;
        cycle_q = 5'd0;
        observed_phase_q = `KDL_HIER_PHASE_LEAF_PREPARE;
    end
    assign rst_n = past_valid;
    assign descriptor_valid = cycle_q == 5'd2;
    assign opcode_valid = opcode <= `KDL_OPCODE_POINT_TO_POINT;
    kdlink_hierarchical_collective_ctrl u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .descriptor_valid_i(descriptor_valid), .descriptor_ready_o(),
        .descriptor_opcode_i(opcode), .descriptor_group_id_i(32'h1), .descriptor_transaction_id_i(64'h2),
        .descriptor_topology_epoch_i(8'd3), .descriptor_local_domain_i(8'd0),
        .descriptor_source_domain_i(8'd0), .descriptor_destination_domain_i(8'd2),
        .group_found_i(1'b1), .group_local_member_i(1'b1),
        .group_member_mask_i({253'd0, 3'b101}), .group_member_count_i(9'd2), .group_root_domain_i(8'd0),
        .command_valid_o(command_valid), .command_ready_i(command_ready), .command_phase_o(command_phase),
        .command_opcode_o(), .command_destination_domain_o(command_destination), .command_group_id_o(),
        .command_transaction_id_o(), .command_topology_epoch_o(), .command_root_domain_o(),
        .busy_o(), .descriptor_error_o(descriptor_error)
    );
    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            cycle_q <= 5'd0;
            observed_phase_q <= `KDL_HIER_PHASE_LEAF_PREPARE;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            if (opcode_valid) assert (!descriptor_error);
            if (!opcode_valid && (cycle_q >= 5'd4)) begin
                assert (descriptor_error);
                assert (!command_valid);
            end
            if (command_valid && opcode_valid) begin
                assert (command_phase >= observed_phase_q);
                if (command_ready) observed_phase_q <= command_phase;
                if (command_phase == `KDL_HIER_PHASE_INTERDOMAIN) begin
                    assert (command_destination == 8'd2);
                    assert (command_destination != 8'd0);
                end
            end
            if ($past(past_valid) && $past(command_valid) && !$past(command_ready)) begin
                assert (command_valid);
                assert (command_phase == $past(command_phase));
                assert (command_destination == $past(command_destination));
            end
        end
    end
endmodule

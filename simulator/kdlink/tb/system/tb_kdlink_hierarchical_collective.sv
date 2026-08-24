`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_hierarchical_collective;
    reg clk;
    reg rst_n;
    reg config_valid;
    reg [2:0] config_index;
    reg [31:0] config_group_id;
    reg [7:0] config_epoch;
    reg [255:0] config_mask;
    reg [8:0] config_count;
    reg [7:0] config_root;
    reg config_invalidate;
    reg descriptor_valid;
    wire descriptor_ready;
    reg [2:0] descriptor_opcode;
    reg [7:0] local_domain;
    reg [31:0] query_group_id;
    reg [7:0] query_epoch;
    reg [63:0] descriptor_transaction_id;
    reg [7:0] descriptor_source_domain;
    reg [7:0] descriptor_destination_domain;
    reg [63:0] collective_lfsr;
    wire group_found;
    wire group_local_member;
    wire [255:0] group_mask;
    wire [8:0] group_count;
    wire [7:0] group_root;
    wire command_valid;
    reg command_ready;
    wire [1:0] command_phase;
    wire [7:0] command_destination;
    wire [2:0] command_opcode;
    wire [31:0] command_group_id;
    wire [63:0] command_transaction_id;
    wire [7:0] command_topology_epoch;
    wire [7:0] command_root_domain;
    wire busy;
    wire descriptor_error;
    wire config_error;
    integer opcode;
    integer inter_count;
    integer prepare_count;
    integer finish_count;
    integer complete_count;
    integer watchdog;
    integer group_slot;
    integer stress_index;
    kdlink_group_table u_group_table (
        .clk_i(clk), .rst_n_i(rst_n), .config_valid_i(config_valid), .config_ready_o(),
        .config_index_i(config_index), .config_group_id_i(config_group_id), .config_topology_epoch_i(config_epoch),
        .config_member_mask_i(config_mask), .config_member_count_i(config_count), .config_root_domain_i(config_root),
        .config_invalidate_i(config_invalidate), .query_valid_i(1'b1), .query_group_id_i(query_group_id),
        .query_topology_epoch_i(query_epoch), .query_local_domain_i(local_domain), .query_found_o(group_found),
        .query_local_member_o(group_local_member), .query_member_mask_o(group_mask),
        .query_member_count_o(group_count), .query_root_domain_o(group_root), .config_error_o(config_error)
    );
    kdlink_hierarchical_collective_ctrl u_controller (
        .clk_i(clk), .rst_n_i(rst_n), .descriptor_valid_i(descriptor_valid), .descriptor_ready_o(descriptor_ready),
        .descriptor_opcode_i(descriptor_opcode), .descriptor_group_id_i(query_group_id),
        .descriptor_transaction_id_i(descriptor_transaction_id), .descriptor_topology_epoch_i(query_epoch),
        .descriptor_local_domain_i(local_domain), .descriptor_source_domain_i(descriptor_source_domain),
        .descriptor_destination_domain_i(descriptor_destination_domain), .group_found_i(group_found),
        .group_local_member_i(group_local_member), .group_member_mask_i(group_mask),
        .group_member_count_i(group_count), .group_root_domain_i(group_root),
        .command_valid_o(command_valid), .command_ready_i(command_ready), .command_phase_o(command_phase),
        .command_opcode_o(command_opcode), .command_destination_domain_o(command_destination), .command_group_id_o(command_group_id),
        .command_transaction_id_o(command_transaction_id), .command_topology_epoch_o(command_topology_epoch), .command_root_domain_o(command_root_domain),
        .busy_o(busy), .descriptor_error_o(descriptor_error)
    );
    always #0.5 clk = ~clk;
    function automatic [8:0] popcount256(input [255:0] value);
        integer bit_index;
        begin
            popcount256 = 0;
            for (bit_index = 0; bit_index < 256; bit_index = bit_index + 1) popcount256 = popcount256 + value[bit_index];
        end
    endfunction
    task run_descriptor;
        input [2:0] requested_opcode;
        input [7:0] requested_local_domain;
        input integer expected_inter_count;
        reg hold_active;
        reg released_last;
        reg [1:0] held_phase;
        reg [2:0] held_opcode;
        reg [7:0] held_destination;
        reg [31:0] held_group_id;
        reg [63:0] held_transaction_id;
        reg [7:0] held_epoch;
        reg [7:0] held_root;
        reg [255:0] expected_mask;
        begin
            inter_count = 0;
            prepare_count = 0;
            finish_count = 0;
            complete_count = 0;
            watchdog = 0;
            hold_active = 1'b0;
            released_last = 1'b0;
            expected_mask = config_mask;
            descriptor_opcode = requested_opcode;
            local_domain = requested_local_domain;
            command_ready = 1'b0;
            descriptor_valid = 1'b1;
            @(negedge clk);
            if (command_valid && command_ready && command_phase == `KDL_HIER_PHASE_LEAF_PREPARE) prepare_count = prepare_count + 1;
            descriptor_valid = 1'b0;
            while ((busy || complete_count == 0) && watchdog < 400) begin
                @(negedge clk);
                if (released_last) begin
                    released_last = 1'b0;
                    command_ready = 1'b0;
                end else if (hold_active) begin
                    if (!command_valid || command_phase != held_phase || command_opcode != held_opcode || command_destination != held_destination || command_group_id != held_group_id || command_transaction_id != held_transaction_id || command_topology_epoch != held_epoch || command_root_domain != held_root) $fatal(1, "hierarchical command changed under backpressure");
                    if (held_opcode != requested_opcode || held_group_id != query_group_id || held_transaction_id != descriptor_transaction_id || held_epoch != query_epoch || held_root != group_root) $fatal(1, "held hierarchical command metadata snapshot mismatch");
                    case (held_phase)
                        `KDL_HIER_PHASE_LEAF_PREPARE: prepare_count = prepare_count + 1;
                        `KDL_HIER_PHASE_INTERDOMAIN: begin
                            inter_count = inter_count + 1;
                            if (!expected_mask[held_destination] || held_destination == local_domain) $fatal(1, "held interdomain command targets a non-member or local domain destination=%0d local=%0d member=%0d opcode=%0d", held_destination, local_domain, expected_mask[held_destination], requested_opcode);
                        end
                        `KDL_HIER_PHASE_LEAF_FINISH: finish_count = finish_count + 1;
                        `KDL_HIER_PHASE_COMPLETE: complete_count = complete_count + 1;
                        default: $fatal(1, "unknown held hierarchical phase");
                    endcase
                    hold_active = 1'b0;
                    command_ready = 1'b1;
                    released_last = 1'b1;
                end else if (command_valid) begin
                    hold_active = 1'b1;
                    held_phase = command_phase;
                    held_opcode = command_opcode;
                    held_destination = command_destination;
                    held_group_id = command_group_id;
                    held_transaction_id = command_transaction_id;
                    held_epoch = command_topology_epoch;
                    held_root = command_root_domain;
                    command_ready = 1'b0;
                end else command_ready = 1'b0;
                watchdog = watchdog + 1;
            end
            if (watchdog >= 400 || prepare_count != 1 || finish_count != 1 || complete_count != 1 || inter_count != expected_inter_count) begin
                $display("sequence opcode=%0d local=%0d watchdog=%0d prepare=%0d inter=%0d finish=%0d complete=%0d expected_inter=%0d", requested_opcode, requested_local_domain, watchdog, prepare_count, inter_count, finish_count, complete_count, expected_inter_count);
                $fatal(1, "hierarchical command sequence mismatch");
            end
        end
    endtask
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        config_valid = 1'b0;
        config_index = 3'd0;
        config_group_id = 32'h1122_3344;
        config_epoch = 8'd19;
        config_mask = 256'd0;
        config_mask[0] = 1'b1;
        config_mask[8] = 1'b1;
        config_mask[63] = 1'b1;
        config_mask[255] = 1'b1;
        config_count = 9'd4;
        config_root = 8'd0;
        config_invalidate = 1'b0;
        descriptor_valid = 1'b0;
        descriptor_opcode = 3'd0;
        local_domain = 8'd0;
        query_group_id = 32'h1122_3344;
        query_epoch = 8'd19;
        descriptor_transaction_id = 64'h0123_4567_89ab_cdef;
        descriptor_source_domain = 8'd0;
        descriptor_destination_domain = 8'd255;
        collective_lfsr = 64'ha076_1d64_78bd_642f;
        command_ready = 1'b1;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(negedge clk);
        @(negedge clk);
        #0.01;
        if (!group_found || !group_local_member || group_count != 4 || group_root != 0 || config_error) $fatal(1, "group table configuration mismatch");
        for (group_slot = 1; group_slot < 4; group_slot = group_slot + 1) begin
            config_index = group_slot[2:0];
            config_group_id = 32'hffff_0000 | {29'd0, group_slot[2:0]};
            config_epoch = {4'hf, 1'b0, group_slot[2:0]};
            config_mask = {256{1'b1}} ^ {224'd0, group_slot[31:0]};
            config_mask[0] = 1'b1;
            config_count = popcount256(config_mask);
            config_root = 8'd0;
            config_valid = 1'b1;
            @(negedge clk);
            config_valid = 1'b0;
            @(negedge clk);
            @(negedge clk);
        end
        config_index = 3'd0;
        config_group_id = 32'h1122_3344;
        config_epoch = 8'd19;
        config_mask = 256'd0;
        config_mask[0] = 1'b1;
        config_mask[8] = 1'b1;
        config_mask[63] = 1'b1;
        config_mask[255] = 1'b1;
        config_count = 9'd4;
        for (opcode = 0; opcode < 5; opcode = opcode + 1) run_descriptor(opcode[2:0], 8'd0, 3);
        run_descriptor(`KDL_OPCODE_POINT_TO_POINT, 8'd0, 1);
        run_descriptor(`KDL_OPCODE_POINT_TO_POINT, 8'd255, 0);
        for (stress_index = 0; stress_index < 128; stress_index = stress_index + 1) begin
            collective_lfsr = {collective_lfsr[62:0], collective_lfsr[63] ^ collective_lfsr[62] ^ collective_lfsr[60] ^ collective_lfsr[59]};
            config_index = {1'b0, stress_index[1:0]};
            config_group_id = collective_lfsr[31:0] ^ {25'd0, stress_index[6:0]};
            config_epoch = collective_lfsr[39:32];
            descriptor_source_domain = collective_lfsr[47:40];
            descriptor_destination_domain = collective_lfsr[47:40] + 8'd1;
            config_root = collective_lfsr[63:56];
            config_mask = {collective_lfsr, ~collective_lfsr, collective_lfsr ^ 64'h5a5a_a5a5_3c3c_c3c3, collective_lfsr ^ 64'hc3c3_3c3c_a5a5_5a5a};
            config_mask[descriptor_source_domain] = 1'b1;
            config_mask[descriptor_destination_domain] = 1'b1;
            config_mask[config_root] = 1'b1;
            config_count = popcount256(config_mask);
            config_valid = 1'b1;
            @(negedge clk);
            config_valid = 1'b0;
            @(negedge clk);
            @(negedge clk);
            query_group_id = config_group_id;
            query_epoch = config_epoch;
            descriptor_transaction_id = collective_lfsr ^ {57'd0, stress_index[6:0]};
            run_descriptor(`KDL_OPCODE_POINT_TO_POINT, descriptor_source_domain, 1);
        end
        config_index = 3'd0;
        config_group_id = 32'h1122_3344;
        config_epoch = 8'd19;
        config_mask = 256'd0;
        config_mask[0] = 1'b1;
        config_mask[8] = 1'b1;
        config_mask[63] = 1'b1;
        config_mask[255] = 1'b1;
        config_count = 9'd4;
        config_root = 8'd0;
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(negedge clk);
        @(negedge clk);
        query_group_id = 32'h1122_3344;
        query_epoch = 8'd19;
        descriptor_source_domain = 8'd0;
        descriptor_destination_domain = 8'd255;
        local_domain = 8'd7;
        descriptor_opcode = `KDL_OPCODE_ALL_REDUCE;
        descriptor_valid = 1'b1;
        @(negedge clk);
        descriptor_valid = 1'b0;
        repeat (2) @(negedge clk);
        if (!descriptor_error || busy) $fatal(1, "non-member descriptor was not rejected");
        local_domain = 8'd0;
        descriptor_opcode = 3'd7;
        descriptor_valid = 1'b1;
        @(negedge clk);
        descriptor_valid = 1'b0;
        repeat (2) @(negedge clk);
        if (busy || command_valid) $fatal(1, "reserved collective opcode was accepted");
        descriptor_opcode = `KDL_OPCODE_ALL_REDUCE;
        query_group_id = 32'hdead_beef;
        #0.1;
        descriptor_valid = 1'b1;
        @(negedge clk);
        descriptor_valid = 1'b0;
        repeat (2) @(negedge clk);
        if (busy || command_valid) $fatal(1, "missing group descriptor was accepted");
        query_group_id = 32'h1122_3344;
        descriptor_opcode = `KDL_OPCODE_POINT_TO_POINT;
        descriptor_source_domain = 8'd0;
        descriptor_destination_domain = 8'd0;
        #0.1;
        descriptor_valid = 1'b1;
        @(negedge clk);
        descriptor_valid = 1'b0;
        repeat (2) @(negedge clk);
        if (busy || command_valid) $fatal(1, "point-to-point self destination was accepted");
        if (config_error) $fatal(1, "legal group-table stress unexpectedly raised a configuration error");
        config_index = 3'd0;
        config_group_id = 32'hdead_0001;
        config_epoch = 8'd20;
        config_mask = 256'd1;
        config_count = 9'd2;
        config_root = 8'd0;
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(negedge clk);
        @(negedge clk);
        query_group_id = 32'hdead_0001;
        query_epoch = 8'd20;
        #0.1;
        if (group_found || !config_error) $fatal(1, "member-count mismatch was not rejected");
        config_index = 3'd1;
        config_group_id = 32'h1122_3344;
        config_epoch = 8'd19;
        config_mask = 256'd1;
        config_count = 9'd1;
        config_root = 8'd0;
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(negedge clk);
        @(negedge clk);
        query_group_id = 32'h1122_3344;
        query_epoch = 8'd19;
        #0.1;
        if (!group_found || group_count != 9'd4) $fatal(1, "duplicate exact group key displaced the original entry");
        config_index = 3'd2;
        config_group_id = 32'hdead_0002;
        config_epoch = 8'd21;
        config_mask = 256'd2;
        config_count = 9'd1;
        config_root = 8'd0;
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(negedge clk);
        @(negedge clk);
        query_group_id = 32'hdead_0002;
        query_epoch = 8'd21;
        #0.1;
        if (group_found) $fatal(1, "group root outside the member mask was accepted");
        config_index = 3'd4;
        config_group_id = 32'hdead_0003;
        config_epoch = 8'd22;
        config_mask = 256'd1;
        config_count = 9'd1;
        config_root = 8'd0;
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(negedge clk);
        @(negedge clk);
        query_group_id = 32'hdead_0003;
        query_epoch = 8'd22;
        #0.1;
        if (group_found) $fatal(1, "out-of-range group-table index was accepted");
        config_index = 3'd0;
        config_invalidate = 1'b1;
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        config_invalidate = 1'b0;
        @(negedge clk);
        @(negedge clk);
        query_group_id = 32'h1122_3344;
        query_epoch = 8'd19;
        #0.1;
        if (group_found) $fatal(1, "valid group-table invalidation did not remove the entry");
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        force u_controller.state_q = 3'd7;
        @(negedge clk);
        release u_controller.state_q;
        @(negedge clk);
        #0.1;
        if (u_controller.state_q != 3'd0 || !descriptor_error) $fatal(1, "illegal controller state did not recover to idle");
        $display("TB_KDLINK_HIERARCHICAL_COLLECTIVE_PASS");
        $finish;
    end
endmodule

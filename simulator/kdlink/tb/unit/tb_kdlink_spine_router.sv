`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_spine_router;
    logic clk;
    logic rst_n;
    logic [3:0] domain_count;
    logic [7:0] active_domain_mask;
    logic ingress_valid;
    wire ingress_ready;
    logic [639:0] ingress_flit;
    wire [7:0] egress_valid;
    logic [7:0] egress_ready;
    wire [5119:0] egress_flit;
    wire route_active;
    wire [2:0] selected_egress;
    wire protocol_error;
    wire escape_violation;
    integer route_count;
    integer backpressure_count;
    integer domain_index;

    always #1 clk = ~clk;

    kdlink_spine_router u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .domain_count_i(domain_count),
        .active_domain_mask_i(active_domain_mask), .ingress_valid_i(ingress_valid),
        .ingress_ready_o(ingress_ready), .ingress_flit_i(ingress_flit),
        .egress_valid_o(egress_valid), .egress_ready_i(egress_ready),
        .egress_flit_o(egress_flit), .route_active_o(route_active),
        .selected_egress_o(selected_egress), .protocol_error_o(protocol_error),
        .escape_violation_o(escape_violation)
    );

    task automatic drive_context;
        input integer destination_domain;
        input [11:0] context_sequence;
        input [11:0] data_sequence;
        input bit apply_backpressure;
        reg [95:0] header_value;
        reg [511:0] payload_value;
        begin
            header_value = 96'd0;
            header_value[3:0] = `KDL_ROUTE_SCHEMA;
            header_value[7:4] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            header_value[15:13] = `KDL_VC_ROLE_POINT_TO_POINT;
            header_value[17] = 1'b1;
            header_value[18] = 1'b1;
            header_value[24:20] = 5'd3;
            header_value[29:25] = 5'd29;
            header_value[32:30] = 3'd2;
            header_value[37:33] = 5'd3;
            header_value[45:38] = 8'h2a;
            header_value[57:46] = 12'h710;
            header_value[81:70] = context_sequence;
            header_value[94:88] = 7'd64;
            payload_value = 512'd0;
            payload_value[7:0] = 8'd0;
            payload_value[15:8] = destination_domain[7:0];
            payload_value[20:16] = 5'd3;
            payload_value[25:21] = 5'd29;
            payload_value[33:26] = 8'd9;
            payload_value[41:34] = 8'd2;
            payload_value[44:42] = 3'd2;
            payload_value[46:45] = 2'b11;
            payload_value[54:50] = 5'd1;
            payload_value[66:55] = data_sequence;
            payload_value[130:67] = 64'h7000_0000_0000_0000 + {61'd0, destination_domain[2:0]};
            payload_value[162:131] = 32'h7000_0000;
            payload_value[165:163] = `KDL_VC_ROLE_POINT_TO_POINT;
            @(negedge clk);
            ingress_flit = {32'd0, header_value, payload_value};
            ingress_valid = 1'b1;
            if (apply_backpressure) begin
                egress_ready[destination_domain] = 1'b0;
                @(posedge clk);
                if (ingress_ready || egress_valid != (8'b1 << destination_domain)) $fatal(1, "spine context backpressure decode mismatch domain=%0d", destination_domain);
                if (egress_flit[destination_domain*640 + 34 +: 8] != 8'd1) $fatal(1, "spine hop decrement changed under backpressure");
                backpressure_count = backpressure_count + 1;
                @(negedge clk);
                egress_ready[destination_domain] = 1'b1;
            end
            @(posedge clk);
            if (!ingress_ready || egress_valid != (8'b1 << destination_domain)) $fatal(1, "spine context egress mismatch domain=%0d valid=%b", destination_domain, egress_valid);
            if (egress_flit[destination_domain*640 + 34 +: 8] != 8'd1) $fatal(1, "spine did not decrement domain hop limit domain=%0d", destination_domain);
            @(negedge clk);
            ingress_valid = 1'b0;
            ingress_flit = 640'd0;
            if (!route_active || selected_egress != destination_domain[2:0]) $fatal(1, "spine did not lock selected egress domain=%0d", destination_domain);
        end
    endtask

    task automatic drive_data;
        input integer destination_domain;
        input [11:0] data_sequence;
        reg [95:0] header_value;
        reg [511:0] payload_value;
        begin
            header_value = 96'd0;
            header_value[3:0] = `KDL_SCHEMA_VERSION;
            header_value[7:4] = `KDL_MESSAGE_TYPE_DATA;
            header_value[10:8] = `KDL_OPCODE_POINT_TO_POINT;
            header_value[15:13] = `KDL_VC_ROLE_POINT_TO_POINT;
            header_value[17] = 1'b1;
            header_value[18] = 1'b1;
            header_value[24:20] = 5'd3;
            header_value[29:25] = 5'd29;
            header_value[32:30] = 3'd2;
            header_value[37:33] = 5'd3;
            header_value[45:38] = 8'h2a;
            header_value[57:46] = 12'h710;
            header_value[81:70] = data_sequence;
            header_value[94:88] = 7'd64;
            payload_value = {512{1'b1}};
            payload_value[31:0] = 32'h5a00_0000 | {24'd0, destination_domain[7:0]};
            @(negedge clk);
            ingress_flit = {32'd0, header_value, payload_value};
            ingress_valid = 1'b1;
            @(posedge clk);
            if (!ingress_ready || egress_valid != (8'b1 << destination_domain)) $fatal(1, "spine packet egress mismatch domain=%0d valid=%b", destination_domain, egress_valid);
            if (egress_flit[destination_domain*640 +: 32] != (32'h5a00_0000 | {24'd0, destination_domain[7:0]})) $fatal(1, "spine packet payload mismatch domain=%0d", destination_domain);
            @(negedge clk);
            ingress_valid = 1'b0;
            ingress_flit = 640'd0;
            if (route_active) $fatal(1, "spine retained route lock after EOP domain=%0d", destination_domain);
            route_count = route_count + 1;
        end
    endtask

    task automatic exercise_profile;
        input integer profile_domains;
        integer profile_index;
        begin
            domain_count = profile_domains[3:0];
            active_domain_mask = (profile_domains == 4) ? 8'h0f : 8'hff;
            for (profile_index = 0; profile_index < profile_domains; profile_index = profile_index + 1) begin
                drive_context(profile_index, 12'(16 + profile_domains*16 + profile_index*2), 12'(17 + profile_domains*16 + profile_index*2), profile_index == profile_domains-1);
                drive_data(profile_index, 12'(17 + profile_domains*16 + profile_index*2));
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        domain_count = 4'd4;
        active_domain_mask = 8'h0f;
        ingress_valid = 1'b0;
        ingress_flit = 640'd0;
        egress_ready = 8'hff;
        route_count = 0;
        backpressure_count = 0;
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        exercise_profile(4);
        exercise_profile(8);
        if (protocol_error || escape_violation) $fatal(1, "valid spine profiles raised error protocol=%b escape=%b", protocol_error, escape_violation);
        domain_count = 4'd8;
        active_domain_mask = 8'hff;
        @(negedge clk);
        ingress_flit = 640'd0;
        ingress_flit[515:512] = `KDL_ROUTE_SCHEMA;
        ingress_flit[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
        ingress_flit[527:525] = `KDL_VC_ROLE_POINT_TO_POINT;
        ingress_flit[529] = 1'b1;
        ingress_flit[530] = 1'b1;
        ingress_flit[606:600] = 7'd64;
        ingress_flit[15:8] = 8'd7;
        ingress_flit[20:16] = 5'd3;
        ingress_flit[25:21] = 5'd29;
        ingress_flit[41:34] = 8'd1;
        ingress_flit[44:42] = 3'd2;
        ingress_flit[46:45] = 2'b11;
        ingress_flit[54:50] = 5'd1;
        ingress_flit[66:55] = 12'd99;
        ingress_flit[165:163] = `KDL_VC_ROLE_POINT_TO_POINT;
        ingress_valid = 1'b1;
        @(posedge clk);
        if (!ingress_ready || egress_valid != 8'd0) $fatal(1, "exhausted spine route was not consumed and rejected");
        @(negedge clk); ingress_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (!protocol_error || !escape_violation) $fatal(1, "exhausted spine route did not latch escape error");
        if (route_count != 12 || backpressure_count != 2) $fatal(1, "spine profile coverage mismatch routes=%0d backpressure=%0d", route_count, backpressure_count);
        $display("TB_KDLINK_SPINE_ROUTER_PASS profiles=4,8 destinations=12 hop_decrement=12 packet_lock=12 backpressure=2 exhausted_route_reject=1 leaf_up_spine_leaf_down=1");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "KDLink spine router timeout routes=%0d", route_count);
    end
endmodule

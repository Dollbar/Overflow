`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_route_stage_scale;
    reg clk;
    reg rst_n;
    reg ingress_valid;
    wire ready0;
    wire ready1;
    wire ready2;
    reg [639:0] ingress_flit;
    wire [7:0] valid0;
    wire [7:0] valid1;
    wire [7:0] valid2;
    wire [5119:0] flit0;
    wire [5119:0] flit1;
    wire [5119:0] flit2;
    wire [2:0] select0;
    wire [2:0] select1;
    wire [2:0] select2;
    wire final0;
    wire final1;
    wire final2;
    wire error0;
    wire error1;
    wire error2;
    wire escape0;
    wire escape1;
    wire escape2;
    reg [7:0] destination_domain;
    reg [7:0] source_domain;
    reg [4:0] source_node;
    reg [4:0] destination_node;
    reg [7:0] topology_epoch;
    reg [2:0] logical_plane;
    reg [2:0] logical_vc;
    reg [31:0] group_id;
    reg [63:0] global_transaction_id;
    reg [7:0] active_mask0;
    reg [7:0] active_mask1;
    reg [7:0] active_mask2;
    wire [7:0] ready_mask0;
    wire [7:0] ready_mask1;
    reg [7:0] ready_mask2;
    wire chain_valid1;
    wire chain_valid2;
    wire [639:0] chain_flit1;
    wire [639:0] chain_flit2;
    reg [63:0] route_lfsr;
    reg [11:0] packet_sequence;
    reg [4:0] packet_flit_count;
    wire [511:0] route_payload;
    integer destination;
    integer flit_index;
    reg [639:0] context_flit;
    reg [639:0] data_flit;
    assign chain_valid1 = |valid0;
    assign chain_valid2 = |valid1;
    assign chain_flit1 = flit0[639:0] | flit0[1279:640] | flit0[1919:1280] | flit0[2559:1920] | flit0[3199:2560] | flit0[3839:3200] | flit0[4479:3840] | flit0[5119:4480];
    assign chain_flit2 = flit1[639:0] | flit1[1279:640] | flit1[1919:1280] | flit1[2559:1920] | flit1[3199:2560] | flit1[3839:3200] | flit1[4479:3840] | flit1[5119:4480];
    assign ready_mask0 = {8{ready1}};
    assign ready_mask1 = {8{ready2}};
    kdlink_route_context_encoder u_encoder (
        .source_domain_i(source_domain),
        .destination_domain_i(destination_domain),
        .source_node_i(source_node),
        .destination_node_i(destination_node),
        .topology_epoch_i(topology_epoch),
        .domain_hop_limit_i(8'd4),
        .logical_plane_i(logical_plane),
        .slice_mask_i(2'b11),
        .route_policy_i(3'd0),
        .packet_flit_count_i(packet_flit_count),
        .expected_packet_sequence_i(packet_sequence),
        .global_transaction_id_i(global_transaction_id),
        .group_id_i(group_id),
        .logical_vc_i(logical_vc),
        .payload_o(route_payload)
    );
    kdlink_route_stage #(.DOMAIN_COUNT(256), .STAGE_INDEX(0)) u_stage0 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(active_mask0),
        .ingress_valid_i(ingress_valid), .ingress_ready_o(ready0), .ingress_flit_i(ingress_flit),
        .egress_valid_o(valid0), .egress_ready_i(ready_mask0), .egress_flit_o(flit0),
        .route_active_o(), .selected_egress_o(select0), .final_stage_o(final0),
        .protocol_error_o(error0), .escape_violation_o(escape0)
    );
    kdlink_route_stage #(.DOMAIN_COUNT(256), .STAGE_INDEX(1)) u_stage1 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(active_mask1),
        .ingress_valid_i(chain_valid1), .ingress_ready_o(ready1), .ingress_flit_i(chain_flit1),
        .egress_valid_o(valid1), .egress_ready_i(ready_mask1), .egress_flit_o(flit1),
        .route_active_o(), .selected_egress_o(select1), .final_stage_o(final1),
        .protocol_error_o(error1), .escape_violation_o(escape1)
    );
    kdlink_route_stage #(.DOMAIN_COUNT(256), .STAGE_INDEX(2)) u_stage2 (
        .clk_i(clk), .rst_n_i(rst_n), .active_egress_mask_i(active_mask2),
        .ingress_valid_i(chain_valid2), .ingress_ready_o(ready2), .ingress_flit_i(chain_flit2),
        .egress_valid_o(valid2), .egress_ready_i(ready_mask2), .egress_flit_o(flit2),
        .route_active_o(), .selected_egress_o(select2), .final_stage_o(final2),
        .protocol_error_o(error2), .escape_violation_o(escape2)
    );
    always #0.5 clk = ~clk;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ingress_valid = 1'b0;
        ingress_flit = 640'd0;
        destination_domain = 8'd0;
        source_domain = 8'd0;
        source_node = 5'd1;
        destination_node = 5'd2;
        topology_epoch = 8'd9;
        logical_plane = 3'd0;
        logical_vc = 3'd0;
        group_id = 32'h55aa;
        global_transaction_id = 64'd0;
        active_mask0 = 8'hff;
        active_mask1 = 8'hff;
        active_mask2 = 8'hff;
        ready_mask2 = 8'hff;
        route_lfsr = 64'hf135_7aea_2e62_a9c5;
        packet_sequence = 12'd0;
        packet_flit_count = 5'd1;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        for (destination = 0; destination < 256; destination = destination + 1) begin
            route_lfsr = {route_lfsr[62:0], route_lfsr[63] ^ route_lfsr[62] ^ route_lfsr[60] ^ route_lfsr[59]};
            destination_domain = destination[7:0];
            source_domain = route_lfsr[7:0];
            source_node = route_lfsr[12:8];
            destination_node = route_lfsr[17:13];
            topology_epoch = route_lfsr[25:18];
            logical_plane = route_lfsr[28:26];
            logical_vc = (route_lfsr[31:29] < 6) ? route_lfsr[31:29] : 3'd0;
            group_id = route_lfsr[63:32];
            global_transaction_id = route_lfsr ^ {56'd0, destination_domain};
            packet_sequence = route_lfsr[43:32];
            packet_flit_count = {1'b0, destination[3:0]} + 5'd1;
            active_mask0 = route_lfsr[7:0] | (8'b1 << destination_domain[7:6]);
            active_mask1 = route_lfsr[15:8] | (8'b1 << destination_domain[5:3]);
            active_mask2 = route_lfsr[23:16] | (8'b1 << destination_domain[2:0]);
            ready_mask2 = route_lfsr[47:40] | (8'b1 << destination_domain[2:0]);
            #0.01;
            context_flit = 640'd0;
            context_flit[511:0] = route_payload;
            context_flit[515:512] = `KDL_ROUTE_SCHEMA;
            context_flit[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            context_flit[527:525] = logical_vc;
            context_flit[529] = 1'b1;
            context_flit[530] = 1'b1;
            context_flit[536:532] = source_node;
            context_flit[541:537] = destination_node;
            context_flit[544:542] = logical_plane;
            context_flit[593:582] = packet_sequence;
            context_flit[599:594] = 6'd0;
            context_flit[606:600] = 7'd64;
            @(negedge clk);
            ingress_flit = context_flit;
            ingress_valid = 1'b1;
            #0.01;
            if (!ready0 || !ready1 || !ready2) $fatal(1, "route context was unexpectedly blocked");
            if (valid0 != (8'b1 << destination_domain[7:6])) $fatal(1, "top route digit mismatch");
            if (valid1 != (8'b1 << destination_domain[5:3])) $fatal(1, "middle route digit mismatch");
            if (valid2 != (8'b1 << destination_domain[2:0])) $fatal(1, "leaf route digit mismatch");
            if (flit0[destination_domain[7:6]*640 + 34 +: 8] != 3 || flit1[destination_domain[5:3]*640 + 34 +: 8] != 2 || flit2[destination_domain[2:0]*640 + 34 +: 8] != 1) $fatal(1, "route hop was not decremented at every cascaded stage");
            @(negedge clk);
            for (flit_index = 0; flit_index < packet_flit_count; flit_index = flit_index + 1) begin
                data_flit = 640'd0;
                data_flit[511:0] = {8{route_lfsr ^ {32'd0, destination[15:0], flit_index[15:0]}}};
                data_flit[515:512] = `KDL_SCHEMA_VERSION;
                data_flit[527:525] = destination[0] ? `KDL_VC_ROLE_REPLAY : logical_vc;
                data_flit[529] = flit_index == 0;
                data_flit[530] = flit_index[4:0] == (packet_flit_count - 5'd1);
                data_flit[531] = destination[0];
                data_flit[536:532] = source_node;
                data_flit[541:537] = destination_node;
                data_flit[544:542] = logical_plane;
                data_flit[593:582] = packet_sequence;
                data_flit[599:594] = flit_index[5:0];
                data_flit[606:600] = (flit_index[4:0] == (packet_flit_count - 5'd1)) ? 7'd1 : 7'd64;
                ingress_flit = data_flit;
                #0.01;
                if (select0 != {1'b0, destination_domain[7:6]} || select1 != destination_domain[5:3] || select2 != destination_domain[2:0]) $fatal(1, "packet lock digit mismatch");
                if (destination[1] && (flit_index == 0)) begin
                    ready_mask2[destination_domain[2:0]] = 1'b0;
                    #0.01;
                    if (ready0 || !valid2[destination_domain[2:0]]) $fatal(1, "cascaded backpressure did not reach the root");
                    @(negedge clk);
                    if (ingress_flit != data_flit) $fatal(1, "packet changed while the cascaded route was stalled");
                    ready_mask2[destination_domain[2:0]] = 1'b1;
                end
                @(negedge clk);
            end
            ingress_valid = 1'b0;
        end
        if (final0 || final1 || !final2 || error0 || error1 || error2 || escape0 || escape1 || escape2) $fatal(1, "scale route final status mismatch");
        active_mask0 = 8'd0;
        active_mask1 = 8'd0;
        active_mask2 = 8'd0;
        ready_mask2 = 8'd0;
        destination_domain = 8'd0;
        #0.01;
        context_flit = 640'd0;
        context_flit[511:0] = route_payload;
        context_flit[515:512] = `KDL_ROUTE_SCHEMA;
        context_flit[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
        context_flit[527:525] = logical_vc;
        context_flit[529] = 1'b1;
        context_flit[530] = 1'b1;
        context_flit[536:532] = source_node;
        context_flit[541:537] = destination_node;
        context_flit[544:542] = logical_plane;
        context_flit[593:582] = packet_sequence;
        context_flit[606:600] = 7'd64;
        @(negedge clk);
        ingress_flit = context_flit;
        ingress_valid = 1'b1;
        @(negedge clk);
        ingress_valid = 1'b0;
        if (!error0 || !escape0 || error1 || error2) $fatal(1, "inactive root route was not isolated from downstream stages");
        $display("TB_KDLINK_ROUTE_STAGE_SCALE_PASS");
        $finish;
    end
endmodule

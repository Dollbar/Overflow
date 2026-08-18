`timescale 1ns/1ps
module tb_kdlink_v2_direct32;
    localparam integer FLITS_PER_CHUNK = 2;
    logic clk;
    logic rst_n;
    logic load_valid_i;
    wire load_ready_o;
    logic [4:0] load_chunk_i;
    logic [6:0] load_flit_i;
    logic [262143:0] load_data_i;
    logic start_i;
    wire start_ready_o;
    logic [2:0] opcode_i;
    logic [11:0] collective_id_i;
    logic [7:0] link_epoch_i;
    logic direct_cfg_valid_i;
    wire direct_cfg_ready_o;
    logic [4:0] direct_cfg_src_i;
    logic [4:0] direct_cfg_dst_i;
    logic [7:0] direct_cfg_flits_i;
    logic [4:0] p2p_src_node_i;
    logic [4:0] p2p_dst_node_i;
    logic [7:0] p2p_flits_i;
    wire busy_o;
    wire done_o;
    wire operation_error_o;
    wire lane_alignment_error_o;
    wire [31:0] operation_cycles_o;
    logic [4:0] result_chunk_i;
    logic [6:0] result_flit_i;
    wire [262143:0] result_data_o;
    wire [15:0] fabric_protocol_error_o;
    integer src;
    integer dst;
    integer bank;
    integer flit;
    integer lane;
    integer endpoint;
    integer count;
    integer expected;
    integer a2a_cycles;
    integer a2av_cycles;
    integer p2p_cycles;
    integer a2a_payload_cycles;
    integer a2a_bubbles;
    real a2a_effective_gbps;

    function automatic [31:0] pattern;
        input integer source_node;
        input integer destination_node;
        input integer bank_index;
        input integer flit_index;
        input integer lane_index;
        begin
            pattern = 32'h40000000 | (source_node << 22) | (destination_node << 17) |
                      (bank_index << 13) | (flit_index << 8) | lane_index;
        end
    endfunction

    kdlink_v2_collective32_int32 #(.FLITS_PER_CHUNK(FLITS_PER_CHUNK)) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .load_valid_i(load_valid_i), .load_ready_o(load_ready_o),
        .load_chunk_i(load_chunk_i), .load_flit_i(load_flit_i), .load_data_i(load_data_i),
        .start_i(start_i), .start_ready_o(start_ready_o), .opcode_i(opcode_i),
        .collective_id_i(collective_id_i), .link_epoch_i(link_epoch_i),
        .direct_cfg_valid_i(direct_cfg_valid_i), .direct_cfg_ready_o(direct_cfg_ready_o),
        .direct_cfg_src_i(direct_cfg_src_i), .direct_cfg_dst_i(direct_cfg_dst_i),
        .direct_cfg_flits_i(direct_cfg_flits_i),
        .p2p_src_node_i(p2p_src_node_i), .p2p_dst_node_i(p2p_dst_node_i), .p2p_flits_i(p2p_flits_i),
        .busy_o(busy_o), .done_o(done_o), .operation_error_o(operation_error_o),
        .lane_alignment_error_o(lane_alignment_error_o), .operation_cycles_o(operation_cycles_o),
        .result_chunk_i(result_chunk_i), .result_flit_i(result_flit_i),
        .result_data_o(result_data_o), .fabric_protocol_error_o(fabric_protocol_error_o)
    );

    always #0.5 clk = ~clk;

    task automatic start_operation(input [2:0] operation, input [11:0] identity);
        begin
            @(negedge clk);
            if (!start_ready_o) $fatal(1, "start not ready opcode=%0d", operation);
            opcode_i = operation;
            collective_id_i = identity;
            start_i = 1'b1;
            @(negedge clk);
            start_i = 1'b0;
            wait (done_o);
            #0.01;
            if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 0)
                $fatal(1, "direct operation status failure opcode=%0d op=%b align=%b fabric=%h", operation, operation_error_o, lane_alignment_error_o, fabric_protocol_error_o);
        end
    endtask

    task automatic check_pair(input integer source_node, input integer destination_node, input integer flit_count);
        begin
            for (flit = 0; flit < flit_count; flit = flit + 1) begin
                @(negedge clk);
                result_chunk_i = source_node[4:0];
                result_flit_i = flit[6:0];
                #0.01;
                for (bank = 0; bank < 16; bank = bank + 1) begin
                    endpoint = destination_node*16 + bank;
                    for (lane = 0; lane < 16; lane = lane + 1) begin
                        expected = pattern(source_node, destination_node, bank, flit, lane);
                        if (result_data_o[endpoint*512 + lane*32 +: 32] !== expected[31:0])
                            $fatal(1, "direct mismatch src=%0d dst=%0d bank=%0d flit=%0d lane=%0d got=%h expected=%h", source_node, destination_node, bank, flit, lane, result_data_o[endpoint*512 + lane*32 +: 32], expected[31:0]);
                    end
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && opcode_i == 3'd3 && busy_o && u_dut.state_q == 3'd5) begin
            if (u_dut.fabric_tx_valid == {512{1'b1}}) begin
                a2a_payload_cycles = a2a_payload_cycles + 1;
                if (!u_dut.send_fire) a2a_bubbles = a2a_bubbles + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_valid_i = 1'b0;
        load_chunk_i = 5'd0;
        load_flit_i = 7'd0;
        for (endpoint = 0; endpoint < 512; endpoint = endpoint + 1) load_data_i[endpoint*512 +: 512] = 512'd0;
        start_i = 1'b0;
        opcode_i = 3'd0;
        collective_id_i = 12'd0;
        link_epoch_i = 8'h4D;
        direct_cfg_valid_i = 1'b0;
        direct_cfg_src_i = 5'd0;
        direct_cfg_dst_i = 5'd0;
        direct_cfg_flits_i = 8'd0;
        p2p_src_node_i = 5'd0;
        p2p_dst_node_i = 5'd1;
        p2p_flits_i = 8'd1;
        result_chunk_i = 5'd0;
        result_flit_i = 7'd0;
        a2a_cycles = 0;
        a2av_cycles = 0;
        p2p_cycles = 0;
        a2a_payload_cycles = 0;
        a2a_bubbles = 0;
        a2a_effective_gbps = 0.0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (dst = 0; dst < 32; dst = dst + 1) begin
            for (flit = 0; flit < FLITS_PER_CHUNK; flit = flit + 1) begin
                @(negedge clk);
                if (!load_ready_o) $fatal(1, "load unexpectedly blocked");
                load_valid_i = 1'b1;
                load_chunk_i = dst[4:0];
                load_flit_i = flit[6:0];
                for (endpoint = 0; endpoint < 512; endpoint = endpoint + 1) begin
                    src = endpoint / 16;
                    bank = endpoint & 15;
                    for (lane = 0; lane < 16; lane = lane + 1)
                        load_data_i[endpoint*512 + lane*32 +: 32] = pattern(src, dst, bank, flit, lane);
                end
            end
        end
        @(negedge clk);
        load_valid_i = 1'b0;

        start_operation(3'd3, 12'h510);
        a2a_cycles = operation_cycles_o;
        if (a2a_payload_cycles != 32*FLITS_PER_CHUNK || a2a_bubbles != 0)
            $fatal(1, "AllToAll streaming failure payload_cycles=%0d bubbles=%0d", a2a_payload_cycles, a2a_bubbles);
        for (src = 0; src < 32; src = src + 1)
            for (dst = 0; dst < 32; dst = dst + 1)
                check_pair(src, dst, FLITS_PER_CHUNK);

        for (src = 0; src < 32; src = src + 1) begin
            for (dst = 0; dst < 32; dst = dst + 1) begin
                @(negedge clk);
                if (!direct_cfg_ready_o) $fatal(1, "direct config unexpectedly blocked");
                direct_cfg_valid_i = 1'b1;
                direct_cfg_src_i = src[4:0];
                direct_cfg_dst_i = dst[4:0];
                count = (src + 2*dst) % (FLITS_PER_CHUNK+1);
                direct_cfg_flits_i = count[7:0];
            end
        end
        @(negedge clk);
        direct_cfg_valid_i = 1'b0;
        start_operation(3'd4, 12'h511);
        a2av_cycles = operation_cycles_o;
        for (src = 0; src < 32; src = src + 1) begin
            for (dst = 0; dst < 32; dst = dst + 1) begin
                count = (src + 2*dst) % (FLITS_PER_CHUNK+1);
                check_pair(src, dst, count);
            end
        end

        p2p_src_node_i = 5'd7;
        p2p_dst_node_i = 5'd23;
        p2p_flits_i = 8'd2;
        start_operation(3'd5, 12'h512);
        p2p_cycles = operation_cycles_o;
        check_pair(7, 23, FLITS_PER_CHUNK);

        a2a_effective_gbps = (32.0*FLITS_PER_CHUNK*16.0*64.0) / a2a_cycles;
        $display("TB_KDLINK_V2_DIRECT32_PASS a2a_cycles=%0d a2av_cycles=%0d p2p_cycles=%0d a2a_payload_cycles=%0d a2a_bubbles=%0d a2a_effective_GBps_per_node=%0.3f", a2a_cycles, a2av_cycles, p2p_cycles, a2a_payload_cycles, a2a_bubbles, a2a_effective_gbps);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "KDLink-v2 direct32 timeout");
    end
endmodule

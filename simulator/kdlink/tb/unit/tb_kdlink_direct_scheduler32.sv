`timescale 1ns/1ps
module tb_kdlink_direct_scheduler32;
    reg clk;
    reg rst_n;
    reg [2:0] opcode;
    reg [4:0] step;
    reg [6:0] flit_index;
    reg [255:0] source_pair_counts;
    reg [7:0] alltoallv_step_limit;
    reg [4:0] p2p_src_node;
    reg [4:0] p2p_dst_node;
    reg [7:0] p2p_flits;
    wire [31:0] source_valid;
    wire [255:0] source_count;
    wire [7:0] step_limit;
    integer source_index;
    reg [7:0] expected_count;

    kdlink_direct_scheduler32 #(.FLITS_PER_CHUNK(8)) dut (
        .clk_i(clk), .rst_n_i(rst_n), .opcode_i(opcode), .step_i(step),
        .flit_index_i(flit_index), .source_pair_counts_i(source_pair_counts),
        .alltoallv_step_limit_i(alltoallv_step_limit),
        .p2p_src_node_i(p2p_src_node), .p2p_dst_node_i(p2p_dst_node),
        .p2p_flits_i(p2p_flits), .source_valid_o(source_valid),
        .source_count_o(source_count), .step_limit_o(step_limit)
    );

    always #0.5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        opcode = 3'd0;
        step = 5'd0;
        flit_index = 7'd0;
        source_pair_counts = 256'd0;
        alltoallv_step_limit = 8'd0;
        p2p_src_node = 5'd0;
        p2p_dst_node = 5'd0;
        p2p_flits = 8'd0;
        #2 rst_n = 1'b1;

        opcode = 3'd3;
        #0.01;
        if (source_valid != 32'hffff_ffff || source_count != {32{8'd8}} ||
            step_limit != 8'd8)
            $fatal(1, "AllToAll schedule mismatch");

        for (source_index = 0; source_index < 32; source_index = source_index + 1) begin
            expected_count = source_index[7:0] * 8'h5d ^ 8'ha7;
            source_pair_counts[source_index*8 +: 8] = expected_count;
        end
        opcode = 3'd4;
        alltoallv_step_limit = 8'he3;
        flit_index = 7'd37;
        #0.01;
        for (source_index = 0; source_index < 32; source_index = source_index + 1) begin
            expected_count = source_index[7:0] * 8'h5d ^ 8'ha7;
            if (source_count[source_index*8 +: 8] != expected_count)
                $fatal(1, "AllToAllv count mismatch source=%0d", source_index);
            if (source_valid[source_index] !=
                ({1'b0, flit_index} < source_count[source_index*8 +: 8]))
                $fatal(1, "AllToAllv valid mismatch source=%0d", source_index);
        end
        if (step_limit != 8'he3) $fatal(1, "AllToAllv step limit mismatch");

        opcode = 3'd5;
        p2p_src_node = 5'd27;
        p2p_dst_node = 5'd3;
        p2p_flits = 8'hb6;
        step = 5'd8;
        flit_index = 7'd63;
        #0.01;
        if (source_valid != 32'h0800_0000 || source_count[27*8 +: 8] != 8'hb6 ||
            step_limit != 8'hb6)
            $fatal(1, "PointToPoint active schedule mismatch");
        step = 5'd9;
        #0.01;
        if (source_valid != 32'd0 || step_limit != 8'd0)
            $fatal(1, "PointToPoint inactive step mismatch");

        opcode = 3'd7;
        #0.01;
        if (source_valid != 32'd0 || source_count != 256'd0 || step_limit != 8'd0)
            $fatal(1, "illegal opcode was not idle");
        $display("TB_KDLINK_DIRECT_SCHEDULER32_PASS alltoall=1 alltoallv=1 p2p=1 illegal=1");
        $finish;
    end
endmodule

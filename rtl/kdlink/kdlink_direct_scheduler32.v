module kdlink_direct_scheduler32 #(
    parameter integer FLITS_PER_CHUNK = 128
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire [2:0] opcode_i,
    input wire [4:0] step_i,
    input wire [6:0] flit_index_i,
    input wire [255:0] source_pair_counts_i,
    input wire [7:0] alltoallv_step_limit_i,
    input wire [4:0] p2p_src_node_i,
    input wire [4:0] p2p_dst_node_i,
    input wire [7:0] p2p_flits_i,
    output reg [31:0] source_valid_o,
    output reg [255:0] source_count_o,
    output wire [7:0] step_limit_o
);
    wire [4:0] p2p_step;
    reg [7:0] selected_count;
    integer source_index;

    always @(*) begin
        source_valid_o = 32'd0;
        source_count_o = 256'd0;
        selected_count = 8'd0;
        for (source_index = 0; source_index < 32; source_index = source_index + 1) begin
            if (opcode_i == 3'd3) selected_count = FLITS_PER_CHUNK[7:0];
            else if (opcode_i == 3'd4) selected_count = source_pair_counts_i[source_index*8 +: 8];
            else if ((opcode_i == 3'd5) && (source_index[4:0] == p2p_src_node_i) && (step_i == p2p_step)) selected_count = p2p_flits_i;
            else selected_count = 8'd0;
            source_count_o[source_index*8 +: 8] = selected_count;
            if (opcode_i == 3'd3) source_valid_o[source_index] = 1'b1;
            else if (opcode_i == 3'd4) source_valid_o[source_index] = {1'b0, flit_index_i} < source_pair_counts_i[source_index*8 +: 8];
            else if (opcode_i == 3'd5) source_valid_o[source_index] = (source_index[4:0] == p2p_src_node_i) && (step_i == p2p_step) && ({1'b0, flit_index_i} < p2p_flits_i);
            else source_valid_o[source_index] = 1'b0;
        end
    end

    assign p2p_step = p2p_dst_node_i - p2p_src_node_i;
    assign step_limit_o = (opcode_i == 3'd3) ? FLITS_PER_CHUNK[7:0] :
                          (opcode_i == 3'd4) ? alltoallv_step_limit_i :
                          ((opcode_i == 3'd5) && (step_i == p2p_step)) ? p2p_flits_i : 8'd0;

    wire unused_clock;
    assign unused_clock = clk_i ^ rst_n_i;
endmodule

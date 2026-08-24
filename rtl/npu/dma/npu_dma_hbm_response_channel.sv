`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_response_channel #(
    parameter int unsigned HBM_LANES = 5,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned SELECT_FANOUT_BITS = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic [HBM_LANES-1:0] lane_select_i,
    input  logic [HBM_LANES-1:0] lane_write_i,
    input  logic [HBM_LANES*LOCAL_TAG_WIDTH-1:0] lane_local_tag_i,
    input  logic [HBM_LANES*DATA_BYTES*8-1:0] lane_read_data_i,
    input  logic [HBM_LANES*2-1:0] lane_status_i,
    output logic response_valid_o,
    input  logic response_ready_i,
    output logic response_write_o,
    output logic [LOCAL_TAG_WIDTH-1:0] response_local_tag_o,
    output logic [DATA_BYTES*8-1:0] response_read_data_o,
    output logic [1:0] response_status_o
);
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned DATA_CHUNKS = DATA_WIDTH / SELECT_FANOUT_BITS;
    localparam int unsigned SELECT_COPIES = DATA_CHUNKS + 1;

    logic [SELECT_COPIES*HBM_LANES-1:0] lane_select_buffered;
    logic [DATA_CHUNKS-1:0] chunk_selected;
    logic metadata_selected;
    logic [HBM_LANES*DATA_WIDTH-1:0] masked_data;
    logic [DATA_WIDTH-1:0] data_pair01;
    logic [DATA_WIDTH-1:0] data_pair23;
    logic [DATA_WIDTH-1:0] data_group0123;
    logic [DATA_WIDTH-1:0] selected_data;
    logic [HBM_LANES-1:0] masked_write;
    logic [HBM_LANES*LOCAL_TAG_WIDTH-1:0] masked_local_tag;
    logic [HBM_LANES*2-1:0] masked_status;
    logic selected_write;
    logic [LOCAL_TAG_WIDTH-1:0] selected_local_tag;
    logic [1:0] selected_status;

    generate
        for (genvar copy_index = 0; copy_index < SELECT_COPIES;
             copy_index = copy_index + 1) begin : g_select_copy
            for (genvar lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin : g_lane
                npu_dma_hbm_control_buffer u_control_buffer (
                    .data_i(lane_select_i[lane_index]),
                    .data_o(lane_select_buffered[
                        copy_index*HBM_LANES + lane_index])
                );
            end
        end

        for (genvar chunk_index = 0; chunk_index < DATA_CHUNKS;
             chunk_index = chunk_index + 1) begin : g_data_chunk
            assign chunk_selected[chunk_index] =
                |lane_select_buffered[
                    chunk_index*HBM_LANES +: HBM_LANES];
            for (genvar lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin : g_lane
                assign masked_data[
                    lane_index*DATA_WIDTH +
                    chunk_index*SELECT_FANOUT_BITS +: SELECT_FANOUT_BITS] =
                    lane_read_data_i[
                        lane_index*DATA_WIDTH +
                        chunk_index*SELECT_FANOUT_BITS +: SELECT_FANOUT_BITS] &
                    {SELECT_FANOUT_BITS{lane_select_buffered[
                        chunk_index*HBM_LANES + lane_index]}};
            end
        end

        for (genvar lane_index = 0; lane_index < HBM_LANES;
             lane_index = lane_index + 1) begin : g_masked_metadata
            assign masked_write[lane_index] = lane_write_i[lane_index] &
                lane_select_buffered[DATA_CHUNKS*HBM_LANES + lane_index];
            assign masked_local_tag[
                lane_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                lane_local_tag_i[
                    lane_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] &
                {LOCAL_TAG_WIDTH{lane_select_buffered[
                    DATA_CHUNKS*HBM_LANES + lane_index]}};
            assign masked_status[lane_index*2 +: 2] =
                lane_status_i[lane_index*2 +: 2] &
                {2{lane_select_buffered[
                    DATA_CHUNKS*HBM_LANES + lane_index]}};
        end
    endgenerate

    assign metadata_selected =
        |lane_select_buffered[DATA_CHUNKS*HBM_LANES +: HBM_LANES];

    assign data_pair01 = masked_data[0*DATA_WIDTH +: DATA_WIDTH] |
                         masked_data[1*DATA_WIDTH +: DATA_WIDTH];
    assign data_pair23 = masked_data[2*DATA_WIDTH +: DATA_WIDTH] |
                         masked_data[3*DATA_WIDTH +: DATA_WIDTH];
    assign data_group0123 = data_pair01 | data_pair23;
    assign selected_data = data_group0123 |
                           masked_data[4*DATA_WIDTH +: DATA_WIDTH];

    assign selected_write = (masked_write[0] | masked_write[1]) |
                            (masked_write[2] | masked_write[3]) |
                            masked_write[4];
    assign selected_local_tag =
        ((masked_local_tag[0*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] |
          masked_local_tag[1*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]) |
         (masked_local_tag[2*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] |
          masked_local_tag[3*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH])) |
        masked_local_tag[4*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH];
    assign selected_status =
        ((masked_status[0*2 +: 2] | masked_status[1*2 +: 2]) |
         (masked_status[2*2 +: 2] | masked_status[3*2 +: 2])) |
        masked_status[4*2 +: 2];

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            response_valid_o <= 1'b0;
        end else if (|lane_select_i) begin
            response_valid_o <= 1'b1;
        end else if (response_valid_o && response_ready_i) begin
            response_valid_o <= 1'b0;
        end
    end

    generate
        for (genvar chunk_index = 0; chunk_index < DATA_CHUNKS;
             chunk_index = chunk_index + 1) begin : g_response_data_register
            always_ff @(posedge clk_i) begin
                if (chunk_selected[chunk_index]) begin
                    response_read_data_o[
                        chunk_index*SELECT_FANOUT_BITS +:
                        SELECT_FANOUT_BITS] <= selected_data[
                            chunk_index*SELECT_FANOUT_BITS +:
                            SELECT_FANOUT_BITS];
                end
            end
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (metadata_selected) begin
            response_write_o <= selected_write;
            response_local_tag_o <= selected_local_tag;
            response_status_o <= selected_status;
        end
    end

    initial begin
        if ((HBM_LANES != 5) || (SELECT_FANOUT_BITS < 1) ||
            ((DATA_WIDTH % SELECT_FANOUT_BITS) != 0)) begin
            $error("HBM response channel select fanout geometry is invalid");
        end
    end
endmodule

`default_nettype wire

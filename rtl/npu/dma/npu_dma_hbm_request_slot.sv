`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_request_slot #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned PAYLOAD_WIDTH = 1200,
    parameter int unsigned SELECT_FANOUT_BITS = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic [CHANNELS-1:0] channel_select_i,
    input  logic [CHANNELS*PAYLOAD_WIDTH-1:0] channel_payload_i,
    input  logic slot_ready_i,
    output logic slot_valid_o,
    output logic [PAYLOAD_WIDTH-1:0] slot_payload_o
);
    localparam int unsigned FULL_CHUNKS = PAYLOAD_WIDTH / SELECT_FANOUT_BITS;
    localparam int unsigned LAST_CHUNK_BITS = PAYLOAD_WIDTH % SELECT_FANOUT_BITS;
    localparam int unsigned PAYLOAD_CHUNKS =
        FULL_CHUNKS + ((LAST_CHUNK_BITS == 0) ? 0 : 1);

    logic [PAYLOAD_CHUNKS*CHANNELS-1:0] select_buffered;
    logic [PAYLOAD_CHUNKS-1:0] chunk_selected;
    logic [CHANNELS*PAYLOAD_WIDTH-1:0] masked_payload;
    logic [8*PAYLOAD_WIDTH-1:0] reduce_level1;
    logic [4*PAYLOAD_WIDTH-1:0] reduce_level2;
    logic [2*PAYLOAD_WIDTH-1:0] reduce_level3;
    logic [PAYLOAD_WIDTH-1:0] selected_payload;
    logic [PAYLOAD_WIDTH-1:0] slot_payload_q;

    generate
        for (genvar chunk_index = 0; chunk_index < PAYLOAD_CHUNKS;
             chunk_index = chunk_index + 1) begin : g_chunk
            assign chunk_selected[chunk_index] =
                |select_buffered[chunk_index*CHANNELS +: CHANNELS];
            for (genvar channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin : g_channel
                npu_dma_hbm_control_buffer u_control_buffer (
                    .data_i(channel_select_i[channel_index]),
                    .data_o(select_buffered[
                        chunk_index*CHANNELS + channel_index])
                );
                if (chunk_index < FULL_CHUNKS) begin : g_full_chunk
                    assign masked_payload[
                        channel_index*PAYLOAD_WIDTH +
                        chunk_index*SELECT_FANOUT_BITS +: SELECT_FANOUT_BITS] =
                        channel_payload_i[
                            channel_index*PAYLOAD_WIDTH +
                            chunk_index*SELECT_FANOUT_BITS +: SELECT_FANOUT_BITS] &
                        {SELECT_FANOUT_BITS{select_buffered[
                            chunk_index*CHANNELS + channel_index]}};
                end else begin : g_last_chunk
                    assign masked_payload[
                        channel_index*PAYLOAD_WIDTH +
                        chunk_index*SELECT_FANOUT_BITS +: LAST_CHUNK_BITS] =
                        channel_payload_i[
                            channel_index*PAYLOAD_WIDTH +
                            chunk_index*SELECT_FANOUT_BITS +: LAST_CHUNK_BITS] &
                        {LAST_CHUNK_BITS{select_buffered[
                            chunk_index*CHANNELS + channel_index]}};
                end
            end
            if (chunk_index < FULL_CHUNKS) begin : g_full_register
                always_ff @(posedge clk_i) begin
                    if (chunk_selected[chunk_index]) begin
                        slot_payload_q[
                            chunk_index*SELECT_FANOUT_BITS +:
                            SELECT_FANOUT_BITS] <= selected_payload[
                                chunk_index*SELECT_FANOUT_BITS +:
                                SELECT_FANOUT_BITS];
                    end
                end
            end else begin : g_last_register
                always_ff @(posedge clk_i) begin
                    if (chunk_selected[chunk_index]) begin
                        slot_payload_q[
                            chunk_index*SELECT_FANOUT_BITS +:
                            LAST_CHUNK_BITS] <= selected_payload[
                                chunk_index*SELECT_FANOUT_BITS +:
                                LAST_CHUNK_BITS];
                    end
                end
            end
        end

        for (genvar pair_index = 0; pair_index < 8;
             pair_index = pair_index + 1) begin : g_reduce_level1
            assign reduce_level1[pair_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                masked_payload[(pair_index*2)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] |
                masked_payload[(pair_index*2+1)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
        end
        for (genvar quad_index = 0; quad_index < 4;
             quad_index = quad_index + 1) begin : g_reduce_level2
            assign reduce_level2[quad_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                reduce_level1[(quad_index*2)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] |
                reduce_level1[(quad_index*2+1)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
        end
        for (genvar oct_index = 0; oct_index < 2;
             oct_index = oct_index + 1) begin : g_reduce_level3
            assign reduce_level3[oct_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                reduce_level2[(oct_index*2)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] |
                reduce_level2[(oct_index*2+1)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
        end
    endgenerate

    assign selected_payload =
        reduce_level3[0*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] |
        reduce_level3[1*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
    assign slot_payload_o = slot_payload_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            slot_valid_o <= 1'b0;
        end else if (|channel_select_i) begin
            slot_valid_o <= 1'b1;
        end else if (slot_valid_o && slot_ready_i) begin
            slot_valid_o <= 1'b0;
        end
    end

    initial begin
        if ((CHANNELS != 16) || (SELECT_FANOUT_BITS < 1) ||
            (PAYLOAD_WIDTH < SELECT_FANOUT_BITS)) begin
            $error("HBM request slot geometry is invalid");
        end
    end
endmodule

`default_nettype wire

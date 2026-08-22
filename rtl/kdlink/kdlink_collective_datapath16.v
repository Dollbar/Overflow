`include "kdlink_defs.vh"
module kdlink_collective_datapath16 (
    input wire clk_i,
    input wire rst_n_i,
    input wire descriptor_valid_i,
    output wire descriptor_ready_o,
    input wire [511:0] descriptor_i,
    output wire allocate_valid_o,
    output wire [3:0] allocate_context_o,
    input wire [15:0] context_block_i,
    input wire local_valid_i,
    output wire local_ready_o,
    input wire [3:0] local_context_i,
    input wire [511:0] local_payload_i,
    input wire [63:0] local_byte_valid_i,
    input wire local_last_i,
    input wire remote_valid_i,
    output wire remote_ready_o,
    input wire [3:0] remote_context_i,
    input wire [511:0] remote_payload_i,
    input wire [63:0] remote_byte_valid_i,
    input wire remote_last_i,
    output wire result_valid_o,
    input wire result_ready_i,
    output wire [3:0] result_context_o,
    output wire [1:0] result_dtype_o,
    output wire [11:0] result_collective_id_o,
    output wire [31:0] result_user_tag_o,
    output wire [511:0] result_payload_o,
    output wire [63:0] result_byte_valid_o,
    output wire result_last_o,
    output wire completion_valid_o,
    input wire completion_ready_i,
    output wire [3:0] completion_context_o,
    output wire [11:0] completion_collective_id_o,
    output wire [31:0] completion_user_tag_o,
    output wire completion_error_o,
    output wire [15:0] active_context_o,
    output wire descriptor_error_o,
    output wire duplicate_error_o,
    output reg stream_error_o,
    output reg internal_error_o
);
    localparam integer CONTEXT_QUEUE_ADDR_BITS = 2;
    localparam integer CONTEXT_QUEUE_COUNT_BITS = 3;
    localparam integer META_WIDTH = 115;
    localparam integer RESULT_WIDTH = 627;
    localparam integer COMPLETION_WIDTH = 49;
    localparam [2:0] CONTEXT_QUEUE_DEPTH_COUNT = 3'd4;
    localparam [7:0] RESULT_FIFO_DEPTH_COUNT = 8'd64;

    reg [576:0] local_mem_q [0:63];
    reg [576:0] remote_mem_q [0:63];
    reg [CONTEXT_QUEUE_ADDR_BITS-1:0] local_read_q [0:15];
    reg [CONTEXT_QUEUE_ADDR_BITS-1:0] local_write_q [0:15];
    reg [CONTEXT_QUEUE_ADDR_BITS-1:0] remote_read_q [0:15];
    reg [CONTEXT_QUEUE_ADDR_BITS-1:0] remote_write_q [0:15];
    reg [CONTEXT_QUEUE_COUNT_BITS-1:0] local_count_q [0:15];
    reg [CONTEXT_QUEUE_COUNT_BITS-1:0] remote_count_q [0:15];
    reg [15:0] final_issued_q;
    reg [15:0] context_error_q;
    reg [15:0] scheduler_blocked_d;
    reg [4:0] active_count_d;
    reg [6:0] reduction_inflight_q;

    wire scheduler_submit_ready;
    wire scheduler_submit_valid;
    wire scheduler_allocate_valid;
    wire [3:0] scheduler_allocate_index;
    wire scheduler_issue_valid;
    wire scheduler_issue_ready;
    wire [3:0] scheduler_issue_index;
    wire [511:0] scheduler_issue_descriptor;
    wire [31:0] scheduler_reservation_count;
    wire scheduler_complete_valid;
    wire [3:0] scheduler_complete_index;
    wire [15:0] scheduler_active;
    wire completion_capacity_available;
    wire local_push;
    wire remote_push;
    wire issue_fire;
    wire [576:0] local_head;
    wire [576:0] remote_head;
    wire pair_last;
    wire pair_mismatch;
    wire [63:0] pair_byte_valid;
    wire reduction_valid;
    wire [511:0] reduction_result;
    wire [63:0] reduction_byte_valid;
    wire [META_WIDTH-1:0] meta_push_data;
    wire [META_WIDTH-1:0] meta_pop_data;
    wire meta_push_ready;
    wire meta_pop_valid;
    wire [6:0] meta_occupancy;
    wire meta_fifo_overflow;
    wire meta_fifo_underflow;
    wire [RESULT_WIDTH-1:0] result_push_data;
    wire [RESULT_WIDTH-1:0] result_pop_data;
    wire result_push_ready;
    wire result_pop_valid;
    wire [6:0] result_occupancy;
    wire result_fifo_overflow;
    wire result_fifo_underflow;
    wire [COMPLETION_WIDTH-1:0] completion_push_data;
    wire [COMPLETION_WIDTH-1:0] completion_pop_data;
    wire completion_push_ready;
    wire completion_pop_valid;
    wire [4:0] completion_occupancy;
    wire completion_fifo_overflow;
    wire completion_fifo_underflow;
    wire reduction_capacity_available;
    wire result_push_valid;
    wire completion_push_valid;
    wire meta_pop_ready;
    wire [7:0] reserved_results;
    integer context_index;

    always @(*) begin
        active_count_d = 5'd0;
        scheduler_blocked_d = context_block_i;
        for (context_index = 0; context_index < 16; context_index = context_index + 1) begin
            if (scheduler_active[context_index]) active_count_d = active_count_d + 1'b1;
            if (!scheduler_active[context_index] || final_issued_q[context_index] ||
                (local_count_q[context_index] <= {1'b0, scheduler_reservation_count[context_index*2 +: 2]}) ||
                (remote_count_q[context_index] <= {1'b0, scheduler_reservation_count[context_index*2 +: 2]}))
                scheduler_blocked_d[context_index] = 1'b1;
        end
    end

    assign completion_capacity_available =
        ({1'b0, completion_occupancy} + {1'b0, active_count_d}) < 6'd16;
    assign scheduler_submit_valid = descriptor_valid_i && completion_capacity_available;
    assign descriptor_ready_o = scheduler_submit_ready && completion_capacity_available;
    assign allocate_valid_o = scheduler_allocate_valid;
    assign allocate_context_o = scheduler_allocate_index;
    assign active_context_o = scheduler_active;

    kdlink_context_scheduler16 u_context_scheduler (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .submit_valid_i(scheduler_submit_valid),
        .submit_ready_o(scheduler_submit_ready), .descriptor_i(descriptor_i),
        .allocate_valid_o(scheduler_allocate_valid),
        .allocate_index_o(scheduler_allocate_index), .blocked_i(scheduler_blocked_d),
        .issue_valid_o(scheduler_issue_valid),
        .issue_ready_i(scheduler_issue_ready),
        .issue_index_o(scheduler_issue_index),
        .issue_descriptor_o(scheduler_issue_descriptor),
        .reservation_count_o(scheduler_reservation_count),
        .complete_valid_i(scheduler_complete_valid),
        .complete_index_i(scheduler_complete_index), .active_o(scheduler_active),
        .descriptor_error_o(descriptor_error_o),
        .duplicate_error_o(duplicate_error_o)
    );

    assign local_ready_o = scheduler_active[local_context_i] &&
        !final_issued_q[local_context_i] &&
        (local_count_q[local_context_i] < CONTEXT_QUEUE_DEPTH_COUNT);
    assign remote_ready_o = scheduler_active[remote_context_i] &&
        !final_issued_q[remote_context_i] &&
        (remote_count_q[remote_context_i] < CONTEXT_QUEUE_DEPTH_COUNT);
    assign local_push = local_valid_i && local_ready_o;
    assign remote_push = remote_valid_i && remote_ready_o;
    assign local_head = local_mem_q[{scheduler_issue_index,
        local_read_q[scheduler_issue_index]}];
    assign remote_head = remote_mem_q[{scheduler_issue_index,
        remote_read_q[scheduler_issue_index]}];
    assign pair_last = local_head[576] || remote_head[576];
    assign pair_mismatch = (local_head[576] != remote_head[576]) ||
        (local_head[575:512] != remote_head[575:512]);
    assign pair_byte_valid = local_head[575:512] & remote_head[575:512];

    assign reserved_results = {1'b0, result_occupancy} +
        {1'b0, reduction_inflight_q};
    assign reduction_capacity_available = reserved_results < RESULT_FIFO_DEPTH_COUNT;
    assign scheduler_issue_ready = reduction_capacity_available && meta_push_ready;
    assign issue_fire = scheduler_issue_valid && scheduler_issue_ready;

    coll_reduction_engine u_reduction_engine (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(issue_fire),
        .dtype_i(scheduler_issue_descriptor[4:3]),
        .byte_valid_i(pair_byte_valid), .local_i(local_head[511:0]),
        .remote_i(remote_head[511:0]), .valid_o(reduction_valid),
        .result_o(reduction_result), .byte_valid_o(reduction_byte_valid)
    );

    assign meta_push_data = {scheduler_issue_index, pair_last, pair_byte_valid,
        scheduler_issue_descriptor[4:3], scheduler_issue_descriptor[36:25],
        scheduler_issue_descriptor[415:384]};
    assign meta_pop_ready = reduction_valid;
    coll_sync_fifo #(
        .WIDTH(META_WIDTH), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)
    ) u_metadata_fifo (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .push_data_i(meta_push_data),
        .push_valid_i(issue_fire), .push_ready_o(meta_push_ready),
        .pop_data_o(meta_pop_data), .pop_valid_o(meta_pop_valid),
        .pop_ready_i(meta_pop_ready), .occupancy_o(meta_occupancy),
        .overflow_o(meta_fifo_overflow), .underflow_o(meta_fifo_underflow)
    );

    assign result_push_valid = reduction_valid && meta_pop_valid;
    assign result_push_data = {meta_pop_data, reduction_result};
    coll_sync_fifo #(
        .WIDTH(RESULT_WIDTH), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)
    ) u_result_fifo (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .push_data_i(result_push_data),
        .push_valid_i(result_push_valid), .push_ready_o(result_push_ready),
        .pop_data_o(result_pop_data), .pop_valid_o(result_pop_valid),
        .pop_ready_i(result_ready_i), .occupancy_o(result_occupancy),
        .overflow_o(result_fifo_overflow), .underflow_o(result_fifo_underflow)
    );
    assign result_valid_o = result_pop_valid;
    assign result_context_o = result_pop_data[626:623];
    assign result_last_o = result_pop_data[622];
    assign result_byte_valid_o = result_pop_data[621:558];
    assign result_dtype_o = result_pop_data[557:556];
    assign result_collective_id_o = result_pop_data[555:544];
    assign result_user_tag_o = result_pop_data[543:512];
    assign result_payload_o = result_pop_data[511:0];

    assign scheduler_complete_valid = reduction_valid && meta_pop_valid &&
        meta_pop_data[110];
    assign scheduler_complete_index = meta_pop_data[114:111];
    assign completion_push_valid = scheduler_complete_valid;
    assign completion_push_data = {
        context_error_q[meta_pop_data[114:111]], meta_pop_data[114:111],
        meta_pop_data[43:32], meta_pop_data[31:0]};
    coll_sync_fifo #(
        .WIDTH(COMPLETION_WIDTH), .DEPTH(16), .ADDR_W(4), .COUNT_W(5)
    ) u_completion_fifo (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .push_data_i(completion_push_data),
        .push_valid_i(completion_push_valid), .push_ready_o(completion_push_ready),
        .pop_data_o(completion_pop_data), .pop_valid_o(completion_pop_valid),
        .pop_ready_i(completion_ready_i), .occupancy_o(completion_occupancy),
        .overflow_o(completion_fifo_overflow),
        .underflow_o(completion_fifo_underflow)
    );
    assign completion_valid_o = completion_pop_valid;
    assign completion_error_o = completion_pop_data[48];
    assign completion_context_o = completion_pop_data[47:44];
    assign completion_collective_id_o = completion_pop_data[43:32];
    assign completion_user_tag_o = completion_pop_data[31:0];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            final_issued_q <= 16'd0;
            context_error_q <= 16'd0;
            reduction_inflight_q <= 7'd0;
            stream_error_o <= 1'b0;
            internal_error_o <= 1'b0;
            for (context_index = 0; context_index < 16; context_index = context_index + 1) begin
                local_read_q[context_index] <= 2'd0;
                local_write_q[context_index] <= 2'd0;
                remote_read_q[context_index] <= 2'd0;
                remote_write_q[context_index] <= 2'd0;
                local_count_q[context_index] <= 3'd0;
                remote_count_q[context_index] <= 3'd0;
            end
        end else begin
            if (local_push) begin
                local_mem_q[{local_context_i, local_write_q[local_context_i]}] <=
                    {local_last_i, local_byte_valid_i, local_payload_i};
                local_write_q[local_context_i] <= local_write_q[local_context_i] + 1'b1;
            end
            if (remote_push) begin
                remote_mem_q[{remote_context_i, remote_write_q[remote_context_i]}] <=
                    {remote_last_i, remote_byte_valid_i, remote_payload_i};
                remote_write_q[remote_context_i] <= remote_write_q[remote_context_i] + 1'b1;
            end
            if (issue_fire) begin
                local_read_q[scheduler_issue_index] <=
                    local_read_q[scheduler_issue_index] + 1'b1;
                remote_read_q[scheduler_issue_index] <=
                    remote_read_q[scheduler_issue_index] + 1'b1;
                if (pair_last) final_issued_q[scheduler_issue_index] <= 1'b1;
                if (pair_mismatch) begin
                    context_error_q[scheduler_issue_index] <= 1'b1;
                    stream_error_o <= 1'b1;
                end
            end

            if (local_push && issue_fire) begin
                if (local_context_i != scheduler_issue_index) begin
                    local_count_q[local_context_i] <= local_count_q[local_context_i] + 1'b1;
                    local_count_q[scheduler_issue_index] <= local_count_q[scheduler_issue_index] - 1'b1;
                end
            end else if (local_push) begin
                local_count_q[local_context_i] <= local_count_q[local_context_i] + 1'b1;
            end else if (issue_fire) begin
                local_count_q[scheduler_issue_index] <= local_count_q[scheduler_issue_index] - 1'b1;
            end
            if (remote_push && issue_fire) begin
                if (remote_context_i != scheduler_issue_index) begin
                    remote_count_q[remote_context_i] <= remote_count_q[remote_context_i] + 1'b1;
                    remote_count_q[scheduler_issue_index] <= remote_count_q[scheduler_issue_index] - 1'b1;
                end
            end else if (remote_push) begin
                remote_count_q[remote_context_i] <= remote_count_q[remote_context_i] + 1'b1;
            end else if (issue_fire) begin
                remote_count_q[scheduler_issue_index] <= remote_count_q[scheduler_issue_index] - 1'b1;
            end

            case ({issue_fire, reduction_valid})
                2'b10: reduction_inflight_q <= reduction_inflight_q + 1'b1;
                2'b01: reduction_inflight_q <= reduction_inflight_q - 1'b1;
                default: reduction_inflight_q <= reduction_inflight_q;
            endcase

            if (scheduler_allocate_valid) begin
                final_issued_q[scheduler_allocate_index] <= 1'b0;
                context_error_q[scheduler_allocate_index] <= 1'b0;
                local_read_q[scheduler_allocate_index] <= 2'd0;
                local_write_q[scheduler_allocate_index] <= 2'd0;
                remote_read_q[scheduler_allocate_index] <= 2'd0;
                remote_write_q[scheduler_allocate_index] <= 2'd0;
                local_count_q[scheduler_allocate_index] <= 3'd0;
                remote_count_q[scheduler_allocate_index] <= 3'd0;
            end
            if (scheduler_complete_valid) begin
                final_issued_q[scheduler_complete_index] <= 1'b0;
                local_read_q[scheduler_complete_index] <= 2'd0;
                local_write_q[scheduler_complete_index] <= 2'd0;
                remote_read_q[scheduler_complete_index] <= 2'd0;
                remote_write_q[scheduler_complete_index] <= 2'd0;
                local_count_q[scheduler_complete_index] <= 3'd0;
                remote_count_q[scheduler_complete_index] <= 3'd0;
            end
            if ((reduction_valid && (!meta_pop_valid || !result_push_ready)) ||
                (completion_push_valid && !completion_push_ready) ||
                meta_fifo_overflow || meta_fifo_underflow || result_fifo_overflow ||
                result_fifo_underflow || completion_fifo_overflow ||
                completion_fifo_underflow)
                internal_error_o <= 1'b1;
        end
    end
endmodule

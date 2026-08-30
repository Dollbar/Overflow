`timescale 1ns/1ps
`default_nettype none

module tb_npu_2x4_pod_array;

    import npu_command_pkg::*;
    import npu_pod_array_tb_pkg::*;

    localparam int unsigned PODS = 8;
    localparam int unsigned CLUSTERS = 2;
    localparam int unsigned ARRAY_DIM = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned TOTAL_HBM_LANES = PODS * HBM_LANES;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned HBM_TAG_WIDTH = 12;
    localparam int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH;
    localparam int unsigned DATA_LANES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_LANES;
    localparam int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH;

    logic clk;
    logic [PODS-1:0] pod_clk_i;
    logic [PODS-1:0] pod_rst_i;
    logic [PODS-1:0] pod_clear_i;
    logic [PODS-1:0] pod_quiesce_i;

    logic [PODS-1:0] command_valid_i;
    logic [PODS-1:0] command_ready_o;
    logic [PODS*NPU_DECODED_COMMAND_WIDTH-1:0] command_i;
    logic [PODS-1:0] completion_valid_o;
    logic [PODS-1:0] completion_ready_i;
    logic [PODS*NPU_UNIFIED_COMPLETION_WIDTH-1:0] completion_o;

    logic [TOTAL_HBM_LANES-1:0] hbm_request_valid_o;
    logic [TOTAL_HBM_LANES-1:0] hbm_request_ready_i;
    logic [TOTAL_HBM_LANES-1:0] hbm_request_write_o;
    logic [TOTAL_HBM_LANES*PARTITION_BITS-1:0]
        hbm_request_partition_o;
    logic [TOTAL_HBM_LANES*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
        hbm_request_address_o;
    logic [TOTAL_HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o;
    logic [TOTAL_HBM_LANES*DATA_BYTES*8-1:0]
        hbm_request_write_data_o;
    logic [TOTAL_HBM_LANES*DATA_BYTES-1:0]
        hbm_request_byte_enable_o;
    logic [TOTAL_HBM_LANES-1:0] hbm_response_valid_i;
    logic [TOTAL_HBM_LANES-1:0] hbm_response_ready_o;
    logic [TOTAL_HBM_LANES-1:0] hbm_response_write_i;
    logic [TOTAL_HBM_LANES*PARTITION_BITS-1:0]
        hbm_response_partition_i;
    logic [TOTAL_HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i;
    logic [TOTAL_HBM_LANES*DATA_BYTES*8-1:0]
        hbm_response_read_data_i;
    logic [TOTAL_HBM_LANES*2-1:0] hbm_response_status_i;

    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_output_valid_o;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_output_ready_i;
    logic [PODS*CLUSTERS*ARRAY_DIM*
        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0] gemm_output_result_o;
    logic [PODS*CLUSTERS*ARRAY_DIM*
        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0] gemm_output_command_o;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_vector_valid_o;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_vector_ready_i;
    logic [PODS*CLUSTERS*ARRAY_DIM*
        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0] gemm_vector_result_o;
    logic [PODS*CLUSTERS*ARRAY_DIM*
        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0] gemm_vector_command_o;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_valid_o;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_ready_i;
    logic [PODS*CLUSTERS*ARRAY_DIM*
        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0] gemm_feedback_result_o;
    logic [PODS*CLUSTERS*ARRAY_DIM*
        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        gemm_feedback_command_o;
    logic [PODS*CLUSTERS-1:0] event_set_valid_i;
    logic [PODS*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
        event_set_id_i;
    logic [PODS*CLUSTERS-1:0] event_clear_valid_i;
    logic [PODS*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
        event_clear_id_i;

    logic [PODS-1:0] pod_control_tx_valid_i;
    logic [PODS-1:0] pod_control_tx_ready_o;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit_i;
    logic [PODS-1:0] noc_control_tx_valid_o;
    logic [PODS-1:0] noc_control_tx_ready_i;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] noc_control_tx_flit_o;
    logic [PODS*DATA_LANES-1:0] pod_data_tx_valid_i;
    logic [PODS*DATA_LANES-1:0] pod_data_tx_ready_o;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit_i;
    logic [PODS*DATA_LANES-1:0] noc_data_tx_valid_o;
    logic [PODS*DATA_LANES-1:0] noc_data_tx_ready_i;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_tx_flit_o;
    logic [PODS-1:0] noc_control_rx_valid_i;
    logic [PODS-1:0] noc_control_rx_ready_o;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] noc_control_rx_flit_i;
    logic [PODS-1:0] pod_control_rx_valid_o;
    logic [PODS-1:0] pod_control_rx_ready_i;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit_o;
    logic [PODS*DATA_LANES-1:0] noc_data_rx_valid_i;
    logic [PODS*DATA_LANES-1:0] noc_data_rx_ready_o;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_rx_flit_i;
    logic [PODS*DATA_LANES-1:0] pod_data_rx_valid_o;
    logic [PODS*DATA_LANES-1:0] pod_data_rx_ready_i;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit_o;

    logic [PODS-1:0] pod_busy_o;
    logic [PODS-1:0] pod_quiesced_o;
    logic [PODS-1:0] pod_protocol_error_o;
    logic [PODS-1:0] command_busy_o;
    logic [PODS-1:0] command_protocol_error_o;
    logic [PODS-1:0] malformed_command_seen_o;
    logic [PODS-1:0] noc_busy_o;
    logic [PODS-1:0] noc_quiesced_o;
    logic [PODS-1:0] noc_protocol_error_o;
    logic [PODS*64-1:0] accepted_commands_o;
    logic [PODS*64-1:0] rejected_commands_o;
    logic [PODS*64-1:0] delivered_completions_o;

    logic hbm_enable;
    logic [63:0] hbm_accepted_requests;
    logic [63:0] hbm_delivered_responses;
    logic [PODS-1:0] hbm_partition_seen;
    logic hbm_backpressure_seen;
    logic hbm_vip_protocol_error;
    logic [31:0] hbm_seed;
    npu_pod_array_coverage_t coverage_q;

    assign pod_clk_i = {PODS{clk}};

    npu_2x4_pod_array #(
        .ARRAY_DIM(ARRAY_DIM)
    ) dut (.*);

    npu_hbm_partition_responder_vip #(
        .PODS(PODS),
        .LANES_PER_POD(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .ADDRESS_WIDTH(npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH),
        .TAG_WIDTH(HBM_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES)
    ) u_hbm_vip (
        .clk_i(clk),
        .rst_i(|pod_rst_i),
        .clear_i(1'b0),
        .enable_i(hbm_enable),
        .seed_i(hbm_seed),
        .request_valid_i(hbm_request_valid_o),
        .request_ready_o(hbm_request_ready_i),
        .request_write_i(hbm_request_write_o),
        .request_partition_i(hbm_request_partition_o),
        .request_address_i(hbm_request_address_o),
        .request_tag_i(hbm_request_tag_o),
        .request_write_data_i(hbm_request_write_data_o),
        .request_byte_enable_i(hbm_request_byte_enable_o),
        .response_valid_o(hbm_response_valid_i),
        .response_ready_i(hbm_response_ready_o),
        .response_write_o(hbm_response_write_i),
        .response_partition_o(hbm_response_partition_i),
        .response_tag_o(hbm_response_tag_i),
        .response_read_data_o(hbm_response_read_data_i),
        .response_status_o(hbm_response_status_i),
        .accepted_requests_o(hbm_accepted_requests),
        .delivered_responses_o(hbm_delivered_responses),
        .partition_seen_o(hbm_partition_seen),
        .backpressure_seen_o(hbm_backpressure_seen),
        .protocol_error_o(hbm_vip_protocol_error)
    );

    generate
        for (genvar pod = 0; pod < PODS; pod++) begin : g_protocol_checkers
            npu_ready_valid_protocol_checker #(
                .WIDTH(NPU_DECODED_COMMAND_WIDTH),
                .CHANNEL_ID(pod)
            ) u_command_checker (
                .clk_i(clk), .rst_i(pod_rst_i[pod]),
                .clear_i(pod_clear_i[pod]),
                .valid_i(command_valid_i[pod]),
                .ready_i(command_ready_o[pod]),
                .payload_i(command_i[
                    pod*NPU_DECODED_COMMAND_WIDTH +:
                    NPU_DECODED_COMMAND_WIDTH])
            );
            npu_ready_valid_protocol_checker #(
                .WIDTH(NPU_UNIFIED_COMPLETION_WIDTH),
                .CHANNEL_ID(PODS + pod)
            ) u_completion_checker (
                .clk_i(clk), .rst_i(pod_rst_i[pod]),
                .clear_i(pod_clear_i[pod]),
                .valid_i(completion_valid_o[pod]),
                .ready_i(completion_ready_i[pod]),
                .payload_i(completion_o[
                    pod*NPU_UNIFIED_COMPLETION_WIDTH +:
                    NPU_UNIFIED_COMPLETION_WIDTH])
            );
        end
    endgenerate

    always #0.5 clk = ~clk;

    task automatic submit_all_commands;
        logic [PODS-1:0] accepted;
        begin
            @(negedge clk);
            command_valid_i = {PODS{1'b1}};
            do begin
                #0.1;
                accepted = command_valid_i & command_ready_o;
                @(posedge clk);
                @(negedge clk);
                command_valid_i = command_valid_i & ~accepted;
            end while (command_valid_i != '0);
        end
    endtask

    task automatic collect_all_completions(
        input npu_completion_source_e source,
        input logic [15:0] request_base,
        input logic success,
        input logic [7:0] code,
        input integer expected_target,
        output logic [PODS-1:0] seen
    );
        npu_unified_completion_t observed;
        logic [PODS*NPU_UNIFIED_COMPLETION_WIDTH-1:0] held;
        begin
            completion_ready_i = '0;
            while (completion_valid_o != {PODS{1'b1}}) @(posedge clk);
            held = completion_o;
            repeat (3) begin
                @(posedge clk);
                if ((completion_valid_o != {PODS{1'b1}}) ||
                    (completion_o !== held)) begin
                    $fatal(1, "array completion changed under backpressure");
                end
            end
            coverage_q.completion_backpressure_seen = 1'b1;
            for (integer pod = 0; pod < PODS; pod++) begin
                observed = held[
                    pod*NPU_UNIFIED_COMPLETION_WIDTH +:
                    NPU_UNIFIED_COMPLETION_WIDTH];
                if ((observed.source != source) ||
                    (observed.request_id != request_base + 16'(pod)) ||
                    (observed.pod_id != 3'(pod)) ||
                    (observed.target !=
                     ((expected_target >= 0) ? 4'(expected_target) :
                      4'(pod & 1))) ||
                    (observed.success != success) ||
                    (observed.code != code) ||
                    (observed.detail !=
                     ((source == NPU_COMPLETION_DMA) ? 32'd1 : 32'd0))) begin
                    $fatal(1,
                        "array completion mismatch slot=%0d observed_pod=%0d source=%0d id=%0h target=%0d success=%0b code=%0d detail=%0d expected_source=%0d expected_target=%0d expected_detail=%0d",
                        pod, observed.pod_id, observed.source, observed.request_id,
                        observed.target, observed.success, observed.code,
                        observed.detail, source,
                        ((expected_target >= 0) ? 4'(expected_target) :
                         4'(pod & 1)),
                        ((source == NPU_COMPLETION_DMA) ? 32'd1 : 32'd0));
                end
                seen[pod] = 1'b1;
            end
            @(negedge clk);
            completion_ready_i = {PODS{1'b1}};
            @(posedge clk);
            @(negedge clk);
            completion_ready_i = '0;
            while (completion_valid_o != '0) @(negedge clk);
        end
    endtask

    task automatic check_array_counters(
        input logic [63:0] accepted_value,
        input logic [63:0] rejected_value,
        input logic [63:0] completed_value,
        input integer skip_pod
    );
        begin
            for (integer pod = 0; pod < PODS; pod++) begin
                if ((pod != skip_pod) &&
                    ((accepted_commands_o[pod*64 +: 64] != accepted_value) ||
                     (rejected_commands_o[pod*64 +: 64] != rejected_value) ||
                     (delivered_completions_o[pod*64 +: 64] !=
                      completed_value))) begin
                    $fatal(1,
                        "array counter mismatch pod=%0d accepted=%0d rejected=%0d completed=%0d",
                        pod, accepted_commands_o[pod*64 +: 64],
                        rejected_commands_o[pod*64 +: 64],
                        delivered_completions_o[pod*64 +: 64]);
                end
            end
        end
    endtask

    task automatic exercise_noc_array;
        logic [CONTROL_FLIT_WIDTH-1:0] expected_control;
        logic [DATA_FLIT_WIDTH-1:0] expected_data;
        begin
            for (integer pod = 0; pod < PODS; pod++) begin
                pod_control_tx_flit_i[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH] =
                    make_array_control_flit(3'(pod), 3'(7-pod),
                        2'(pod), {64'hc011_0000_0000_0000, 61'd0, 3'(pod)});
                noc_control_rx_flit_i[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH] =
                    make_array_control_flit(3'(7-pod), 3'(pod),
                        2'(pod+1), {64'hc022_0000_0000_0000, 61'd0, 3'(pod)});
                for (integer lane = 0; lane < DATA_LANES; lane++) begin
                    pod_data_tx_flit_i[
                        (pod*DATA_LANES+lane)*DATA_FLIT_WIDTH +:
                        DATA_FLIT_WIDTH] = make_array_data_flit(
                            3'(pod), 3'(7-pod), 2'(lane),
                            8'h40 + 8'(pod*2+lane));
                    noc_data_rx_flit_i[
                        (pod*DATA_LANES+lane)*DATA_FLIT_WIDTH +:
                        DATA_FLIT_WIDTH] = make_array_data_flit(
                            3'(7-pod), 3'(pod), 2'(lane+1),
                            8'h80 + 8'(pod*2+lane));
                end
            end

            pod_control_tx_valid_i = {PODS{1'b1}};
            pod_data_tx_valid_i = {PODS*DATA_LANES{1'b1}};
            noc_control_rx_valid_i = {PODS{1'b1}};
            noc_data_rx_valid_i = {PODS*DATA_LANES{1'b1}};
            noc_control_tx_ready_i = '0;
            noc_data_tx_ready_i = '0;
            pod_control_rx_ready_i = '0;
            pod_data_rx_ready_i = '0;
            @(posedge clk);
            @(negedge clk);
            pod_control_tx_valid_i = '0;
            pod_data_tx_valid_i = '0;
            noc_control_rx_valid_i = '0;
            noc_data_rx_valid_i = '0;

            repeat (3) begin
                @(posedge clk);
                if ((noc_control_tx_valid_o != {PODS{1'b1}}) ||
                    (noc_data_tx_valid_o != {PODS*DATA_LANES{1'b1}}) ||
                    (pod_control_rx_valid_o != {PODS{1'b1}}) ||
                    (pod_data_rx_valid_o != {PODS*DATA_LANES{1'b1}})) begin
                    $fatal(1, "array NoC attachment lost a stalled flit");
                end
            end
            for (integer pod = 0; pod < PODS; pod++) begin
                expected_control = make_array_control_flit(
                    3'(pod), 3'(7-pod), 2'(pod),
                    {64'hc011_0000_0000_0000, 61'd0, 3'(pod)});
                if (noc_control_tx_flit_o[
                        pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH] !==
                    expected_control) begin
                    $fatal(1, "array NoC control TX cross-wire pod=%0d", pod);
                end
                expected_control = make_array_control_flit(
                    3'(7-pod), 3'(pod), 2'(pod+1),
                    {64'hc022_0000_0000_0000, 61'd0, 3'(pod)});
                if (pod_control_rx_flit_o[
                        pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH] !==
                    expected_control) begin
                    $fatal(1, "array NoC control RX cross-wire pod=%0d", pod);
                end
                coverage_q.noc_control_tx_seen[pod] = 1'b1;
                coverage_q.noc_control_rx_seen[pod] = 1'b1;
                for (integer lane = 0; lane < DATA_LANES; lane++) begin
                    expected_data = make_array_data_flit(
                        3'(pod), 3'(7-pod), 2'(lane),
                        8'h40 + 8'(pod*2+lane));
                    if (noc_data_tx_flit_o[
                            (pod*DATA_LANES+lane)*DATA_FLIT_WIDTH +:
                            DATA_FLIT_WIDTH] !== expected_data) begin
                        $fatal(1,
                            "array NoC data TX cross-wire pod=%0d lane=%0d",
                            pod, lane);
                    end
                    expected_data = make_array_data_flit(
                        3'(7-pod), 3'(pod), 2'(lane+1),
                        8'h80 + 8'(pod*2+lane));
                    if (pod_data_rx_flit_o[
                            (pod*DATA_LANES+lane)*DATA_FLIT_WIDTH +:
                            DATA_FLIT_WIDTH] !== expected_data) begin
                        $fatal(1,
                            "array NoC data RX cross-wire pod=%0d lane=%0d",
                            pod, lane);
                    end
                end
                coverage_q.noc_data_tx_seen[pod] = 1'b1;
                coverage_q.noc_data_rx_seen[pod] = 1'b1;
            end
            @(negedge clk);
            noc_control_tx_ready_i = {PODS{1'b1}};
            noc_data_tx_ready_i = {PODS*DATA_LANES{1'b1}};
            pod_control_rx_ready_i = {PODS{1'b1}};
            pod_data_rx_ready_i = {PODS*DATA_LANES{1'b1}};
            @(posedge clk);
            @(negedge clk);
            noc_control_tx_ready_i = '0;
            noc_data_tx_ready_i = '0;
            pod_control_rx_ready_i = '0;
            pod_data_rx_ready_i = '0;
        end
    endtask

    initial begin
        logic [PODS-1:0] seen;
        npu_decoded_command_t command;

        clk = 1'b0;
        pod_rst_i = {PODS{1'b1}};
        pod_clear_i = '0;
        pod_quiesce_i = '0;
        command_valid_i = '0;
        command_i = '0;
        completion_ready_i = '0;
        gemm_output_ready_i = {PODS*CLUSTERS*ARRAY_DIM{1'b1}};
        gemm_vector_ready_i = {PODS*CLUSTERS*ARRAY_DIM{1'b1}};
        gemm_feedback_ready_i = {PODS*CLUSTERS*ARRAY_DIM{1'b1}};
        event_set_valid_i = '0;
        event_set_id_i = '0;
        event_clear_valid_i = '0;
        event_clear_id_i = '0;
        pod_control_tx_valid_i = '0;
        pod_control_tx_flit_i = '0;
        noc_control_tx_ready_i = '0;
        pod_data_tx_valid_i = '0;
        /* verilator lint_off WIDTHCONCAT */
        pod_data_tx_flit_i = '0;
        /* verilator lint_on WIDTHCONCAT */
        noc_data_tx_ready_i = '0;
        noc_control_rx_valid_i = '0;
        noc_control_rx_flit_i = '0;
        pod_control_rx_ready_i = '0;
        noc_data_rx_valid_i = '0;
        /* verilator lint_off WIDTHCONCAT */
        noc_data_rx_flit_i = '0;
        /* verilator lint_on WIDTHCONCAT */
        pod_data_rx_ready_i = '0;
        hbm_enable = 1'b0;
        hbm_seed = 32'h52a7_31c9;
        void'($value$plusargs("SEED=%h", hbm_seed));
        coverage_q = '0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        pod_rst_i = '0;
        @(posedge clk);
        if ((|pod_busy_o) || (|command_busy_o) || (|noc_busy_o) ||
            (pod_quiesced_o != '0) ||
            (noc_quiesced_o != {PODS{1'b1}}) ||
            (|pod_protocol_error_o) || (|command_protocol_error_o) ||
            (|noc_protocol_error_o)) begin
            $fatal(1, "array reset state mismatch");
        end

        for (integer pod = 0; pod < PODS; pod++) begin
            command = make_array_task_command(
                3'(pod), 16'h1000 + 16'(pod), 4'(pod & 1));
            command_i[pod*NPU_DECODED_COMMAND_WIDTH +:
                NPU_DECODED_COMMAND_WIDTH] = command;
        end
        submit_all_commands();
        seen = '0;
        collect_all_completions(NPU_COMPLETION_TASK, 16'h1000,
                                1'b1, 8'd0, -1, seen);
        coverage_q.task_completion_seen = seen;
        repeat (5) begin
            @(posedge clk);
            if (completion_valid_o != '0) begin
                $fatal(1,
                    "duplicate Task completion after drain valid=%h accepted0=%0d delivered0=%0d",
                    completion_valid_o, accepted_commands_o[0 +: 64],
                    delivered_completions_o[0 +: 64]);
            end
        end

        hbm_enable = 1'b0;
        for (integer pod = 0; pod < PODS; pod++) begin
            command = make_array_dma_read_command(
                3'(pod), 16'h2000 + 16'(pod),
                35'h1000 + 35'(pod*128), 24'h1000 + 24'(pod*128));
            command_i[pod*NPU_DECODED_COMMAND_WIDTH +:
                NPU_DECODED_COMMAND_WIDTH] = command;
        end
        submit_all_commands();
        // Hold the HBM sink disabled only after at least one request is
        // observable.  This guarantees protocol-stall coverage independently
        // of the selected LFSR seed and of DMA command-to-request latency.
        while (hbm_request_valid_o == '0) @(posedge clk);
        repeat (3) @(posedge clk);
        hbm_enable = 1'b1;
        seen = '0;
        collect_all_completions(NPU_COMPLETION_DMA, 16'h2000,
                                1'b1, 8'd0, 0, seen);
        coverage_q.dma_completion_seen = seen;
        coverage_q.hbm_partition_seen = hbm_partition_seen;
        coverage_q.hbm_backpressure_seen = hbm_backpressure_seen;
        if ((hbm_accepted_requests != 64'd8) ||
            (hbm_delivered_responses != 64'd8) ||
            (hbm_partition_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            hbm_vip_protocol_error) begin
            $fatal(1,
                "array HBM affinity/closure mismatch requests=%0d responses=%0d partitions=%h error=%0b",
                hbm_accepted_requests, hbm_delivered_responses,
                hbm_partition_seen, hbm_vip_protocol_error);
        end
        check_array_counters(64'd2, 64'd0, 64'd2, -1);

        // Exercise both loader FSMs in every Pod through the production
        // decoded-command and shared-SRAM paths.  The preceding DMA command
        // supplied one readable shared-SRAM beat per Pod.
        for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
            for (integer pod = 0; pod < PODS; pod++) begin
                command = make_array_local_command(
                    3'(pod), 16'h2800 + 16'(cluster*PODS + pod),
                    1'(cluster), 24'h1000 + 24'(pod*128));
                command_i[pod*NPU_DECODED_COMMAND_WIDTH +:
                    NPU_DECODED_COMMAND_WIDTH] = command;
            end
            submit_all_commands();
            seen = '0;
            collect_all_completions(
                NPU_COMPLETION_LOCAL,
                16'h2800 + 16'(cluster*PODS), 1'b1, 8'd0,
                cluster, seen);
            coverage_q.local_completion_seen[cluster*PODS +: PODS] = seen;
        end
        check_array_counters(64'd4, 64'd0, 64'd4, -1);

        exercise_noc_array();

        @(negedge clk);
        pod_clear_i[3] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pod_clear_i[3] = 1'b0;
        @(posedge clk);
        if ((accepted_commands_o[3*64 +: 64] != 64'd0) ||
            (rejected_commands_o[3*64 +: 64] != 64'd0) ||
            (delivered_completions_o[3*64 +: 64] != 64'd0)) begin
            $fatal(1, "isolated Pod clear did not reset Pod 3 counters");
        end
        check_array_counters(64'd4, 64'd0, 64'd4, 3);
        coverage_q.isolated_clear_seen = 1'b1;

        for (integer pod = 0; pod < PODS; pod++) begin
            command = make_array_task_command(
                3'((pod+1) % PODS), 16'h3000 + 16'(pod),
                4'(pod & 1));
            command_i[pod*NPU_DECODED_COMMAND_WIDTH +:
                NPU_DECODED_COMMAND_WIDTH] = command;
        end
        submit_all_commands();
        seen = '0;
        collect_all_completions(NPU_COMPLETION_COMMAND, 16'h3000,
            1'b0, 8'(NPU_COMMAND_ERROR_POD), -1, seen);
        coverage_q.malformed_completion_seen = seen;
        if ((malformed_command_seen_o != {PODS{1'b1}}) ||
            (command_protocol_error_o != '0)) begin
            $fatal(1, "array malformed command diagnostics mismatch");
        end

        @(negedge clk);
        pod_clear_i = {PODS{1'b1}};
        @(posedge clk);
        @(negedge clk);
        pod_clear_i = '0;
        @(posedge clk);
        if ((|pod_protocol_error_o) || (|command_protocol_error_o) ||
            (|noc_protocol_error_o) || (|malformed_command_seen_o) ||
            (|accepted_commands_o) || (|rejected_commands_o) ||
            (|delivered_completions_o)) begin
            $fatal(1, "array clear recovery mismatch");
        end

        @(negedge clk);
        pod_quiesce_i[3] = 1'b1;
        pod_control_tx_flit_i[3*CONTROL_FLIT_WIDTH +:
            CONTROL_FLIT_WIDTH] = make_array_control_flit(
                3'd3, 3'd0, 2'd0, 128'h3333);
        pod_control_tx_flit_i[4*CONTROL_FLIT_WIDTH +:
            CONTROL_FLIT_WIDTH] = make_array_control_flit(
                3'd4, 3'd0, 2'd0, 128'h4444);
        pod_control_tx_valid_i[3] = 1'b1;
        pod_control_tx_valid_i[4] = 1'b1;
        #0.1;
        if (pod_control_tx_ready_o[3] || !pod_control_tx_ready_o[4]) begin
            $fatal(1, "per-Pod quiesce isolation mismatch");
        end
        coverage_q.isolated_quiesce_seen = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pod_control_tx_valid_i = '0;
        pod_quiesce_i = '0;
        pod_clear_i[4] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pod_clear_i = '0;

        if ((coverage_q.task_completion_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.dma_completion_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.local_completion_seen != 16'hffff) ||
            (coverage_q.malformed_completion_seen !=
             NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.hbm_partition_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.noc_control_tx_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.noc_control_rx_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.noc_data_tx_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            (coverage_q.noc_data_rx_seen != NPU_POD_ARRAY_ALL_SEEN) ||
            !coverage_q.isolated_clear_seen ||
            !coverage_q.isolated_quiesce_seen ||
            !coverage_q.completion_backpressure_seen ||
            !coverage_q.hbm_backpressure_seen) begin
            $fatal(1, "array functional coverage matrix incomplete: %h",
                   coverage_q);
        end

        $display("[RTL_SIM PASS] npu_2x4_pod_array seed=%08h task=8 dma=8 local=16 malformed=8 hbm=8 noc_flits=48 coverage=%h",
                 hbm_seed, coverage_q);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "npu_2x4_pod_array timeout");
    end

    wire _unused_compute_outputs = &{1'b0, gemm_output_valid_o,
        gemm_output_result_o, gemm_output_command_o, gemm_vector_valid_o,
        gemm_vector_result_o, gemm_vector_command_o, gemm_feedback_valid_o,
        gemm_feedback_result_o, gemm_feedback_command_o};
    wire _unused_array_ready = &{1'b0, pod_control_tx_ready_o,
        pod_data_tx_ready_o, noc_control_rx_ready_o, noc_data_rx_ready_o};

endmodule

`default_nettype wire

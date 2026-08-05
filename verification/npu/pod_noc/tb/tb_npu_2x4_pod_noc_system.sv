`timescale 1ns/1ps
`default_nettype none

module tb_npu_2x4_pod_noc_system;

    import npu_command_pkg::*;
    import npu_pod_noc_system_tb_pkg::*;

    localparam int unsigned PODS = 8;
    localparam int unsigned CLUSTERS = 2;
    localparam int unsigned ARRAY_DIM = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned HBM_TAG_WIDTH = 12;
    localparam int unsigned NOC_PORTS = 5;
    localparam int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH;
    localparam int unsigned DATA_LANES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_LANES;
    localparam int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH;

    logic [PODS-1:0] pod_clk_i;
    logic noc_clk_i;
    logic async_rst_i;
    logic clear_i;
    logic quiesce_i;

    logic [PODS-1:0] command_valid_i;
    logic [PODS-1:0] command_ready_o;
    logic [PODS*NPU_DECODED_COMMAND_WIDTH-1:0] command_i;
    logic [PODS-1:0] completion_valid_o;
    logic [PODS-1:0] completion_ready_i;
    logic [PODS*NPU_UNIFIED_COMPLETION_WIDTH-1:0] completion_o;

    logic [PODS*HBM_LANES-1:0] hbm_request_ready_i;
    logic [PODS*HBM_LANES-1:0] hbm_response_valid_i;
    logic [PODS*HBM_LANES-1:0] hbm_response_write_i;
    logic [PODS*HBM_LANES*PARTITION_BITS-1:0]
        hbm_response_partition_i;
    logic [PODS*HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i;
    logic [PODS*HBM_LANES*DATA_BYTES*8-1:0] hbm_response_read_data_i;
    logic [PODS*HBM_LANES*2-1:0] hbm_response_status_i;

    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_output_ready_i;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_vector_ready_i;
    logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_ready_i;
    logic [PODS*CLUSTERS-1:0] event_set_valid_i;
    logic [PODS*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
        event_set_id_i;
    logic [PODS*CLUSTERS-1:0] event_clear_valid_i;
    logic [PODS*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
        event_clear_id_i;

    logic [PODS-1:0] pod_control_tx_valid_i;
    logic [PODS-1:0] pod_control_tx_ready_o;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit_i;
    logic [PODS-1:0] pod_control_rx_valid_o;
    logic [PODS-1:0] pod_control_rx_ready_i;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit_o;
    logic [PODS*DATA_LANES-1:0] pod_data_tx_valid_i;
    logic [PODS*DATA_LANES-1:0] pod_data_tx_ready_o;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit_i;
    logic [PODS*DATA_LANES-1:0] pod_data_rx_valid_o;
    logic [PODS*DATA_LANES-1:0] pod_data_rx_ready_i;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit_o;

    logic [PODS-1:0] pod_rst_o;
    logic noc_rst_o;
    logic [PODS-1:0] pod_quiesce_o;
    logic [PODS-1:0] pod_busy_o;
    logic [PODS-1:0] pod_quiesced_o;
    logic [PODS-1:0] pod_protocol_error_o;
    logic [PODS-1:0] command_busy_o;
    logic [PODS-1:0] command_protocol_error_o;
    logic [PODS-1:0] malformed_command_seen_o;
    logic [PODS-1:0] attachment_busy_o;
    logic [PODS-1:0] attachment_quiesced_o;
    logic [PODS-1:0] attachment_protocol_error_o;
    logic [PODS*64-1:0] accepted_commands_o;
    logic [PODS*64-1:0] rejected_commands_o;
    logic [PODS*64-1:0] delivered_completions_o;
    logic noc_busy_o;
    logic noc_quiesced_o;
    logic noc_protocol_error_o;
    logic system_busy_o;
    logic system_quiesced_o;
    logic system_protocol_error_o;
    logic [PODS*NOC_PORTS*64-1:0] control_accepted_flits_o;
    logic [DATA_LANES*PODS*NOC_PORTS*64-1:0] data_accepted_flits_o;

    npu_pod_noc_system_coverage_t coverage_q;

    /* verilator lint_off PINCONNECTEMPTY */
    npu_2x4_pod_noc_system #(
        .ARRAY_DIM(ARRAY_DIM)
    ) dut (
        .hbm_request_valid_o(), .hbm_request_write_o(),
        .hbm_request_partition_o(), .hbm_request_address_o(),
        .hbm_request_tag_o(), .hbm_request_write_data_o(),
        .hbm_request_byte_enable_o(), .hbm_response_ready_o(),
        .gemm_output_valid_o(), .gemm_output_result_o(),
        .gemm_output_command_o(), .gemm_vector_valid_o(),
        .gemm_vector_result_o(), .gemm_vector_command_o(),
        .gemm_feedback_valid_o(), .gemm_feedback_result_o(),
        .gemm_feedback_command_o(),
        .pod_cdc_busy_o(), .noc_cdc_busy_o(),
        .control_router_busy_o(), .data_router_busy_o(),
        .control_router_protocol_error_o(),
        .data_router_protocol_error_o(),
        .control_transmitted_flits_o(), .control_blocked_cycles_o(),
        .control_accepted_packets_o(), .control_transmitted_packets_o(),
        .control_maximum_wait_cycles_o(),
        .control_credit_low_watermark_o(),
        .control_invalid_route_events_o(),
        .data_transmitted_flits_o(), .data_blocked_cycles_o(),
        .data_accepted_packets_o(), .data_transmitted_packets_o(),
        .data_maximum_wait_cycles_o(), .data_credit_low_watermark_o(),
        .data_invalid_route_events_o(),
        .*
    );
    /* verilator lint_on PINCONNECTEMPTY */

    generate
        for (genvar pod = 0; pod < PODS; pod++) begin : g_checkers
            npu_ready_valid_protocol_checker #(
                .WIDTH(NPU_DECODED_COMMAND_WIDTH), .CHANNEL_ID(pod)
            ) u_command_checker (
                .clk_i(pod_clk_i[pod]), .rst_i(pod_rst_o[pod]),
                .clear_i(1'b0), .valid_i(command_valid_i[pod]),
                .ready_i(command_ready_o[pod]),
                .payload_i(command_i[pod*NPU_DECODED_COMMAND_WIDTH +:
                    NPU_DECODED_COMMAND_WIDTH]));
            npu_ready_valid_protocol_checker #(
                .WIDTH(NPU_UNIFIED_COMPLETION_WIDTH),
                .CHANNEL_ID(PODS + pod)
            ) u_completion_checker (
                .clk_i(pod_clk_i[pod]), .rst_i(pod_rst_o[pod]),
                .clear_i(1'b0), .valid_i(completion_valid_o[pod]),
                .ready_i(completion_ready_i[pod]),
                .payload_i(completion_o[pod*NPU_UNIFIED_COMPLETION_WIDTH +:
                    NPU_UNIFIED_COMPLETION_WIDTH]));
            npu_ready_valid_protocol_checker #(
                .WIDTH(CONTROL_FLIT_WIDTH), .CHANNEL_ID(2*PODS + pod)
            ) u_control_tx_checker (
                .clk_i(pod_clk_i[pod]), .rst_i(pod_rst_o[pod]),
                .clear_i(1'b0), .valid_i(pod_control_tx_valid_i[pod]),
                .ready_i(pod_control_tx_ready_o[pod]),
                .payload_i(pod_control_tx_flit_i[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]));
            npu_ready_valid_protocol_checker #(
                .WIDTH(CONTROL_FLIT_WIDTH), .CHANNEL_ID(3*PODS + pod)
            ) u_control_rx_checker (
                .clk_i(pod_clk_i[pod]), .rst_i(pod_rst_o[pod]),
                .clear_i(1'b0), .valid_i(pod_control_rx_valid_o[pod]),
                .ready_i(pod_control_rx_ready_i[pod]),
                .payload_i(pod_control_rx_flit_o[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]));
            for (genvar lane = 0; lane < DATA_LANES; lane++) begin : g_lane
                npu_ready_valid_protocol_checker #(
                    .WIDTH(DATA_FLIT_WIDTH),
                    .CHANNEL_ID(4*PODS + pod*DATA_LANES + lane)
                ) u_data_tx_checker (
                    .clk_i(pod_clk_i[pod]), .rst_i(pod_rst_o[pod]),
                    .clear_i(1'b0),
                    .valid_i(pod_data_tx_valid_i[pod*DATA_LANES+lane]),
                    .ready_i(pod_data_tx_ready_o[pod*DATA_LANES+lane]),
                    .payload_i(pod_data_tx_flit_i[
                        (pod*DATA_LANES+lane)*DATA_FLIT_WIDTH +:
                        DATA_FLIT_WIDTH]));
                npu_ready_valid_protocol_checker #(
                    .WIDTH(DATA_FLIT_WIDTH),
                    .CHANNEL_ID(6*PODS + pod*DATA_LANES + lane)
                ) u_data_rx_checker (
                    .clk_i(pod_clk_i[pod]), .rst_i(pod_rst_o[pod]),
                    .clear_i(1'b0),
                    .valid_i(pod_data_rx_valid_o[pod*DATA_LANES+lane]),
                    .ready_i(pod_data_rx_ready_i[pod*DATA_LANES+lane]),
                    .payload_i(pod_data_rx_flit_o[
                        (pod*DATA_LANES+lane)*DATA_FLIT_WIDTH +:
                        DATA_FLIT_WIDTH]));
            end
        end
    endgenerate

    initial pod_clk_i = '0;
    initial noc_clk_i = 1'b0;
    always #0.53 pod_clk_i[0] = ~pod_clk_i[0];
    always #0.59 pod_clk_i[1] = ~pod_clk_i[1];
    always #0.61 pod_clk_i[2] = ~pod_clk_i[2];
    always #0.67 pod_clk_i[3] = ~pod_clk_i[3];
    always #0.71 pod_clk_i[4] = ~pod_clk_i[4];
    always #0.73 pod_clk_i[5] = ~pod_clk_i[5];
    always #0.79 pod_clk_i[6] = ~pod_clk_i[6];
    always #0.83 pod_clk_i[7] = ~pod_clk_i[7];
    always #0.41 noc_clk_i = ~noc_clk_i;

    task automatic send_task_command(input int unsigned pod);
        npu_decoded_command_t command;
        npu_unified_completion_t completion;
        begin
            command = make_task_command(
                3'(pod), 16'h5100 + 16'(pod), 4'(pod & 1));
            @(negedge pod_clk_i[pod]);
            command_i[pod*NPU_DECODED_COMMAND_WIDTH +:
                NPU_DECODED_COMMAND_WIDTH] = command;
            command_valid_i[pod] = 1'b1;
            do @(posedge pod_clk_i[pod]);
            while (!command_ready_o[pod]);
            @(negedge pod_clk_i[pod]);
            command_valid_i[pod] = 1'b0;
            do @(posedge pod_clk_i[pod]);
            while (!completion_valid_o[pod]);
            completion = completion_o[pod*NPU_UNIFIED_COMPLETION_WIDTH +:
                NPU_UNIFIED_COMPLETION_WIDTH];
            if (completion.source != NPU_COMPLETION_TASK ||
                completion.request_id != 16'h5100 + 16'(pod) ||
                completion.pod_id != 3'(pod) ||
                completion.target != 4'(pod & 1) || !completion.success ||
                completion.code != NPU_COMMAND_OK || completion.detail != 0) begin
                $fatal(1, "joint command completion mismatch pod=%0d", pod);
            end
            coverage_q.command_overlap[pod] = 1'b1;
        end
    endtask

    task automatic send_control(
        input int unsigned source,
        input int unsigned destination,
        input logic [23:0] sequence_id,
        input logic apply_backpressure
    );
        logic [CONTROL_FLIT_WIDTH-1:0] flit;
        logic [CONTROL_FLIT_WIDTH-1:0] held;
        begin
            flit = make_control_flit(3'(source), 3'(destination),
                2'(sequence_id), make_control_payload(
                    3'(source), 3'(destination), sequence_id));
            if (apply_backpressure) begin
                @(negedge pod_clk_i[destination]);
                pod_control_rx_ready_i[destination] = 1'b0;
            end
            @(negedge pod_clk_i[source]);
            pod_control_tx_flit_i[source*CONTROL_FLIT_WIDTH +:
                CONTROL_FLIT_WIDTH] = flit;
            pod_control_tx_valid_i[source] = 1'b1;
            do @(posedge pod_clk_i[source]);
            while (!pod_control_tx_ready_o[source]);
            @(negedge pod_clk_i[source]);
            pod_control_tx_valid_i[source] = 1'b0;

            do @(posedge pod_clk_i[destination]);
            while (!pod_control_rx_valid_o[destination]);
            if (pod_control_rx_flit_o[destination*CONTROL_FLIT_WIDTH +:
                    CONTROL_FLIT_WIDTH] !== flit) begin
                $fatal(1, "control route mismatch source=%0d destination=%0d",
                       source, destination);
            end
            if (apply_backpressure) begin
                held = pod_control_rx_flit_o[
                    destination*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH];
                repeat (3) begin
                    @(posedge pod_clk_i[destination]);
                    if (!pod_control_rx_valid_o[destination] ||
                        pod_control_rx_flit_o[
                            destination*CONTROL_FLIT_WIDTH +:
                            CONTROL_FLIT_WIDTH] !== held) begin
                        $fatal(1, "control flit unstable under backpressure");
                    end
                end
                coverage_q.control_backpressure = 1'b1;
                @(negedge pod_clk_i[destination]);
                pod_control_rx_ready_i[destination] = 1'b1;
                @(posedge pod_clk_i[destination]);
            end
            coverage_q.control_routes[
                control_route_index(source, destination)] = 1'b1;
        end
    endtask

    task automatic send_data(
        input int unsigned source,
        input int unsigned destination,
        input int unsigned lane,
        input int unsigned virtual_channel,
        input logic apply_backpressure
    );
        int unsigned source_channel;
        int unsigned destination_channel;
        logic [DATA_FLIT_WIDTH-1:0] flit;
        logic [DATA_FLIT_WIDTH-1:0] held;
        begin
            source_channel = source*DATA_LANES + lane;
            destination_channel = destination*DATA_LANES + lane;
            flit = make_data_flit(3'(source), 3'(destination),
                2'(virtual_channel), make_data_payload_byte(
                    3'(source), 3'(destination), 1'(lane),
                    2'(virtual_channel)));
            if (apply_backpressure) begin
                @(negedge pod_clk_i[destination]);
                pod_data_rx_ready_i[destination_channel] = 1'b0;
            end
            @(negedge pod_clk_i[source]);
            pod_data_tx_flit_i[source_channel*DATA_FLIT_WIDTH +:
                DATA_FLIT_WIDTH] = flit;
            pod_data_tx_valid_i[source_channel] = 1'b1;
            do @(posedge pod_clk_i[source]);
            while (!pod_data_tx_ready_o[source_channel]);
            @(negedge pod_clk_i[source]);
            pod_data_tx_valid_i[source_channel] = 1'b0;

            do @(posedge pod_clk_i[destination]);
            while (!pod_data_rx_valid_o[destination_channel]);
            if (pod_data_rx_flit_o[destination_channel*DATA_FLIT_WIDTH +:
                    DATA_FLIT_WIDTH] !== flit) begin
                $fatal(1,
                    "data route mismatch source=%0d destination=%0d lane=%0d vc=%0d",
                    source, destination, lane, virtual_channel);
            end
            if (apply_backpressure) begin
                held = pod_data_rx_flit_o[
                    destination_channel*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH];
                repeat (3) begin
                    @(posedge pod_clk_i[destination]);
                    if (!pod_data_rx_valid_o[destination_channel] ||
                        pod_data_rx_flit_o[
                            destination_channel*DATA_FLIT_WIDTH +:
                            DATA_FLIT_WIDTH] !== held) begin
                        $fatal(1, "data flit unstable under backpressure");
                    end
                end
                coverage_q.data_backpressure = 1'b1;
                @(negedge pod_clk_i[destination]);
                pod_data_rx_ready_i[destination_channel] = 1'b1;
                @(posedge pod_clk_i[destination]);
            end
            coverage_q.data_lane_vc_routes[data_route_index(
                source, destination, lane, virtual_channel)] = 1'b1;
        end
    endtask

    task automatic wait_for_reset_release;
        int unsigned cycles;
        begin
            cycles = 0;
            while ((noc_rst_o || (|pod_rst_o)) && cycles < 100) begin
                @(posedge noc_clk_i);
                cycles++;
            end
            if (noc_rst_o || (|pod_rst_o))
                $fatal(1, "joint reset did not release");
        end
    endtask

    initial begin
        async_rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        command_valid_i = '0;
        command_i = '0;
        completion_ready_i = '0;
        hbm_request_ready_i = '0;
        hbm_response_valid_i = '0;
        hbm_response_write_i = '0;
        hbm_response_partition_i = '0;
        hbm_response_tag_i = '0;
        /* verilator lint_off WIDTHCONCAT */
        hbm_response_read_data_i = '0;
        hbm_response_status_i = '0;
        gemm_output_ready_i = '1;
        gemm_vector_ready_i = '1;
        gemm_feedback_ready_i = '1;
        event_set_valid_i = '0;
        event_set_id_i = '0;
        event_clear_valid_i = '0;
        event_clear_id_i = '0;
        pod_control_tx_valid_i = '0;
        pod_control_tx_flit_i = '0;
        pod_control_rx_ready_i = '1;
        pod_data_tx_valid_i = '0;
        pod_data_tx_flit_i = '0;
        /* verilator lint_on WIDTHCONCAT */
        pod_data_rx_ready_i = '1;
        coverage_q = '0;

        #10;
        async_rst_i = 1'b0;
        wait_for_reset_release();
        repeat (8) @(posedge noc_clk_i);

        // Keep task completions backpressured while the first real Mesh traffic
        // crosses all four integration layers, proving concurrent operation.
        fork
            begin
                fork
                    send_task_command(0); send_task_command(1);
                    send_task_command(2); send_task_command(3);
                    send_task_command(4); send_task_command(5);
                    send_task_command(6); send_task_command(7);
                join
            end
            begin
                for (int source = 0; source < PODS; source++) begin
                    send_control(source, PODS-1-source, 24'(source),
                                 source == 0);
                end
            end
            begin
                repeat (40) @(posedge noc_clk_i);
                completion_ready_i = '1;
            end
        join

        for (int source = 0; source < PODS; source++) begin
            for (int destination = 0; destination < PODS; destination++) begin
                if (destination != PODS-1-source) begin
                    send_control(source, destination,
                        24'(source*PODS + destination),
                        source == 3 && destination == 6);
                end
            end
        end

        for (int source = 0; source < PODS; source++) begin
            for (int destination = 0; destination < PODS; destination++) begin
                for (int lane = 0; lane < DATA_LANES; lane++) begin
                    for (int vc = 0; vc < 4; vc++) begin
                        send_data(source, destination, lane, vc,
                            source == 6 && destination == 1 &&
                            lane == 1 && vc == 3);
                    end
                end
            end
        end

        if (coverage_q.control_routes != '1 ||
            coverage_q.data_lane_vc_routes != '1 ||
            coverage_q.command_overlap != '1 ||
            !coverage_q.control_backpressure ||
            !coverage_q.data_backpressure) begin
            $fatal(1, "joint functional coverage matrix incomplete");
        end
        if (system_protocol_error_o || (|pod_protocol_error_o) ||
            (|command_protocol_error_o) ||
            (|attachment_protocol_error_o) || noc_protocol_error_o ||
            (|malformed_command_seen_o) || (|rejected_commands_o)) begin
            $fatal(1, "joint path reported a protocol error");
        end

        @(negedge noc_clk_i);
        quiesce_i = 1'b1;
        for (int cycles = 0; cycles < 500 && !system_quiesced_o; cycles++)
            @(posedge noc_clk_i);
        if (!system_quiesced_o || !noc_quiesced_o ||
            pod_control_tx_ready_o != '0 || pod_data_tx_ready_o != '0) begin
            $fatal(1, "joint quiesce did not drain and block injection");
        end
        coverage_q.quiesce_drain = 1'b1;
        @(negedge noc_clk_i);
        quiesce_i = 1'b0;
        repeat (16) @(posedge noc_clk_i);

        @(negedge noc_clk_i);
        clear_i = 1'b1;
        repeat (4) @(posedge noc_clk_i);
        clear_i = 1'b0;
        wait_for_reset_release();
        repeat (8) @(posedge noc_clk_i);
        if ((|accepted_commands_o) || (|delivered_completions_o) ||
            (|control_accepted_flits_o) || (|data_accepted_flits_o) ||
            system_protocol_error_o) begin
            $fatal(1, "joint clear did not recover all integrated state");
        end
        coverage_q.clear_recovery = 1'b1;

        if (!coverage_q.quiesce_drain || !coverage_q.clear_recovery)
            $fatal(1, "joint lifecycle coverage incomplete");

        $display("[RTL_SIM PASS] npu_2x4_pod_noc_system control_routes=64 data_lane_vc_routes=512 commands=8 distinct_pod_clocks=8");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "npu_2x4_pod_noc_system timeout");
    end

    wire _unused_status = &{1'b0, pod_quiesce_o, pod_busy_o,
        pod_quiesced_o, command_busy_o, attachment_busy_o,
        attachment_quiesced_o, accepted_commands_o,
        delivered_completions_o, noc_busy_o, system_busy_o};

endmodule

`default_nettype wire

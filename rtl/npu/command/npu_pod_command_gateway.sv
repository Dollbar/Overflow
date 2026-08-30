`timescale 1ns/1ps
`default_nettype none

// Router-independent NPU internal command sink for one Pod. It consumes an
// already-decoded record, fans it into the existing task/local/DMA interfaces,
// and serializes leaf completions into one stable ready/valid stream.
module npu_pod_command_gateway #(
    parameter int unsigned POD_ID = 0,
    parameter int unsigned CLUSTERS = 2,
    parameter int unsigned DMA_CHANNELS = 16,
    parameter int unsigned CLUSTER_INDEX_WIDTH =
        (CLUSTERS <= 1) ? 1 : $clog2(CLUSTERS)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_command_pkg::NPU_DECODED_COMMAND_WIDTH-1:0]
                 command_i,

    output logic task_valid_o,
    input  logic task_ready_i,
    output logic task_preferred_cluster_valid_o,
    output logic [CLUSTER_INDEX_WIDTH-1:0] task_preferred_cluster_o,
    output logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_o,

    output logic [CLUSTERS-1:0] local_command_valid_o,
    input  logic [CLUSTERS-1:0] local_command_ready_i,
    output logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]
                 local_command_o,

    output logic [DMA_CHANNELS-1:0] dma_command_valid_o,
    input  logic [DMA_CHANNELS-1:0] dma_command_ready_i,
    output logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]
                 dma_command_o,

    input  logic task_completion_valid_i,
    output logic task_completion_ready_o,
    input  logic [CLUSTER_INDEX_WIDTH-1:0] task_completion_cluster_i,
    input  logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0]
                 task_completion_status_i,

    input  logic [CLUSTERS-1:0] local_completion_valid_i,
    output logic [CLUSTERS-1:0] local_completion_ready_o,
    input  logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH-1:0]
                 local_completion_i,

    input  logic [DMA_CHANNELS-1:0] dma_completion_valid_i,
    output logic [DMA_CHANNELS-1:0] dma_completion_ready_o,
    input  logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0]
                 dma_completion_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH-1:0]
                 completion_o,

    output logic [63:0] accepted_commands_o,
    output logic [63:0] rejected_commands_o,
    output logic [63:0] delivered_completions_o,
    output logic malformed_seen_o,
    output logic busy_o,
    output logic protocol_error_o
);

    localparam int unsigned COMPLETION_SOURCES =
        1 + CLUSTERS + DMA_CHANNELS;
    localparam int unsigned COMPLETION_INDEX_WIDTH =
        (COMPLETION_SOURCES <= 1) ? 1 : $clog2(COMPLETION_SOURCES);

    npu_command_pkg::npu_decoded_command_t command_fields;
    /* verilator lint_off UNUSEDSIGNAL */
    npu_scheduler_pkg::npu_task_descriptor_t task_fields;
    npu_pod_pkg::npu_pod_local_transfer_t local_fields;
    npu_dma_pkg::npu_dma_command_t dma_fields;
    /* verilator lint_on UNUSEDSIGNAL */
    npu_scheduler_pkg::npu_task_status_t task_completion_fields;

    npu_command_pkg::npu_command_error_e envelope_error;
    npu_command_pkg::npu_unified_completion_t error_completion_q;
    npu_command_pkg::npu_unified_completion_t completion_q;
    npu_command_pkg::npu_unified_completion_t selected_completion;
    logic envelope_valid;
    logic command_fire;
    logic command_rejected;
    logic error_valid_q;
    logic error_capture;
    logic completion_valid_q;
    logic completion_capture;
    logic completion_pop;
    logic completion_select_valid;
    logic [COMPLETION_INDEX_WIDTH-1:0] completion_select_index;
    logic [COMPLETION_INDEX_WIDTH-1:0] completion_rr_q;
    integer completion_candidate;

    always_comb begin
        command_fields =
            npu_command_pkg::npu_decoded_command_t'(command_i);
        task_fields = npu_scheduler_pkg::npu_task_descriptor_t'(
            command_fields.payload[
                npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0]);
        local_fields = npu_pod_pkg::npu_pod_local_transfer_t'(
            command_fields.payload[
                npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]);
        dma_fields = npu_dma_pkg::npu_dma_command_t'(
            command_fields.payload[npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]);

        envelope_error = npu_command_pkg::NPU_COMMAND_OK;
        if (command_fields.version !=
            npu_command_pkg::NPU_DECODED_COMMAND_VERSION) begin
            envelope_error = npu_command_pkg::NPU_COMMAND_ERROR_VERSION;
        end else if (integer'(command_fields.command_class) >
                     integer'(npu_command_pkg::NPU_DECODED_DMA)) begin
            envelope_error = npu_command_pkg::NPU_COMMAND_ERROR_CLASS;
        end else if (command_fields.pod_id !=
                     npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID)) begin
            envelope_error = npu_command_pkg::NPU_COMMAND_ERROR_POD;
        end else begin
            unique case (command_fields.command_class)
                npu_command_pkg::NPU_DECODED_TASK: begin
                    if (command_fields.target_valid &&
                        (integer'(command_fields.target) >= CLUSTERS)) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_TARGET;
                    end else if (command_fields.request_id !=
                                 task_fields.job_id) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_REQUEST_ID;
                    end else if (!(((task_fields.operation ==
                                      npu_scheduler_pkg::NPU_TASK_GEMM) &&
                                     (task_fields.version ==
                                      npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_VERSION)) ||
                                    ((task_fields.operation ==
                                      npu_scheduler_pkg::NPU_TASK_VECTOR) &&
                                     (task_fields.version ==
                                      npu_scheduler_pkg::NPU_VECTOR_TASK_DESCRIPTOR_VERSION)))) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_PAYLOAD_VERSION;
                    end
                end
                npu_command_pkg::NPU_DECODED_LOCAL: begin
                    if (!command_fields.target_valid ||
                        (integer'(command_fields.target) >= CLUSTERS)) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_TARGET;
                    end else if (command_fields.request_id !=
                                 local_fields.transfer_id) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_REQUEST_ID;
                    end else if (local_fields.version !=
                                 npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_PAYLOAD_VERSION;
                    end
                end
                npu_command_pkg::NPU_DECODED_DMA: begin
                    if (!command_fields.target_valid ||
                        (integer'(command_fields.target) >= DMA_CHANNELS)) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_TARGET;
                    end else if (command_fields.request_id !=
                                 dma_fields.command_id) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_REQUEST_ID;
                    end else if (dma_fields.version !=
                                 npu_dma_pkg::NPU_DMA_COMMAND_VERSION) begin
                        envelope_error =
                            npu_command_pkg::NPU_COMMAND_ERROR_PAYLOAD_VERSION;
                    end
                end
                default: begin
                    envelope_error =
                        npu_command_pkg::NPU_COMMAND_ERROR_CLASS;
                end
            endcase
        end
        envelope_valid = envelope_error == npu_command_pkg::NPU_COMMAND_OK;

        task_valid_o = 1'b0;
        task_preferred_cluster_valid_o = command_fields.target_valid;
        task_preferred_cluster_o = command_fields.target[
            CLUSTER_INDEX_WIDTH-1:0];
        task_o = command_fields.payload[
            npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0];
        local_command_valid_o = '0;
        local_command_o = '0;
        dma_command_valid_o = '0;
        dma_command_o = '0;
        command_ready_o = 1'b0;

        if (!rst_i && !clear_i && !quiesce_i) begin
            if (!envelope_valid) begin
                command_ready_o = !error_valid_q;
            end else begin
                unique case (command_fields.command_class)
                    npu_command_pkg::NPU_DECODED_TASK: begin
                        task_valid_o = command_valid_i;
                        command_ready_o = task_ready_i;
                    end
                    npu_command_pkg::NPU_DECODED_LOCAL: begin
                        for (integer cluster = 0; cluster < CLUSTERS;
                             cluster++) begin
                            if (cluster == integer'(command_fields.target)) begin
                                local_command_o[
                                    cluster*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH
                                    +: npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH
                                ] = command_fields.payload[
                                    npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0];
                                local_command_valid_o[cluster] = command_valid_i;
                                command_ready_o = local_command_ready_i[cluster];
                            end
                        end
                    end
                    npu_command_pkg::NPU_DECODED_DMA: begin
                        for (integer channel = 0; channel < DMA_CHANNELS;
                             channel++) begin
                            if (channel == integer'(command_fields.target)) begin
                                dma_command_o[
                                    channel*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH
                                    +: npu_dma_pkg::NPU_DMA_COMMAND_WIDTH
                                ] = command_fields.payload[
                                    npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0];
                                dma_command_valid_o[channel] = command_valid_i;
                                command_ready_o = dma_command_ready_i[channel];
                            end
                        end
                    end
                    default: begin
                        command_ready_o = !error_valid_q;
                    end
                endcase
            end
        end
        command_fire = command_valid_i && command_ready_o;
        command_rejected = command_fire && !envelope_valid;
    end

    always_comb begin
        task_completion_fields =
            npu_scheduler_pkg::npu_task_status_t'(task_completion_status_i);

        completion_select_valid = 1'b0;
        completion_select_index = '0;
        selected_completion = '0;
        task_completion_ready_o = 1'b0;
        local_completion_ready_o = '0;
        dma_completion_ready_o = '0;
        completion_capture = 1'b0;
        error_capture = 1'b0;
        completion_pop = completion_valid_q && completion_ready_i;
        completion_candidate = 0;

        if (!completion_valid_q && !error_valid_q) begin
            for (integer offset = 0; offset < COMPLETION_SOURCES; offset++) begin
                completion_candidate = integer'(completion_rr_q) + offset;
                if (completion_candidate >= COMPLETION_SOURCES) begin
                    completion_candidate =
                        completion_candidate - COMPLETION_SOURCES;
                end
                if (!completion_select_valid) begin
                    if ((completion_candidate == 0) &&
                        task_completion_valid_i) begin
                        completion_select_valid = 1'b1;
                        completion_select_index =
                            COMPLETION_INDEX_WIDTH'(completion_candidate);
                        selected_completion.source =
                            npu_command_pkg::NPU_COMPLETION_TASK;
                        selected_completion.request_id =
                            task_completion_fields.job_id;
                        selected_completion.pod_id =
                            npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID);
                        selected_completion.target =
                            npu_command_pkg::NPU_DECODED_TARGET_WIDTH'(
                                task_completion_cluster_i);
                        selected_completion.success =
                            task_completion_fields.success;
                        selected_completion.code =
                            8'(task_completion_fields.code);
                        selected_completion.detail[7:0] =
                            task_completion_fields.tag;
                        task_completion_ready_o = 1'b1;
                    end
                    for (integer cluster = 0; cluster < CLUSTERS;
                         cluster++) begin
                        if ((completion_candidate == (1 + cluster)) &&
                            local_completion_valid_i[cluster]) begin
                            completion_select_valid = 1'b1;
                            completion_select_index =
                                COMPLETION_INDEX_WIDTH'(completion_candidate);
                            selected_completion.source =
                                npu_command_pkg::NPU_COMPLETION_LOCAL;
                            selected_completion.request_id =
                                local_completion_i[
                                    cluster*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH
                                    + 4 +: 16];
                            selected_completion.pod_id =
                                npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID);
                            selected_completion.target =
                                npu_command_pkg::NPU_DECODED_TARGET_WIDTH'(
                                    cluster);
                            selected_completion.success =
                                local_completion_i[
                                    cluster*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH
                                    + 3];
                            selected_completion.code =
                                8'(local_completion_i[
                                    cluster*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH
                                    +: 3]);
                            local_completion_ready_o[cluster] = 1'b1;
                        end
                    end
                    for (integer channel = 0; channel < DMA_CHANNELS;
                         channel++) begin
                        if ((completion_candidate ==
                             (1 + CLUSTERS + channel)) &&
                            dma_completion_valid_i[channel]) begin
                            completion_select_valid = 1'b1;
                            completion_select_index =
                                COMPLETION_INDEX_WIDTH'(completion_candidate);
                            selected_completion.source =
                                npu_command_pkg::NPU_COMPLETION_DMA;
                            selected_completion.request_id =
                                dma_completion_i[
                                    channel*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH
                                    + 23 +: 16];
                            selected_completion.pod_id =
                                npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID);
                            selected_completion.target =
                                npu_command_pkg::NPU_DECODED_TARGET_WIDTH'(
                                    channel);
                            selected_completion.success =
                                dma_completion_i[
                                    channel*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH
                                    + 22];
                            selected_completion.code =
                                8'(dma_completion_i[
                                    channel*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH
                                    + 19 +: 3]);
                            selected_completion.detail[
                                npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH-1:0
                            ] = dma_completion_i[
                                channel*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH
                                +: npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH];
                            selected_completion.detail[31] =
                                dma_completion_i[
                                    channel*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH
                                    + 18];
                            dma_completion_ready_o[channel] = 1'b1;
                        end
                    end
                end
            end
        end
        completion_capture = completion_select_valid;
        error_capture = !completion_valid_q && error_valid_q;
    end

    assign completion_valid_o = completion_valid_q;
    assign completion_o = completion_q;
    assign busy_o = error_valid_q || completion_valid_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            error_valid_q <= 1'b0;
            error_completion_q <= '0;
            completion_valid_q <= 1'b0;
            completion_q <= '0;
            completion_rr_q <= '0;
            accepted_commands_o <= 64'd0;
            rejected_commands_o <= 64'd0;
            delivered_completions_o <= 64'd0;
            malformed_seen_o <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            if (command_fire && envelope_valid) begin
                accepted_commands_o <= accepted_commands_o + 64'd1;
            end
            if (command_rejected) begin
                rejected_commands_o <= rejected_commands_o + 64'd1;
                malformed_seen_o <= 1'b1;
                error_valid_q <= 1'b1;
                error_completion_q.source <=
                    npu_command_pkg::NPU_COMPLETION_COMMAND;
                error_completion_q.request_id <= command_fields.request_id;
                error_completion_q.pod_id <=
                    npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID);
                error_completion_q.target <= command_fields.target;
                error_completion_q.success <= 1'b0;
                error_completion_q.code <= 8'(envelope_error);
                error_completion_q.detail <= '0;
            end
            if (error_capture) begin
                completion_valid_q <= 1'b1;
                completion_q <= error_completion_q;
                error_valid_q <= 1'b0;
            end else if (completion_capture) begin
                completion_valid_q <= 1'b1;
                completion_q <= selected_completion;
                if (completion_select_index ==
                    COMPLETION_INDEX_WIDTH'(COMPLETION_SOURCES - 1)) begin
                    completion_rr_q <= '0;
                end else begin
                    completion_rr_q <= completion_select_index + 1'b1;
                end
            end else if (completion_pop) begin
                completion_valid_q <= 1'b0;
            end
            if (completion_pop) begin
                delivered_completions_o <= delivered_completions_o + 64'd1;
            end
            if (command_rejected && error_valid_q && !error_capture) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (POD_ID < npu_pod_pkg::NPU_POD_COUNT)
            else $error("npu_pod_command_gateway POD_ID is out of range");
        assert (CLUSTERS > 0 && CLUSTERS <=
                (1 << npu_command_pkg::NPU_DECODED_TARGET_WIDTH))
            else $error("npu_pod_command_gateway CLUSTERS is invalid");
        assert (DMA_CHANNELS > 0 && DMA_CHANNELS <=
                (1 << npu_command_pkg::NPU_DECODED_TARGET_WIDTH))
            else $error("npu_pod_command_gateway DMA_CHANNELS is invalid");
        assert (npu_command_pkg::NPU_DECODED_COMMAND_PAYLOAD_WIDTH >=
                npu_dma_pkg::NPU_DMA_COMMAND_WIDTH)
            else $error("decoded payload is narrower than DMA command");
        assert (npu_command_pkg::NPU_DECODED_COMMAND_PAYLOAD_WIDTH >=
                npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH)
            else $error("decoded payload is narrower than local command");
        assert (npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH ==
                $bits(npu_scheduler_pkg::npu_task_descriptor_t))
            else $error("task descriptor ABI width constant is stale");
        assert (npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH ==
                $bits(npu_scheduler_pkg::npu_task_status_t))
            else $error("task status ABI width constant is stale");
        assert (npu_command_pkg::NPU_DECODED_COMMAND_WIDTH ==
                $bits(npu_command_pkg::npu_decoded_command_t))
            else $error("decoded command ABI width constant is stale");
        assert (npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH ==
                $bits(npu_command_pkg::npu_unified_completion_t))
            else $error("unified completion ABI width constant is stale");
        assert (npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH == 20)
            else $error("local completion packed slicing must be updated");
        assert (npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH == 39)
            else $error("DMA completion packed slicing must be updated");
    end
`endif

endmodule

`default_nettype wire

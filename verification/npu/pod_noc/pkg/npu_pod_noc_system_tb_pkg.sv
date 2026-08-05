`timescale 1ns/1ps

package npu_pod_noc_system_tb_pkg;

    typedef struct packed {
        logic [63:0] control_routes;
        logic [511:0] data_lane_vc_routes;
        logic [7:0] command_overlap;
        logic control_backpressure;
        logic data_backpressure;
        logic quiesce_drain;
        logic clear_recovery;
    } npu_pod_noc_system_coverage_t;

    function automatic int unsigned control_route_index(
        input int unsigned source,
        input int unsigned destination
    );
        return source * 8 + destination;
    endfunction

    function automatic int unsigned data_route_index(
        input int unsigned source,
        input int unsigned destination,
        input int unsigned lane,
        input int unsigned virtual_channel
    );
        return (((source * 8) + destination) * 2 + lane) * 4 +
            virtual_channel;
    endfunction

    function automatic [127:0] make_control_payload(
        input logic [2:0] source,
        input logic [2:0] destination,
        input logic [23:0] sequence_id
    );
        return {32'hc011_cafe, 24'(sequence_id), 3'(source), 3'(destination),
                66'h2_55aa_1234_5678_9abc};
    endfunction

    function automatic [7:0] make_data_payload_byte(
        input logic [2:0] source,
        input logic [2:0] destination,
        input logic lane,
        input logic [1:0] virtual_channel
    );
        return (8'(source) << 5) ^ (8'(destination) << 2) ^
            (8'(lane) << 1) ^ 8'(virtual_channel) ^ 8'ha5;
    endfunction

    function automatic npu_command_pkg::npu_decoded_command_t
        make_task_command(
            input logic [2:0] pod_id,
            input logic [15:0] job_id,
            input logic [3:0] cluster
        );
        npu_command_pkg::npu_decoded_command_t command;
        npu_scheduler_pkg::npu_task_descriptor_t descriptor;
        descriptor = '0;
        descriptor.version = npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_VERSION;
        descriptor.operation = npu_scheduler_pkg::NPU_TASK_GEMM;
        descriptor.job_id = job_id;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_TASK;
        command.request_id = job_id;
        command.pod_id = pod_id;
        command.target_valid = 1'b1;
        command.target = cluster;
        command.payload = descriptor;
        return command;
    endfunction

    function automatic [npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH-1:0]
        make_control_flit(
            input logic [2:0] source,
            input logic [2:0] destination,
            input logic [1:0] traffic_class,
            input logic [127:0] payload
        );
        return {
            npu_pod_noc_pkg::NPU_POD_NOC_VERSION, 1'b1, 1'b1,
            source, destination, traffic_class,
            {npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES{1'b1}}, payload
        };
    endfunction

    function automatic [npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH-1:0]
        make_data_flit(
            input logic [2:0] source,
            input logic [2:0] destination,
            input logic [1:0] traffic_class,
            input logic [7:0] payload_byte
        );
        return {
            npu_pod_noc_pkg::NPU_POD_NOC_VERSION, 1'b1, 1'b1,
            source, destination, traffic_class,
            {npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES{1'b1}},
            {npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES{payload_byte}}
        };
    endfunction

endpackage

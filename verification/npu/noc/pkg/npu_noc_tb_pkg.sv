`timescale 1ns/1ps

package npu_noc_tb_pkg;

    localparam int unsigned CONTROL_BYTES =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES;
    localparam int unsigned DATA_BYTES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES;
    localparam int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH;
    localparam int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH;

    typedef struct packed {
        logic version_error_seen;
        logic malformed_packet_seen;
        logic local_backpressure_seen;
        logic credit_exhaustion_seen;
        logic credit_return_seen;
        logic arbitration_seen;
        logic [3:0] traffic_class_seen;
        logic [4:0] output_port_seen;
    } npu_noc_router_coverage_t;

    function automatic [CONTROL_FLIT_WIDTH-1:0] make_control_flit(
        input logic sop,
        input logic eop,
        input logic [2:0] source,
        input logic [2:0] destination,
        input logic [1:0] traffic_class,
        input logic [127:0] payload
    );
        make_control_flit = {
            npu_pod_noc_pkg::NPU_POD_NOC_VERSION,
            sop,
            eop,
            source,
            destination,
            traffic_class,
            {CONTROL_BYTES{1'b1}},
            payload
        };
    endfunction

    function automatic [DATA_FLIT_WIDTH-1:0] make_data_flit(
        input logic sop,
        input logic eop,
        input logic [2:0] source,
        input logic [2:0] destination,
        input logic [1:0] traffic_class,
        input logic [7:0] payload_byte
    );
        make_data_flit = {
            npu_pod_noc_pkg::NPU_POD_NOC_VERSION,
            sop,
            eop,
            source,
            destination,
            traffic_class,
            {DATA_BYTES{1'b1}},
            {DATA_BYTES{payload_byte}}
        };
    endfunction

    /* Field accessors intentionally ignore the remaining opaque flit bits. */
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [2:0] data_destination(
        input logic [DATA_FLIT_WIDTH-1:0] flit
    );
        data_destination = flit[DATA_BYTES*9 + 2 +: 3];
    endfunction

    function automatic logic [2:0] data_source(
        input logic [DATA_FLIT_WIDTH-1:0] flit
    );
        data_source = flit[DATA_BYTES*9 + 5 +: 3];
    endfunction

    function automatic logic [1:0] data_traffic_class(
        input logic [DATA_FLIT_WIDTH-1:0] flit
    );
        data_traffic_class = flit[DATA_BYTES*9 +: 2];
    endfunction

    function automatic logic [7:0] data_payload_byte(
        input logic [DATA_FLIT_WIDTH-1:0] flit
    );
        data_payload_byte = flit[7:0];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

endpackage

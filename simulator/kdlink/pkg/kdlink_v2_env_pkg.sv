package kdlink_v2_env_pkg;
    localparam int unsigned KDLINK_V2_CARD_SLOTS = 8;
    localparam int unsigned KDLINK_V2_NPUS_PER_CARD = 4;
    localparam int unsigned KDLINK_V2_NODES = 32;
    localparam int unsigned KDLINK_V2_PLANES = 8;
    localparam int unsigned KDLINK_V2_SLICES_PER_PORT = 2;
    localparam int unsigned KDLINK_V2_SLICES_PER_NPU = 16;
    localparam int unsigned KDLINK_V2_SLICES_PER_CARD = 64;
    localparam int unsigned KDLINK_V2_ENDPOINT_SLICES = 512;
    localparam int unsigned KDLINK_V2_PCS_LANES = 10;
    localparam int unsigned KDLINK_V2_PCS_BLOCK_WIDTH = 66;
    localparam int unsigned KDLINK_V2_PCS_GROUP_WIDTH = 660;

    typedef enum logic [1:0] {
        KDLINK_LINK_DOWN = 2'd0,
        KDLINK_LINK_TRAINING = 2'd1,
        KDLINK_LINK_UP = 2'd2,
        KDLINK_LINK_DEGRADED = 2'd3
    } kdlink_v2_link_state_t;

    typedef enum logic [2:0] {
        KDLINK_FAULT_NONE = 3'd0,
        KDLINK_FAULT_DROP = 3'd1,
        KDLINK_FAULT_CORRUPT = 3'd2,
        KDLINK_FAULT_LANE_DOWN = 3'd3,
        KDLINK_FAULT_CARD_REMOVE = 3'd4,
        KDLINK_FAULT_PLANE_DOWN = 3'd5
    } kdlink_v2_fault_kind_t;

    typedef struct packed {
        logic [2:0] plane_id;
        logic slice_id;
        logic [1:0] local_npu;
        logic [2:0] slot_id;
        logic [4:0] node_id;
    } kdlink_v2_endpoint_location_t;

    function automatic int unsigned kdlink_v2_endpoint_index(
        input int unsigned slot_id,
        input int unsigned local_npu,
        input int unsigned plane_id,
        input int unsigned slice_id
    );
        kdlink_v2_endpoint_index =
            (((slot_id * KDLINK_V2_NPUS_PER_CARD) + local_npu) * KDLINK_V2_SLICES_PER_NPU) +
            (plane_id * KDLINK_V2_SLICES_PER_PORT) + slice_id;
    endfunction

    function automatic kdlink_v2_endpoint_location_t kdlink_v2_decode_endpoint(
        input int unsigned endpoint_index
    );
        kdlink_v2_endpoint_location_t location;
        int unsigned node_id;
        int unsigned bank_id;
        begin
            node_id = endpoint_index / KDLINK_V2_SLICES_PER_NPU;
            bank_id = endpoint_index % KDLINK_V2_SLICES_PER_NPU;
            location.node_id = node_id[4:0];
            location.slot_id = node_id[4:2];
            location.local_npu = node_id[1:0];
            location.plane_id = bank_id[3:1];
            location.slice_id = bank_id[0];
            kdlink_v2_decode_endpoint = location;
        end
    endfunction
endpackage

package kdlink_env_pkg;
    localparam int unsigned KDLINK_MAX_CARD_SLOTS = 32; // 声明可配置目录支持的最大物理卡槽数
    localparam int unsigned KDLINK_DEFAULT_CARD_SLOTS = 8; // 声明复位兼容布局默认使用八个卡槽
    localparam int unsigned KDLINK_DEFAULT_NPUS_PER_CARD = 4; // 声明复位兼容布局默认每卡四个NPU
    localparam int unsigned KDLINK_CARD_SLOTS = KDLINK_DEFAULT_CARD_SLOTS; // 保留旧测试使用的默认卡槽别名
    localparam int unsigned KDLINK_NPUS_PER_CARD = KDLINK_DEFAULT_NPUS_PER_CARD; // 保留旧测试使用的默认卡规格别名
    localparam int unsigned KDLINK_NODES = 32;
    localparam int unsigned KDLINK_PLANES = 8;
    localparam int unsigned KDLINK_SLICES_PER_PORT = 2;
    localparam int unsigned KDLINK_SLICES_PER_NPU = 16;
    localparam int unsigned KDLINK_DEFAULT_SLICES_PER_CARD = 64; // 声明四NPU默认卡的端口切片数量
    localparam int unsigned KDLINK_SLICES_PER_CARD = KDLINK_DEFAULT_SLICES_PER_CARD; // 保留旧测试使用的默认切片别名
    localparam int unsigned KDLINK_ENDPOINT_SLICES = 512;
    localparam int unsigned KDLINK_PCS_LANES = 10;
    localparam int unsigned KDLINK_PCS_BLOCK_WIDTH = 66;
    localparam int unsigned KDLINK_PCS_GROUP_WIDTH = 660;
    localparam logic [2:0] KDLINK_NPU_COUNT_CODE_1 = 3'd0; // 编码单NPU卡规格
    localparam logic [2:0] KDLINK_NPU_COUNT_CODE_2 = 3'd1; // 编码双NPU卡规格
    localparam logic [2:0] KDLINK_NPU_COUNT_CODE_4 = 3'd2; // 编码四NPU卡规格
    localparam logic [2:0] KDLINK_NPU_COUNT_CODE_8 = 3'd3; // 编码八NPU卡规格
    localparam logic [2:0] KDLINK_NPU_COUNT_CODE_16 = 3'd4; // 编码十六NPU卡规格
    localparam logic [2:0] KDLINK_NPU_COUNT_CODE_32 = 3'd5; // 编码三十二NPU卡规格

    typedef enum logic [1:0] {
        KDLINK_LINK_DOWN = 2'd0,
        KDLINK_LINK_TRAINING = 2'd1,
        KDLINK_LINK_UP = 2'd2,
        KDLINK_LINK_DEGRADED = 2'd3
    } kdlink_link_state_t;

    typedef enum logic [2:0] {
        KDLINK_FAULT_NONE = 3'd0,
        KDLINK_FAULT_DROP = 3'd1,
        KDLINK_FAULT_CORRUPT = 3'd2,
        KDLINK_FAULT_LANE_DOWN = 3'd3,
        KDLINK_FAULT_CARD_REMOVE = 3'd4,
        KDLINK_FAULT_PLANE_DOWN = 3'd5
    } kdlink_fault_kind_t;

    typedef struct packed {
        logic [2:0] plane_id;
        logic slice_id;
        logic [4:0] local_npu; // 容纳三十二NPU卡的卡内编号
        logic [4:0] slot_id; // 容纳最多三十二个物理卡槽编号
        logic [4:0] node_id;
    } kdlink_endpoint_location_t;

    function automatic int unsigned kdlink_endpoint_index(
        input int unsigned slot_id,
        input int unsigned local_npu,
        input int unsigned plane_id,
        input int unsigned slice_id
    );
        kdlink_endpoint_index =
            (((slot_id * KDLINK_DEFAULT_NPUS_PER_CARD) + local_npu) * KDLINK_SLICES_PER_NPU) +
            (plane_id * KDLINK_SLICES_PER_PORT) + slice_id;
    endfunction

    function automatic bit kdlink_npu_count_code_is_valid(
        input logic [2:0] npu_count_code
    );
        kdlink_npu_count_code_is_valid =
            (npu_count_code <= KDLINK_NPU_COUNT_CODE_32);
    endfunction

    function automatic int unsigned kdlink_npu_count_from_code(
        input logic [2:0] npu_count_code
    );
        case (npu_count_code)
            KDLINK_NPU_COUNT_CODE_1: kdlink_npu_count_from_code = 1;
            KDLINK_NPU_COUNT_CODE_2: kdlink_npu_count_from_code = 2;
            KDLINK_NPU_COUNT_CODE_4: kdlink_npu_count_from_code = 4;
            KDLINK_NPU_COUNT_CODE_8: kdlink_npu_count_from_code = 8;
            KDLINK_NPU_COUNT_CODE_16: kdlink_npu_count_from_code = 16;
            KDLINK_NPU_COUNT_CODE_32: kdlink_npu_count_from_code = 32;
            default: kdlink_npu_count_from_code = 0;
        endcase
    endfunction

    function automatic int unsigned kdlink_card_slices_from_code(
        input logic [2:0] npu_count_code
    );
        kdlink_card_slices_from_code =
            kdlink_npu_count_from_code(npu_count_code) * KDLINK_SLICES_PER_NPU;
    endfunction

    function automatic kdlink_endpoint_location_t kdlink_decode_endpoint(
        input int unsigned endpoint_index
    );
        kdlink_endpoint_location_t location;
        int unsigned node_id;
        int unsigned bank_id;
        begin
            node_id = endpoint_index / KDLINK_SLICES_PER_NPU;
            bank_id = endpoint_index % KDLINK_SLICES_PER_NPU;
            location.node_id = node_id[4:0];
            location.slot_id = {2'b00, node_id[4:2]}; // 按默认八卡四NPU布局解码卡槽
            location.local_npu = {3'b000, node_id[1:0]}; // 按默认八卡四NPU布局解码卡内编号
            location.plane_id = bank_id[3:1];
            location.slice_id = bank_id[0];
            kdlink_decode_endpoint = location;
        end
    endfunction
endpackage

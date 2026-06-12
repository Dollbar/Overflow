`timescale 1ns/1ps
`default_nettype none

// UALink Switch普通明文Transit组合顶层。
// RX只能来自Station的DL验证提交；TX严格经过UPLI整包准入、TL信用和逐Port DL replay。
// Security/Compression不在本profile中，非法metadata、路由或协议形状均失败关闭。
module ualink_switch_full_ip_top #(
    parameter integer C_NUM_STATIONS = 8,
    parameter integer C_NUM_GROUPS = 1,
    parameter integer C_TILES_PER_GROUP = 1,
    parameter integer C_INGRESS_PER_TILE = 32,
    parameter integer C_BANKS_PER_TILE = 8,
    parameter integer C_NUM_PLANES = 1,
    parameter integer C_PORTS_PER_TILE = 32,
    // 目标发布默认保留完整Route/Port表；缩小验证可显式减少物理展开规模。
    parameter integer C_DST_COUNT = 4096,
    parameter integer C_PORT_COUNT = 32,
    parameter integer C_REPLAY_DEPTH = 4,
    parameter integer C_PORTS = C_NUM_STATIONS*4,
    parameter integer C_COUNT_WIDTH = 4,
    parameter integer C_RX_SLOT_WIDTH = 2,
    parameter integer C_RX_GENERATION_WIDTH = 8,
    parameter integer C_EPOCH_WIDTH = 8,
    parameter integer C_RX_TOKEN_WIDTH = C_EPOCH_WIDTH+C_RX_GENERATION_WIDTH+C_RX_SLOT_WIDTH,
    parameter integer C_RX_REF_WIDTH = 4,
    parameter integer C_OWNER_COUNT = 17,
    parameter integer C_FABRIC_META_WIDTH = 512,
    parameter integer C_CREDIT_WIDTH = 8,
    parameter integer C_FABRIC_TIMEOUT_CYCLES = 1024,
    parameter integer C_UPLI_CREDIT_WIDTH = 4,
    parameter integer C_INPUTS = C_NUM_GROUPS*C_TILES_PER_GROUP*C_INGRESS_PER_TILE,
    parameter integer C_OUTPUTS = C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE,
    parameter integer C_LANES = C_TILES_PER_GROUP*C_BANKS_PER_TILE,
    parameter integer C_RESOURCES = C_TILES_PER_GROUP*C_PORTS_PER_TILE*4,
    parameter integer C_ACCOUNTS = (C_LANES+C_NUM_PLANES)*C_RESOURCES,
    parameter integer C_ACCOUNT_WIDTH = (C_ACCOUNTS<=2)?1:(C_ACCOUNTS<=4)?2:
        (C_ACCOUNTS<=8)?3:(C_ACCOUNTS<=16)?4:(C_ACCOUNTS<=32)?5:
        (C_ACCOUNTS<=64)?6:(C_ACCOUNTS<=128)?7:(C_ACCOUNTS<=256)?8:
        (C_ACCOUNTS<=512)?9:(C_ACCOUNTS<=1024)?10:(C_ACCOUNTS<=2048)?11:
        (C_ACCOUNTS<=4096)?12:(C_ACCOUNTS<=8192)?13:(C_ACCOUNTS<=16384)?14:15,
    parameter integer C_FABRIC_SLOT_WIDTH = ((C_RESOURCES*4) <= 2) ? 1 :
        ((C_RESOURCES*4) <= 4) ? 2 : ((C_RESOURCES*4) <= 8) ? 3 :
        ((C_RESOURCES*4) <= 16) ? 4 : ((C_RESOURCES*4) <= 32) ? 5 :
        ((C_RESOURCES*4) <= 64) ? 6 : ((C_RESOURCES*4) <= 128) ? 7 :
        ((C_RESOURCES*4) <= 256) ? 8 : ((C_RESOURCES*4) <= 512) ? 9 :
        ((C_RESOURCES*4) <= 1024) ? 10 : 11,
    parameter integer C_FABRIC_TOKEN_WIDTH = C_EPOCH_WIDTH+8+C_FABRIC_SLOT_WIDTH,
    parameter integer C_BANK_WIDTH = (C_BANKS_PER_TILE <= 2) ? 1 :
        (C_BANKS_PER_TILE <= 4) ? 2 : 3,
    parameter integer C_NUM_VOQS = C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE*4,
    parameter integer C_QUEUE_WIDTH = (C_NUM_VOQS <= 2) ? 1 :
        (C_NUM_VOQS <= 4) ? 2 : (C_NUM_VOQS <= 8) ? 3 :
        (C_NUM_VOQS <= 16) ? 4 : (C_NUM_VOQS <= 32) ? 5 :
        (C_NUM_VOQS <= 64) ? 6 : 7,
    parameter integer C_INGRESS_WIDTH = (C_INGRESS_PER_TILE <= 2) ? 1 :
        (C_INGRESS_PER_TILE <= 4) ? 2 : (C_INGRESS_PER_TILE <= 8) ? 3 :
        (C_INGRESS_PER_TILE <= 16) ? 4 : 5,
    parameter integer C_TILE_WIDTH = (C_TILES_PER_GROUP <= 2) ? 1 : 2,
    parameter integer C_SOURCE_WIDTH = (C_LANES <= 2) ? 1 :
        (C_LANES <= 4) ? 2 : (C_LANES <= 8) ? 3 :
        (C_LANES <= 16) ? 4 : 5,
    parameter integer C_PLANE_WIDTH = (C_NUM_PLANES <= 2) ? 1 :
        (C_NUM_PLANES <= 4) ? 2 : (C_NUM_PLANES <= 8) ? 3 :
        (C_NUM_PLANES <= 16) ? 4 : 5,
    parameter integer C_OWNER_WIDTH = ((C_LANES+C_NUM_PLANES) <= 2) ? 1 :
        ((C_LANES+C_NUM_PLANES) <= 4) ? 2 :
        ((C_LANES+C_NUM_PLANES) <= 8) ? 3 :
        ((C_LANES+C_NUM_PLANES) <= 16) ? 4 :
        ((C_LANES+C_NUM_PLANES) <= 32) ? 5 : 6,
    parameter integer C_RESOURCE_WIDTH = (C_RESOURCES <= 2) ? 1 :
        (C_RESOURCES <= 4) ? 2 : (C_RESOURCES <= 8) ? 3 :
        (C_RESOURCES <= 16) ? 4 : (C_RESOURCES <= 32) ? 5 :
        (C_RESOURCES <= 64) ? 6 : (C_RESOURCES <= 128) ? 7 :
        (C_RESOURCES <= 256) ? 8 : 9,
    parameter integer C_RETURN_BANKS = (C_PORTS >= 32) ? 32 :
        (C_PORTS >= 16) ? 16 : (C_PORTS >= 8) ? 8 :
        (C_PORTS >= 4) ? 4 : (C_PORTS >= 2) ? 2 : 1
) (
    input wire i_clk,
    input wire i_rstn,
    input wire i_enable,
    input wire [C_NUM_STATIONS*2-1:0] i_station_requested_mode,
    input wire [C_NUM_STATIONS-1:0] i_station_mode_commit,
    input wire [C_PORTS-1:0] i_lane_up,
    input wire [C_PORTS-1:0] i_port_link_reset,
    input wire [C_PORTS-1:0] i_link_rx_frame_valid,
    output wire [C_PORTS-1:0] o_link_rx_frame_ready,
    input wire [C_PORTS*512-1:0] i_link_rx_frame_data,
    input wire [C_PORTS-1:0] i_link_rx_frame_sop,
    input wire [C_PORTS-1:0] i_link_rx_frame_eop,
    input wire [C_PORTS-1:0] i_link_rx_fec_complete,
    input wire [C_PORTS-1:0] i_link_rx_crc_ok,
    output wire [C_PORTS-1:0] o_link_control_valid,
    input wire [C_PORTS-1:0] i_link_control_ready,
    output wire [C_PORTS-1:0] o_link_control_replay_request,
    output wire [C_PORTS*9-1:0] o_link_control_target,
    output wire [C_PORTS-1:0] o_crc_frame_valid,
    input wire [C_PORTS-1:0] i_crc_frame_ready,
    output wire [C_PORTS*512-1:0] o_crc_frame_data,
    output wire [C_PORTS-1:0] o_crc_frame_sop,
    output wire [C_PORTS-1:0] o_crc_frame_eop,
    output wire [C_PORTS*9-1:0] o_crc_frame_sequence,
    output wire [C_PORTS-1:0] o_crc_frame_replay,
    output wire [C_PORTS-1:0] o_crc_required,
    output wire [C_PORTS-1:0] o_physical_valid,
    output wire [C_PORTS*8-1:0] o_tx_resident_count,
    input wire [C_PORTS*4-1:0] i_upli_credit_connected,
    input wire [C_PORTS*4-1:0] i_upli_beats_connected,
    input wire [C_PORTS*4-1:0] i_upli_credit_valid,
    input wire [C_PORTS*4-1:0] i_upli_credit_pool,
    input wire [C_PORTS*8-1:0] i_upli_credit_vc,
    input wire [C_PORTS*8-1:0] i_upli_credit_num,
    input wire [C_PORTS*4-1:0] i_upli_credit_init_done,
    output wire [C_PORTS-1:0] o_upli_credit_candidate_ready,
    output wire o_mgmt_upli_credit_error_event_level,
    output wire o_mgmt_tl_credit_underflow_event_level,
    output wire o_mgmt_tl_credit_overflow_event_level,
    output wire [3:0] o_mgmt_destination_return_error_event_level,
    output wire o_mgmt_ingress_queue_overflow_event_level,
    output wire o_mgmt_ingress_queue_underflow_event_level,
    input wire [C_PORTS-1:0] i_tl_rx_start,
    input wire [C_PORTS-1:0] i_tl_rx_shared,
    input wire [C_PORTS*20*C_CREDIT_WIDTH-1:0] i_tl_rx_capacities,
    input wire i_route_shadow_write,
    input wire [11:0] i_route_shadow_dst_id,
    input wire i_route_shadow_valid,
    input wire [9:0] i_route_shadow_global_port,
    input wire [7:0] i_route_shadow_policy,
    input wire i_identity_shadow_write,
    input wire [9:0] i_identity_shadow_global_port,
    input wire i_identity_shadow_active,
    input wire [2:0] i_identity_shadow_group,
    input wire [1:0] i_identity_shadow_tile,
    input wire [4:0] i_identity_shadow_local_port,
    input wire [7:0] i_identity_shadow_station,
    input wire [3:0] i_identity_shadow_lane_mask,
    input wire [2:0] i_identity_shadow_service_units,
    input wire [1:0] i_identity_shadow_station_mode,
    input wire i_route_commit_request,
    input wire i_shadow_illegal,
    input wire [C_NUM_PLANES-1:0] i_plane_enable,
    input wire [C_PORTS-1:0] i_release_path_enable,
    input wire [C_PORTS-1:0] i_egress_flush,
    output wire [C_NUM_STATIONS*2-1:0] o_station_active_mode,
    output wire [C_PORTS-1:0] o_port_active,
    output wire [C_PORTS*10-1:0] o_global_port_id,
    output wire [C_PORTS-1:0] o_rx_release_valid,
    output wire [C_PORTS*C_RX_TOKEN_WIDTH-1:0] o_rx_release_token,
    output wire [C_PORTS*80-1:0] o_rx_release_vector,
    output wire [C_PORTS-1:0] o_upli_mapping_unsupported,
    output wire o_route_commit_ready,
    output wire o_route_commit_rejected,
    output wire o_quiescent,
    output wire o_config_error,
    output wire o_error,
    // 只读管理观测；不复制任何Route、VOQ或credit owner。
    output wire [C_EPOCH_WIDTH-1:0] o_mgmt_route_epoch,
    output wire o_mgmt_route_pending,output wire [10:0] o_mgmt_commit_wait_cycles,
    output wire o_mgmt_fabric_timeout_error,
    output wire [C_NUM_STATIONS-1:0] o_mgmt_station_busy,
    output wire [C_NUM_STATIONS-1:0] o_mgmt_station_quiescent,
    output wire [C_NUM_STATIONS-1:0] o_mgmt_station_error,
    output wire [C_PORTS-1:0] o_mgmt_release_valid,output wire [C_PORTS-1:0] o_mgmt_release_ready,
    output wire [C_NUM_GROUPS*C_RESOURCES*3-1:0] o_mgmt_resource_free,
    output wire [C_NUM_GROUPS*C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_mgmt_queue_occupancy,
    output wire [C_NUM_GROUPS*C_ACCOUNTS*3-1:0] o_mgmt_credit_issued,
    output wire [C_NUM_GROUPS*C_ACCOUNTS*3-1:0] o_mgmt_credit_occupied,
    // 只读Fabric计量tap；不参与任何ready生成或owner推进。
    output wire [C_PORTS-1:0] o_observe_ingress_committed_valid,
    output wire [C_PORTS-1:0] o_observe_ingress_committed_ready,
    output wire [C_PORTS-1:0] o_observe_egress_retired_valid,
    output wire [C_PORTS-1:0] o_observe_egress_retired_ready
);
    localparam C_CONFIG_LEGAL =
        (C_NUM_STATIONS >= 1) && (C_NUM_STATIONS <= 8) &&
        (C_PORTS == C_NUM_STATIONS*4) && (C_INPUTS == C_PORTS) &&
        (C_OUTPUTS == C_PORTS) && (C_COUNT_WIDTH == 4) &&
        (C_BANKS_PER_TILE >= 1) && (C_BANKS_PER_TILE <= 8) &&
        (C_DST_COUNT >= 32) && (C_DST_COUNT <= 4096) &&
        (C_PORT_COUNT >= C_PORTS) && (C_PORT_COUNT <= 32) &&
        ((1 << C_BANK_WIDTH) == C_BANKS_PER_TILE) &&
        (C_NUM_VOQS == C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE*4) &&
        (C_RX_REF_WIDTH >= 4) && (C_FABRIC_META_WIDTH == 512) &&
        (C_OWNER_COUNT == 17) && (C_RX_TOKEN_WIDTH == 18) &&
        (C_FABRIC_TIMEOUT_CYCLES >= 1) && (C_FABRIC_TIMEOUT_CYCLES <= 2047);

    wire [C_PORTS-1:0] station_active_mask;
    wire [C_PORTS-1:0] station_slot_enable;
    wire [C_NUM_STATIONS-1:0] station_commit_accept;
    wire [C_NUM_STATIONS-1:0] station_mode_error;
    wire [C_NUM_STATIONS-1:0] station_busy;
    wire [C_NUM_STATIONS-1:0] station_quiescent;
    wire [C_NUM_STATIONS-1:0] station_error;
    wire [C_NUM_STATIONS*2-1:0] station_slot_port;
    wire [C_PORTS-1:0] station_rx_valid;
    wire [C_PORTS-1:0] station_rx_ready;
    wire [C_PORTS*512-1:0] station_rx_data;
    wire [C_PORTS*2-1:0] station_rx_msg;
    wire [C_PORTS-1:0] station_tx_valid;
    wire [C_PORTS-1:0] station_tx_ready;
    wire [C_PORTS*512-1:0] station_tx_data;
    wire [C_PORTS*2-1:0] station_tx_msg;
    wire station_busy_any;
    wire station_quiescent_all;
    wire station_config_error;
    wire station_link_error;
    wire [C_PORTS*3-1:0] map_group_id;
    wire [C_PORTS*2-1:0] map_tile_id;
    wire [C_PORTS*5-1:0] map_local_port;
    wire [C_PORTS*8-1:0] map_station_id;
    wire [C_PORTS*4-1:0] map_lane_mask;
    wire [C_PORTS*3-1:0] map_service_units;
    wire map_config_error;
    wire map_identity_error;

    wire [C_PORTS-1:0] normal_rx_valid;
    wire [C_PORTS-1:0] normal_rx_ready;
    wire [C_PORTS*512-1:0] normal_rx_data;
    wire [C_PORTS*2-1:0] normal_rx_msg;
    wire [C_PORTS-1:0] normal_tx_valid;
    wire [C_PORTS-1:0] normal_tx_ready;
    wire [C_PORTS*512-1:0] normal_tx_data;
    wire [C_PORTS*2-1:0] normal_tx_msg;
    wire [C_PORTS*80-1:0] normal_tx_demands;
    wire [C_PORTS-1:0] link_tx_valid;
    wire [C_PORTS-1:0] link_tx_ready;
    wire [C_PORTS*512-1:0] link_tx_data;
    wire [C_PORTS*2-1:0] link_tx_msg;
    wire [C_PORTS-1:0] link_tx_is_fc;
    wire [C_PORTS-1:0] link_tx_sop;
    wire [C_PORTS-1:0] link_tx_eop;
    wire [C_PORTS-1:0] tl_operational;
    wire [C_PORTS-1:0] tl_tx_initialized;
    wire [C_PORTS-1:0] tl_rx_initialized;
    wire [C_PORTS-1:0] owner_release_ready;
    wire tl_ras_error;
    wire [C_PORTS-1:0] tl_rx_start_ready;
    wire [C_PORTS-1:0] tl_rx_start_taken;
    wire [C_PORTS-1:0] tl_rx_retire_taken;
    wire [C_PORTS-1:0] tl_active_ports;
    wire [C_PORTS*20*(C_CREDIT_WIDTH+1)-1:0] tl_tx_available;
    wire [C_PORTS*20*(C_CREDIT_WIDTH+1)-1:0] tl_rx_pending;
    wire tl_invalid_rx_error;
    wire tl_starvation_error;
    wire tl_credit_error;

    wire [C_PORTS-1:0] owner_decode_valid;
    wire [C_PORTS-1:0] owner_decode_ready;
    wire [C_PORTS*512-1:0] owner_decode_data;
    wire [C_PORTS*2-1:0] owner_decode_msg;
    wire [C_PORTS*C_RX_TOKEN_WIDTH-1:0] owner_decode_token;
    wire [C_PORTS*6-1:0] owner_decode_classes;
    wire [C_PORTS*80-1:0] owner_decode_demands;
    wire [C_PORTS*80-1:0] owner_decode_release_obligation;
    wire [C_PORTS-1:0] owner_quiescent;
    wire [C_PORTS-1:0] owner_error;
    wire [C_PORTS-1:0] owner_config_error;

    wire [C_PORTS-1:0] decoder_valid;
    wire [C_PORTS-1:0] decoder_ready;
    wire [C_PORTS*512-1:0] decoder_data;
    wire [C_PORTS*2-1:0] decoder_msg;
    wire [C_PORTS*10-1:0] decoder_dst;
    wire [C_PORTS*2-1:0] decoder_class;
    wire [C_PORTS*2-1:0] decoder_vc;
    wire [C_PORTS-1:0] decoder_pool;
    wire [C_PORTS*10-1:0] decoder_src;
    wire [C_PORTS-1:0] decoder_sop;
    wire [C_PORTS-1:0] decoder_eop;
    wire [C_PORTS*C_COUNT_WIDTH-1:0] decoder_flits;
    wire [C_PORTS-1:0] decoder_busy;
    wire [C_PORTS-1:0] decoder_error;
    wire decoder_config_error;
    wire [C_PORTS-1:0] owner_bind_valid;
    wire [C_PORTS-1:0] owner_bind_ready;
    wire [C_PORTS*C_RX_TOKEN_WIDTH-1:0] owner_bind_token;
    wire [C_PORTS*C_RX_REF_WIDTH-1:0] owner_bind_count;
    wire [C_PORTS-1:0] owner_bind_drop;
    wire [C_PORTS*C_OWNER_COUNT-1:0] decoder_owner_valid;
    wire [C_PORTS*C_OWNER_COUNT*C_RX_TOKEN_WIDTH-1:0] decoder_owner_tokens;
    wire [C_PORTS*5-1:0] decoder_owner_count;
    wire [C_PORTS-1:0] decoder_retire_valid;
    wire [C_PORTS-1:0] decoder_retire_ready;
    wire [C_PORTS*C_RX_TOKEN_WIDTH-1:0] decoder_retire_token;

    wire [C_PORTS*C_FABRIC_META_WIDTH-1:0] ingress_meta;
    wire [C_PORTS-1:0] ingress_meta_valid;
    wire [C_PORTS*12-1:0] fabric_dst_id;
    wire [C_PORTS-1:0] fabric_valid;
    wire [C_PORTS-1:0] fabric_ready;
    wire [C_PORTS*512-1:0] fabric_data;
    wire [C_PORTS*C_FABRIC_META_WIDTH-1:0] fabric_meta;
    wire [C_PORTS*2-1:0] fabric_class;
    wire [C_PORTS*2-1:0] fabric_vc;
    wire [C_PORTS-1:0] fabric_pool;
    wire [C_PORTS-1:0] fabric_sop;
    wire [C_PORTS-1:0] fabric_eop;
    wire [C_PORTS*10-1:0] fabric_src;
    wire [C_PORTS*10-1:0] fabric_dst;
    wire [C_PORTS*8-1:0] fabric_policy;
    wire [C_PORTS*C_COUNT_WIDTH-1:0] fabric_flits;
    localparam integer C_EGRESS_PAYLOAD_WIDTH = 512+C_FABRIC_META_WIDTH+2+2+1+1+1+10+10+8+C_COUNT_WIDTH;
    wire [C_PORTS-1:0] fabric_raw_valid;
    wire [C_PORTS-1:0] fabric_raw_ready;
    wire [C_PORTS*512-1:0] fabric_raw_data;
    wire [C_PORTS*C_FABRIC_META_WIDTH-1:0] fabric_raw_meta;
    wire [C_PORTS*2-1:0] fabric_raw_class;
    wire [C_PORTS*2-1:0] fabric_raw_vc;
    wire [C_PORTS-1:0] fabric_raw_pool;
    wire [C_PORTS-1:0] fabric_raw_sop;
    wire [C_PORTS-1:0] fabric_raw_eop;
    wire [C_PORTS*10-1:0] fabric_raw_src;
    wire [C_PORTS*10-1:0] fabric_raw_dst;
    wire [C_PORTS*8-1:0] fabric_raw_policy;
    wire [C_PORTS*C_COUNT_WIDTH-1:0] fabric_raw_flits;
    wire [C_PORTS-1:0] fabric_slice_quiescent;
    wire [C_PORTS-1:0] fabric_slice_error;
    wire [C_PORTS-1:0] fabric_slice_config_error;
    wire [C_PORTS-1:0] fabric_head_valid;
    wire [C_PORTS*3-1:0] fabric_src_group;
    wire [C_PORTS*C_EPOCH_WIDTH-1:0] fabric_route_epoch;
    wire [C_PORTS-1:0] fabric_release_valid;
    wire [C_PORTS-1:0] fabric_release_ready;
    wire [C_PORTS*C_ACCOUNT_WIDTH-1:0] fabric_release_account;
    wire [C_PORTS*C_FABRIC_TOKEN_WIDTH-1:0] fabric_release_token;
    wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] fabric_advisory_valid;
    wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] fabric_advisory_match;
    wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] fabric_advisory_mismatch;
    wire [C_NUM_GROUPS*C_NUM_PLANES-1:0] fabric_advisory_stale;
    wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] fabric_hint_eligible;
    wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] fabric_hint_used;
    wire [C_NUM_GROUPS*C_LANES*C_NUM_PLANES-1:0] fabric_probe_path;
    wire [C_NUM_GROUPS-1:0] fabric_hint_pending;
    wire [C_NUM_GROUPS-1:0] fabric_hint_error;
    wire fabric_new_sop;
    wire fabric_quiesce_request;
    wire fabric_commit_pulse;
    wire fabric_commit_pending;
    wire [10:0] fabric_commit_wait_cycles;
    wire fabric_timeout_error;
    wire fabric_inactive_group_error;
    wire [C_NUM_GROUPS*C_RESOURCES*3-1:0] fabric_effective_free;
    wire [C_NUM_GROUPS*C_TILES_PER_GROUP*C_NUM_VOQS*C_COUNT_WIDTH-1:0] fabric_queue_occupancy;
    wire [C_NUM_GROUPS*C_ACCOUNTS*3-1:0] fabric_credit_issued,fabric_credit_occupied;
    wire [C_EPOCH_WIDTH-1:0] fabric_epoch;
    wire fabric_all_empty;
    wire fabric_config_error;
    wire fabric_error;
    wire [C_PORTS-1:0] unpack_valid;
    wire [C_PORTS*128-1:0] unpack_user_meta;
    wire [C_PORTS*C_OWNER_COUNT-1:0] unpack_owner_valid;
    wire [C_PORTS*C_OWNER_COUNT*C_RX_TOKEN_WIDTH-1:0] unpack_owner_tokens;
    wire [C_PORTS*10-1:0] unpack_owner_source;
    wire [C_PORTS-1:0] codec_error;
    wire [C_PORTS-1:0] codec_config_error;
    wire [C_PORTS-1:0] codec_unpack_error;
    reg [C_PORTS-1:0] metadata_error_q;

    wire [C_PORTS-1:0] semantic_valid;
    wire [C_PORTS-1:0] semantic_ready;
    wire [C_PORTS*512-1:0] semantic_data;
    wire [C_PORTS*128-1:0] semantic_meta;
    wire [C_PORTS*2-1:0] semantic_class;
    wire [C_PORTS*2-1:0] semantic_msg;
    wire [C_PORTS*2-1:0] semantic_vc;
    wire [C_PORTS-1:0] semantic_pool;
    wire [C_PORTS*10-1:0] semantic_src;
    wire [C_PORTS*10-1:0] semantic_dst;
    wire [C_PORTS-1:0] semantic_sop;
    wire [C_PORTS-1:0] semantic_eop;
    wire [C_PORTS*4-1:0] semantic_flits;
    wire [C_PORTS-1:0] semantic_reserved_body;
    wire [C_PORTS*4-1:0] upli_demand_valid;
    wire [C_PORTS*8-1:0] upli_demand_vc;
    wire [C_PORTS*4-1:0] upli_demand_pool;
    wire [C_PORTS*12-1:0] upli_demand_count;
    wire [C_PORTS*C_OWNER_COUNT-1:0] semantic_owner_valid;
    wire [C_PORTS*C_OWNER_COUNT*C_RX_TOKEN_WIDTH-1:0] semantic_owner_tokens;
    wire [C_PORTS-1:0] semantic_provenance_valid;
    wire [C_PORTS-1:0] egress_upli_pool;
    wire [C_PORTS-1:0] egress_upli_pool_valid;
    wire [C_PORTS*2-1:0] egress_tl_msg;
    wire [C_PORTS*10-1:0] egress_protocol_dst;
    wire [C_PORTS-1:0] semantic_error;
    wire semantic_config_error;

    wire [C_PORTS-1:0] upli_admitted_valid;
    wire [C_PORTS-1:0] upli_admitted_ready;
    wire [C_PORTS-1:0] upli_eligible;
    wire upli_ras_error;
    wire [C_PORTS-1:0] upli_admitted_fire;
    wire [C_PORTS-1:0] upli_active_ports;
    wire [C_PORTS-1:0] upli_operational_ports;
    wire [C_PORTS*4-1:0] upli_init_confirmed;
    wire [C_PORTS*4*5*C_UPLI_CREDIT_WIDTH-1:0] upli_balances;
    wire upli_invalid_demand_error;
    wire upli_inactive_candidate_error;
    wire upli_credit_error;
    wire upli_illegal_mode_error;
    wire [C_PORTS-1:0] packer_tl_valid;
    wire [C_PORTS-1:0] packer_tl_ready;
    wire [C_PORTS-1:0] packer_tl_sop;
    wire [C_PORTS-1:0] packer_tl_eop;
    wire [C_PORTS*10-1:0] packer_tl_source;
    wire [C_PORTS*C_OWNER_COUNT-1:0] packer_tl_owner_valid;
    wire [C_PORTS*C_OWNER_COUNT*C_RX_TOKEN_WIDTH-1:0] packer_tl_owner_tokens;
    wire [C_PORTS-1:0] packer_busy;
    wire [C_PORTS-1:0] packer_error;
    wire packer_config_error;
    wire [C_PORTS-1:0] return_input_valid;
    wire [C_PORTS-1:0] return_input_ready;
    wire [C_PORTS-1:0] return_source_valid;
    wire [C_PORTS-1:0] return_source_ready;
    wire [C_PORTS*C_OWNER_COUNT-1:0] return_source_owner_valid;
    wire [C_PORTS*C_OWNER_COUNT*C_RX_TOKEN_WIDTH-1:0] return_source_owner_tokens;
    wire return_quiescent;
    wire return_error;
    wire return_config_error;

    // Station终止每条Logical Port的DL sequence/replay，RX输出只包含已验证TL字。
    ualink_switch_station_link_array #(
        .C_NUM_STATIONS(C_NUM_STATIONS), .C_REPLAY_DEPTH(C_REPLAY_DEPTH)
    ) u_station_links (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL), .i_enable(i_enable),
        .i_station_requested_mode(i_station_requested_mode), .i_station_mode_commit(i_station_mode_commit),
        .i_lane_up(i_lane_up), .i_port_link_reset(i_port_link_reset),
        .o_active_mode(o_station_active_mode), .o_active_mask(station_active_mask),
        .o_mode_commit_accept(station_commit_accept), .o_mode_error(station_mode_error),
        .o_port_slot_enable(station_slot_enable), .o_slot_port(station_slot_port),
        .i_egress_tl_valid(station_tx_valid), .o_egress_tl_ready(station_tx_ready),
        .i_egress_tl_data(station_tx_data), .i_egress_tl_msg(station_tx_msg),
        .i_egress_tl_sop(link_tx_sop), .i_egress_tl_eop(link_tx_eop),
        .i_egress_flush(i_egress_flush & link_tx_eop),
        .i_link_rx_frame_valid(i_link_rx_frame_valid), .o_link_rx_frame_ready(o_link_rx_frame_ready),
        .i_link_rx_frame_data(i_link_rx_frame_data), .i_link_rx_frame_sop(i_link_rx_frame_sop),
        .i_link_rx_frame_eop(i_link_rx_frame_eop), .i_link_rx_fec_complete(i_link_rx_fec_complete),
        .i_link_rx_crc_ok(i_link_rx_crc_ok), .o_ingress_tl_valid(station_rx_valid),
        .i_ingress_tl_ready(station_rx_ready), .o_ingress_tl_data(station_rx_data),
        .o_ingress_tl_msg(station_rx_msg), .o_link_control_valid(o_link_control_valid),
        .i_link_control_ready(i_link_control_ready),
        .o_link_control_replay_request(o_link_control_replay_request),
        .o_link_control_target(o_link_control_target), .o_crc_frame_valid(o_crc_frame_valid),
        .i_crc_frame_ready(i_crc_frame_ready), .o_crc_frame_data(o_crc_frame_data),
        .o_crc_frame_sop(o_crc_frame_sop), .o_crc_frame_eop(o_crc_frame_eop),
        .o_crc_frame_sequence(o_crc_frame_sequence), .o_crc_frame_replay(o_crc_frame_replay),
        .o_crc_required(o_crc_required), .o_physical_valid(o_physical_valid),
        .o_tx_resident_count(o_tx_resident_count), .o_station_busy(station_busy),
        .o_station_quiescent(station_quiescent), .o_station_error(station_error),
        .o_busy(station_busy_any), .o_quiescent(station_quiescent_all),
        .o_config_error(station_config_error), .o_error(station_link_error)
    );

    switch_station_fabric_port_map #(
        .C_NUM_STATIONS(C_NUM_STATIONS), .C_NUM_GROUPS(C_NUM_GROUPS),
        .C_TILES_PER_GROUP(C_TILES_PER_GROUP), .C_PORTS_PER_TILE(C_PORTS_PER_TILE)
    ) u_port_map (
        .i_station_active_mode(o_station_active_mode), .i_station_active_mask(station_active_mask),
        .i_link_up(i_lane_up), .o_port_active(o_port_active), .o_global_port_id(o_global_port_id),
        .o_group_id(map_group_id), .o_tile_id(map_tile_id), .o_local_port(map_local_port),
        .o_station_id(map_station_id), .o_lane_mask(map_lane_mask),
        .o_service_units(map_service_units), .o_config_error(map_config_error),
        .o_identity_error(map_identity_error)
    );

    switch_station_tl_flow_control_bridge #(
        .C_NUM_STATIONS(C_NUM_STATIONS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH),
        .C_PACKET_BOUNDARY_ENABLE(1)
    ) u_tl_fc (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL), .i_station_mode(o_station_active_mode),
        .i_port_link_up(i_lane_up), .i_port_link_reset(i_port_link_reset),
        .i_rx_valid(station_rx_valid), .o_rx_ready(station_rx_ready),
        .i_rx_validated(station_rx_valid), .i_rx_flit(station_rx_data), .i_rx_msg(station_rx_msg),
        .o_normal_rx_valid(normal_rx_valid), .i_normal_rx_ready(normal_rx_ready),
        .o_normal_rx_flit(normal_rx_data), .o_normal_rx_msg(normal_rx_msg),
        .i_normal_tx_valid(normal_tx_valid), .o_normal_tx_ready(normal_tx_ready),
        .i_normal_tx_flit(normal_tx_data), .i_normal_tx_msg(normal_tx_msg),
        .i_normal_tx_demands(normal_tx_demands), .i_normal_tx_sop(packer_tl_sop),
        .i_normal_tx_eop(packer_tl_eop), .o_link_tx_valid(link_tx_valid),
        .i_link_tx_ready(link_tx_ready), .o_link_tx_flit(link_tx_data),
        .o_link_tx_msg(link_tx_msg), .o_link_tx_is_fc(link_tx_is_fc),
        .o_link_tx_sop(link_tx_sop), .o_link_tx_eop(link_tx_eop),
        .i_rx_start(i_tl_rx_start), .i_rx_shared(i_tl_rx_shared),
        .i_rx_capacities(i_tl_rx_capacities), .i_rx_retire_valid(o_rx_release_valid),
        .i_rx_releases(o_rx_release_vector), .o_rx_start_ready(tl_rx_start_ready),
        .o_rx_start_taken(tl_rx_start_taken), .o_rx_retire_ready(owner_release_ready),
        .o_rx_retire_taken(tl_rx_retire_taken), .o_active_logical_ports(tl_active_ports),
        .o_operational_ports(tl_operational), .o_tx_initialized(tl_tx_initialized),
        .o_tx_available(tl_tx_available), .o_rx_initialized(tl_rx_initialized),
        .o_rx_pending(tl_rx_pending), .o_invalid_rx_error(tl_invalid_rx_error),
        .o_tx_underflow_event_level(o_mgmt_tl_credit_underflow_event_level),
        .o_tx_overflow_event_level(o_mgmt_tl_credit_overflow_event_level),
        .o_starvation_error(tl_starvation_error), .o_credit_error(tl_credit_error),
        .o_ras_error(tl_ras_error)
    );

    assign station_tx_valid = link_tx_valid;
    assign link_tx_ready = station_tx_ready;
    assign station_tx_data = link_tx_data;
    assign station_tx_msg = link_tx_msg;

    genvar port_index;
    generate
        for (port_index = 0; port_index < C_PORTS; port_index = port_index + 1) begin : g_rx_owner
            switch_rx_tl_credit_ownership_adapter #(
                .C_DEPTH(4), .C_SLOT_WIDTH(C_RX_SLOT_WIDTH),
                .C_GENERATION_WIDTH(C_RX_GENERATION_WIDTH), .C_EPOCH_WIDTH(C_EPOCH_WIDTH),
                .C_REF_WIDTH(C_RX_REF_WIDTH)
            ) u_owner (
                .i_clk(i_clk), .i_rstn(i_rstn && tl_operational[port_index]),
                .i_epoch(fabric_epoch), .i_auth(1'b0),
                .i_rx_valid(normal_rx_valid[port_index]), .o_rx_ready(normal_rx_ready[port_index]),
                .i_rx_data(normal_rx_data[port_index*512 +: 512]),
                .i_rx_msg(normal_rx_msg[port_index*2 +: 2]),
                .o_decode_valid(owner_decode_valid[port_index]),
                .i_decode_ready(owner_decode_ready[port_index]),
                .o_decode_data(owner_decode_data[port_index*512 +: 512]),
                .o_decode_msg(owner_decode_msg[port_index*2 +: 2]),
                .o_decode_token(owner_decode_token[port_index*C_RX_TOKEN_WIDTH +: C_RX_TOKEN_WIDTH]),
                .o_decode_classes(owner_decode_classes[port_index*6 +: 6]),
                .o_decode_demands(owner_decode_demands[port_index*80 +: 80]),
                .o_decode_release_obligation(owner_decode_release_obligation[port_index*80 +: 80]),
                .i_bind_valid(owner_bind_valid[port_index] && owner_bind_ready[port_index]),
                .i_bind_token(owner_bind_token[port_index*C_RX_TOKEN_WIDTH +: C_RX_TOKEN_WIDTH]),
                .i_bind_retire_count(owner_bind_count[port_index*C_RX_REF_WIDTH +: C_RX_REF_WIDTH]),
                .i_bind_drop_safe(owner_bind_drop[port_index]),
                .i_retire_valid(decoder_retire_valid[port_index] && decoder_retire_ready[port_index]),
                .i_retire_token(decoder_retire_token[port_index*C_RX_TOKEN_WIDTH +: C_RX_TOKEN_WIDTH]),
                .o_release_valid(o_rx_release_valid[port_index]),
                .i_release_ready(owner_release_ready[port_index]),
                .o_release_token(o_rx_release_token[port_index*C_RX_TOKEN_WIDTH +: C_RX_TOKEN_WIDTH]),
                .o_release_vector(o_rx_release_vector[port_index*80 +: 80]),
                .o_quiescent(owner_quiescent[port_index]), .o_error(owner_error[port_index]),
                .o_config_error(owner_config_error[port_index])
            );
            assign owner_bind_ready[port_index] = tl_operational[port_index] && !owner_error[port_index];
            assign decoder_retire_ready[port_index] = tl_operational[port_index] && !owner_error[port_index];
        end
    endgenerate

    switch_packed_tl_multi_envelope_decoder_owned #(
        .C_PORTS(C_PORTS), .C_COUNT_WIDTH(C_COUNT_WIDTH),
        .C_OWNER_TOKEN_WIDTH(C_RX_TOKEN_WIDTH), .C_MAX_GROUP_WORDS(C_OWNER_COUNT),
        .C_OWNER_REF_WIDTH(C_RX_REF_WIDTH)
    ) u_decoder (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_valid(owner_decode_valid), .o_ready(owner_decode_ready),
        .i_tl_data(owner_decode_data), .i_tl_msg(owner_decode_msg),
        .i_source_port(o_global_port_id), .i_owner_token(owner_decode_token),
        .i_owner_classes(owner_decode_classes), .o_valid(decoder_valid),
        .i_ready(decoder_ready), .o_data(decoder_data), .o_tl_msg(decoder_msg),
        .o_dst_id(decoder_dst), .o_class(decoder_class), .o_original_vc(decoder_vc),
        .o_original_pool(decoder_pool), .o_source_port(decoder_src),
        .o_sop(decoder_sop), .o_eop(decoder_eop), .o_packet_flits(decoder_flits),
        .o_busy(decoder_busy), .o_error(decoder_error), .o_config_error(decoder_config_error),
        .o_owner_bind_valid(owner_bind_valid), .i_owner_bind_ready(owner_bind_ready),
        .o_owner_bind_token(owner_bind_token), .o_owner_bind_retire_count(owner_bind_count),
        .o_owner_bind_drop_safe(owner_bind_drop), .o_owner_valid(decoder_owner_valid),
        .o_owner_tokens(decoder_owner_tokens), .o_owner_count(decoder_owner_count),
        .i_owner_retire_envelope_valid(return_source_valid),
        .o_owner_retire_envelope_ready(return_source_ready),
        .i_owner_retire_envelope_eop(return_source_valid),
        .i_owner_retire_valid(return_source_owner_valid),
        .i_owner_retire_tokens(return_source_owner_tokens),
        .o_owner_retire_valid(decoder_retire_valid),
        .i_owner_retire_ready(decoder_retire_ready),
        .o_owner_retire_token(decoder_retire_token)
    );

    generate
        for (port_index = 0; port_index < C_PORTS; port_index = port_index + 1) begin : g_metadata
            wire [127:0] user_meta;
            localparam [9:0] OWNER_SOURCE = port_index;
            // Fabric的10b source仍保存GlobalPort provenance。RX信用归还必须回到
            // 捕获该native word的物理Logical Port，因此另存输入lane ordinal，禁止
            // 从稀疏GlobalPortID反推物理owner。
            assign user_meta = {106'd0, OWNER_SOURCE,
                decoder_dst[port_index*10 +: 10],
                decoder_msg[port_index*2 +: 2]};
            switch_fabric_provenance_metadata_codec #(
                .C_FABRIC_META_WIDTH(C_FABRIC_META_WIDTH), .C_USER_META_WIDTH(128),
                .C_OWNER_COUNT(C_OWNER_COUNT), .C_OWNER_TOKEN_WIDTH(C_RX_TOKEN_WIDTH)
            ) u_codec (
                .i_pack_valid(decoder_valid[port_index]), .i_user_meta(user_meta),
                .i_owner_valid(decoder_owner_valid[port_index*C_OWNER_COUNT +: C_OWNER_COUNT]),
                .i_owner_tokens(decoder_owner_tokens[port_index*C_OWNER_COUNT*C_RX_TOKEN_WIDTH +:
                    C_OWNER_COUNT*C_RX_TOKEN_WIDTH]),
                .o_pack_valid(ingress_meta_valid[port_index]),
                .o_packed_meta(ingress_meta[port_index*C_FABRIC_META_WIDTH +: C_FABRIC_META_WIDTH]),
                .i_unpack_valid(fabric_valid[port_index]),
                .i_packed_meta(fabric_meta[port_index*C_FABRIC_META_WIDTH +: C_FABRIC_META_WIDTH]),
                .o_unpack_valid(unpack_valid[port_index]),
                .o_user_meta(unpack_user_meta[port_index*128 +: 128]),
                .o_owner_valid(unpack_owner_valid[port_index*C_OWNER_COUNT +: C_OWNER_COUNT]),
                .o_owner_tokens(unpack_owner_tokens[port_index*C_OWNER_COUNT*C_RX_TOKEN_WIDTH +:
                    C_OWNER_COUNT*C_RX_TOKEN_WIDTH]),
                .o_unpack_error(codec_unpack_error[port_index]), .o_error(codec_error[port_index]),
                .o_config_error(codec_config_error[port_index])
            );
            assign fabric_dst_id[port_index*12 +: 12] =
                {2'b00, decoder_dst[port_index*10 +: 10]};
            assign unpack_owner_source[port_index*10 +: 10] =
                unpack_user_meta[port_index*128+12 +: 10];
        end
    endgenerate

    // 完整分层Fabric；旧credit/link端口只作为观测输入，egress valid不再被协议信用预门控。
    ualink_switch_hierarchical_fabric_top #(
        .C_NUM_GROUPS(C_NUM_GROUPS), .C_TILES_PER_GROUP(C_TILES_PER_GROUP),
        .C_INGRESS_PER_TILE(C_INGRESS_PER_TILE), .C_BANKS_PER_TILE(C_BANKS_PER_TILE),
        .C_NUM_PLANES(C_NUM_PLANES), .C_PORTS_PER_TILE(C_PORTS_PER_TILE),
        .C_DST_COUNT(C_DST_COUNT), .C_PORT_COUNT(C_PORT_COUNT),
        .C_META_WIDTH(C_FABRIC_META_WIDTH), .C_COUNT_WIDTH(C_COUNT_WIDTH),
        .C_NUM_VOQS(C_NUM_VOQS), .C_BANK_WIDTH(C_BANK_WIDTH),
        .C_QUEUE_WIDTH(C_QUEUE_WIDTH), .C_INGRESS_WIDTH(C_INGRESS_WIDTH),
        .C_TILE_WIDTH(C_TILE_WIDTH), .C_SOURCE_WIDTH(C_SOURCE_WIDTH),
        .C_PLANE_WIDTH(C_PLANE_WIDTH), .C_OWNER_WIDTH(C_OWNER_WIDTH),
        .C_RESOURCE_WIDTH(C_RESOURCE_WIDTH),
        .C_INPUTS(C_INPUTS), .C_TOTAL_PORTS(C_OUTPUTS),
        .C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH), .C_SLOT_WIDTH(C_FABRIC_SLOT_WIDTH),
        .C_TOKEN_WIDTH(C_FABRIC_TOKEN_WIDTH),
        .C_TIMEOUT_CYCLES(C_FABRIC_TIMEOUT_CYCLES), .C_TIMEOUT_WIDTH(11)
    ) u_fabric (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_valid(decoder_valid & ingress_meta_valid), .o_ready(decoder_ready),
        .i_committed(decoder_valid & ingress_meta_valid), .i_data(decoder_data),
        .i_meta(ingress_meta), .i_dst_id(fabric_dst_id), .i_class(decoder_class),
        .i_src_port(decoder_src), .i_vc(decoder_vc), .i_pool(decoder_pool),
        .i_sop(decoder_sop), .i_eop(decoder_eop), .i_packet_flits(decoder_flits),
        .i_route_shadow_write(i_route_shadow_write), .i_route_shadow_dst_id(i_route_shadow_dst_id),
        .i_route_shadow_valid(i_route_shadow_valid),
        .i_route_shadow_global_port(i_route_shadow_global_port),
        .i_route_shadow_policy(i_route_shadow_policy),
        .i_identity_shadow_write(i_identity_shadow_write),
        .i_identity_shadow_global_port(i_identity_shadow_global_port),
        .i_identity_shadow_active(i_identity_shadow_active),
        .i_identity_shadow_group(i_identity_shadow_group), .i_identity_shadow_tile(i_identity_shadow_tile),
        .i_identity_shadow_local_port(i_identity_shadow_local_port),
        .i_identity_shadow_station(i_identity_shadow_station),
        .i_identity_shadow_lane_mask(i_identity_shadow_lane_mask),
        .i_identity_shadow_service_units(i_identity_shadow_service_units),
        .i_station_active_mode(i_identity_shadow_station_mode),
        .i_route_commit_request(i_route_commit_request),
        .i_shadow_illegal(i_shadow_illegal), .i_plane_enable(i_plane_enable),
        .i_port_active(o_port_active), .i_upli_credit(upli_eligible),
        .i_tl_credit(tl_tx_initialized), .i_link_up(i_lane_up),
        .o_head_valid(fabric_head_valid), .o_valid(fabric_raw_valid), .i_ready(fabric_raw_ready),
        .o_data(fabric_raw_data), .o_meta(fabric_raw_meta), .o_class(fabric_raw_class),
        .o_original_vc(fabric_raw_vc), .o_pool(fabric_raw_pool), .o_sop(fabric_raw_sop),
        .o_eop(fabric_raw_eop), .o_global_port_id(fabric_raw_dst), .o_src_group(fabric_src_group),
        .o_src_port(fabric_raw_src), .o_route_policy(fabric_raw_policy),
        .o_route_epoch(fabric_route_epoch),
        .o_packet_flits(fabric_raw_flits), .i_release_path_enable(i_release_path_enable),
        .o_release_valid(fabric_release_valid), .o_release_ready(fabric_release_ready),
        .o_release_account(fabric_release_account), .o_release_token(fabric_release_token),
        .o_advisory_valid(fabric_advisory_valid), .o_advisory_match(fabric_advisory_match),
        .o_advisory_mismatch(fabric_advisory_mismatch), .o_advisory_stale(fabric_advisory_stale),
        .o_source_hint_eligible(fabric_hint_eligible), .o_source_hint_used(fabric_hint_used),
        .o_source_probe_path(fabric_probe_path), .o_credit_hint_pending(fabric_hint_pending),
        .o_credit_hint_error(fabric_hint_error), .o_new_sop_admission(fabric_new_sop),
        .o_quiesce_request(fabric_quiesce_request), .o_commit_pulse(fabric_commit_pulse),
        .o_commit_pending(fabric_commit_pending),
        .o_active_epoch(fabric_epoch), .o_all_empty(fabric_all_empty),
        .o_commit_wait_cycles(fabric_commit_wait_cycles), .o_timeout_error(fabric_timeout_error),
        .o_inactive_group_error(fabric_inactive_group_error),
        .o_effective_free(fabric_effective_free),.o_queue_occupancy(fabric_queue_occupancy),
        .o_credit_issued(fabric_credit_issued),.o_credit_occupied(fabric_credit_occupied),
        .o_destination_return_error_event_level(o_mgmt_destination_return_error_event_level),
        .o_ingress_queue_overflow_event_level(o_mgmt_ingress_queue_overflow_event_level),
        .o_ingress_queue_underflow_event_level(o_mgmt_ingress_queue_underflow_event_level),
        .o_config_error(fabric_config_error),
        .o_error(fabric_error)
    );

    generate
        for (port_index = 0; port_index < C_PORTS; port_index = port_index + 1) begin : g_fabric_egress_slice
            wire [C_EGRESS_PAYLOAD_WIDTH-1:0] slice_input_payload;
            wire [C_EGRESS_PAYLOAD_WIDTH-1:0] slice_output_payload;
            assign slice_input_payload = {
                fabric_raw_flits[port_index*C_COUNT_WIDTH +: C_COUNT_WIDTH],
                fabric_raw_policy[port_index*8 +: 8],
                fabric_raw_src[port_index*10 +: 10],
                fabric_raw_dst[port_index*10 +: 10],
                fabric_raw_eop[port_index], fabric_raw_sop[port_index],
                fabric_raw_pool[port_index], fabric_raw_vc[port_index*2 +: 2],
                fabric_raw_class[port_index*2 +: 2],
                fabric_raw_meta[port_index*C_FABRIC_META_WIDTH +: C_FABRIC_META_WIDTH],
                fabric_raw_data[port_index*512 +: 512]
            };
            assign {
                fabric_flits[port_index*C_COUNT_WIDTH +: C_COUNT_WIDTH],
                fabric_policy[port_index*8 +: 8],
                fabric_src[port_index*10 +: 10],
                fabric_dst[port_index*10 +: 10],
                fabric_eop[port_index], fabric_sop[port_index], fabric_pool[port_index],
                fabric_vc[port_index*2 +: 2], fabric_class[port_index*2 +: 2],
                fabric_meta[port_index*C_FABRIC_META_WIDTH +: C_FABRIC_META_WIDTH],
                fabric_data[port_index*512 +: 512]
            } = slice_output_payload;
            switch_fabric_elastic_slice #(
                .C_PAYLOAD_WIDTH(C_EGRESS_PAYLOAD_WIDTH)
            ) u_slice (
                .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
                .i_valid(fabric_raw_valid[port_index]),
                .o_ready(fabric_raw_ready[port_index]), .i_payload(slice_input_payload),
                .o_valid(fabric_valid[port_index]), .i_ready(fabric_ready[port_index]),
                .o_payload(slice_output_payload),
                .o_quiescent(fabric_slice_quiescent[port_index]),
                .o_config_error(fabric_slice_config_error[port_index]),
                .o_error(fabric_slice_error[port_index])
            );
        end
    endgenerate

    generate
        for (port_index = 0; port_index < C_PORTS; port_index = port_index + 1) begin : g_egress_policy
            assign egress_upli_pool_valid[port_index] = fabric_policy[port_index*8];
            assign egress_upli_pool[port_index] = fabric_policy[port_index*8+1];
            assign egress_tl_msg[port_index*2 +: 2] =
                unpack_user_meta[port_index*128 +: 2];
            assign egress_protocol_dst[port_index*10 +: 10] =
                unpack_user_meta[port_index*128+2 +: 10];
            assign semantic_provenance_valid[port_index] =
                |semantic_owner_valid[port_index*C_OWNER_COUNT +: C_OWNER_COUNT];
        end
    endgenerate

    // 合法头按semantic容量消费；保留位损坏的头本地丢弃并置sticky RAS，避免永久堵塞端口。
    assign fabric_ready = (semantic_ready & unpack_valid) |
        (fabric_valid & ~unpack_valid);
    assign o_observe_ingress_committed_valid=decoder_valid&ingress_meta_valid;
    assign o_observe_ingress_committed_ready=decoder_ready;
    assign o_observe_egress_retired_valid=fabric_valid;
    assign o_observe_egress_retired_ready=fabric_ready;
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            metadata_error_q <= {C_PORTS{1'b0}};
        end else begin
            metadata_error_q <= metadata_error_q | (fabric_valid & ~unpack_valid);
        end
    end
    switch_egress_upli_repack #(
        .C_PORTS(C_PORTS), .C_OWNER_MASK_WIDTH(C_OWNER_COUNT),
        .C_OWNER_TOKEN_WIDTH(C_RX_TOKEN_WIDTH)
    ) u_upli_semantic (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_valid(fabric_valid & unpack_valid), .o_ready(semantic_ready),
        .i_data(fabric_data), .i_meta(unpack_user_meta), .i_class(fabric_class),
        .i_tl_msg(egress_tl_msg), .i_original_upli_vc(fabric_vc),
        .i_egress_upli_pool(egress_upli_pool),
        .i_egress_upli_pool_valid(egress_upli_pool_valid),
        .i_source_port(unpack_owner_source), .i_dst_port(egress_protocol_dst), .i_sop(fabric_sop),
        .i_eop(fabric_eop), .i_packet_flits(fabric_flits),
        .i_owner_valid(unpack_owner_valid), .i_owner_tokens(unpack_owner_tokens),
        .o_valid(semantic_valid), .i_ready(o_upli_credit_candidate_ready),
        .o_data(semantic_data), .o_meta(semantic_meta), .o_class(semantic_class),
        .o_tl_msg(semantic_msg), .o_original_upli_vc(semantic_vc),
        .o_original_upli_pool(semantic_pool), .o_source_port(semantic_src),
        .o_dst_port(semantic_dst), .o_sop(semantic_sop), .o_eop(semantic_eop),
        .o_packet_flits(semantic_flits), .o_owner_valid(semantic_owner_valid),
        .o_owner_tokens(semantic_owner_tokens), .o_reserved_body(semantic_reserved_body),
        .o_demand_valid(upli_demand_valid), .o_demand_vc(upli_demand_vc),
        .o_demand_pool(upli_demand_pool), .o_demand_count(upli_demand_count),
        .o_error(semantic_error), .o_config_error(semantic_config_error)
    );

    switch_station_upli_multi_channel_admission #(
        .C_NUM_STATIONS(C_NUM_STATIONS), .C_CREDIT_WIDTH(C_UPLI_CREDIT_WIDTH)
    ) u_upli_credit (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_station_mode(o_station_active_mode), .i_port_link_up(i_lane_up),
        .i_port_link_reset(i_port_link_reset),
        .i_credit_connected(i_upli_credit_connected), .i_beats_connected(i_upli_beats_connected),
        .i_credit_valid(i_upli_credit_valid), .i_credit_pool(i_upli_credit_pool),
        .i_credit_vc(i_upli_credit_vc), .i_credit_num(i_upli_credit_num),
        .i_credit_init_done(i_upli_credit_init_done), .i_candidate_valid(semantic_valid),
        .o_candidate_ready(o_upli_credit_candidate_ready),
        .i_pre_reserved(semantic_reserved_body), .i_demand_valid(upli_demand_valid),
        .i_demand_pool(upli_demand_pool), .i_demand_vc(upli_demand_vc),
        .i_demand_count(upli_demand_count), .o_admitted_valid(upli_admitted_valid),
        .i_admitted_ready(upli_admitted_ready), .o_admitted_fire(upli_admitted_fire),
        .o_candidate_eligible(upli_eligible), .o_active_logical_ports(upli_active_ports),
        .o_operational_ports(upli_operational_ports), .o_init_confirmed(upli_init_confirmed),
        .o_balances(upli_balances), .o_invalid_demand_error(upli_invalid_demand_error),
        .o_inactive_candidate_error(upli_inactive_candidate_error),
        .o_credit_error_event_level(o_mgmt_upli_credit_error_event_level),
        .o_credit_error(upli_credit_error), .o_illegal_mode_error(upli_illegal_mode_error),
        .o_ras_error(upli_ras_error)
    );

    switch_admitted_upli_tl_packer #(
        .C_PORTS(C_PORTS), .C_COUNT_WIDTH(C_COUNT_WIDTH),
        .C_OWNER_MASK_WIDTH(C_OWNER_COUNT), .C_OWNER_TOKEN_WIDTH(C_RX_TOKEN_WIDTH)
    ) u_tl_packer (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_admitted_valid(upli_admitted_valid), .o_admitted_ready(upli_admitted_ready),
        .i_data(semantic_data), .i_meta(semantic_meta), .i_class(semantic_class),
        .i_tl_msg(semantic_msg), .i_original_upli_vc(semantic_vc),
        .i_original_upli_pool(semantic_pool), .i_source_port(semantic_src),
        .i_dst_port(semantic_dst), .i_sop(semantic_sop), .i_eop(semantic_eop),
        .i_packet_flits(semantic_flits), .i_provenance_valid(semantic_provenance_valid),
        .i_reserved_body(semantic_reserved_body), .i_demand_valid(upli_demand_valid),
        .i_demand_vc(upli_demand_vc), .i_demand_pool(upli_demand_pool),
        .i_demand_count(upli_demand_count), .i_owner_valid(semantic_owner_valid),
        .i_owner_tokens(semantic_owner_tokens), .o_tl_valid(packer_tl_valid),
        .i_tl_ready(packer_tl_ready), .o_tl_data(normal_tx_data),
        .o_tl_msg(normal_tx_msg), .o_tl_demands(normal_tx_demands),
        .o_tl_sop(packer_tl_sop), .o_tl_eop(packer_tl_eop),
        .o_tl_source_port(packer_tl_source), .o_tl_owner_valid(packer_tl_owner_valid),
        .o_tl_owner_tokens(packer_tl_owner_tokens), .o_busy(packer_busy),
        .o_error(packer_error), .o_config_error(packer_config_error)
    );

    // 尾TL拍必须同时进入FC持久slot和RX return网络，任一路反压都禁止另一侧先消费。
    assign normal_tx_valid = packer_tl_valid & (~packer_tl_eop | return_input_ready);
    assign packer_tl_ready = normal_tx_ready & (~packer_tl_eop | return_input_ready);
    assign return_input_valid = packer_tl_valid & packer_tl_eop & normal_tx_ready;
    switch_rx_retirement_return_fabric #(
        .C_INPUTS(C_PORTS), .C_NUM_SOURCES(C_PORTS), .C_NUM_BANKS(C_RETURN_BANKS),
        .C_SOURCE_WIDTH(10), .C_MASK_WIDTH(C_OWNER_COUNT),
        .C_TOKEN_WIDTH(C_RX_TOKEN_WIDTH)
    ) u_retirement_return (
        .i_clk(i_clk), .i_rstn(i_rstn && C_CONFIG_LEGAL),
        .i_valid(return_input_valid), .o_ready(return_input_ready),
        .i_eop(packer_tl_eop), .i_source_port(packer_tl_source),
        .i_owner_valid(packer_tl_owner_valid), .i_owner_tokens(packer_tl_owner_tokens),
        .o_source_valid(return_source_valid), .i_source_ready(return_source_ready),
        .o_source_owner_valid(return_source_owner_valid),
        .o_source_owner_tokens(return_source_owner_tokens),
        .o_quiescent(return_quiescent), .o_error(return_error),
        .o_config_error(return_config_error)
    );

    wire protocol_empty = !(|decoder_busy) && (&fabric_slice_quiescent) &&
        !(|semantic_valid) && !(|packer_busy) &&
        (&(owner_quiescent | ~tl_operational)) && return_quiescent && !(|link_tx_valid);
    assign o_route_commit_ready = C_CONFIG_LEGAL && fabric_all_empty &&
        protocol_empty && station_quiescent_all;
    reg route_commit_rejected_q;
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            route_commit_rejected_q <= 1'b0;
        end else if (i_route_commit_request && fabric_commit_pending) begin
            route_commit_rejected_q <= 1'b1;
        end
    end
    assign o_route_commit_rejected = route_commit_rejected_q;
    assign o_mgmt_route_epoch=fabric_epoch;
    assign o_mgmt_route_pending=fabric_commit_pending;
    assign o_mgmt_commit_wait_cycles=fabric_commit_wait_cycles;
    assign o_mgmt_fabric_timeout_error=fabric_timeout_error;
    assign o_mgmt_station_busy=station_busy;
    assign o_mgmt_station_quiescent=station_quiescent;
    assign o_mgmt_station_error=station_error;
    assign o_mgmt_release_valid=fabric_release_valid;
    assign o_mgmt_release_ready=fabric_release_ready;
    assign o_mgmt_resource_free=fabric_effective_free;
    assign o_mgmt_queue_occupancy=fabric_queue_occupancy;
    assign o_mgmt_credit_issued=fabric_credit_issued;
    assign o_mgmt_credit_occupied=fabric_credit_occupied;
    assign o_upli_mapping_unsupported = semantic_error;
    assign o_quiescent = C_CONFIG_LEGAL && o_route_commit_ready;
    assign o_config_error = !C_CONFIG_LEGAL || station_config_error || decoder_config_error ||
        fabric_config_error || semantic_config_error || packer_config_error || map_config_error ||
        return_config_error || (|owner_config_error) || (|codec_config_error) ||
        (|fabric_slice_config_error);
    assign o_error = o_config_error || station_link_error || tl_ras_error ||
        (|owner_error) || (|decoder_error) || fabric_error || map_identity_error || (|codec_error) ||
        (|metadata_error_q) ||
        (|semantic_error) || upli_ras_error || (|packer_error) || return_error ||
        (|fabric_slice_error) ||
        route_commit_rejected_q;

    wire unused = ^{station_active_mask, station_slot_enable, station_commit_accept,
        station_mode_error, station_busy, station_quiescent, station_error, station_slot_port,
        station_busy_any, link_tx_is_fc, tl_rx_initialized, owner_decode_demands,
        owner_decode_release_obligation, fabric_pool, fabric_dst, fabric_policy, packer_tl_sop,
        map_group_id, map_tile_id, map_local_port, map_station_id, map_lane_mask,
        map_service_units, tl_rx_start_ready, tl_rx_start_taken, tl_rx_retire_taken,
        tl_active_ports, tl_tx_available, tl_rx_pending, tl_invalid_rx_error,
        tl_starvation_error, tl_credit_error, decoder_owner_count, fabric_head_valid,
        fabric_src, fabric_src_group, fabric_route_epoch, fabric_release_valid, fabric_release_ready,
        fabric_release_account, fabric_release_token, fabric_advisory_valid,
        fabric_advisory_match, fabric_advisory_mismatch, fabric_advisory_stale,
        fabric_hint_eligible, fabric_hint_used, fabric_probe_path, fabric_hint_pending,
        fabric_hint_error, fabric_new_sop, fabric_quiesce_request, fabric_commit_pulse,
        fabric_commit_pending, fabric_commit_wait_cycles, fabric_timeout_error,
        fabric_inactive_group_error, codec_unpack_error,
        upli_admitted_fire, upli_active_ports, upli_operational_ports,
        upli_init_confirmed, upli_balances, upli_invalid_demand_error,
        upli_inactive_candidate_error, upli_credit_error, upli_illegal_mode_error};
endmodule

`default_nettype wire

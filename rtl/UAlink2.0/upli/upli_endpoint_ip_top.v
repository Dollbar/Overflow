`timescale 1ns/1ps // 原生接口、接收SRAM和角色控制共享一个同步时钟域。
`default_nettype none // 禁止原生字段、信用或角色归属接线遗漏。
module upli_endpoint_ip_top #( // 模块聚合原生UPLI双角色前端，后端上下文接口仍显式开放。
parameter integer C_NUM_PORTS=1, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_CREDIT_WIDTH=4, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY=4, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_IS_TL=0, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_TX_REQ_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_TX_DATA_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_TX_RD_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_TX_WR_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_RX_REQ_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_RX_DATA_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_RX_RD_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_RX_WR_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_INIT_COUNT_WIDTH=4, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_INIT_CYCLES=2, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_RETURN_DEPTH=4, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_PENDING_WIDTH=(C_RETURN_DEPTH<=1)?1:(C_RETURN_DEPTH<=3)?2:(C_RETURN_DEPTH<=7)?3:(C_RETURN_DEPTH<=15)?4:5, // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
parameter integer C_ORDER_COUNT_WIDTH=C_CREDIT_WIDTH+3 // 沿用实际子模块参数，TX远端容量和本地RX容量分别配置。
)( // typed发送候选与真实响应collector握手分别保留所有权。
input wire  i_clk, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rstn, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_originator_ready, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_originator_peer_req, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_originator_peer_ack, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_originator_req, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_originator_ack, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_originator_tx_connected, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_originator_rx_connected, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_originator_beats_connected, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_completer_ready, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_completer_peer_req, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_completer_peer_ack, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_completer_req, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_completer_ack, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_completer_tx_connected, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_completer_rx_connected, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_completer_beats_connected, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_fault_ack, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_drop_roles, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2*C_NUM_PORTS-1:0] o_drop_ports, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_notify_roles, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_ack_accepted, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_reset_required, // 完整原生字段、可信描述符或独立消费者资格。
output wire [31:0] o_reason_sticky, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_init_incomplete, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_data_error_observed, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_raw_credit_valid_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_raw_credit_control_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_raw_credit_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_backend_implemented, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_req_candidate_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_req_candidate_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_req_candidate_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_req_candidate_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_req_candidate_has_data, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_req_candidate_num_beats, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_req_candidate_data_pools, // 完整原生字段、可信描述符或独立消费者资格。
input wire [183:0] i_tx_req_candidate_request, // 完整原生字段、可信描述符或独立消费者资格。
input wire [2047:0] i_tx_req_candidate_data, // 完整原生字段、可信描述符或独立消费者资格。
input wire [255:0] i_tx_req_candidate_byte_enable, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_req_candidate_error, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_req_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_req_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_req_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_req_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_req_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_data_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_data_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_data_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_data_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_data_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_candidate_accepted, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_req_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_req_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [183:0] o_tx_req_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_data_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_data_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_data_offset, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_last, // 完整原生字段、可信描述符或独立消费者资格。
output wire [511:0] o_tx_data_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [63:0] o_tx_data_byte_enable, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_req_balances, // 完整原生字段、可信描述符或独立消费者资格。
output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_data_balances, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_req_init, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_data_init, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_credit_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_credit_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_data_credit_error_sticky, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_req_busy, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_tdm_known, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_req_tdm_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_req_asi, // 完整原生字段、可信描述符或独立消费者资格。
output wire [63:0] o_tx_req_auth_tag, // 完整原生字段、可信描述符或独立消费者资格。
output wire [9:0] o_tx_req_src, // 完整原生字段、可信描述符或独立消费者资格。
output wire [9:0] o_tx_req_dst, // 完整原生字段、可信描述符或独立消费者资格。
output wire [10:0] o_tx_req_tag, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_req_num_beats, // 完整原生字段、可信描述符或独立消费者资格。
output wire [56:0] o_tx_req_address, // 完整原生字段、可信描述符或独立消费者资格。
output wire [5:0] o_tx_req_command, // 完整原生字段、可信描述符或独立消费者资格。
output wire [5:0] o_tx_req_length, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_tx_req_attr, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_tx_req_metadata, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_auth_tag_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_address_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_req_control_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_byte_enable_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_data_fields_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_tx_data_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_rd_candidate_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_rd_candidate_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_rd_candidate_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_rd_candidate_pools, // 完整原生字段、可信描述符或独立消费者资格。
input wire [2475:0] i_tx_rd_candidate_payload, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_rd_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_rd_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_rd_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_rd_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_rd_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_candidate_accepted, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_candidate_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_rd_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [63:0] o_tx_rd_auth_tag, // 完整原生字段、可信描述符或独立消费者资格。
output wire [9:0] o_tx_rd_src, // 完整原生字段、可信描述符或独立消费者资格。
output wire [9:0] o_tx_rd_dst, // 完整原生字段、可信描述符或独立消费者资格。
output wire [10:0] o_tx_rd_tag, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_rd_num_beats, // 完整原生字段、可信描述符或独立消费者资格。
output wire [511:0] o_tx_rd_data, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_rd_status, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_rd_offset, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_last, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_data_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_rd_type_info, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_rd_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_auth_tag_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_tx_rd_data_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_control_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [618:0] o_tx_rd_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_rd_busy, // 完整原生字段、可信描述符或独立消费者资格。
output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_rd_balances, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_rd_init_confirmed, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_credit_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_credit_error_sticky, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_rd_tdm_known, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_rd_tdm_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_wr_candidate_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_wr_candidate_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_tx_wr_candidate_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_wr_candidate_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [100:0] i_tx_wr_candidate_payload, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_wr_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_wr_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_wr_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire [7:0] i_tx_wr_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_tx_wr_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_candidate_accepted, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_wr_type_info, // 完整原生字段、可信描述符或独立消费者资格。
output wire [10:0] o_tx_wr_tag, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_wr_status, // 完整原生字段、可信描述符或独立消费者资格。
output wire [9:0] o_tx_wr_src, // 完整原生字段、可信描述符或独立消费者资格。
output wire [9:0] o_tx_wr_dst, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_wr_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_wr_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [63:0] o_tx_wr_auth_tag, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_auth_tag_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_control_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_wr_balances, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_wr_init_confirmed, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_credit_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_credit_error_sticky, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_tx_wr_tdm_known, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_tx_wr_tdm_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_req_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_req_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_data_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_data_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_rd_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_rd_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_wr_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_tx_wr_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_credit_valid_parity_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_credit_control_parity_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_credit_parity_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_tx_credit_integrity_ok, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_auth_enabled, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_select_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire i_req_class_known, // 与原始Request同沿的外部可信分类，不猜命令编码。
input wire i_req_has_data, // 已确认命令是否携带OrigData，不能从Data有效反推。
output wire [9:0] o_rx_burst_error, // 原始burst本拍完整诊断，接唯一角色故障控制器。
output wire [9:0] o_rx_burst_error_sticky, // 首组burst错误保存到共同reset。
output wire [C_NUM_PORTS-1:0] o_rx_burst_active, // 原始尾部描述符只作诊断观察。
input wire  i_rx_req_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_req_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_req_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_req_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [183:0] i_rx_req_payload, // 完整原生字段、可信描述符或独立消费者资格。
input wire [12:0] i_rx_req_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_req_consumer_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_req_head_taken, // 完整原生字段、可信描述符或独立消费者资格。
output wire [183:0] o_rx_req_head_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [12:0] o_rx_req_head_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_req_head_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_req_head_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2:0] o_rx_req_head_account, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_req_head_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_req_consume_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_req_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_req_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_req_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_req_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_req_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_req_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_req_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_data_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_data_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_data_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_data_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [579:0] i_rx_data_payload, // 完整原生字段、可信描述符或独立消费者资格。
input wire [12:0] i_rx_data_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_data_consumer_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_data_head_taken, // 完整原生字段、可信描述符或独立消费者资格。
output wire [579:0] o_rx_data_head_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [12:0] o_rx_data_head_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_data_head_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_data_head_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2:0] o_rx_data_head_account, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_data_head_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_data_consume_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_data_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_data_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_data_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_data_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_data_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_data_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_data_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_rd_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_rd_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_rd_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_rd_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [618:0] i_rx_rd_payload, // 完整原生字段、可信描述符或独立消费者资格。
input wire [12:0] i_rx_rd_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [618:0] o_rx_rd_head_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [12:0] o_rx_rd_head_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_rd_head_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_rd_head_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2:0] o_rx_rd_head_account, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_rd_head_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_rd_consume_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_rd_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_rd_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_rd_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_rd_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_rd_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_rd_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_rd_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_wr_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_wr_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_rx_wr_vc, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_wr_pool, // 完整原生字段、可信描述符或独立消费者资格。
input wire [100:0] i_rx_wr_payload, // 完整原生字段、可信描述符或独立消费者资格。
input wire [12:0] i_rx_wr_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [100:0] o_rx_wr_head_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [12:0] o_rx_wr_head_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_wr_head_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_wr_head_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2:0] o_rx_wr_head_account, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_wr_head_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_wr_consume_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_wr_credit_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_wr_credit_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_wr_credit_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire [7:0] o_rx_wr_credit_num, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_wr_credit_init_done, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_wr_credit_valid_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_wr_credit_parity, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_receive_accepted, // 完整原生字段、可信描述符或独立消费者资格。
output wire [51:0] o_rx_ingress_errors, // 完整原生字段、可信描述符或独立消费者资格。
output wire [51:0] o_rx_head_errors, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_control_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_data_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_auth_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_auth_profile_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_metadata_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_fault_stop_request, // 完整原生字段、可信描述符或独立消费者资格。
output wire [11:0] o_rx_storage_diagnostic, // 完整原生字段、可信描述符或独立消费者资格。
output wire [4*C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_rx_counts, // 完整原生字段、可信描述符或独立消费者资格。
output wire [16*C_PENDING_WIDTH-1:0] o_rx_pending_count, // 完整原生字段、可信描述符或独立消费者资格。
output wire [4*C_NUM_PORTS*C_ORDER_COUNT_WIDTH-1:0] o_rx_order_counts, // 完整原生字段、可信描述符或独立消费者资格。
output wire [4*C_NUM_PORTS-1:0] o_rx_order_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [4*C_NUM_PORTS-1:0] o_rx_order_error_sticky, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_tdm_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_tdm_error_sticky, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2:0] o_rx_tdm_phase_known, // 完整原生字段、可信描述符或独立消费者资格。
output wire [5:0] o_rx_tdm_expected_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire  i_rx_request_ready, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_request_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_request_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_rx_request_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_request_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [183:0] o_rx_request_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [2047:0] o_rx_request_data, // 完整原生字段、可信描述符或独立消费者资格。
output wire [255:0] o_rx_request_be, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_request_poison, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_rx_request_data_pools, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_bridge_busy, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_rx_bridge_error, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_response_select_valid, // 完整原生字段、可信描述符或独立消费者资格。
input wire [3:0] i_response_select_port, // 完整原生字段、可信描述符或独立消费者资格。
input wire [1:0] i_response_retire_ready, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_response_valid, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_response_port, // 完整原生字段、可信描述符或独立消费者资格。
output wire [3:0] o_response_vc, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_response_pool, // 完整原生字段、可信描述符或独立消费者资格。
output wire [5:0] o_response_account, // 完整原生字段、可信描述符或独立消费者资格。
output wire [618:0] o_response_read_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [100:0] o_response_write_payload, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_response_retired, // 完整原生字段、可信描述符或独立消费者资格。
output wire [1:0] o_response_metadata_error, // 完整原生字段、可信描述符或独立消费者资格。
output wire  o_response_fault_stop_request // 完整原生字段、可信描述符或独立消费者资格。
); // 结束完整原生前端聚合接口。
wire [3:0] collector_port;wire [1:0] collector_ready; // 实际collector唯一驱动两个原RX的选择和退休。
assign o_backend_implemented=1'b0; // 当前未接真正Endpoint上下文和执行器，禁止假完成。
upli_connection_side #(.C_IS_COMPLETER(1'b0)) u_originator_connection( // 本角色唯一连接状态机。
 .i_clk(i_clk),.i_rstn(i_rstn),.i_ready(i_originator_ready), // 连接保持与业务Drop分离，不撤销既有承诺。
 .i_peer_req(i_originator_peer_req),.i_peer_ack(i_originator_peer_ack), // 真实对端输入，不制造本地虚假应答。
 .o_req(o_originator_req),.o_ack(o_originator_ack), // 原生握手直接由实际寄存器驱动。
 .o_tx_connected(o_originator_tx_connected),.o_rx_connected(o_originator_rx_connected),.o_beats_connected(o_originator_beats_connected)); // 状态直接复用。
upli_connection_side #(.C_IS_COMPLETER(1'b1)) u_completer_connection( // 本角色唯一连接状态机。
 .i_clk(i_clk),.i_rstn(i_rstn),.i_ready(i_completer_ready), // 连接保持与业务Drop分离，不撤销既有承诺。
 .i_peer_req(i_completer_peer_req),.i_peer_ack(i_completer_peer_ack), // 真实对端输入，不制造本地虚假应答。
 .o_req(o_completer_req),.o_ack(o_completer_ack), // 原生握手直接由实际寄存器驱动。
 .o_tx_connected(o_completer_tx_connected),.o_rx_connected(o_completer_rx_connected),.o_beats_connected(o_completer_beats_connected)); // 状态直接复用。
wire [3:0] qualified_req_valid,qualified_req_pool,qualified_req_done; // 此组只筛掉当前不可信信用，不新建bank。
wire [7:0] qualified_req_vc,qualified_req_num; // 完整原账户字段零周期传递。
wire qualified_req_vp,qualified_req_fp,unused_req_integrity; // 过滤后使用公共primitive生成内部真实码。
upli_credit_guard u_req_raw_guard( // 首次检查实际外部收到的信用，不用重新生成码掩盖错误。
 .i_check_enable(i_rstn),.i_credit_valid(i_tx_req_credit_valid),.i_credit_pool(i_tx_req_credit_pool), // 全部四valid和完整控制组。
 .i_credit_vc(i_tx_req_credit_vc),.i_credit_num(i_tx_req_credit_num), // 原始元信息不先遮蔽。
 .i_credit_valid_parity(i_tx_req_credit_valid_parity),.i_credit_parity(i_tx_req_credit_parity), // 收到的两类实际保护。
 .o_valid_error(o_raw_credit_valid_error[0]),.o_control_error(o_raw_credit_control_error[0]),.o_error(o_raw_credit_error[0]),.o_integrity_ok(unused_req_integrity)); // 原始诊断接唯一角色故障所有者。
upli_credit_return_adapter u_req_qualified_credit( // 公共无状态保护只用于内部已筛选组，不是新增原生返回器。
 .i_credit_valid(i_tx_req_credit_valid & {4{i_rstn && !o_raw_credit_error[0]}}), // 坏组整组禁止进入唯一bank。
 .i_credit_pool(i_tx_req_credit_pool),.i_credit_vc(i_tx_req_credit_vc),.i_credit_num(i_tx_req_credit_num), // 完整控制字段保留。
 .i_credit_init_done(i_tx_req_credit_init_done & {4{i_rstn && !o_raw_credit_error[0]}}), // 坏valid组不能借独立done确认初始化。
 .o_credit_valid(qualified_req_valid),.o_credit_pool(qualified_req_pool),.o_credit_vc(qualified_req_vc),.o_credit_num(qualified_req_num), // 正常组不增加周期。
 .o_credit_init_done(qualified_req_done),.o_credit_valid_parity(qualified_req_vp),.o_credit_parity(qualified_req_fp)); // station内部既有guard检查实际交付组。
wire [3:0] qualified_data_valid,qualified_data_pool,qualified_data_done; // 此组只筛掉当前不可信信用，不新建bank。
wire [7:0] qualified_data_vc,qualified_data_num; // 完整原账户字段零周期传递。
wire qualified_data_vp,qualified_data_fp,unused_data_integrity; // 过滤后使用公共primitive生成内部真实码。
upli_credit_guard u_data_raw_guard( // 首次检查实际外部收到的信用，不用重新生成码掩盖错误。
 .i_check_enable(i_rstn),.i_credit_valid(i_tx_data_credit_valid),.i_credit_pool(i_tx_data_credit_pool), // 全部四valid和完整控制组。
 .i_credit_vc(i_tx_data_credit_vc),.i_credit_num(i_tx_data_credit_num), // 原始元信息不先遮蔽。
 .i_credit_valid_parity(i_tx_data_credit_valid_parity),.i_credit_parity(i_tx_data_credit_parity), // 收到的两类实际保护。
 .o_valid_error(o_raw_credit_valid_error[1]),.o_control_error(o_raw_credit_control_error[1]),.o_error(o_raw_credit_error[1]),.o_integrity_ok(unused_data_integrity)); // 原始诊断接唯一角色故障所有者。
upli_credit_return_adapter u_data_qualified_credit( // 公共无状态保护只用于内部已筛选组，不是新增原生返回器。
 .i_credit_valid(i_tx_data_credit_valid & {4{i_rstn && !o_raw_credit_error[1]}}), // 坏组整组禁止进入唯一bank。
 .i_credit_pool(i_tx_data_credit_pool),.i_credit_vc(i_tx_data_credit_vc),.i_credit_num(i_tx_data_credit_num), // 完整控制字段保留。
 .i_credit_init_done(i_tx_data_credit_init_done & {4{i_rstn && !o_raw_credit_error[1]}}), // 坏valid组不能借独立done确认初始化。
 .o_credit_valid(qualified_data_valid),.o_credit_pool(qualified_data_pool),.o_credit_vc(qualified_data_vc),.o_credit_num(qualified_data_num), // 正常组不增加周期。
 .o_credit_init_done(qualified_data_done),.o_credit_valid_parity(qualified_data_vp),.o_credit_parity(qualified_data_fp)); // station内部既有guard检查实际交付组。
wire [3:0] qualified_rd_valid,qualified_rd_pool,qualified_rd_done; // 此组只筛掉当前不可信信用，不新建bank。
wire [7:0] qualified_rd_vc,qualified_rd_num; // 完整原账户字段零周期传递。
wire qualified_rd_vp,qualified_rd_fp,unused_rd_integrity; // 过滤后使用公共primitive生成内部真实码。
upli_credit_guard u_rd_raw_guard( // 首次检查实际外部收到的信用，不用重新生成码掩盖错误。
 .i_check_enable(i_rstn),.i_credit_valid(i_tx_rd_credit_valid),.i_credit_pool(i_tx_rd_credit_pool), // 全部四valid和完整控制组。
 .i_credit_vc(i_tx_rd_credit_vc),.i_credit_num(i_tx_rd_credit_num), // 原始元信息不先遮蔽。
 .i_credit_valid_parity(i_tx_rd_credit_valid_parity),.i_credit_parity(i_tx_rd_credit_parity), // 收到的两类实际保护。
 .o_valid_error(o_raw_credit_valid_error[2]),.o_control_error(o_raw_credit_control_error[2]),.o_error(o_raw_credit_error[2]),.o_integrity_ok(unused_rd_integrity)); // 原始诊断接唯一角色故障所有者。
upli_credit_return_adapter u_rd_qualified_credit( // 公共无状态保护只用于内部已筛选组，不是新增原生返回器。
 .i_credit_valid(i_tx_rd_credit_valid & {4{i_rstn && !o_raw_credit_error[2]}}), // 坏组整组禁止进入唯一bank。
 .i_credit_pool(i_tx_rd_credit_pool),.i_credit_vc(i_tx_rd_credit_vc),.i_credit_num(i_tx_rd_credit_num), // 完整控制字段保留。
 .i_credit_init_done(i_tx_rd_credit_init_done & {4{i_rstn && !o_raw_credit_error[2]}}), // 坏valid组不能借独立done确认初始化。
 .o_credit_valid(qualified_rd_valid),.o_credit_pool(qualified_rd_pool),.o_credit_vc(qualified_rd_vc),.o_credit_num(qualified_rd_num), // 正常组不增加周期。
 .o_credit_init_done(qualified_rd_done),.o_credit_valid_parity(qualified_rd_vp),.o_credit_parity(qualified_rd_fp)); // station内部既有guard检查实际交付组。
wire [3:0] qualified_wr_valid,qualified_wr_pool,qualified_wr_done; // 此组只筛掉当前不可信信用，不新建bank。
wire [7:0] qualified_wr_vc,qualified_wr_num; // 完整原账户字段零周期传递。
wire qualified_wr_vp,qualified_wr_fp,unused_wr_integrity; // 过滤后使用公共primitive生成内部真实码。
upli_credit_guard u_wr_raw_guard( // 首次检查实际外部收到的信用，不用重新生成码掩盖错误。
 .i_check_enable(i_rstn),.i_credit_valid(i_tx_wr_credit_valid),.i_credit_pool(i_tx_wr_credit_pool), // 全部四valid和完整控制组。
 .i_credit_vc(i_tx_wr_credit_vc),.i_credit_num(i_tx_wr_credit_num), // 原始元信息不先遮蔽。
 .i_credit_valid_parity(i_tx_wr_credit_valid_parity),.i_credit_parity(i_tx_wr_credit_parity), // 收到的两类实际保护。
 .o_valid_error(o_raw_credit_valid_error[3]),.o_control_error(o_raw_credit_control_error[3]),.o_error(o_raw_credit_error[3]),.o_integrity_ok(unused_wr_integrity)); // 原始诊断接唯一角色故障所有者。
upli_credit_return_adapter u_wr_qualified_credit( // 公共无状态保护只用于内部已筛选组，不是新增原生返回器。
 .i_credit_valid(i_tx_wr_credit_valid & {4{i_rstn && !o_raw_credit_error[3]}}), // 坏组整组禁止进入唯一bank。
 .i_credit_pool(i_tx_wr_credit_pool),.i_credit_vc(i_tx_wr_credit_vc),.i_credit_num(i_tx_wr_credit_num), // 完整控制字段保留。
 .i_credit_init_done(i_tx_wr_credit_init_done & {4{i_rstn && !o_raw_credit_error[3]}}), // 坏valid组不能借独立done确认初始化。
 .o_credit_valid(qualified_wr_valid),.o_credit_pool(qualified_wr_pool),.o_credit_vc(qualified_wr_vc),.o_credit_num(qualified_wr_num), // 正常组不增加周期。
 .o_credit_init_done(qualified_wr_done),.o_credit_valid_parity(qualified_wr_vp),.o_credit_parity(qualified_wr_fp)); // station内部既有guard检查实际交付组。
upli_station_tx #(.C_NUM_PORTS(C_NUM_PORTS),.C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), // 三sender四bank和三相位只有此实例拥有。
.C_REQ_CAPACITIES(C_TX_REQ_CAPACITIES),.C_DATA_CAPACITIES(C_TX_DATA_CAPACITIES),.C_RD_CAPACITIES(C_TX_RD_CAPACITIES),.C_WR_CAPACITIES(C_TX_WR_CAPACITIES), // TX容量描述远端接收资源。
 .C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH),.C_INIT_CYCLES(C_INIT_CYCLES)) u_tx( // Drop在调度资格处阻断首拍及已预约尾部。
.i_clk(i_clk), // 完整typed字段和实际bank观察保持原语义。
.i_rstn(i_rstn), // 完整typed字段和实际bank观察保持原语义。
.i_originator_credit_connected(o_originator_rx_connected), // 完整typed字段和实际bank观察保持原语义。
.i_originator_beats_connected(o_originator_beats_connected && !o_drop_roles[0]), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_valid(i_tx_req_candidate_valid), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_port(i_tx_req_candidate_port), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_vc(i_tx_req_candidate_vc), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_pool(i_tx_req_candidate_pool), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_has_data(i_tx_req_candidate_has_data), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_num_beats(i_tx_req_candidate_num_beats), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_data_pools(i_tx_req_candidate_data_pools), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_request(i_tx_req_candidate_request), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_data(i_tx_req_candidate_data), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_byte_enable(i_tx_req_candidate_byte_enable), // 完整typed字段和实际bank观察保持原语义。
.i_req_candidate_error(i_tx_req_candidate_error), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_valid(qualified_req_valid), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_pool(qualified_req_pool), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_vc(qualified_req_vc), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_num(qualified_req_num), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_init_done(qualified_req_done), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_valid(qualified_data_valid), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_pool(qualified_data_pool), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_vc(qualified_data_vc), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_num(qualified_data_num), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_init_done(qualified_data_done), // 完整typed字段和实际bank观察保持原语义。
.o_req_candidate_accepted(o_tx_req_candidate_accepted), // 完整typed字段和实际bank观察保持原语义。
.o_req_valid(o_tx_req_valid), // 完整typed字段和实际bank观察保持原语义。
.o_req_port(o_tx_req_port), // 完整typed字段和实际bank观察保持原语义。
.o_req_vc(o_tx_req_vc), // 完整typed字段和实际bank观察保持原语义。
.o_req_pool(o_tx_req_pool), // 完整typed字段和实际bank观察保持原语义。
.o_req_payload(o_tx_req_payload), // 完整typed字段和实际bank观察保持原语义。
.o_data_valid(o_tx_data_valid), // 完整typed字段和实际bank观察保持原语义。
.o_data_port(o_tx_data_port), // 完整typed字段和实际bank观察保持原语义。
.o_data_vc(o_tx_data_vc), // 完整typed字段和实际bank观察保持原语义。
.o_data_pool(o_tx_data_pool), // 完整typed字段和实际bank观察保持原语义。
.o_data_offset(o_tx_data_offset), // 完整typed字段和实际bank观察保持原语义。
.o_data_last(o_tx_data_last), // 完整typed字段和实际bank观察保持原语义。
.o_data_payload(o_tx_data_payload), // 完整typed字段和实际bank观察保持原语义。
.o_data_byte_enable(o_tx_data_byte_enable), // 完整typed字段和实际bank观察保持原语义。
.o_data_error(o_tx_data_error), // 完整typed字段和实际bank观察保持原语义。
.o_req_balances(o_tx_req_balances), // 完整typed字段和实际bank观察保持原语义。
.o_data_balances(o_tx_data_balances), // 完整typed字段和实际bank观察保持原语义。
.o_req_init(o_tx_req_init), // 完整typed字段和实际bank观察保持原语义。
.o_data_init(o_tx_data_init), // 完整typed字段和实际bank观察保持原语义。
.o_req_credit_error(o_tx_req_credit_error), // 完整typed字段和实际bank观察保持原语义。
.o_data_credit_error(o_tx_data_credit_error), // 完整typed字段和实际bank观察保持原语义。
.o_req_data_credit_error_sticky(o_tx_req_data_credit_error_sticky), // 完整typed字段和实际bank观察保持原语义。
.o_req_busy(o_tx_req_busy), // 完整typed字段和实际bank观察保持原语义。
.o_req_tdm_known(o_tx_req_tdm_known), // 完整typed字段和实际bank观察保持原语义。
.o_req_tdm_port(o_tx_req_tdm_port), // 完整typed字段和实际bank观察保持原语义。
.o_req_asi(o_tx_req_asi), // 完整typed字段和实际bank观察保持原语义。
.o_req_auth_tag(o_tx_req_auth_tag), // 完整typed字段和实际bank观察保持原语义。
.o_req_src(o_tx_req_src), // 完整typed字段和实际bank观察保持原语义。
.o_req_dst(o_tx_req_dst), // 完整typed字段和实际bank观察保持原语义。
.o_req_tag(o_tx_req_tag), // 完整typed字段和实际bank观察保持原语义。
.o_req_num_beats(o_tx_req_num_beats), // 完整typed字段和实际bank观察保持原语义。
.o_req_address(o_tx_req_address), // 完整typed字段和实际bank观察保持原语义。
.o_req_command(o_tx_req_command), // 完整typed字段和实际bank观察保持原语义。
.o_req_length(o_tx_req_length), // 完整typed字段和实际bank观察保持原语义。
.o_req_attr(o_tx_req_attr), // 完整typed字段和实际bank观察保持原语义。
.o_req_metadata(o_tx_req_metadata), // 完整typed字段和实际bank观察保持原语义。
.o_req_valid_parity(o_tx_req_valid_parity), // 完整typed字段和实际bank观察保持原语义。
.o_req_auth_tag_parity(o_tx_req_auth_tag_parity), // 完整typed字段和实际bank观察保持原语义。
.o_req_address_parity(o_tx_req_address_parity), // 完整typed字段和实际bank观察保持原语义。
.o_req_control_parity(o_tx_req_control_parity), // 完整typed字段和实际bank观察保持原语义。
.o_data_valid_parity(o_tx_data_valid_parity), // 完整typed字段和实际bank观察保持原语义。
.o_data_byte_enable_parity(o_tx_data_byte_enable_parity), // 完整typed字段和实际bank观察保持原语义。
.o_data_fields_parity(o_tx_data_fields_parity), // 完整typed字段和实际bank观察保持原语义。
.o_data_parity(o_tx_data_parity), // 完整typed字段和实际bank观察保持原语义。
.i_completer_credit_connected(o_completer_rx_connected), // 完整typed字段和实际bank观察保持原语义。
.i_completer_beats_connected(o_completer_beats_connected && !o_drop_roles[1]), // 完整typed字段和实际bank观察保持原语义。
.i_rd_candidate_valid(i_tx_rd_candidate_valid), // 完整typed字段和实际bank观察保持原语义。
.i_rd_candidate_port(i_tx_rd_candidate_port), // 完整typed字段和实际bank观察保持原语义。
.i_rd_candidate_vc(i_tx_rd_candidate_vc), // 完整typed字段和实际bank观察保持原语义。
.i_rd_candidate_pools(i_tx_rd_candidate_pools), // 完整typed字段和实际bank观察保持原语义。
.i_rd_candidate_payload(i_tx_rd_candidate_payload), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_valid(qualified_rd_valid), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_pool(qualified_rd_pool), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_vc(qualified_rd_vc), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_num(qualified_rd_num), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_init_done(qualified_rd_done), // 完整typed字段和实际bank观察保持原语义。
.o_rd_candidate_accepted(o_tx_rd_candidate_accepted), // 完整typed字段和实际bank观察保持原语义。
.o_rd_candidate_error(o_tx_rd_candidate_error), // 完整typed字段和实际bank观察保持原语义。
.o_rd_valid(o_tx_rd_valid), // 完整typed字段和实际bank观察保持原语义。
.o_rd_port(o_tx_rd_port), // 完整typed字段和实际bank观察保持原语义。
.o_rd_auth_tag(o_tx_rd_auth_tag), // 完整typed字段和实际bank观察保持原语义。
.o_rd_src(o_tx_rd_src), // 完整typed字段和实际bank观察保持原语义。
.o_rd_dst(o_tx_rd_dst), // 完整typed字段和实际bank观察保持原语义。
.o_rd_tag(o_tx_rd_tag), // 完整typed字段和实际bank观察保持原语义。
.o_rd_num_beats(o_tx_rd_num_beats), // 完整typed字段和实际bank观察保持原语义。
.o_rd_data(o_tx_rd_data), // 完整typed字段和实际bank观察保持原语义。
.o_rd_status(o_tx_rd_status), // 完整typed字段和实际bank观察保持原语义。
.o_rd_offset(o_tx_rd_offset), // 完整typed字段和实际bank观察保持原语义。
.o_rd_last(o_tx_rd_last), // 完整typed字段和实际bank观察保持原语义。
.o_rd_data_error(o_tx_rd_data_error), // 完整typed字段和实际bank观察保持原语义。
.o_rd_type_info(o_tx_rd_type_info), // 完整typed字段和实际bank观察保持原语义。
.o_rd_vc(o_tx_rd_vc), // 完整typed字段和实际bank观察保持原语义。
.o_rd_pool(o_tx_rd_pool), // 完整typed字段和实际bank观察保持原语义。
.o_rd_valid_parity(o_tx_rd_valid_parity), // 完整typed字段和实际bank观察保持原语义。
.o_rd_auth_tag_parity(o_tx_rd_auth_tag_parity), // 完整typed字段和实际bank观察保持原语义。
.o_rd_data_parity(o_tx_rd_data_parity), // 完整typed字段和实际bank观察保持原语义。
.o_rd_control_parity(o_tx_rd_control_parity), // 完整typed字段和实际bank观察保持原语义。
.o_rd_payload(o_tx_rd_payload), // 完整typed字段和实际bank观察保持原语义。
.o_rd_busy(o_tx_rd_busy), // 完整typed字段和实际bank观察保持原语义。
.o_rd_balances(o_tx_rd_balances), // 完整typed字段和实际bank观察保持原语义。
.o_rd_init_confirmed(o_tx_rd_init_confirmed), // 完整typed字段和实际bank观察保持原语义。
.o_rd_credit_error(o_tx_rd_credit_error), // 完整typed字段和实际bank观察保持原语义。
.o_rd_credit_error_sticky(o_tx_rd_credit_error_sticky), // 完整typed字段和实际bank观察保持原语义。
.o_rd_tdm_known(o_tx_rd_tdm_known), // 完整typed字段和实际bank观察保持原语义。
.o_rd_tdm_port(o_tx_rd_tdm_port), // 完整typed字段和实际bank观察保持原语义。
.i_wr_candidate_valid(i_tx_wr_candidate_valid), // 完整typed字段和实际bank观察保持原语义。
.i_wr_candidate_port(i_tx_wr_candidate_port), // 完整typed字段和实际bank观察保持原语义。
.i_wr_candidate_vc(i_tx_wr_candidate_vc), // 完整typed字段和实际bank观察保持原语义。
.i_wr_candidate_pool(i_tx_wr_candidate_pool), // 完整typed字段和实际bank观察保持原语义。
.i_wr_candidate_payload(i_tx_wr_candidate_payload), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_valid(qualified_wr_valid), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_pool(qualified_wr_pool), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_vc(qualified_wr_vc), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_num(qualified_wr_num), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_init_done(qualified_wr_done), // 完整typed字段和实际bank观察保持原语义。
.o_wr_candidate_accepted(o_tx_wr_candidate_accepted), // 完整typed字段和实际bank观察保持原语义。
.o_wr_valid(o_tx_wr_valid), // 完整typed字段和实际bank观察保持原语义。
.o_wr_type_info(o_tx_wr_type_info), // 完整typed字段和实际bank观察保持原语义。
.o_wr_tag(o_tx_wr_tag), // 完整typed字段和实际bank观察保持原语义。
.o_wr_status(o_tx_wr_status), // 完整typed字段和实际bank观察保持原语义。
.o_wr_src(o_tx_wr_src), // 完整typed字段和实际bank观察保持原语义。
.o_wr_dst(o_tx_wr_dst), // 完整typed字段和实际bank观察保持原语义。
.o_wr_port(o_tx_wr_port), // 完整typed字段和实际bank观察保持原语义。
.o_wr_vc(o_tx_wr_vc), // 完整typed字段和实际bank观察保持原语义。
.o_wr_pool(o_tx_wr_pool), // 完整typed字段和实际bank观察保持原语义。
.o_wr_auth_tag(o_tx_wr_auth_tag), // 完整typed字段和实际bank观察保持原语义。
.o_wr_valid_parity(o_tx_wr_valid_parity), // 完整typed字段和实际bank观察保持原语义。
.o_wr_auth_tag_parity(o_tx_wr_auth_tag_parity), // 完整typed字段和实际bank观察保持原语义。
.o_wr_control_parity(o_tx_wr_control_parity), // 完整typed字段和实际bank观察保持原语义。
.o_wr_balances(o_tx_wr_balances), // 完整typed字段和实际bank观察保持原语义。
.o_wr_init_confirmed(o_tx_wr_init_confirmed), // 完整typed字段和实际bank观察保持原语义。
.o_wr_credit_error(o_tx_wr_credit_error), // 完整typed字段和实际bank观察保持原语义。
.o_wr_credit_error_sticky(o_tx_wr_credit_error_sticky), // 完整typed字段和实际bank观察保持原语义。
.o_wr_tdm_known(o_tx_wr_tdm_known), // 完整typed字段和实际bank观察保持原语义。
.o_wr_tdm_port(o_tx_wr_tdm_port), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_valid_parity(qualified_req_vp), // 完整typed字段和实际bank观察保持原语义。
.i_req_credit_parity(qualified_req_fp), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_valid_parity(qualified_data_vp), // 完整typed字段和实际bank观察保持原语义。
.i_data_credit_parity(qualified_data_fp), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_valid_parity(qualified_rd_vp), // 完整typed字段和实际bank观察保持原语义。
.i_rd_credit_parity(qualified_rd_fp), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_valid_parity(qualified_wr_vp), // 完整typed字段和实际bank观察保持原语义。
.i_wr_credit_parity(qualified_wr_fp), // 完整typed字段和实际bank观察保持原语义。
.o_credit_valid_parity_error(o_tx_credit_valid_parity_error), // 完整typed字段和实际bank观察保持原语义。
.o_credit_control_parity_error(o_tx_credit_control_parity_error), // 完整typed字段和实际bank观察保持原语义。
.o_credit_parity_error(o_tx_credit_parity_error), // 完整typed字段和实际bank观察保持原语义。
.o_credit_integrity_ok(o_tx_credit_integrity_ok) // 完整typed字段和实际bank观察保持原语义。
); // 结束真实station TX聚合。
upli_endpoint_native_rx_path #(.C_NUM_PORTS(C_NUM_PORTS),.C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), // 四RX与完整holding保持既有唯一所有权。
.C_REQ_CAPACITIES(C_RX_REQ_CAPACITIES),.C_DATA_CAPACITIES(C_RX_DATA_CAPACITIES),.C_RD_CAPACITIES(C_RX_RD_CAPACITIES),.C_WR_CAPACITIES(C_RX_WR_CAPACITIES), // RX容量描述本地真实SRAM资源。
 .C_RETURN_DEPTH(C_RETURN_DEPTH),.C_PENDING_WIDTH(C_PENDING_WIDTH),.C_ORDER_COUNT_WIDTH(C_ORDER_COUNT_WIDTH)) u_rx( // 可信返回不被业务Drop过滤。
.i_clk(i_clk), // 保留完整native、可信head、descriptor与分类诊断。
.i_rstn(i_rstn), // 保留完整native、可信head、descriptor与分类诊断。
.i_originator_credit_connected(o_originator_tx_connected), // 保留完整native、可信head、descriptor与分类诊断。
.i_originator_beats_connected(o_originator_beats_connected), // 保留完整native、可信head、descriptor与分类诊断。
.i_completer_credit_connected(o_completer_tx_connected), // 保留完整native、可信head、descriptor与分类诊断。
.i_completer_beats_connected(o_completer_beats_connected), // 保留完整native、可信head、descriptor与分类诊断。
.i_originator_drop(o_drop_roles[0]), // 保留完整native、可信head、descriptor与分类诊断。
.i_completer_drop(o_drop_roles[1]), // 保留完整native、可信head、descriptor与分类诊断。
.i_auth_enabled(i_rx_auth_enabled), // 保留完整native、可信head、descriptor与分类诊断。
.i_select_port(i_rx_select_port), // 保留完整native、可信head、descriptor与分类诊断。
.i_req_valid(i_rx_req_valid), // 保留完整native、可信head、descriptor与分类诊断。
.i_req_port(i_rx_req_port), // 保留完整native、可信head、descriptor与分类诊断。
.i_req_vc(i_rx_req_vc), // 保留完整native、可信head、descriptor与分类诊断。
.i_req_pool(i_rx_req_pool), // 保留完整native、可信head、descriptor与分类诊断。
.i_req_payload(i_rx_req_payload), // 保留完整native、可信head、descriptor与分类诊断。
.i_req_parity(i_rx_req_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_consumer_port(o_rx_req_consumer_port), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_taken(o_rx_req_head_taken), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_payload(o_rx_req_head_payload), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_parity(o_rx_req_head_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_vc(o_rx_req_head_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_pool(o_rx_req_head_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_account(o_rx_req_head_account), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_head_valid(o_rx_req_head_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_consume_valid(o_rx_req_consume_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_valid(o_rx_req_credit_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_pool(o_rx_req_credit_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_vc(o_rx_req_credit_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_num(o_rx_req_credit_num), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_init_done(o_rx_req_credit_init_done), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_valid_parity(o_rx_req_credit_valid_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_req_credit_parity(o_rx_req_credit_parity), // 保留完整native、可信head、descriptor与分类诊断。
.i_data_valid(i_rx_data_valid), // 保留完整native、可信head、descriptor与分类诊断。
.i_data_port(i_rx_data_port), // 保留完整native、可信head、descriptor与分类诊断。
.i_data_vc(i_rx_data_vc), // 保留完整native、可信head、descriptor与分类诊断。
.i_data_pool(i_rx_data_pool), // 保留完整native、可信head、descriptor与分类诊断。
.i_data_payload(i_rx_data_payload), // 保留完整native、可信head、descriptor与分类诊断。
.i_data_parity(i_rx_data_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_consumer_port(o_rx_data_consumer_port), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_taken(o_rx_data_head_taken), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_payload(o_rx_data_head_payload), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_parity(o_rx_data_head_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_vc(o_rx_data_head_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_pool(o_rx_data_head_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_account(o_rx_data_head_account), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_head_valid(o_rx_data_head_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_consume_valid(o_rx_data_consume_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_valid(o_rx_data_credit_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_pool(o_rx_data_credit_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_vc(o_rx_data_credit_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_num(o_rx_data_credit_num), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_init_done(o_rx_data_credit_init_done), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_valid_parity(o_rx_data_credit_valid_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_credit_parity(o_rx_data_credit_parity), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_valid(i_rx_rd_valid), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_port(i_rx_rd_port), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_vc(i_rx_rd_vc), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_pool(i_rx_rd_pool), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_payload(i_rx_rd_payload), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_parity(i_rx_rd_parity), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_consumer_port(collector_port[0 +: 2]), // 保留完整native、可信head、descriptor与分类诊断。
.i_rd_consumer_ready(collector_ready[0]), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_head_payload(o_rx_rd_head_payload), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_head_parity(o_rx_rd_head_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_head_vc(o_rx_rd_head_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_head_pool(o_rx_rd_head_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_head_account(o_rx_rd_head_account), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_head_valid(o_rx_rd_head_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_consume_valid(o_rx_rd_consume_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_valid(o_rx_rd_credit_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_pool(o_rx_rd_credit_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_vc(o_rx_rd_credit_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_num(o_rx_rd_credit_num), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_init_done(o_rx_rd_credit_init_done), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_valid_parity(o_rx_rd_credit_valid_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_rd_credit_parity(o_rx_rd_credit_parity), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_valid(i_rx_wr_valid), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_port(i_rx_wr_port), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_vc(i_rx_wr_vc), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_pool(i_rx_wr_pool), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_payload(i_rx_wr_payload), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_parity(i_rx_wr_parity), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_consumer_port(collector_port[2 +: 2]), // 保留完整native、可信head、descriptor与分类诊断。
.i_wr_consumer_ready(collector_ready[1]), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_head_payload(o_rx_wr_head_payload), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_head_parity(o_rx_wr_head_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_head_vc(o_rx_wr_head_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_head_pool(o_rx_wr_head_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_head_account(o_rx_wr_head_account), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_head_valid(o_rx_wr_head_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_consume_valid(o_rx_wr_consume_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_valid(o_rx_wr_credit_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_pool(o_rx_wr_credit_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_vc(o_rx_wr_credit_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_num(o_rx_wr_credit_num), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_init_done(o_rx_wr_credit_init_done), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_valid_parity(o_rx_wr_credit_valid_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_wr_credit_parity(o_rx_wr_credit_parity), // 保留完整native、可信head、descriptor与分类诊断。
.o_receive_accepted(o_rx_receive_accepted), // 保留完整native、可信head、descriptor与分类诊断。
.o_ingress_errors(o_rx_ingress_errors), // 保留完整native、可信head、descriptor与分类诊断。
.o_head_errors(o_rx_head_errors), // 保留完整native、可信head、descriptor与分类诊断。
.o_control_error(o_rx_control_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_data_error(o_rx_data_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_auth_error(o_rx_auth_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_auth_profile_error(o_rx_auth_profile_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_metadata_error(o_rx_metadata_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_fault_stop_request(o_rx_fault_stop_request), // 保留完整native、可信head、descriptor与分类诊断。
.o_storage_diagnostic(o_rx_storage_diagnostic), // 保留完整native、可信head、descriptor与分类诊断。
.o_counts(o_rx_counts), // 保留完整native、可信head、descriptor与分类诊断。
.o_pending_count(o_rx_pending_count), // 保留完整native、可信head、descriptor与分类诊断。
.o_order_counts(o_rx_order_counts), // 保留完整native、可信head、descriptor与分类诊断。
.o_order_error(o_rx_order_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_order_error_sticky(o_rx_order_error_sticky), // 保留完整native、可信head、descriptor与分类诊断。
.o_tdm_error(o_rx_tdm_error), // 保留完整native、可信head、descriptor与分类诊断。
.o_tdm_error_sticky(o_rx_tdm_error_sticky), // 保留完整native、可信head、descriptor与分类诊断。
.o_tdm_phase_known(o_rx_tdm_phase_known), // 保留完整native、可信head、descriptor与分类诊断。
.o_tdm_expected_port(o_rx_tdm_expected_port), // 保留完整native、可信head、descriptor与分类诊断。
.i_request_ready(i_rx_request_ready), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_valid(o_rx_request_valid), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_port(o_rx_request_port), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_vc(o_rx_request_vc), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_pool(o_rx_request_pool), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_payload(o_rx_request_payload), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_data(o_rx_request_data), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_be(o_rx_request_be), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_poison(o_rx_request_poison), // 保留完整native、可信head、descriptor与分类诊断。
.o_request_data_pools(o_rx_request_data_pools), // 保留完整native、可信head、descriptor与分类诊断。
.o_bridge_busy(o_rx_bridge_busy), // 保留完整native、可信head、descriptor与分类诊断。
.o_bridge_error(o_rx_bridge_error) // 保留完整native、可信head、descriptor与分类诊断。
); // 结束冻结的实际native RX路径。
upli_endpoint_response_collector #(.C_NUM_PORTS(C_NUM_PORTS)) u_response( // 实际响应交付层，不新增payload存储或信用银行。
 .i_clk(i_clk),.i_rstn(i_rstn),.i_stop(o_drop_roles[0]), // Originator角色Drop统一停止可信响应退休。
 .i_select_valid(i_response_select_valid),.i_select_port(i_response_select_port), // 两路独立端口候选，背压锁定由collector拥有。
 .i_head_valid({o_rx_wr_head_valid,o_rx_rd_head_valid}),.i_consume_valid({o_rx_wr_consume_valid,o_rx_rd_consume_valid}), // 低Read高Write，实际返回队列空间也必须具备。
 .i_head_vc({o_rx_wr_head_vc,o_rx_rd_head_vc}),.i_head_pool({o_rx_wr_head_pool,o_rx_rd_head_pool}),.i_head_account({o_rx_wr_head_account,o_rx_rd_head_account}), // 原账户不重构、不另归还。
 .i_read_payload(o_rx_rd_head_payload),.i_write_payload(o_rx_wr_head_payload),.i_retire_ready(i_response_retire_ready), // 完整保护头与真实消费者接受资格。
 .o_consumer_port(collector_port),.o_consumer_ready(collector_ready), // 唯一真实SRAM退休直接接原RX。
 .o_response_valid(o_response_valid),.o_response_port(o_response_port),.o_response_vc(o_response_vc),.o_response_pool(o_response_pool),.o_response_account(o_response_account), // 保留完整port/VC/pool身份。
 .o_read_payload(o_response_read_payload),.o_write_payload(o_response_write_payload),.o_retired(o_response_retired), // 只定义原始响应交付，不能当作Tag或应用完成。
 .o_metadata_error(o_response_metadata_error),.o_fault_stop_request(o_response_fault_stop_request)); // 本地结构诊断送唯一角色所有者。
reg [1:0] collector_error_q; // 两路元数据诊断同步过桥，避免Stop与RX headvalid形成组合反馈。
always @(posedge i_clk)begin // 仅扩展本地诊断时序，不增加响应数据或退休延时。
 if(!i_rstn)collector_error_q<=2'd0; // 共同reset清除旧epoch诊断。
 else collector_error_q<=collector_error_q | o_response_metadata_error; // collector已同沿阻断坏头，下一沿统一角色Drop。
end // 结束本地诊断同步桥接。
upli_native_rx_burst_monitor #(.C_NUM_PORTS(C_NUM_PORTS)) u_burst_monitor( // 仅增加burst诊断，沿用既有TDM相位。
 .i_clk(i_clk),.i_rstn(i_rstn), // 使用全层共同reset，Drop不是重建边界。
 .i_tdm_known(o_rx_tdm_phase_known[0]),.i_tdm_port(o_rx_tdm_expected_port[1:0]), // 唯一接收时隙观察者的沿前状态。
 .i_req_valid(i_rx_req_valid),.i_req_port(i_rx_req_port),.i_req_class_known(i_req_class_known),.i_req_has_data(i_req_has_data), // 原始事件及同沿外部确认分类。
 .i_req_vc(i_rx_req_vc),.i_req_num_beats(i_rx_req_payload[86:85]), // 保存原始请求VC与完整拍数编码。
 .i_data_valid(i_rx_data_valid),.i_data_port(i_rx_data_port),.i_data_vc(i_rx_data_vc), // 原始OrigData，不用延迟存储accepted替换。
 .i_data_offset(i_rx_data_payload[3:2]),.i_data_last(i_rx_data_payload[1]), // 本地完整580位bundle的原生控制字段。
 .o_error(o_rx_burst_error),.o_error_sticky(o_rx_burst_error_sticky),.o_active(o_rx_burst_active)); // 完整诊断保留独立原因，不产生ready或信用。
wire [3:0] kind_control,kind_credit,kind_auth,kind_profile,kind_metadata,kind_order,kind_storage,kind_tdm,kind_data; // controller按Req/Rd/Wr/Data的kind次序接收。
wire [1:0] init_done_roles; // 只记录真实两方向初始化资格，不控制恢复。
reg bridge_error_q; // 寄存本地组装错误避免Drop取消holding形成组合自反馈，不是第二Drop状态。
always @(posedge i_clk)begin // 非原生控制类的本地非法描述符先同步捕获诊断。
 if(!i_rstn)bridge_error_q<=1'b0; // 共同reset取消旧epoch的组装诊断。
 else bridge_error_q<=bridge_error_q || o_rx_bridge_error; // 下一沿由唯一角色控制器扩大本地fail-stop范围。
end // 结束单个位的本地诊断桥接。
assign kind_control={o_rx_control_error[1],o_rx_control_error[3],o_rx_control_error[2],o_rx_control_error[0]}; // Req/Data/Rd/Wr转为规范kind索引，不交换角色。
assign kind_auth={o_rx_auth_error[1],o_rx_auth_error[3],o_rx_auth_error[2],o_rx_auth_error[0]}; // Req/Data/Rd/Wr转为规范kind索引，不交换角色。
assign kind_profile={o_rx_auth_profile_error[1],o_rx_auth_profile_error[3],o_rx_auth_profile_error[2],o_rx_auth_profile_error[0]}; // Req/Data/Rd/Wr转为规范kind索引，不交换角色。
assign kind_tdm={o_rx_tdm_error[1],o_rx_tdm_error[3],o_rx_tdm_error[2],o_rx_tdm_error[0]}; // Req/Data/Rd/Wr转为规范kind索引，不交换角色。
assign kind_data={o_rx_data_error[1],o_rx_data_error[3],o_rx_data_error[2],o_rx_data_error[0]}; // Req/Data/Rd/Wr转为规范kind索引，不交换角色。
assign kind_metadata={o_rx_metadata_error[1],(o_rx_metadata_error[3] || collector_error_q[1]),(o_rx_metadata_error[2] || collector_error_q[0]),(o_rx_metadata_error[0] || bridge_error_q)}; // 本地组装错误归Request接收角色的保守策略。
assign kind_credit={o_raw_credit_error[1] || o_tx_data_credit_error,o_raw_credit_error[3] || o_tx_wr_credit_error,o_raw_credit_error[2] || o_tx_rd_credit_error,o_raw_credit_error[0] || o_tx_req_credit_error}; // 反向信用归属由controller独立角色掩码判定。
assign kind_order[0]=(|o_rx_burst_error) || (|o_rx_order_error[0*C_NUM_PORTS +: C_NUM_PORTS]) || (|o_rx_order_error_sticky[0*C_NUM_PORTS +: C_NUM_PORTS]); // 角色作用域不从可疑port字段缩小。
assign kind_storage[0]=|o_rx_storage_diagnostic[0*3 +: 3]; // 保留实际FIFO输入诊断的通道归属。
assign kind_order[1]=(|o_rx_order_error[2*C_NUM_PORTS +: C_NUM_PORTS]) || (|o_rx_order_error_sticky[2*C_NUM_PORTS +: C_NUM_PORTS]); // 角色作用域不从可疑port字段缩小。
assign kind_storage[1]=|o_rx_storage_diagnostic[2*3 +: 3]; // 保留实际FIFO输入诊断的通道归属。
assign kind_order[2]=(|o_rx_order_error[3*C_NUM_PORTS +: C_NUM_PORTS]) || (|o_rx_order_error_sticky[3*C_NUM_PORTS +: C_NUM_PORTS]); // 角色作用域不从可疑port字段缩小。
assign kind_storage[2]=|o_rx_storage_diagnostic[3*3 +: 3]; // 保留实际FIFO输入诊断的通道归属。
assign kind_order[3]=(|o_rx_order_error[1*C_NUM_PORTS +: C_NUM_PORTS]) || (|o_rx_order_error_sticky[1*C_NUM_PORTS +: C_NUM_PORTS]); // 角色作用域不从可疑port字段缩小。
assign kind_storage[3]=|o_rx_storage_diagnostic[1*3 +: 3]; // 保留实际FIFO输入诊断的通道归属。
assign init_done_roles[0]=(&o_tx_req_init[C_NUM_PORTS-1:0]) && (&o_tx_data_init[C_NUM_PORTS-1:0]) && (&o_rx_rd_credit_init_done[C_NUM_PORTS-1:0]) && (&o_rx_wr_credit_init_done[C_NUM_PORTS-1:0]); // Originator两向初始化来源真实独立。
assign init_done_roles[1]=(&o_tx_rd_init_confirmed[C_NUM_PORTS-1:0]) && (&o_tx_wr_init_confirmed[C_NUM_PORTS-1:0]) && (&o_rx_req_credit_init_done[C_NUM_PORTS-1:0]) && (&o_rx_data_credit_init_done[C_NUM_PORTS-1:0]); // Completer两向初始化不得借用另一角色。
upli_rx_role_fault_controller #(.C_NUM_PORTS(C_NUM_PORTS),.C_NUM_ROLES(2),.C_IS_TL(C_IS_TL)) u_fault( // 本聚合唯一角色Drop及通知所有者。
 .i_clk(i_clk),.i_rstn(i_rstn),.i_fault_ack(i_fault_ack),.i_init_done_roles(init_done_roles), // ack只确认通知，恢复需要共同reset。
 .i_control_error(kind_control),.i_credit_control_error(kind_credit),.i_auth_error(kind_auth),.i_auth_profile_error(kind_profile), // 原生控制与反向信用分开归属。
 .i_metadata_error(kind_metadata),.i_order_error(kind_order),.i_storage_error(kind_storage),.i_tdm_error(kind_tdm),.i_data_error(kind_data), // data-only按拍poison，不能升级为Drop。
 .o_drop_roles(o_drop_roles),.o_drop_ports(o_drop_ports),.o_notify_roles(o_notify_roles),.o_ack_accepted(o_ack_accepted), // 所有业务使用同一真实角色故障资格。
 .o_reset_required(o_reset_required),.o_reason_sticky(o_reason_sticky),.o_init_incomplete(o_init_incomplete),.o_data_error_observed(o_data_error_observed)); // 保留原因与故障初始化边界。
endmodule // 结束实际原生前端，backend/collector仍须后续真实接入。
`default_nettype wire // 恢复独立编译单元默认网络。

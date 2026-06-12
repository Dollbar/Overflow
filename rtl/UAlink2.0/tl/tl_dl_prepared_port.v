`timescale 1ns/1ps // 角色中立prepared传输连线，沿用唯一真实所有者。
`default_nettype none // 角色中立prepared传输连线，沿用唯一真实所有者。
module tl_dl_prepared_port #( // 角色中立prepared传输连线，沿用唯一真实所有者。
 parameter integer WIDTH=8, HEADER_DEPTH=2, BANK_DEPTH=3, RX_DEPTH=40, DL_DEPTH=3, // 角色中立prepared传输连线，沿用唯一真实所有者。
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:(HEADER_DEPTH<8)?3:(HEADER_DEPTH<16)?4:(HEADER_DEPTH<32)?5:(HEADER_DEPTH<64)?6:(HEADER_DEPTH<128)?7:(HEADER_DEPTH<256)?8:(HEADER_DEPTH<512)?9:(HEADER_DEPTH<1024)?10:(HEADER_DEPTH<2048)?11:(HEADER_DEPTH<4096)?12:(HEADER_DEPTH<8192)?13:(HEADER_DEPTH<16384)?14:(HEADER_DEPTH<32768)?15:16, // 角色中立prepared传输连线，沿用唯一真实所有者。
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:(BANK_DEPTH<8)?3:(BANK_DEPTH<16)?4:(BANK_DEPTH<32)?5:(BANK_DEPTH<64)?6:(BANK_DEPTH<128)?7:(BANK_DEPTH<256)?8:(BANK_DEPTH<512)?9:(BANK_DEPTH<1024)?10:(BANK_DEPTH<2048)?11:(BANK_DEPTH<4096)?12:(BANK_DEPTH<8192)?13:(BANK_DEPTH<16384)?14:(BANK_DEPTH<32768)?15:16, // 角色中立prepared传输连线，沿用唯一真实所有者。
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:(RX_DEPTH<128)?7:(RX_DEPTH<256)?8:(RX_DEPTH<512)?9:(RX_DEPTH<1024)?10:(RX_DEPTH<2048)?11:(RX_DEPTH<4096)?12:(RX_DEPTH<8192)?13:(RX_DEPTH<16384)?14:(RX_DEPTH<32768)?15:16 // 角色中立prepared传输连线，沿用唯一真实所有者。
,parameter integer POISON_ENABLE=0 // 默认关闭追加Poison路径。
,parameter integer DEFERRED_COMMAND_ENABLE=0,REQUEST_QUEUE_DEPTH=20,RESPONSE_QUEUE_DEPTH=20,SHARED_DATA_PROGRESS_ENABLE=0
)( // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire i_clk,i_rstn,i_link_reset,i_start,i_auth,i_shared, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [20*WIDTH-1:0] i_capacities, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [1:0] i_source_valid,i_source_tags_valid, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [511:0] i_source_control, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [1023:0] i_source_tags, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [3:0] i_data_valid, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [511:0] i_data0,i_data1, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [1:0] o_source_captured,o_source_ready,o_data_ready, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [3:0] o_data_accepted, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire i_read_ready, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire o_read_valid, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [511:0] o_read_flit, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [1:0] o_read_msg, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [5:0] o_read_classes, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [79:0] o_read_releases, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire o_link_valid, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [543:0] o_link_data, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire i_link_ready, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire o_link_payload,o_link_replay, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [8:0] o_link_sequence, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire i_link_valid, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [543:0] i_link_data, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire i_link_crc_ok, // 角色中立prepared传输连线，沿用唯一真实所有者。
 input wire [7:0] i_rx_replay_limit, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire o_link_ready, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire o_start_ready,o_start_taken,o_config_error,o_done,o_peer_done,o_peer_shared,o_error, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [20*(WIDTH+1)-1:0] o_capacity,o_available,o_pending, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [6:0] o_tx_pending, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [89:0] o_tx_validation_state, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [2*HEADER_COUNT_WIDTH-1:0] o_header_count, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [2*(DATA_COUNT_WIDTH+1)-1:0] o_data_count, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [RX_COUNT_WIDTH-1:0] o_rx_count, // 角色中立prepared传输连线，沿用唯一真实所有者。
 output wire [7:0] o_unacked_count,o_scheduled_count // 角色中立prepared传输连线，沿用唯一真实所有者。
,output wire o_busy // 包含源准备、初始化、信用、SRAM和固定返回槽的真实忙状态。
,output wire o_route_busy,o_dl_payload_busy,o_dl_control_busy,o_rx_route_busy // 分离路由负载责任与不依赖目的表的DL控制槽。
,input wire [1:0] i_poison0,i_poison1 // 同类Data标记随实际入队。
,input wire i_cmd_release_valid,input wire [39:0] i_cmd_releases
,output wire o_cmd_release_taken,output wire [10*(WIDTH+1)-1:0] o_cmd_pending
); // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [1:0] prepared_busy; // 实际源准备器状态，而非线上pending推测。
assign o_busy=rstn&&(!o_done||!o_peer_done||holding_valid||inflight||(|prepared_busy)||tx_valid||fc_valid||(|o_tx_pending)||(|o_header_count)||(|o_data_count)||(|o_rx_count)||(|o_pending)||(|o_unacked_count)||(|o_scheduled_count)||(|o_cmd_pending)||o_error); // 不把零header计数误当完整排空。
wire rx_safe_control; // 信任实际接收器的CRC/op/sequence接纳，不凭单个Payload位放行。
assign rx_safe_control=unused_u_dl_o_rx_accept&&!i_link_data[540]&&!unused_u_dl_o_rx_command_request; // 被接纳的Original/ACK非payload才不依赖路由。
assign o_rx_route_busy=rstn&&i_link_valid&&!rx_safe_control; // 包含被CRC/格式/序号拒绝的输入以及ReplayRequest。
assign o_dl_payload_busy=rstn&&((holding_valid&&holding_payload)||(inflight&&inflight_payload)||unused_u_dl_o_issue_payload); // 保存预约时类别并覆盖同拍新payload预约。
assign o_dl_control_busy=rstn&&((holding_valid&&!holding_payload)||(inflight&&!inflight_payload)||(dl_issue_accept&&!unused_u_dl_o_issue_payload)); // 控制槽继续真实保持/退休，不因路由提交被取消。
assign o_route_busy=rstn&&(i_start||!o_done||!o_peer_done||o_dl_payload_busy||o_rx_route_busy||(|i_source_valid)||(|i_data_valid)||(|prepared_busy)||tx_valid||fc_valid||(|o_tx_pending)||(|o_header_count)||(|o_data_count)||(|o_rx_count)||(|o_pending)||(|o_unacked_count)||(|o_scheduled_count)||unused_u_dl_o_rx_replay||unused_u_dl_o_rx_ambiguous||(|unused_u_dl_o_tx_request_count)||(|o_cmd_pending)||o_error); // 全部TL/信用/重放/reset责任仍阻止配置生效。
localparam integer DL_ADDR_WIDTH=(DL_DEPTH<=2)?1:(DL_DEPTH<=4)?2:(DL_DEPTH<=8)?3:(DL_DEPTH<=16)?4:(DL_DEPTH<=32)?5:(DL_DEPTH<=64)?6:(DL_DEPTH<=128)?7:(DL_DEPTH<=256)?8:(DL_DEPTH<=512)?9:(DL_DEPTH<=1024)?10:(DL_DEPTH<=2048)?11:12; // 与实际重放存储地址派生一致。
wire [1:0] unused_u_tx_o_source_tags_taken; // 明确未消费的子模块观察输出。
wire [1:0] unused_u_tx_o_group_queued; // 明确未消费的子模块观察输出。
wire [1:0] unused_u_tx_o_partition_taken; // 明确未消费的子模块观察输出。
wire [1:0] unused_u_tx_o_tags_taken; // 明确未消费的子模块观察输出。
wire unused_u_tx_o_packet_sop,unused_u_tx_o_packet_eop; // legacy DL prepared路径明确不消费内部边界。
wire  unused_u_credit_o_rx_allowed; // 明确未消费的子模块观察输出。
wire  unused_u_credit_o_rx_rejected; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_credit_o_rx_lower; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_credit_o_rx_upper; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_credit_o_tx_lower; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_credit_o_tx_upper; // 明确未消费的子模块观察输出。
wire [79:0] unused_u_credit_o_demands; // 明确未消费的子模块观察输出。
wire [6:0] unused_u_credit_o_rx_pending; // 明确未消费的子模块观察输出。
wire [72:0] unused_u_credit_o_rx_be; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_credit_o_requests_available; // 明确未消费的子模块观察输出。
wire [3:0] unused_u_credit_o_responses_available; // 明确未消费的子模块观察输出。
wire  unused_u_credit_o_pair_open; // 明确未消费的子模块观察输出。
wire  unused_u_credit_o_pair_poison; // 明确未消费的子模块观察输出。
wire  unused_u_credit_o_init_repeat; // 明确未消费的子模块观察输出。
wire [72:0] unused_u_credit_o_tx_be; // 明确未消费的子模块观察输出。
wire [437:0] unused_u_credit_o_metadata; // 明确未消费的子模块观察输出。
wire  unused_u_credit_o_admission_wait; // 明确未消费的子模块观察输出。
wire  unused_u_credit_o_capacity_shortfall; // 明确未消费的子模块观察输出。
wire [119:0] unused_u_credit_o_requirements; // 明确未消费的子模块观察输出。
wire [WIDTH+5:0] unused_u_receive_o_required_words; // 明确未消费的子模块观察输出。
wire  unused_u_receive_o_allowed; // 明确未消费的子模块观察输出。
wire  unused_u_receive_o_rejected; // 明确未消费的子模块观察输出。
wire  unused_u_receive_o_fc_complete; // 明确未消费的子模块观察输出。
wire  unused_u_receive_o_active; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_issue_ready; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_issue_payload; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_issue_first; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_issue_sequence; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_out_first; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_out_stored_sequence; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_ack_accept; // 明确未消费的子模块观察输出。
wire [7:0] unused_u_dl_o_ack_count; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_request_accept; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_command_reject; // 明确未消费的子模块观察输出。
wire [7:0] unused_u_dl_o_resident_count; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_ctl_last_sequence; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_ctl_last_ack; // 明确未消费的子模块观察输出。
wire [3:0] unused_u_dl_o_ctl_ignore_count; // 明确未消费的子模块观察输出。
wire [DL_ADDR_WIDTH-1:0] unused_u_dl_o_ctl_head_pointer; // 明确未消费的子模块观察输出。
wire [DL_ADDR_WIDTH-1:0] unused_u_dl_o_ctl_write_pointer; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_ctl_scheduled_sequence; // 明确未消费的子模块观察输出。
wire [DL_ADDR_WIDTH-1:0] unused_u_dl_o_ctl_scheduled_pointer; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_ctl_first_pending; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_ingress_event; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_accept; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_sequence_valid; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_rx_sequence; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_replay_request; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_command_valid; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_command_request; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_rx_command_target; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_crc_error; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_zero_sequence; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_zero_command; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_backpressure_drop; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_unexpected; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_ambiguous_drop; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_replay_drop; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_rx_last_sequence; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_dl_o_rx_bad_crc_count; // 明确未消费的子模块观察输出。
wire [7:0] unused_u_dl_o_rx_unexpected_count; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_ambiguous; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_rx_replay; // 明确未消费的子模块观察输出。
wire [23:0] unused_u_dl_o_issue_header; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_issue_header_valid; // 明确未消费的子模块观察输出。
wire [2:0] unused_u_dl_o_tx_explicit_count; // 明确未消费的子模块观察输出。
wire [1:0] unused_u_dl_o_tx_request_count; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_tx_request_sequence; // 明确未消费的子模块观察输出。
wire  unused_u_dl_o_tx_group_used; // 明确未消费的子模块观察输出。
wire [8:0] unused_u_dl_o_rx_effective_sequence; // 明确未消费的子模块观察输出。
// 全部状态只在i_clk上升沿复位；这是研发全层清除，不是协议LinkDown恢复。
wire rstn; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign rstn=i_rstn&&!i_link_reset; // 角色中立prepared传输连线，沿用唯一真实所有者。
reg r_rx_reject; // 联合准入失败保留至共同reset；不增加数据或信用所有者。
wire rx_storage_allowed=unused_u_receive_o_allowed;
wire rx_credit_allowed=unused_u_credit_o_rx_allowed;
wire rx_reserved=(|rx_data[519:514]); // 本地520bit framing的保留位不能提交任何TL责任。
wire rx_reject=dl_rx&&(!rx_storage_allowed||!rx_credit_allowed||rx_reserved);
always @(posedge i_clk)begin
 if(!rstn)r_rx_reject<=1'b0;
 else if(rx_reject)r_rx_reject<=1'b1;
end
wire tx_valid,tx_taken,tx_allowed,credit_fatal,receive_fatal,credit_tx_error; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [511:0] tx_flit,fc_flit; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [1:0] tx_msg,fc_msg,header_taken,header_error,input_error,prepare_error,prepare_shortfall,capacity_shortfall; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [3:0] data_taken; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire fc_valid,fc_taken,publish_taken,port_rx_taken,storage_rx_taken,retired,release_taken; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire init_conflict; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire dl_issue_accept,dl_accept,dl_issue_replay,dl_valid,dl_payload,dl_replay,dl_rx,tag_error,metadata_error; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [8:0] dl_sequence; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [23:0] dl_header; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire [519:0] dl_data,rx_data; // 角色中立prepared传输连线，沿用唯一真实所有者。
wire reserve,rx_event; // 角色中立prepared传输连线，沿用唯一真实所有者。
reg holding_valid,inflight;reg inflight_payload; // 角色中立prepared传输连线，沿用唯一真实所有者。
reg [543:0] holding_data; // 角色中立prepared传输连线，沿用唯一真实所有者。
reg holding_payload,holding_replay; // 角色中立prepared传输连线，沿用唯一真实所有者。
reg [8:0] holding_sequence; // 角色中立prepared传输连线，沿用唯一真实所有者。

// 固定一拍DL返回必须先预约真实holding容量；不在消费同拍旁路预约。
assign reserve=rstn&&!holding_valid&&!inflight; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_link_valid=rstn&&holding_valid; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_link_data=o_link_valid?holding_data:544'd0; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_link_payload=o_link_valid&&holding_payload; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_link_replay=o_link_valid&&holding_replay; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_link_sequence=o_link_valid?holding_sequence:9'd0; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_link_ready=rstn; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign rx_event=i_link_valid&&o_link_ready; // 角色中立prepared传输连线，沿用唯一真实所有者。
always @(posedge i_clk) begin // 角色中立prepared传输连线，沿用唯一真实所有者。
 if(!rstn)begin // 角色中立prepared传输连线，沿用唯一真实所有者。
  holding_valid<=1'b0;inflight<=1'b0;inflight_payload<=1'b0;holding_data<=544'd0; // 角色中立prepared传输连线，沿用唯一真实所有者。
  holding_payload<=1'b0;holding_replay<=1'b0;holding_sequence<=9'd0; // 角色中立prepared传输连线，沿用唯一真实所有者。
 end else begin // 角色中立prepared传输连线，沿用唯一真实所有者。
  if(o_link_valid&&i_link_ready)holding_valid<=1'b0; // 角色中立prepared传输连线，沿用唯一真实所有者。
  if(dl_issue_accept)begin inflight<=1'b1;inflight_payload<=unused_u_dl_o_issue_payload;end // 角色中立prepared传输连线，沿用唯一真实所有者。
  if(dl_valid)begin // 角色中立prepared传输连线，沿用唯一真实所有者。
   inflight<=1'b0;inflight_payload<=1'b0;holding_valid<=1'b1; // 角色中立prepared传输连线，沿用唯一真实所有者。
   holding_data<={dl_header,dl_data};holding_payload<=dl_payload; // 角色中立prepared传输连线，沿用唯一真实所有者。
   holding_replay<=dl_replay;holding_sequence<=dl_sequence; // 角色中立prepared传输连线，沿用唯一真实所有者。
  end // 角色中立prepared传输连线，沿用唯一真实所有者。
 end // 角色中立prepared传输连线，沿用唯一真实所有者。
end // 角色中立prepared传输连线，沿用唯一真实所有者。

tl_tx_prepared #(.POISON_ENABLE(POISON_ENABLE),.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH)) u_tx( // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_clk(i_clk),.i_rstn(rstn),.i_taken(tx_taken),.i_pending(o_tx_pending),.i_auth(i_auth), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_done(o_peer_done),.i_shared(o_peer_shared),.i_available(o_available),.i_capacity(o_capacity), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_request_budget(o_tx_validation_state[9:7]),.i_response_budget(o_tx_validation_state[6:3]), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_source_valid(i_source_valid),.i_source_control(i_source_control), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_source_tags_valid(i_source_tags_valid),.i_source_tags(i_source_tags), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_source_captured(o_source_captured),.o_source_ready(o_source_ready),.o_prepare_busy(prepared_busy), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_prepare_error(prepare_error),.o_prepare_shortfall(prepare_shortfall), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_poison0(i_poison0),.i_poison1(i_poison1),
 .i_data_valid(i_data_valid),.i_data0(i_data0),.i_data1(i_data1), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_fc_valid(fc_valid),.i_fc_flit(fc_flit),.i_fc_msg(fc_msg),.i_stop_request(1'b0), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_valid(tx_valid),.o_flit(tx_flit),.o_msg(tx_msg),.o_packet_sop(unused_u_tx_o_packet_sop),.o_packet_eop(unused_u_tx_o_packet_eop),.o_header_taken(header_taken), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_data_taken(data_taken),.o_fc_taken(fc_taken),.o_header_error(header_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_capacity_shortfall(capacity_shortfall),.o_data_accepted(o_data_accepted), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_data_ready(o_data_ready),.o_input_error(input_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_header_count(o_header_count),.o_data_count(o_data_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_source_tags_taken(unused_u_tx_o_source_tags_taken), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_group_queued(unused_u_tx_o_group_queued), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_partition_taken(unused_u_tx_o_partition_taken), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tags_taken(unused_u_tx_o_tags_taken)); // 角色中立prepared传输连线，沿用唯一真实所有者。

// 重放不消费TL源；只有DL首次payload接纳才原子扣除TL信用。
wire [159:0] unused_rx_grants;wire [1:0] unused_rx_init;wire unused_rx_runtime;
wire [79:0] unused_rx_demands;wire [663:0] unused_epoch_context;wire [89:0] unused_epoch_validation;
wire [48+20*(WIDTH+1):0] unused_epoch_publish;wire [20*(RX_COUNT_WIDTH+4)-1:0] unused_epoch_stored_releases;
wire [139:0] unused_epoch_context_releases;wire unused_epoch_owner_error;
tl_credit_admitted_port #(.WIDTH(WIDTH)) u_credit( // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_grants(unused_rx_grants),.o_rx_init(unused_rx_init),.o_rx_runtime(unused_rx_runtime),
 .i_clk(i_clk),.i_rstn(rstn),.i_receive(dl_rx&&rx_storage_allowed&&!r_rx_reject&&!rx_reserved),.i_send(dl_accept),.i_auth(i_auth), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_rx_flit(rx_data[511:0]),.i_rx_msg(rx_data[513:512]),.i_tx_flit(tx_flit),.i_tx_msg(tx_msg), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_taken(port_rx_taken),.o_tx_allowed(tx_allowed),.o_tx_taken(tx_taken),.o_tx_error(credit_tx_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_fatal(credit_fatal),.o_done(o_peer_done),.o_shared(o_peer_shared),.o_init_conflict(init_conflict), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_capacity(o_capacity),.o_available(o_available),.o_tx_pending(o_tx_pending), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_validation_state(o_tx_validation_state), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_allowed(unused_u_credit_o_rx_allowed), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_rejected(unused_u_credit_o_rx_rejected), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_lower(unused_u_credit_o_rx_lower), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_upper(unused_u_credit_o_rx_upper), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_lower(unused_u_credit_o_tx_lower), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_upper(unused_u_credit_o_tx_upper), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_demands(unused_u_credit_o_demands), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_pending(unused_u_credit_o_rx_pending), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_be(unused_u_credit_o_rx_be), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_requests_available(unused_u_credit_o_requests_available), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_responses_available(unused_u_credit_o_responses_available), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_pair_open(unused_u_credit_o_pair_open), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_pair_poison(unused_u_credit_o_pair_poison), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_init_repeat(unused_u_credit_o_init_repeat), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_be(unused_u_credit_o_tx_be), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_metadata(unused_u_credit_o_metadata), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_admission_wait(unused_u_credit_o_admission_wait), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_capacity_shortfall(unused_u_credit_o_capacity_shortfall), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_requirements(unused_u_credit_o_requirements)); // 角色中立prepared传输连线，沿用唯一真实所有者。

wire unused_epoch_store_taken; // 新的实际存入观察在默认角色中立端口不消费。
wire raw_start_ready,raw_config_error,cmd_error;
wire [WIDTH+2:0] req_cmd_sum[0:5],rsp_cmd_sum[0:5];
assign req_cmd_sum[0]=0;assign rsp_cmd_sum[0]=0;
genvar q;
generate for(q=0;q<5;q=q+1)begin:gen_cmd_budget
 assign req_cmd_sum[q+1]=req_cmd_sum[q]+{3'b000,i_capacities[q*WIDTH+:WIDTH]};
 assign rsp_cmd_sum[q+1]=rsp_cmd_sum[q]+{3'b000,i_capacities[(q+5)*WIDTH+:WIDTH]};
end endgenerate
// Shared pool is transient RX capacity; all retained fields have original CMD-sized private reservations.
wire deferred_fits=(!i_shared||(SHARED_DATA_PROGRESS_ENABLE!=0))&&({{(29-WIDTH){1'b0}},req_cmd_sum[5]}<=REQUEST_QUEUE_DEPTH)&&({{(29-WIDTH){1'b0}},rsp_cmd_sum[5]}<=RESPONSE_QUEUE_DEPTH);
assign o_start_ready=raw_start_ready&&((DEFERRED_COMMAND_ENABLE==0)||deferred_fits);
assign o_config_error=raw_config_error||((DEFERRED_COMMAND_ENABLE!=0)&&rstn&&i_start&&!unused_u_receive_o_active&&!deferred_fits);
generate if(DEFERRED_COMMAND_ENABLE==0)begin:gen_ordinary_receive
 assign o_cmd_release_taken=0;assign o_cmd_pending=0;assign cmd_error=0;
 wire [40:0] unused_cmd_input={i_cmd_release_valid,i_cmd_releases};
tl_receive_credit #(.WIDTH(WIDTH),.DEPTH(RX_DEPTH),.COUNT_WIDTH(RX_COUNT_WIDTH)) u_receive( // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_epoch_store_taken(unused_epoch_store_taken),
 .o_rx_demands(unused_rx_demands),.o_epoch_context(unused_epoch_context),.o_epoch_validation(unused_epoch_validation),.o_epoch_publish(unused_epoch_publish),.o_epoch_stored_releases(unused_epoch_stored_releases),.o_epoch_context_releases(unused_epoch_context_releases),.o_epoch_owner_error(unused_epoch_owner_error),
 .i_clk(i_clk),.i_rstn(rstn),.i_start(i_start),.i_shared(i_shared),.i_auth(i_auth),.i_capacities(i_capacities), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_start_ready(raw_start_ready),.o_start_taken(o_start_taken),.o_config_error(raw_config_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_valid(dl_rx&&rx_credit_allowed&&!r_rx_reject&&!rx_reserved),.i_flit(rx_data[511:0]),.i_msg(rx_data[513:512]),.o_taken(storage_rx_taken),.o_fatal(receive_fatal), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_read_ready(i_read_ready),.o_read_valid(o_read_valid),.o_read_flit(o_read_flit),.o_read_msg(o_read_msg), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_read_classes(o_read_classes),.o_read_releases(o_read_releases),.o_retired(retired), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_fc_send(fc_taken),.o_fc_valid(fc_valid),.o_fc_taken(publish_taken),.o_fc_flit(fc_flit),.o_fc_msg(fc_msg), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_done(o_done),.o_pending(o_pending),.o_count(o_rx_count),.o_release_taken(release_taken), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_required_words(unused_u_receive_o_required_words), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_allowed(unused_u_receive_o_allowed), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rejected(unused_u_receive_o_rejected), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_fc_complete(unused_u_receive_o_fc_complete), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_active(unused_u_receive_o_active)); // 角色中立prepared传输连线，沿用唯一真实所有者。

end else begin:gen_deferred_receive
tl_receive_credit_deferred #(.WIDTH(WIDTH),.DEPTH(RX_DEPTH),.COUNT_WIDTH(RX_COUNT_WIDTH),.CMD_COUNT_WIDTH(WIDTH+1)) u_receive(
 .i_cmd_release_valid(i_cmd_release_valid),.i_cmd_releases(i_cmd_releases),.o_cmd_release_taken(o_cmd_release_taken),.o_cmd_pending(o_cmd_pending),.o_cmd_error(cmd_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_epoch_store_taken(unused_epoch_store_taken),
 .o_rx_demands(unused_rx_demands),.o_epoch_context(unused_epoch_context),.o_epoch_validation(unused_epoch_validation),.o_epoch_publish(unused_epoch_publish),.o_epoch_stored_releases(unused_epoch_stored_releases),.o_epoch_context_releases(unused_epoch_context_releases),.o_epoch_owner_error(unused_epoch_owner_error),
 .i_clk(i_clk),.i_rstn(rstn),.i_start(i_start&&deferred_fits),.i_shared(i_shared),.i_auth(i_auth),.i_capacities(i_capacities), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_start_ready(raw_start_ready),.o_start_taken(o_start_taken),.o_config_error(raw_config_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_valid(dl_rx&&rx_credit_allowed&&!r_rx_reject&&!rx_reserved),.i_flit(rx_data[511:0]),.i_msg(rx_data[513:512]),.o_taken(storage_rx_taken),.o_fatal(receive_fatal), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_read_ready(i_read_ready),.o_read_valid(o_read_valid),.o_read_flit(o_read_flit),.o_read_msg(o_read_msg), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_read_classes(o_read_classes),.o_read_releases(o_read_releases),.o_retired(retired), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_fc_send(fc_taken),.o_fc_valid(fc_valid),.o_fc_taken(publish_taken),.o_fc_flit(fc_flit),.o_fc_msg(fc_msg), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_done(o_done),.o_pending(o_pending),.o_count(o_rx_count),.o_release_taken(release_taken), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_required_words(unused_u_receive_o_required_words), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_allowed(unused_u_receive_o_allowed), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rejected(unused_u_receive_o_rejected), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_fc_complete(unused_u_receive_o_fc_complete), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_active(unused_u_receive_o_active)); // 角色中立prepared传输连线，沿用唯一真实所有者。

end
if((SHARED_DATA_PROGRESS_ENABLE!=0&&SHARED_DATA_PROGRESS_ENABLE!=1)||(SHARED_DATA_PROGRESS_ENABLE!=0&&DEFERRED_COMMAND_ENABLE==0)||(DEFERRED_COMMAND_ENABLE!=0&&DEFERRED_COMMAND_ENABLE!=1)||REQUEST_QUEUE_DEPTH<1||RESPONSE_QUEUE_DEPTH<1)begin:gen_bad_deferred
 tl_dl_prepared_port_deferred_parameters_invalid Invalid_Inst();
end endgenerate
// 520位仅为研发记录；每slot新group及外部CRC状态保持基准的明确边界。
wire unused_snapshot_begin_ready;
wire unused_snapshot_valid;
wire [519:0] unused_snapshot_data;
wire [8:0] unused_snapshot_sequence;
wire [7:0] unused_snapshot_index;
wire [7:0] unused_snapshot_count;
wire unused_snapshot_last;
wire [7:0] unused_snapshot_epoch;
wire [7:0] unused_snapshot_attempt;
wire unused_snapshot_active;
wire unused_snapshot_done;
wire unused_snapshot_error;
dl_replay_data_port #(.C_DEPTH(DL_DEPTH),.C_DATA_WIDTH(520)) u_dl( // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_clk(i_clk),.i_rstn(rstn),.i_link_reset(1'b0), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_rx_event_valid(rx_event),.i_rx_event_discard(1'b0),.i_rx_crc_ok(i_link_crc_ok), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_rx_header(i_link_data[543:520]),.i_rx_replay_limit(i_rx_replay_limit),.i_rx_data(i_link_data[519:0]), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_flit_request(reserve),.i_new_group(1'b1),.i_payload(tx_valid&&tx_allowed&&!r_rx_reject&&!rx_reject),.i_data({6'd0,tx_msg,tx_flit}), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_accept(dl_issue_accept),.o_payload_accept(dl_accept),.o_issue_replay(dl_issue_replay), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_out_valid(dl_valid),.o_out_payload(dl_payload),.o_out_replay(dl_replay),.o_out_sequence(dl_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_out_header(dl_header),.o_out_data(dl_data),.o_rx_payload_accept(dl_rx),.o_rx_data(rx_data), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tag_error(tag_error),.o_issue_metadata_error(metadata_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_unacked_count(o_unacked_count),.o_ctl_scheduled_count(o_scheduled_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_ready(unused_u_dl_o_issue_ready), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_payload(unused_u_dl_o_issue_payload), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_first(unused_u_dl_o_issue_first), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_sequence(unused_u_dl_o_issue_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_out_first(unused_u_dl_o_out_first), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_out_stored_sequence(unused_u_dl_o_out_stored_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ack_accept(unused_u_dl_o_ack_accept), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ack_count(unused_u_dl_o_ack_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_request_accept(unused_u_dl_o_request_accept), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_command_reject(unused_u_dl_o_command_reject), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_resident_count(unused_u_dl_o_resident_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_last_sequence(unused_u_dl_o_ctl_last_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_last_ack(unused_u_dl_o_ctl_last_ack), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_ignore_count(unused_u_dl_o_ctl_ignore_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_head_pointer(unused_u_dl_o_ctl_head_pointer), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_write_pointer(unused_u_dl_o_ctl_write_pointer), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_scheduled_sequence(unused_u_dl_o_ctl_scheduled_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_scheduled_pointer(unused_u_dl_o_ctl_scheduled_pointer), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_ctl_first_pending(unused_u_dl_o_ctl_first_pending), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_ingress_event(unused_u_dl_o_rx_ingress_event), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_accept(unused_u_dl_o_rx_accept), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_sequence_valid(unused_u_dl_o_rx_sequence_valid), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_sequence(unused_u_dl_o_rx_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_replay_request(unused_u_dl_o_rx_replay_request), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_command_valid(unused_u_dl_o_rx_command_valid), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_command_request(unused_u_dl_o_rx_command_request), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_command_target(unused_u_dl_o_rx_command_target), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_crc_error(unused_u_dl_o_rx_crc_error), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_zero_sequence(unused_u_dl_o_rx_zero_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_zero_command(unused_u_dl_o_rx_zero_command), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_backpressure_drop(unused_u_dl_o_rx_backpressure_drop), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_unexpected(unused_u_dl_o_rx_unexpected), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_ambiguous_drop(unused_u_dl_o_rx_ambiguous_drop), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_replay_drop(unused_u_dl_o_rx_replay_drop), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_last_sequence(unused_u_dl_o_rx_last_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_bad_crc_count(unused_u_dl_o_rx_bad_crc_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_unexpected_count(unused_u_dl_o_rx_unexpected_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_ambiguous(unused_u_dl_o_rx_ambiguous), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_rx_replay(unused_u_dl_o_rx_replay), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_header(unused_u_dl_o_issue_header), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_issue_header_valid(unused_u_dl_o_issue_header_valid), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_explicit_count(unused_u_dl_o_tx_explicit_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_request_count(unused_u_dl_o_tx_request_count), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_request_sequence(unused_u_dl_o_tx_request_sequence), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .o_tx_group_used(unused_u_dl_o_tx_group_used), // 角色中立prepared传输连线，沿用唯一真实所有者。
 .i_snapshot_begin(1'b0),.i_snapshot_owner_error(1'b0),.i_snapshot_scope(1'b0),.i_snapshot_epoch(8'd0),.i_current_epoch(8'd0),.i_snapshot_attempt(8'd0),.i_snapshot_fenced(2'd0),.i_snapshot_fence_epoch(8'd0),.i_snapshot_fence_attempt(8'd0),.i_snapshot_ready(1'b0),
 .o_snapshot_begin_ready(unused_snapshot_begin_ready),
 .o_snapshot_valid(unused_snapshot_valid),
 .o_snapshot_data(unused_snapshot_data),
 .o_snapshot_sequence(unused_snapshot_sequence),
 .o_snapshot_index(unused_snapshot_index),
 .o_snapshot_count(unused_snapshot_count),
 .o_snapshot_last(unused_snapshot_last),
 .o_snapshot_epoch(unused_snapshot_epoch),
 .o_snapshot_attempt(unused_snapshot_attempt),
 .o_snapshot_active(unused_snapshot_active),
 .o_snapshot_done(unused_snapshot_done),
 .o_snapshot_error(unused_snapshot_error),
 .o_rx_effective_sequence(unused_u_dl_o_rx_effective_sequence)); // 角色中立prepared传输连线，沿用唯一真实所有者。

wire buffer_error,atomicity_error; // 角色中立prepared传输连线，沿用唯一真实所有者。
assign buffer_error=(dl_issue_accept&&(holding_valid||inflight))||(dl_valid&&(!inflight||holding_valid)); // 角色中立prepared传输连线，沿用唯一真实所有者。
assign atomicity_error=(dl_accept!=tx_taken)|| // 角色中立prepared传输连线，沿用唯一真实所有者。
 (((|header_taken)||(|data_taken)||fc_taken)&&!dl_accept)|| // 角色中立prepared传输连线，沿用唯一真实所有者。
 (dl_issue_replay&&tx_taken)||(dl_rx&&(!port_rx_taken||!storage_rx_taken))|| // 角色中立prepared传输连线，沿用唯一真实所有者。
 ((retired||((DEFERRED_COMMAND_ENABLE!=0)&&o_cmd_release_taken))!=release_taken)||(fc_taken!=publish_taken); // 角色中立prepared传输连线，沿用唯一真实所有者。
assign o_error=rstn&&(cmd_error||((DEFERRED_COMMAND_ENABLE!=0)&&unused_epoch_owner_error)||r_rx_reject||rx_reject||credit_fatal||receive_fatal||o_config_error||init_conflict|| // 角色中立prepared传输连线，沿用唯一真实所有者。
 (tx_valid&&credit_tx_error)||(|header_error)||(|input_error)||(|prepare_error)|| // 角色中立prepared传输连线，沿用唯一真实所有者。
 (|prepare_shortfall)||(|capacity_shortfall)||tag_error||metadata_error||buffer_error||atomicity_error|| // 角色中立prepared传输连线，沿用唯一真实所有者。
 (dl_rx&&(|rx_data[519:514]))); // 角色中立prepared传输连线，沿用唯一真实所有者。
endmodule // 角色中立prepared传输连线，沿用唯一真实所有者。
`default_nettype wire // 角色中立prepared传输连线，沿用唯一真实所有者。

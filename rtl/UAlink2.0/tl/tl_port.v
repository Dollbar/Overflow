`timescale 1ns/1ps
`default_nettype none
// 单个Logical Port的明文TL终止边界。发送队列、对端信用、接收存储各只有一个owner。
module tl_port #(
 parameter integer WIDTH=8, HEADER_DEPTH=2, BANK_DEPTH=3, RX_DEPTH=40,
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:3,
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:3,
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:7,
 parameter integer PACKET_BOUNDARY_ENABLE=0
)(
 input wire i_clk,i_rstn,i_enable,i_link_reset,i_start,i_shared,
 input wire i_security_enable,i_compression_enable,
 input wire [20*WIDTH-1:0] i_capacities,
 input wire [1:0] i_source_valid,input wire [511:0] i_source_control,
 input wire [1:0] i_source_tags_valid,input wire [1023:0] i_source_tags,
 input wire [3:0] i_data_valid,input wire [511:0] i_data0,i_data1,
 output wire [1:0] o_source_ready,o_source_captured,o_data_ready,
 output wire [1:0] o_header_taken,
 output wire [3:0] o_data_accepted,
 output wire o_tx_valid,output wire [511:0] o_tx_flit,output wire [1:0] o_tx_msg,output wire o_tx_packet_sop,o_tx_packet_eop,input wire i_tx_ready,
 input wire i_rx_valid,input wire [511:0] i_rx_flit,input wire [1:0] i_rx_msg,
 output wire o_rx_ready,o_rx_taken,
 input wire i_read_ready,output wire o_read_valid,output wire [511:0] o_read_flit,
 output wire [1:0] o_read_msg,output wire [5:0] o_read_classes,output wire [79:0] o_read_releases,
 output wire o_start_ready,o_start_taken,o_local_done,o_peer_done,o_peer_shared,
 output wire [20*(WIDTH+1)-1:0] o_capacity,o_available,o_pending,
 output wire [89:0] o_tx_validation_state,
 output wire o_idle,o_feature_error,o_error,o_implemented,
 // 旧scaffold入口没有类型/VC/Pool语义，继续明确fail-closed。
 input wire i_valid,input wire [511:0] i_data,input wire [127:0] i_meta,
 output wire o_ready,o_valid,output wire [511:0] o_data,output wire [127:0] o_meta
);
wire blocked=i_security_enable||i_compression_enable;
wire rstn=i_rstn&&!i_link_reset&&i_enable&&!blocked;
assign o_feature_error=i_rstn&&i_enable&&blocked;
assign o_implemented=1'b1;

wire tx_valid,tx_allowed,tx_taken,tx_error;
wire [511:0] tx_flit,fc_flit;wire [1:0] tx_msg,fc_msg;
wire [6:0] tx_pending;wire [89:0] tx_state;
wire [1:0] source_ready,source_captured,data_ready,prepare_error,prepare_shortfall,header_error,capacity_shortfall,input_error;
wire [3:0] data_accepted;
wire [2*HEADER_COUNT_WIDTH-1:0] header_count;
wire [2*(DATA_COUNT_WIDTH+1)-1:0] data_count;
wire [1:0] unused_source_tags_taken,unused_group_queued,unused_partition_taken,unused_tags_taken,unused_prepare_busy;
wire [3:0] unused_data_taken;wire fc_valid,publish_taken,unused_fc_taken;
tl_tx_prepared #(.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),.HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH),.STOP_ENABLE(0),.POISON_ENABLE(0),.PACKET_BOUNDARY_ENABLE(PACKET_BOUNDARY_ENABLE)) u_tx(
 .i_clk(i_clk),.i_rstn(rstn),.i_taken(tx_taken),.i_pending(tx_pending),.i_auth(1'b0),.i_done(o_peer_done),.i_shared(o_peer_shared),.i_available(o_available),.i_capacity(o_capacity),.i_request_budget(tx_state[9:7]),.i_response_budget(tx_state[6:3]),
 .i_source_valid(i_source_valid&{2{rstn}}),.i_source_control(i_source_control),.i_source_tags_valid(i_source_tags_valid),.i_source_tags(i_source_tags),.i_data_valid(i_data_valid&{4{rstn}}),.i_data0(i_data0),.i_data1(i_data1),
 .i_fc_valid(fc_valid),.i_fc_flit(fc_flit),.i_fc_msg(fc_msg),.i_stop_request(1'b0),.i_poison0(2'b00),.i_poison1(2'b00),
 .o_source_ready(source_ready),.o_source_captured(source_captured),.o_source_tags_taken(unused_source_tags_taken),.o_group_queued(unused_group_queued),.o_partition_taken(unused_partition_taken),.o_prepare_error(prepare_error),.o_prepare_shortfall(prepare_shortfall),
 .o_valid(tx_valid),.o_flit(tx_flit),.o_msg(tx_msg),.o_packet_sop(o_tx_packet_sop),.o_packet_eop(o_tx_packet_eop),.o_header_taken(o_header_taken),.o_tags_taken(unused_tags_taken),.o_data_taken(unused_data_taken),.o_fc_taken(unused_fc_taken),.o_header_error(header_error),.o_capacity_shortfall(capacity_shortfall),
 .o_data_accepted(data_accepted),.o_data_ready(data_ready),.o_input_error(input_error),.o_header_count(header_count),.o_data_count(data_count),.o_prepare_busy(unused_prepare_busy));
assign o_source_ready=source_ready&{2{rstn}};assign o_source_captured=source_captured&{2{rstn}};
assign o_data_ready=data_ready&{2{rstn}};assign o_data_accepted=data_accepted&{4{rstn}};
assign o_tx_valid=rstn&&tx_valid&&tx_allowed;assign o_tx_flit=o_tx_valid?tx_flit:512'd0;assign o_tx_msg=o_tx_valid?tx_msg:2'd0;

wire credit_allowed,credit_taken,credit_rejected,credit_fatal,init_repeat,init_conflict,admission_wait,credit_shortfall;
wire storage_allowed,storage_taken;
wire [2:0] unused_rx_lower,unused_rx_upper,unused_tx_lower,unused_tx_upper,unused_requests_available;
wire [3:0] unused_responses_available;wire [79:0] unused_demands;wire [6:0] unused_rx_pending;
wire [72:0] unused_rx_be,unused_tx_be;wire [437:0] unused_metadata;wire [119:0] unused_requirements;
wire unused_pair_open,unused_pair_poison;wire [159:0] unused_rx_grants;wire [1:0] unused_rx_init;wire unused_rx_runtime;
tl_credit_admitted_port #(.WIDTH(WIDTH)) u_credit(
 .i_clk(i_clk),.i_rstn(rstn),.i_receive(rstn&&i_rx_valid&&storage_allowed),.i_send(rstn&&tx_valid&&i_tx_ready),.i_auth(1'b0),.i_rx_flit(i_rx_flit),.i_rx_msg(i_rx_msg),.i_tx_flit(tx_flit),.i_tx_msg(tx_msg),
 .o_rx_allowed(credit_allowed),.o_rx_taken(credit_taken),.o_rx_rejected(credit_rejected),.o_tx_allowed(tx_allowed),.o_tx_taken(tx_taken),.o_tx_error(tx_error),.o_rx_lower(unused_rx_lower),.o_rx_upper(unused_rx_upper),.o_tx_lower(unused_tx_lower),.o_tx_upper(unused_tx_upper),.o_demands(unused_demands),
 .o_rx_pending(unused_rx_pending),.o_rx_be(unused_rx_be),.o_requests_available(unused_requests_available),.o_responses_available(unused_responses_available),.o_fatal(credit_fatal),.o_pair_open(unused_pair_open),.o_pair_poison(unused_pair_poison),.o_capacity(o_capacity),.o_available(o_available),.o_done(o_peer_done),.o_shared(o_peer_shared),.o_init_repeat(init_repeat),.o_init_conflict(init_conflict),
 .o_tx_pending(tx_pending),.o_tx_be(unused_tx_be),.o_metadata(unused_metadata),.o_tx_validation_state(tx_state),.o_admission_wait(admission_wait),.o_capacity_shortfall(credit_shortfall),.o_requirements(unused_requirements),.o_rx_grants(unused_rx_grants),.o_rx_init(unused_rx_init),.o_rx_runtime(unused_rx_runtime));

wire storage_rejected,storage_fatal,config_error,fc_complete,unused_receive_active,retired,release_taken;
wire [RX_COUNT_WIDTH-1:0] rx_count;wire [WIDTH+5:0] unused_required_words;wire [79:0] unused_rx_demands;
wire [663:0] unused_epoch_context;wire [89:0] unused_epoch_validation;wire [48+20*(WIDTH+1):0] unused_epoch_publish;
wire [20*(RX_COUNT_WIDTH+4)-1:0] unused_epoch_stored_releases;wire [139:0] unused_epoch_context_releases;
wire epoch_owner_error,unused_epoch_store_taken;
tl_receive_credit #(.WIDTH(WIDTH),.DEPTH(RX_DEPTH),.COUNT_WIDTH(RX_COUNT_WIDTH)) u_receive(
 .i_clk(i_clk),.i_rstn(rstn),.i_start(i_start&&rstn),.i_shared(i_shared),.i_auth(1'b0),.i_capacities(i_capacities),.o_start_ready(o_start_ready),.o_start_taken(o_start_taken),.o_config_error(config_error),.o_required_words(unused_required_words),
 .i_valid(rstn&&i_rx_valid&&credit_allowed),.i_flit(i_rx_flit),.i_msg(i_rx_msg),.o_allowed(storage_allowed),.o_taken(storage_taken),.o_rejected(storage_rejected),.o_fatal(storage_fatal),
 .i_read_ready(i_read_ready&&rstn),.o_read_valid(o_read_valid),.o_read_flit(o_read_flit),.o_read_msg(o_read_msg),.o_read_classes(o_read_classes),.o_read_releases(o_read_releases),.o_retired(retired),
 .i_fc_send(unused_fc_taken&&tx_taken),.o_fc_valid(fc_valid),.o_fc_taken(publish_taken),.o_fc_complete(fc_complete),.o_fc_flit(fc_flit),.o_fc_msg(fc_msg),.o_active(unused_receive_active),.o_done(o_local_done),.o_pending(o_pending),.o_count(rx_count),.o_release_taken(release_taken),
 .o_rx_demands(unused_rx_demands),.o_epoch_context(unused_epoch_context),.o_epoch_validation(unused_epoch_validation),.o_epoch_publish(unused_epoch_publish),.o_epoch_stored_releases(unused_epoch_stored_releases),.o_epoch_context_releases(unused_epoch_context_releases),.o_epoch_owner_error(epoch_owner_error),.o_epoch_store_taken(unused_epoch_store_taken));
assign o_rx_ready=rstn&&credit_allowed&&storage_allowed;
assign o_rx_taken=rstn&&credit_taken&&storage_taken;
assign o_tx_validation_state=tx_state;

wire owner_error=tx_error||credit_fatal||init_repeat||init_conflict||storage_fatal||config_error||epoch_owner_error||(|prepare_error)||(|prepare_shortfall)||(|header_error)||(|capacity_shortfall)||(|input_error)||(credit_taken!=storage_taken)||(retired!=release_taken)||(publish_taken!=(unused_fc_taken&&tx_taken));
assign o_error=o_feature_error||owner_error||(i_rstn&&i_enable&&i_valid);
assign o_idle=!rstn||(!tx_valid&&(header_count==0)&&(data_count==0)&&(tx_pending==0)&&(rx_count==0)&&(o_pending==0)&&!fc_valid&&!admission_wait&&!credit_shortfall);
assign o_ready=1'b0;assign o_valid=1'b0;assign o_data=512'd0;assign o_meta=128'd0;
wire [639:0] unused_legacy={i_data,i_meta};
wire unused_observation=credit_rejected||storage_rejected||fc_complete||unused_legacy[0];
endmodule
`default_nettype wire

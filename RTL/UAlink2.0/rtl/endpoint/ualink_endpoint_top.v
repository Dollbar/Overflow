`default_nettype none
module ualink_endpoint_top #(
 parameter integer TRANSACTION_MODE=0, // 0保留prepared接口；1连接真实单64B Read事务核
 parameter integer WIDTH=8, HEADER_DEPTH=2, BANK_DEPTH=3, RX_DEPTH=40, DL_DEPTH=3,
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:(HEADER_DEPTH<8)?3:(HEADER_DEPTH<16)?4:(HEADER_DEPTH<32)?5:(HEADER_DEPTH<64)?6:(HEADER_DEPTH<128)?7:(HEADER_DEPTH<256)?8:(HEADER_DEPTH<512)?9:(HEADER_DEPTH<1024)?10:(HEADER_DEPTH<2048)?11:(HEADER_DEPTH<4096)?12:(HEADER_DEPTH<8192)?13:(HEADER_DEPTH<16384)?14:(HEADER_DEPTH<32768)?15:16,
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:(BANK_DEPTH<8)?3:(BANK_DEPTH<16)?4:(BANK_DEPTH<32)?5:(BANK_DEPTH<64)?6:(BANK_DEPTH<128)?7:(BANK_DEPTH<256)?8:(BANK_DEPTH<512)?9:(BANK_DEPTH<1024)?10:(BANK_DEPTH<2048)?11:(BANK_DEPTH<4096)?12:(BANK_DEPTH<8192)?13:(BANK_DEPTH<16384)?14:(BANK_DEPTH<32768)?15:16,
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:(RX_DEPTH<128)?7:(RX_DEPTH<256)?8:(RX_DEPTH<512)?9:(RX_DEPTH<1024)?10:(RX_DEPTH<2048)?11:(RX_DEPTH<4096)?12:(RX_DEPTH<8192)?13:(RX_DEPTH<16384)?14:(RX_DEPTH<32768)?15:16
)(
 input wire i_clk,i_rstn,i_link_reset,i_start,i_auth,i_shared,
 input wire [20*WIDTH-1:0] i_capacities,
 input wire [1:0] i_source_valid,i_source_tags_valid,
 input wire [511:0] i_source_control,
 input wire [1023:0] i_source_tags,
 input wire [3:0] i_data_valid,
 input wire [511:0] i_data0,i_data1,
 output wire [1:0] o_source_captured,o_source_ready,o_data_ready,
 output wire [3:0] o_data_accepted,
 input wire i_read_ready,
 output wire o_read_valid,
 output wire [511:0] o_read_flit,
 output wire [1:0] o_read_msg,
 output wire [5:0] o_read_classes,
 output wire [79:0] o_read_releases,
 output wire o_link_valid,
 output wire [543:0] o_link_data,
 input wire i_link_ready,
 output wire o_link_payload,o_link_replay,
 output wire [8:0] o_link_sequence,
 input wire i_link_valid,
 input wire [543:0] i_link_data,
 input wire i_link_crc_ok,
 input wire [7:0] i_rx_replay_limit,
 output wire o_link_ready,
 output wire o_start_ready,o_start_taken,o_config_error,o_done,o_peer_done,o_peer_shared,o_error,
 output wire [20*(WIDTH+1)-1:0] o_capacity,o_available,o_pending,
 output wire [6:0] o_tx_pending,
 output wire [89:0] o_tx_validation_state,
 output wire [2*HEADER_COUNT_WIDTH-1:0] o_header_count,
 output wire [2*(DATA_COUNT_WIDTH+1)-1:0] o_data_count,
 output wire [RX_COUNT_WIDTH-1:0] o_rx_count,
 output wire [7:0] o_unacked_count,o_scheduled_count,
 input wire [1:0] i_port,input wire [9:0] i_local_id,
 input wire i_request_valid,output wire o_request_ready,input wire [1:0] i_request_port,
 input wire [10:0] i_request_tag,input wire [56:0] i_request_address,input wire [9:0] i_request_dst,
 input wire [5:0] i_request_length,input wire [7:0] i_request_attr,
 output wire o_complete_valid,input wire i_complete_ready,output wire [1:0] o_complete_port,
 output wire [10:0] o_complete_tag,output wire [3:0] o_complete_status,output wire [511:0] o_complete_data,output wire o_complete_data_valid,
 output wire o_mem_valid,input wire i_mem_ready,output wire [1:0] o_mem_slot,output wire [56:0] o_mem_address,
 output wire [5:0] o_mem_length,output wire [7:0] o_mem_attr,output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata,
 input wire i_mem_result_valid,output wire o_mem_result_ready,input wire [1:0] i_mem_result_slot,
 input wire [511:0] i_mem_result_data,input wire [3:0] i_mem_result_status,
 output wire [7:0] o_outstanding_count,o_completer_count,output wire o_transaction_error,
 output wire [127:0] o_pending_features
);
// 全部状态只在i_clk上升沿复位；这是研发全层清除，不是协议LinkDown恢复。
wire rstn;
assign rstn=i_rstn&&!i_link_reset;
wire tx_valid,tx_taken,tx_allowed,credit_fatal,receive_fatal,credit_tx_error;
wire [511:0] tx_flit,fc_flit;
wire [1:0] tx_msg,fc_msg,header_taken,header_error,input_error,prepare_error,prepare_shortfall,capacity_shortfall;
wire [3:0] data_taken;
wire fc_valid,fc_taken,publish_taken,port_rx_taken,storage_rx_taken,retired,release_taken;
wire init_conflict;
wire dl_issue_accept,dl_accept,dl_issue_replay,dl_valid,dl_payload,dl_replay,dl_rx,tag_error,metadata_error;
wire [8:0] dl_sequence;
wire [23:0] dl_header;
wire [519:0] dl_data,rx_data;
wire reserve,rx_event;
reg holding_valid,inflight;
reg [543:0] holding_data;
reg holding_payload,holding_replay;
reg [8:0] holding_sequence;

// 参数在展开时选择源所有者；旧prepared回归仍使用原接口。
wire [1:0] selected_source_valid,selected_tags_valid;
wire [511:0] selected_source_control,selected_data0,selected_data1;
wire [1023:0] selected_tags;
wire [3:0] selected_data_valid;
wire selected_read_ready,transaction_error;
generate if(TRANSACTION_MODE!=0)begin:transactions
 wire core_error;
 endpoint_transaction_core u_core(
 .i_clk(i_clk),.i_rstn(rstn&&!i_auth&&(i_port==2'd0)),.i_port(i_port),.i_local_id(i_local_id),
 .i_request_valid(i_request_valid),.o_request_ready(o_request_ready),.i_request_port(i_request_port),.i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid),
 .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length),.o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata),
 .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot),.i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status),
 .o_source_valid(selected_source_valid),.o_source_control(selected_source_control),.i_source_captured(o_source_captured),.i_request_header_taken(header_taken[0]),
 .o_data_valid(selected_data_valid),.o_data0(selected_data0),.o_data1(selected_data1),.i_data_accepted(o_data_accepted),
 .i_read_valid(o_read_valid),.o_read_ready(selected_read_ready),.i_read_flit(o_read_flit),.i_read_msg(o_read_msg),.i_read_classes(o_read_classes),.i_read_releases(o_read_releases),
 .o_outstanding_count(o_outstanding_count),.o_completer_count(o_completer_count),.o_error(core_error));
 assign selected_tags_valid=2'b11;assign selected_tags=1024'd0;
 assign transaction_error=rstn&&(core_error||i_auth||(i_port!=2'd0)); // 当前真实事务仅单物理端口、Auth关闭
end else begin:prepared
 assign selected_source_valid=i_source_valid;assign selected_source_control=i_source_control;
 assign selected_tags_valid=i_source_tags_valid;assign selected_tags=i_source_tags;
 assign selected_data_valid=i_data_valid;assign selected_data0=i_data0;assign selected_data1=i_data1;
 assign selected_read_ready=i_read_ready;assign transaction_error=1'b0;
 assign o_request_ready=1'b0;assign o_complete_valid=1'b0;assign o_complete_port=2'd0;
 assign o_complete_tag=11'd0;assign o_complete_status=4'd0;assign o_complete_data=512'd0;assign o_complete_data_valid=1'b0;
 assign o_mem_valid=1'b0;assign o_mem_slot=2'd0;assign o_mem_address=57'd0;assign o_mem_length=6'd0;
 assign o_mem_attr=8'd0;assign o_mem_asi=2'd0;assign o_mem_metadata=8'd0;assign o_mem_result_ready=1'b0;
 assign o_outstanding_count=8'd0;assign o_completer_count=8'd0;
end endgenerate
assign o_transaction_error=transaction_error;

// 固定一拍DL返回必须先预约真实holding容量；不在消费同拍旁路预约。
assign reserve=rstn&&!holding_valid&&!inflight;
assign o_link_valid=rstn&&holding_valid;
assign o_link_data=o_link_valid?holding_data:544'd0;
assign o_link_payload=o_link_valid&&holding_payload;
assign o_link_replay=o_link_valid&&holding_replay;
assign o_link_sequence=o_link_valid?holding_sequence:9'd0;
assign o_link_ready=rstn;
assign rx_event=i_link_valid&&o_link_ready;
always @(posedge i_clk) begin
 if(!rstn)begin
  holding_valid<=1'b0;inflight<=1'b0;holding_data<=544'd0;
  holding_payload<=1'b0;holding_replay<=1'b0;holding_sequence<=9'd0;
 end else begin
  if(o_link_valid&&i_link_ready)holding_valid<=1'b0;
  if(dl_issue_accept)inflight<=1'b1;
  if(dl_valid)begin
   inflight<=1'b0;holding_valid<=1'b1;
   holding_data<={dl_header,dl_data};holding_payload<=dl_payload;
   holding_replay<=dl_replay;holding_sequence<=dl_sequence;
  end
 end
end

tl_tx_prepared #(.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),
 .HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH)) u_tx(
 .i_clk(i_clk),.i_rstn(rstn),.i_taken(tx_taken),.i_pending(o_tx_pending),.i_auth(i_auth),
 .i_done(o_peer_done),.i_shared(o_peer_shared),.i_available(o_available),.i_capacity(o_capacity),
 .i_request_budget(o_tx_validation_state[9:7]),.i_response_budget(o_tx_validation_state[6:3]),
 .i_source_valid(selected_source_valid),.i_source_control(selected_source_control),
 .i_source_tags_valid(selected_tags_valid),.i_source_tags(selected_tags),
 .o_source_captured(o_source_captured),.o_source_ready(o_source_ready),
 .o_prepare_error(prepare_error),.o_prepare_shortfall(prepare_shortfall),
 .i_data_valid(selected_data_valid),.i_data0(selected_data0),.i_data1(selected_data1),
 .i_fc_valid(fc_valid),.i_fc_flit(fc_flit),.i_fc_msg(fc_msg),
 .o_valid(tx_valid),.o_flit(tx_flit),.o_msg(tx_msg),.o_header_taken(header_taken),
 .o_data_taken(data_taken),.o_fc_taken(fc_taken),.o_header_error(header_error),
 .o_capacity_shortfall(capacity_shortfall),.o_data_accepted(o_data_accepted),
 .o_data_ready(o_data_ready),.o_input_error(input_error),
 .o_header_count(o_header_count),.o_data_count(o_data_count));

// 重放不消费TL源；只有DL首次payload接纳才原子扣除TL信用。
tl_credit_admitted_port #(.WIDTH(WIDTH)) u_credit(
 .i_clk(i_clk),.i_rstn(rstn),.i_receive(dl_rx),.i_send(dl_accept),.i_auth(i_auth),
 .i_rx_flit(rx_data[511:0]),.i_rx_msg(rx_data[513:512]),.i_tx_flit(tx_flit),.i_tx_msg(tx_msg),
 .o_rx_taken(port_rx_taken),.o_tx_allowed(tx_allowed),.o_tx_taken(tx_taken),.o_tx_error(credit_tx_error),
 .o_fatal(credit_fatal),.o_done(o_peer_done),.o_shared(o_peer_shared),.o_init_conflict(init_conflict),
 .o_capacity(o_capacity),.o_available(o_available),.o_tx_pending(o_tx_pending),
 .o_tx_validation_state(o_tx_validation_state));

tl_receive_credit #(.WIDTH(WIDTH),.DEPTH(RX_DEPTH),.COUNT_WIDTH(RX_COUNT_WIDTH)) u_receive(
 .i_clk(i_clk),.i_rstn(rstn),.i_start(i_start),.i_shared(i_shared),.i_auth(i_auth),.i_capacities(i_capacities),
 .o_start_ready(o_start_ready),.o_start_taken(o_start_taken),.o_config_error(o_config_error),
 .i_valid(dl_rx),.i_flit(rx_data[511:0]),.i_msg(rx_data[513:512]),.o_taken(storage_rx_taken),.o_fatal(receive_fatal),
 .i_read_ready(selected_read_ready),.o_read_valid(o_read_valid),.o_read_flit(o_read_flit),.o_read_msg(o_read_msg),
 .o_read_classes(o_read_classes),.o_read_releases(o_read_releases),.o_retired(retired),
 .i_fc_send(fc_taken),.o_fc_valid(fc_valid),.o_fc_taken(publish_taken),.o_fc_flit(fc_flit),.o_fc_msg(fc_msg),
 .o_done(o_done),.o_pending(o_pending),.o_count(o_rx_count),.o_release_taken(release_taken));

// 520位仅为研发记录；每slot新group及外部CRC状态保持基准的明确边界。
dl_replay_data_port #(.C_DEPTH(DL_DEPTH),.C_DATA_WIDTH(520)) u_dl(
 .i_clk(i_clk),.i_rstn(rstn),.i_link_reset(1'b0),
 .i_rx_event_valid(rx_event),.i_rx_event_discard(1'b0),.i_rx_crc_ok(i_link_crc_ok),
 .i_rx_header(i_link_data[543:520]),.i_rx_replay_limit(i_rx_replay_limit),.i_rx_data(i_link_data[519:0]),
 .i_flit_request(reserve),.i_new_group(1'b1),.i_payload(tx_valid&&tx_allowed),.i_data({6'd0,tx_msg,tx_flit}),
 .o_issue_accept(dl_issue_accept),.o_payload_accept(dl_accept),.o_issue_replay(dl_issue_replay),
 .o_out_valid(dl_valid),.o_out_payload(dl_payload),.o_out_replay(dl_replay),.o_out_sequence(dl_sequence),
 .o_out_header(dl_header),.o_out_data(dl_data),.o_rx_payload_accept(dl_rx),.o_rx_data(rx_data),
 .o_tag_error(tag_error),.o_issue_metadata_error(metadata_error),
 .o_ctl_unacked_count(o_unacked_count),.o_ctl_scheduled_count(o_scheduled_count));

wire buffer_error,atomicity_error;
assign buffer_error=(dl_issue_accept&&(holding_valid||inflight))||(dl_valid&&(!inflight||holding_valid));
assign atomicity_error=(dl_accept!=tx_taken)||
 (((|header_taken)||(|data_taken)||fc_taken)&&!dl_accept)||
 (dl_issue_replay&&tx_taken)||(dl_rx&&(!port_rx_taken||!storage_rx_taken))||
 (retired!=release_taken)||(fc_taken!=publish_taken);
assign o_error=rstn&&(transaction_error||credit_fatal||receive_fatal||o_config_error||init_conflict||
 (tx_valid&&credit_tx_error)||(|header_error)||(|input_error)||(|prepare_error)||
 (|prepare_shortfall)||(|capacity_shortfall)||tag_error||metadata_error||buffer_error||atomicity_error||
 (dl_rx&&(|rx_data[519:514])));
// 完整架构预留服务仅报告未实现状态，不旁路接纳任何事务。
ualink_endpoint_scaffold u_scaffold(.i_clk(i_clk),.i_rstn(rstn),.o_pending_features(o_pending_features));
endmodule
`default_nettype wire

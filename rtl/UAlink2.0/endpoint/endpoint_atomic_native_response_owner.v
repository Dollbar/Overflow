`timescale 1ns/1ps
`default_nettype none

// 一个Logical Port的Atomic完成到native TL Response所有者。响应先进入既有typed
// ordering owner，再由本模块保存到Header/Data全部被同一tl_port接纳，最后才退休排序token。
module endpoint_atomic_native_response_owner #(
 parameter integer C_TOKEN_WIDTH=16,
 parameter integer C_ORDER_ENTRIES=2,
 parameter integer C_ORDER_ENTRY_WIDTH=1
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_order_profile_valid,input wire[1:0] i_order_mode,input wire[7:0] i_order_epoch,
 input wire i_response_valid,output wire o_response_ready,input wire[C_TOKEN_WIDTH-1:0] i_response_token,
 input wire i_atomic_return,input wire[1:0] i_port,input wire[10:0] i_tag,input wire[9:0] i_src,input wire[9:0] i_dst,input wire[1:0] i_vc,input wire i_pool,input wire[3:0] i_status,input wire[511:0] i_data,input wire i_data_valid,
 output wire o_source_valid,output wire[255:0] o_source_control,input wire i_source_captured,
 output wire[1:0] o_data_valid,output wire[255:0] o_data0,output wire[255:0] o_data1,input wire[1:0] i_data_accepted,
 output wire o_busy,output wire o_quiescent,output wire o_error
);
localparam[2:0] S_EMPTY=3'd0,S_WAIT_ISSUE=3'd1,S_SEND=3'd2,S_RETIRE=3'd3,S_FAILED=3'd4;
localparam[1:0] STREAM_READ_RSP=2'd1,STREAM_WRITE_RSP=2'd2;
localparam CONFIG_LEGAL=(C_TOKEN_WIDTH>=2)&&(C_TOKEN_WIDTH<=30)&&(C_ORDER_ENTRIES>=1)&&(C_ORDER_ENTRIES<=16)&&(C_ORDER_ENTRY_WIDTH>=1)&&(C_ORDER_ENTRY_WIDTH<=4)&&((1<<C_ORDER_ENTRY_WIDTH)>=C_ORDER_ENTRIES);
reg[2:0] state_q;reg atomic_return_q,data_valid_q,pool_q,source_done_q;reg[1:0] vc_q;reg[1:0] data_sent_q;
reg[10:0] tag_q;reg[9:0] src_q,dst_q;reg[3:0] status_q;reg[511:0] data_q;
reg[7:0] order_epoch_q;reg[15:0] order_token_q;reg protocol_error_q;
wire status_legal=(i_status==4'd0)||(i_status==4'd2)||(i_status==4'd3)||(i_status==4'd6)||(i_status==4'd8);
wire input_legal=i_order_profile_valid&&status_legal&&(i_atomic_return==i_data_valid);
wire order_admit_ready,order_issue_valid,order_retire_ready,order_error,order_busy,order_quiescent;
wire[7:0] order_issue_epoch;wire[15:0] order_issue_token;wire[1:0] unused_mode,unused_stream,unused_vc,unused_port;wire[9:0] unused_src,unused_dst;wire[48:0] unused_region;wire[127:0] unused_descriptor;wire[15:0] unused_occupancy;
wire unused_protocol,unused_token_error,unused_duplicate,unused_affinity,unused_epoch_error;
wire response_fire=i_response_valid&&o_response_ready;
wire issue_fire=order_issue_valid&&(state_q==S_WAIT_ISSUE);
wire source_fire=o_source_valid&&i_source_captured;
wire source_complete=source_done_q||source_fire;
wire[2:0] data_total={1'b0,data_sent_q}+{1'b0,i_data_accepted};
wire send_complete=source_complete&&(!data_valid_q||(data_total==3'd2));
wire retire_fire=(state_q==S_RETIRE)&&order_retire_ready;
wire read_encode_valid,read_encode_error;wire[255:0] read_control;
wire[63:0] write_field={4'd2,vc_q,tag_q,pool_q,2'd0,2'd0,status_q,1'b0,1'b0,dst_q,src_q,2'd0,14'd0};

assign o_response_ready=i_rstn&&i_enable&&CONFIG_LEGAL&&!protocol_error_q&&!order_error&&(state_q==S_EMPTY)&&input_legal&&order_admit_ready;
assign o_source_valid=i_rstn&&!protocol_error_q&&!order_error&&(state_q==S_SEND)&&!source_done_q;
assign o_source_control=o_source_valid?(atomic_return_q?read_control:{192'd0,write_field}):256'd0;
assign o_data_valid=(i_rstn&&!protocol_error_q&&!order_error&&(state_q==S_SEND)&&data_valid_q)?(2'd2-data_sent_q):2'b00;
assign o_data0=(data_sent_q==0)?data_q[255:0]:data_q[511:256];assign o_data1=(data_sent_q==0)?data_q[511:256]:256'd0;
assign o_busy=i_rstn&&(state_q!=S_EMPTY);assign o_quiescent=i_rstn&&CONFIG_LEGAL&&!protocol_error_q&&!order_error&&(state_q==S_EMPTY)&&order_quiescent;
assign o_error=i_rstn&&(!CONFIG_LEGAL||protocol_error_q||order_error||read_encode_error);

endpoint_response_encode #(.FULL_READ_ENABLE(1),.NATIVE_FIELDS_ENABLE(1)) u_read_encode(
 .i_valid((state_q==S_SEND)&&atomic_return_q),.i_tag(tag_q),.i_src(dst_q),.i_dst(src_q),.i_status(status_q),.i_num_beats(2'd0),.i_offset(2'd0),.i_last(1'b1),.i_vc(vc_q),.i_pool(pool_q),.o_valid(read_encode_valid),.o_error(read_encode_error),.o_control(read_control));

endpoint_ordering_typed_owner #(.C_ENTRIES(C_ORDER_ENTRIES),.C_ENTRY_WIDTH(C_ORDER_ENTRY_WIDTH),.C_TOKEN_WIDTH(16),.C_EPOCH_WIDTH(8)) u_order(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable&&!protocol_error_q),.i_epoch(i_order_epoch),
 .i_admit_valid(i_response_valid&&(state_q==S_EMPTY)&&input_legal),.o_admit_ready(order_admit_ready),.i_profile_valid(i_order_profile_valid),.i_affinity_valid(1'b1),
 .i_mode(i_order_mode),.i_stream(i_atomic_return?STREAM_READ_RSP:STREAM_WRITE_RSP),.i_vc(i_vc),.i_src(i_dst),.i_dst(i_src),.i_region(49'd0),.i_port(i_port),.i_descriptor({{(128-C_TOKEN_WIDTH){1'b0}},i_response_token}),
 .o_issue_valid(order_issue_valid),.i_issue_ready(state_q==S_WAIT_ISSUE),.o_issue_epoch(order_issue_epoch),.o_issue_token(order_issue_token),.o_issue_mode(unused_mode),.o_issue_stream(unused_stream),.o_issue_vc(unused_vc),.o_issue_src(unused_src),.o_issue_dst(unused_dst),.o_issue_region(unused_region),.o_issue_port(unused_port),.o_issue_descriptor(unused_descriptor),
 .i_retire_valid(state_q==S_RETIRE),.o_retire_ready(order_retire_ready),.i_retire_epoch(order_epoch_q),.i_retire_token(order_token_q),
 .o_busy(order_busy),.o_quiescent(order_quiescent),.o_occupancy(unused_occupancy),.o_protocol_error(unused_protocol),.o_token_error(unused_token_error),.o_duplicate_error(unused_duplicate),.o_affinity_error(unused_affinity),.o_epoch_error(unused_epoch_error),.o_error(order_error));

always @(posedge i_clk)begin
 if(!i_rstn)begin state_q<=S_EMPTY;atomic_return_q<=0;data_valid_q<=0;pool_q<=0;source_done_q<=0;vc_q<=0;data_sent_q<=0;tag_q<=0;src_q<=0;dst_q<=0;status_q<=0;data_q<=0;order_epoch_q<=0;order_token_q<=0;protocol_error_q<=0;end
 else begin
  if(!CONFIG_LEGAL)begin state_q<=S_FAILED;protocol_error_q<=1;end
  if(i_response_valid&&(state_q==S_EMPTY)&&!input_legal)protocol_error_q<=1;
  if((i_source_captured&&!o_source_valid)||(i_data_accepted>o_data_valid))protocol_error_q<=1;
  case(state_q)
   S_EMPTY:if(response_fire)begin atomic_return_q<=i_atomic_return;data_valid_q<=i_data_valid;pool_q<=i_pool;vc_q<=i_vc;tag_q<=i_tag;src_q<=i_src;dst_q<=i_dst;status_q<=i_status;data_q<=i_data;source_done_q<=0;data_sent_q<=0;state_q<=S_WAIT_ISSUE;end
   S_WAIT_ISSUE:if(issue_fire)begin order_epoch_q<=order_issue_epoch;order_token_q<=order_issue_token;state_q<=S_SEND;end
   S_SEND:begin source_done_q<=source_complete;if(i_data_accepted<=o_data_valid)data_sent_q<=data_total[1:0];if(send_complete)state_q<=S_RETIRE;end
   S_RETIRE:if(retire_fire)state_q<=S_EMPTY;
   default:state_q<=S_FAILED;
  endcase
 end
end
wire unused_observation=read_encode_valid^order_busy^unused_mode[0]^unused_stream[0]^unused_vc[0]^unused_port[0]^unused_src[0]^unused_dst[0]^unused_region[0]^unused_descriptor[0]^unused_occupancy[0]^unused_protocol^unused_token_error^unused_duplicate^unused_affinity^unused_epoch_error;
endmodule
`default_nettype wire

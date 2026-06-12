`timescale 1ns/1ps
`default_nettype none
// 单Station速率重配事务所有者。rate_code是外部profile已经判定合法的opaque typed code；
// 本模块不解释物理频率，也不改变固定512-bit数据宽度或公共时钟。
module endpoint_station_rate_reconfiguration_owner #(
 parameter integer C_RATE_WIDTH=16,
 parameter integer C_ACK_TIMEOUT_CYCLES=64
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_request_valid,output wire o_request_ready,input wire[3:0] i_active_mask,
 input wire[4*C_RATE_WIDTH-1:0] i_requested_rate_code,input wire[3:0] i_requested_rate_legal,
 input wire i_station_quiescent,input wire[3:0] i_port_link_reset,
 output wire o_request_accept,output wire o_request_reject,
 output wire o_drain_request,output wire o_admission_enable,
 output wire[3:0] o_notify_valid,input wire[3:0] i_notify_ready,
 output wire[4*C_RATE_WIDTH-1:0] o_notify_rate_code,
 input wire[3:0] i_notify_ack_valid,output wire[3:0] o_notify_ack_ready,
 input wire[3:0] i_notify_ack_success,input wire[4*C_RATE_WIDTH-1:0] i_notify_ack_rate_code,
 output wire[3:0] o_apply_valid,input wire[3:0] i_apply_ready,
 output wire[4*C_RATE_WIDTH-1:0] o_apply_rate_code,
 input wire[3:0] i_apply_accept,input wire[3:0] i_apply_error,
 output reg[3:0] o_rate_configured,output reg[4*C_RATE_WIDTH-1:0] o_active_rate_code,
 output wire o_busy,output wire o_quiescent,output reg o_timeout_error,
 output reg o_protocol_error,output wire o_config_error,output wire o_error
);
localparam [2:0] ST_IDLE=3'd0,ST_DRAIN=3'd1,ST_NOTIFY=3'd2,ST_ACK=3'd3,
 ST_APPLY=3'd4,ST_APPLY_RESULT=3'd5,ST_FAULT=3'd6;
localparam [31:0] C_TIMEOUT_LIMIT=C_ACK_TIMEOUT_CYCLES-1;
localparam C_CONFIG_LEGAL=(C_RATE_WIDTH>=1)&&(C_RATE_WIDTH<=64)&&
 (C_ACK_TIMEOUT_CYCLES>=1)&&(C_ACK_TIMEOUT_CYCLES<=2147483647);
reg[2:0] state_q;
reg[3:0] target_mask_q,notify_sent_q,ack_seen_q,apply_seen_q;
reg[4*C_RATE_WIDTH-1:0] target_rate_q;
reg[31:0] timeout_q;
wire active_mask_legal=(i_active_mask==4'b0001)||(i_active_mask==4'b0101)||(i_active_mask==4'b1111);
wire request_rate_legal=active_mask_legal&&((i_requested_rate_legal&i_active_mask)==i_active_mask);
wire request_fire=i_request_valid&&o_request_ready;
wire[3:0] notify_fire=o_notify_valid&i_notify_ready;
wire[3:0] notify_seen_next=notify_sent_q|notify_fire;
wire notify_complete=((notify_seen_next&target_mask_q)==target_mask_q);
wire[3:0] ack_fire=i_notify_ack_valid&o_notify_ack_ready;
wire[3:0] ack_seen_next=ack_seen_q|ack_fire;
wire ack_complete=((ack_seen_next&target_mask_q)==target_mask_q);
reg ack_code_bad;
integer ack_index;
always @* begin
 ack_code_bad=1'b0;
 for(ack_index=0;ack_index<4;ack_index=ack_index+1)
  if(ack_fire[ack_index]&&(i_notify_ack_rate_code[ack_index*C_RATE_WIDTH+:C_RATE_WIDTH]!=target_rate_q[ack_index*C_RATE_WIDTH+:C_RATE_WIDTH]))ack_code_bad=1'b1;
end
// ack_bad_success单独表达，避免把opaque code进行任何数值解释。
wire ack_bad_success=|(ack_fire&~i_notify_ack_success);
wire all_apply_ready=&(i_apply_ready|~target_mask_q);
wire[3:0] apply_fire=o_apply_valid&i_apply_ready;
wire apply_complete=(&(apply_fire|~target_mask_q));
wire[3:0] apply_seen_next=apply_seen_q|(i_apply_accept&target_mask_q);
wire apply_result_complete=((apply_seen_next&target_mask_q)==target_mask_q);
wire timeout_state=(state_q==ST_NOTIFY)||(state_q==ST_ACK)||(state_q==ST_APPLY)||(state_q==ST_APPLY_RESULT);
wire timeout_hit=timeout_state&&(timeout_q>=C_TIMEOUT_LIMIT);
wire target_reset=|(i_port_link_reset&target_mask_q);
wire mask_changed=(state_q!=ST_IDLE)&&(i_active_mask!=target_mask_q);

assign o_config_error=!C_CONFIG_LEGAL;
assign o_request_ready=C_CONFIG_LEGAL&&i_rstn&&i_enable&&(state_q==ST_IDLE);
assign o_request_accept=request_fire&&request_rate_legal;
assign o_request_reject=C_CONFIG_LEGAL&&i_rstn&&i_enable&&i_request_valid&&
 ((state_q!=ST_IDLE)||(request_fire&&!request_rate_legal));
assign o_busy=C_CONFIG_LEGAL&&i_rstn&&(state_q!=ST_IDLE);
assign o_quiescent=C_CONFIG_LEGAL&&i_rstn&&(state_q==ST_IDLE);
assign o_drain_request=o_busy;
assign o_admission_enable=C_CONFIG_LEGAL&&i_rstn&&i_enable&&(state_q==ST_IDLE);
assign o_notify_valid=(C_CONFIG_LEGAL&&i_rstn&&i_enable&&(state_q==ST_NOTIFY))?(target_mask_q&~notify_sent_q):4'b0;
assign o_notify_rate_code=(C_CONFIG_LEGAL&&i_rstn)?target_rate_q:{(4*C_RATE_WIDTH){1'b0}};
assign o_notify_ack_ready=(C_CONFIG_LEGAL&&i_rstn&&i_enable&&(state_q==ST_ACK))?(target_mask_q&~ack_seen_q):4'b0;
// 必须等所有目标pacer均ready才同时拉高valid，禁止部分端口提前改rate。
assign o_apply_valid=(C_CONFIG_LEGAL&&i_rstn&&i_enable&&(state_q==ST_APPLY)&&all_apply_ready)?target_mask_q:4'b0;
assign o_apply_rate_code=(C_CONFIG_LEGAL&&i_rstn)?target_rate_q:{(4*C_RATE_WIDTH){1'b0}};
assign o_error=o_config_error||o_timeout_error||o_protocol_error;

integer port_index;
always @(posedge i_clk)begin
 if(!i_rstn)begin
  state_q<=ST_IDLE;target_mask_q<=4'b0;notify_sent_q<=4'b0;ack_seen_q<=4'b0;apply_seen_q<=4'b0;
  target_rate_q<={(4*C_RATE_WIDTH){1'b0}};timeout_q<=32'd0;o_rate_configured<=4'b0;
  o_active_rate_code<={(4*C_RATE_WIDTH){1'b0}};o_timeout_error<=1'b0;o_protocol_error<=1'b0;
 end else begin
  // Port link reset只清对应已提交rate；其他Logical Port和其他Station不受影响。
  for(port_index=0;port_index<4;port_index=port_index+1)if(i_port_link_reset[port_index])begin
   o_rate_configured[port_index]<=1'b0;
   o_active_rate_code[port_index*C_RATE_WIDTH+:C_RATE_WIDTH]<={C_RATE_WIDTH{1'b0}};
  end
  if(o_request_reject)o_protocol_error<=1'b1;
  if(mask_changed)o_protocol_error<=1'b1;
  if((state_q!=ST_IDLE)&&target_reset)begin
   state_q<=ST_IDLE;target_mask_q<=4'b0;notify_sent_q<=4'b0;ack_seen_q<=4'b0;apply_seen_q<=4'b0;timeout_q<=32'd0;
   o_protocol_error<=1'b1;
  end else if(mask_changed)begin
   state_q<=ST_FAULT;
  end else case(state_q)
   ST_IDLE:begin
    timeout_q<=32'd0;
    if(request_fire)begin
     if(request_rate_legal)begin
      target_mask_q<=i_active_mask;target_rate_q<=i_requested_rate_code;
      notify_sent_q<=4'b0;ack_seen_q<=4'b0;apply_seen_q<=4'b0;state_q<=ST_DRAIN;
     end else o_protocol_error<=1'b1;
    end
   end
   ST_DRAIN:if(i_station_quiescent)begin state_q<=ST_NOTIFY;timeout_q<=32'd0;end
   ST_NOTIFY:begin
    notify_sent_q<=notify_seen_next;
    if(timeout_hit)begin state_q<=ST_FAULT;o_timeout_error<=1'b1;end
    else if(notify_complete)begin state_q<=ST_ACK;timeout_q<=32'd0;end
    else timeout_q<=timeout_q+32'd1;
   end
   ST_ACK:begin
    ack_seen_q<=ack_seen_next;
    if(ack_bad_success||ack_code_bad)begin state_q<=ST_FAULT;o_protocol_error<=1'b1;end
    else if(timeout_hit)begin state_q<=ST_FAULT;o_timeout_error<=1'b1;end
    else if(ack_complete)begin state_q<=ST_APPLY;timeout_q<=32'd0;end
    else timeout_q<=timeout_q+32'd1;
   end
   ST_APPLY:begin
    if(timeout_hit)begin state_q<=ST_FAULT;o_timeout_error<=1'b1;end
    else if(apply_complete)begin state_q<=ST_APPLY_RESULT;apply_seen_q<=4'b0;timeout_q<=32'd0;end
    else timeout_q<=timeout_q+32'd1;
   end
   ST_APPLY_RESULT:begin
    apply_seen_q<=apply_seen_next;
    if(|(i_apply_error&target_mask_q))begin state_q<=ST_FAULT;o_protocol_error<=1'b1;end
    else if(timeout_hit)begin state_q<=ST_FAULT;o_timeout_error<=1'b1;end
    else if(apply_result_complete)begin
     for(port_index=0;port_index<4;port_index=port_index+1)if(target_mask_q[port_index])begin
      o_rate_configured[port_index]<=1'b1;
      o_active_rate_code[port_index*C_RATE_WIDTH+:C_RATE_WIDTH]<=target_rate_q[port_index*C_RATE_WIDTH+:C_RATE_WIDTH];
     end
     state_q<=ST_IDLE;target_mask_q<=4'b0;apply_seen_q<=4'b0;timeout_q<=32'd0;
    end else timeout_q<=timeout_q+32'd1;
   end
   default:begin state_q<=ST_FAULT;end
  endcase
 end
end
endmodule

`default_nettype wire

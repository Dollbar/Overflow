`timescale 1ns/1ps
`default_nettype none

// 一个Logical Port的明文Atomic TL退休适配器。普通记录保持原600-bit内容直通；
// Atomic只接受tl_sequence已证明的Control/Data、Data/BE次序，并复用唯一typed owner。
// profile位图由平台按OpType提供，本模块不猜具体原子操作语义。
module endpoint_atomic_tl_port_owner #(
 parameter integer C_TOKEN_WIDTH=16,
 parameter integer C_PORT_ID=0
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_request_admission_enable,
 input wire[31:0] i_profile_valid,input wire[31:0] i_two_operand,
 input wire i_tl_valid,output reg o_tl_ready,input wire[511:0] i_tl_flit,input wire[1:0] i_tl_msg,input wire[5:0] i_tl_classes,input wire[79:0] i_tl_releases,
 output reg o_normal_valid,input wire i_normal_ready,output reg[511:0] o_normal_flit,output reg[1:0] o_normal_msg,output reg[5:0] o_normal_classes,output reg[79:0] o_normal_releases,
 output wire o_backend_valid,input wire i_backend_ready,output wire[C_TOKEN_WIDTH-1:0] o_backend_token,output wire[127:0] o_backend_header,output wire[1:0] o_backend_port,output wire[511:0] o_backend_operands,output wire[255:0] o_backend_byte_enable,output wire o_backend_atomic_return,output wire[4:0] o_backend_op_type,output wire[1:0] o_backend_op_size,
 input wire i_backend_result_valid,output wire o_backend_result_ready,input wire[C_TOKEN_WIDTH-1:0] i_backend_result_token,input wire[3:0] i_backend_result_status,input wire[511:0] i_backend_result_data,
 output wire o_response_valid,input wire i_response_ready,output wire[C_TOKEN_WIDTH-1:0] o_response_token,output wire o_response_atomic_return,output wire[1:0] o_response_port,output wire[10:0] o_response_tag,output wire[9:0] o_response_src,output wire[9:0] o_response_dst,output wire[1:0] o_response_vc,output wire o_response_pool,output wire[3:0] o_response_status,output wire[511:0] o_response_data,output wire o_response_data_valid,
 output wire o_busy,output wire o_quiescent,output wire o_request_reject_pulse,output wire o_error
);
localparam CONFIG_LEGAL=(C_TOKEN_WIDTH>=2)&&(C_TOKEN_WIDTH<=30)&&(C_PORT_ID>=0)&&(C_PORT_ID<4);
localparam[2:0] P_IDLE=3'd0,P_FIRST_DATA=3'd1,P_TAIL=3'd2,P_BE=3'd3,P_FAILED=3'd4;
reg[2:0] parser_q;reg[255:0] upper_q;reg parser_error_q,discard_q;
reg[1:0] response_vc_q;reg response_pool_q;
wire[2:0] lower_class=i_tl_classes[2:0],upper_class=i_tl_classes[5:3];
wire[4:0] live_op_type={i_tl_flit[94],i_tl_flit[101:98]};
wire atomic_signature=(lower_class==3'd0)&&((i_tl_flit[123:118]==6'h30)||(i_tl_flit[123:118]==6'h32));
wire header_layout=atomic_signature&&(upper_class==3'd1)&&(i_tl_msg==2'd0)&&(i_tl_flit[255:128]==128'd0);
wire tail_layout=(lower_class==3'd1)&&(upper_class==3'd2)&&(i_tl_msg==2'd0);
wire owner_request_ready,owner_payload_ready,owner_busy,owner_quiescent,owner_error;
wire owner_protocol_error,owner_token_error,owner_duplicate_error,owner_token_exhausted;
wire owner_request_valid=i_rstn&&i_enable&&i_request_admission_enable&&!parser_error_q&&(parser_q==P_IDLE)&&i_tl_valid&&header_layout&&owner_quiescent;
wire owner_payload_valid=i_rstn&&i_enable&&!discard_q&&!parser_error_q&&((parser_q==P_FIRST_DATA)||((parser_q==P_TAIL)&&i_tl_valid&&tail_layout)||(parser_q==P_BE));
wire[1:0] owner_payload_class=(parser_q==P_BE)?2'd1:2'd0;
wire[255:0] owner_payload_data=((parser_q==P_FIRST_DATA)||(parser_q==P_BE))?upper_q:i_tl_flit[255:0];
wire malformed_event=i_rstn&&i_enable&&!parser_error_q&&i_tl_valid&&(((parser_q==P_IDLE)&&atomic_signature&&!header_layout)||((parser_q==P_TAIL)&&!tail_layout));

always @* begin
 o_tl_ready=1'b0;o_normal_valid=1'b0;o_normal_flit=512'd0;o_normal_msg=2'd0;o_normal_classes=6'd0;o_normal_releases=80'd0;
 if(i_rstn&&i_enable&&CONFIG_LEGAL&&!parser_error_q&&!owner_error)begin
  case(parser_q)
   P_IDLE:begin
    if(atomic_signature)begin
     if(!header_layout)o_tl_ready=1'b1;
     else if(!i_request_admission_enable)o_tl_ready=1'b1;
     else if(owner_quiescent)o_tl_ready=owner_request_ready;
    end else begin
     o_normal_valid=i_tl_valid;o_tl_ready=i_normal_ready;
     o_normal_flit=i_tl_flit;o_normal_msg=i_tl_msg;o_normal_classes=i_tl_classes;o_normal_releases=i_tl_releases;
    end
   end
   P_TAIL:if(tail_layout)o_tl_ready=discard_q?1'b1:owner_payload_ready;else o_tl_ready=i_tl_valid;
   default:begin end
  endcase
 end
end

always @(posedge i_clk)begin
 if(!i_rstn)begin parser_q<=P_IDLE;upper_q<=0;parser_error_q<=0;discard_q<=1'b0;response_vc_q<=0;response_pool_q<=0;end
 else begin
  if(!CONFIG_LEGAL)begin parser_q<=P_FAILED;parser_error_q<=1;end
  else if(malformed_event&&o_tl_ready)begin parser_q<=P_FAILED;parser_error_q<=1;end
  else case(parser_q)
   P_IDLE:if(i_tl_valid&&o_tl_ready&&header_layout)begin upper_q<=i_tl_flit[511:256];discard_q<=!i_request_admission_enable;response_vc_q<=i_tl_flit[117:116];response_pool_q<=i_tl_flit[102];parser_q<=P_FIRST_DATA;end
   P_FIRST_DATA:if(discard_q||(owner_payload_valid&&owner_payload_ready))parser_q<=P_TAIL;
   P_TAIL:if(i_tl_valid&&tail_layout&&(discard_q||owner_payload_ready))begin upper_q<=i_tl_flit[511:256];parser_q<=P_BE;end
   P_BE:if(discard_q||(owner_payload_valid&&owner_payload_ready))begin parser_q<=P_IDLE;discard_q<=1'b0;end
   default:parser_q<=P_FAILED;
  endcase
 end
end

endpoint_atomic_typed_owner #(.C_TOKEN_WIDTH(C_TOKEN_WIDTH)) u_owner(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable&&!parser_error_q),
 .i_request_valid(owner_request_valid),.o_request_ready(owner_request_ready),.i_request_header(i_tl_flit[127:0]),.i_request_port(C_PORT_ID[1:0]),.i_profile_valid(i_profile_valid[live_op_type]),.i_two_operand(i_two_operand[live_op_type]),
 .i_payload_valid(owner_payload_valid),.o_payload_ready(owner_payload_ready),.i_payload_class(owner_payload_class),.i_payload_data(owner_payload_data),
 .o_backend_valid(o_backend_valid),.i_backend_ready(i_backend_ready),.o_backend_token(o_backend_token),.o_backend_header(o_backend_header),.o_backend_port(o_backend_port),.o_backend_operands(o_backend_operands),.o_backend_byte_enable(o_backend_byte_enable),.o_backend_atomic_return(o_backend_atomic_return),.o_backend_op_type(o_backend_op_type),.o_backend_op_size(o_backend_op_size),
 .i_backend_result_valid(i_backend_result_valid),.o_backend_result_ready(o_backend_result_ready),.i_backend_result_token(i_backend_result_token),.i_backend_result_status(i_backend_result_status),.i_backend_result_data(i_backend_result_data),
 .o_completion_valid(o_response_valid),.i_completion_ready(i_response_ready),.o_completion_token(o_response_token),.o_completion_atomic_return(o_response_atomic_return),.o_completion_port(o_response_port),.o_completion_tag(o_response_tag),.o_completion_src(o_response_src),.o_completion_dst(o_response_dst),.o_completion_status(o_response_status),.o_completion_data(o_response_data),.o_completion_data_valid(o_response_data_valid),
 .o_busy(owner_busy),.o_quiescent(owner_quiescent),.o_protocol_error(owner_protocol_error),.o_token_error(owner_token_error),.o_duplicate_error(owner_duplicate_error),.o_token_exhausted(owner_token_exhausted),.o_error(owner_error));
assign o_busy=i_rstn&&((parser_q!=P_IDLE)||owner_busy);
assign o_request_reject_pulse=i_rstn&&i_enable&&!i_request_admission_enable&&(parser_q==P_IDLE)&&i_tl_valid&&header_layout&&o_tl_ready;
assign o_response_vc=o_response_valid?response_vc_q:2'd0;assign o_response_pool=o_response_valid&&response_pool_q;
assign o_quiescent=i_rstn&&CONFIG_LEGAL&&!parser_error_q&&!owner_error&&(parser_q==P_IDLE)&&owner_quiescent;
assign o_error=i_rstn&&(!CONFIG_LEGAL||parser_error_q||owner_error||owner_protocol_error||owner_token_error||owner_duplicate_error||owner_token_exhausted);
endmodule
`default_nettype wire

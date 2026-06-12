`timescale 1ns/1ps
`default_nettype none

// 普通明文AtomicR/AtomicNR的单事务typed所有者边界。
// 本模块保存真实Request、两个Operand half和一个ByteEnable half，直到平台后端接纳；
// 后端结果按唯一token关联，完成只在最终consumer握手时退休。OpType的具体运算及其
// 单/双操作数属性由Common 2.0明确留给实现，因此必须由i_profile_valid/i_two_operand
// 提供平台合同；没有合同的Atomic失败关闭，不能透明当作Write执行。
module endpoint_atomic_typed_owner #(
 parameter integer C_TOKEN_WIDTH=16
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_request_valid,output wire o_request_ready,input wire[127:0] i_request_header,input wire[1:0] i_request_port,input wire i_profile_valid,input wire i_two_operand,
 input wire i_payload_valid,output wire o_payload_ready,input wire[1:0] i_payload_class,input wire[255:0] i_payload_data,
 output wire o_backend_valid,input wire i_backend_ready,output wire[C_TOKEN_WIDTH-1:0] o_backend_token,output wire[127:0] o_backend_header,output wire[1:0] o_backend_port,output wire[511:0] o_backend_operands,output wire[255:0] o_backend_byte_enable,output wire o_backend_atomic_return,output wire[4:0] o_backend_op_type,output wire[1:0] o_backend_op_size,
 input wire i_backend_result_valid,output wire o_backend_result_ready,input wire[C_TOKEN_WIDTH-1:0] i_backend_result_token,input wire[3:0] i_backend_result_status,input wire[511:0] i_backend_result_data,
 output wire o_completion_valid,input wire i_completion_ready,output wire[C_TOKEN_WIDTH-1:0] o_completion_token,output wire o_completion_atomic_return,output wire[1:0] o_completion_port,output wire[10:0] o_completion_tag,output wire[9:0] o_completion_src,output wire[9:0] o_completion_dst,output wire[3:0] o_completion_status,output wire[511:0] o_completion_data,output wire o_completion_data_valid,
 output wire o_busy,output wire o_quiescent,output wire o_protocol_error,output wire o_token_error,output wire o_duplicate_error,output wire o_token_exhausted,output wire o_error
);
localparam CONFIG_LEGAL=(C_TOKEN_WIDTH>=2)&&(C_TOKEN_WIDTH<=30);
localparam[2:0] S_IDLE=0,S_OP0=1,S_OP1=2,S_BE=3,S_ISSUE=4,S_WAIT=5,S_COMPLETE=6;
reg[2:0] state_q;reg[127:0] header_q;reg[1:0] port_q;reg two_operand_q;
reg[511:0] operands_q;reg[255:0] be_q;reg[C_TOKEN_WIDTH-1:0] token_q,next_token_q;
reg[3:0] status_q;reg[511:0] result_q;reg protocol_error_q,token_error_q,duplicate_error_q,token_exhausted_q;
wire fatal_error=protocol_error_q||token_error_q||duplicate_error_q;
wire atomic_r=i_request_header[123:118]==6'h30;wire atomic_nr=i_request_header[123:118]==6'h32;
wire[8:0] request_bytes=({3'd0,i_request_header[93:88]}+9'd1)<<2;
wire[7:0] request_offset={i_request_header[30:25],2'b00};wire[8:0] request_end={1'b0,request_offset}+request_bytes;
wire[1:0] request_op_size=i_request_header[97:96];
wire single_geometry=(request_end<=9'd256)&&({3'b000,request_offset[5:0]}+request_bytes<=9'd64)&&
 ((request_op_size!=2'b01)||(i_request_header[88]&&!i_request_header[25]));
wire double_geometry=(i_request_header[93:88]==6'd15)&&(request_offset[4:0]==0);
wire request_legal=CONFIG_LEGAL&&i_profile_valid&&(atomic_r||atomic_nr)&&(i_request_header[127:124]==4'd1)&&!i_request_header[95]&&!i_request_header[4]&&(i_request_header[1:0]==0)&&(i_two_operand?double_geometry:single_geometry);
wire request_fire=i_request_valid&&o_request_ready;wire backend_fire=o_backend_valid&&i_backend_ready;wire completion_fire=o_completion_valid&&i_completion_ready;
wire status_legal=(i_backend_result_status==0)||(i_backend_result_status==2)||(i_backend_result_status==3)||(i_backend_result_status==6)||(i_backend_result_status==8);
reg be_legal;integer byte_index;reg[8:0] be_start,be_end;reg[3:0] element_mask;
always @* begin
 be_start={1'b0,{header_q[30:25],2'b00}};be_end=be_start+(two_operand_q?9'd32:(({3'd0,header_q[93:88]}+9'd1)<<2));
 case(header_q[97:96])2'b00:element_mask=4'h3;2'b01:element_mask=4'h7;2'b10:element_mask=4'h1;default:element_mask=4'h0;endcase
 be_legal=1'b1;
 for(byte_index=0;byte_index<256;byte_index=byte_index+1)begin
  if((byte_index[8:0]<be_start)||(byte_index[8:0]>=be_end))begin if(i_payload_data[byte_index])be_legal=1'b0;end
  else begin
   case(element_mask)
    4'h1:if(i_payload_data[byte_index]!=i_payload_data[{byte_index[7:1],1'b0}])be_legal=1'b0;
    4'h3:if(i_payload_data[byte_index]!=i_payload_data[{byte_index[7:2],2'b00}])be_legal=1'b0;
    4'h7:if(i_payload_data[byte_index]!=i_payload_data[{byte_index[7:3],3'b000}])be_legal=1'b0;
    default:begin end
   endcase
  end
 end
end
assign o_request_ready=i_rstn&&i_enable&&!fatal_error&&!token_exhausted_q&&(state_q==S_IDLE)&&request_legal;
assign o_payload_ready=i_rstn&&!fatal_error&&(((state_q==S_OP0)||(state_q==S_OP1))?(i_payload_class==0):((state_q==S_BE)&&(i_payload_class==1)&&be_legal));
assign o_backend_valid=i_rstn&&!fatal_error&&(state_q==S_ISSUE);assign o_backend_token=token_q;assign o_backend_header=o_backend_valid?header_q:0;assign o_backend_port=o_backend_valid?port_q:0;assign o_backend_operands=o_backend_valid?operands_q:0;assign o_backend_byte_enable=o_backend_valid?be_q:0;assign o_backend_atomic_return=o_backend_valid&&(header_q[123:118]==6'h30);assign o_backend_op_type={header_q[94],header_q[101:98]};assign o_backend_op_size=header_q[97:96];
assign o_backend_result_ready=i_rstn&&!fatal_error&&(state_q==S_WAIT);
assign o_completion_valid=i_rstn&&!fatal_error&&(state_q==S_COMPLETE);assign o_completion_token=token_q;assign o_completion_atomic_return=o_completion_valid&&(header_q[123:118]==6'h30);assign o_completion_port=o_completion_valid?port_q:0;assign o_completion_tag=o_completion_valid?header_q[113:103]:0;assign o_completion_src=o_completion_valid?header_q[24:15]:0;assign o_completion_dst=o_completion_valid?header_q[14:5]:0;assign o_completion_status=o_completion_valid?status_q:0;assign o_completion_data=(o_completion_valid&&header_q[123:118]==6'h30)?result_q:0;assign o_completion_data_valid=o_completion_valid&&(header_q[123:118]==6'h30);
assign o_busy=i_rstn&&(state_q!=S_IDLE);assign o_quiescent=i_rstn&&CONFIG_LEGAL&&!fatal_error&&(state_q==S_IDLE);assign o_protocol_error=protocol_error_q;assign o_token_error=token_error_q;assign o_duplicate_error=duplicate_error_q;assign o_token_exhausted=token_exhausted_q;assign o_error=i_rstn&&(!CONFIG_LEGAL||fatal_error);
always @(posedge i_clk)begin
 if(!i_rstn)begin state_q<=S_IDLE;header_q<=0;port_q<=0;two_operand_q<=0;operands_q<=0;be_q<=0;token_q<=0;next_token_q<={{(C_TOKEN_WIDTH-1){1'b0}},1'b1};status_q<=0;result_q<=0;protocol_error_q<=0;token_error_q<=0;duplicate_error_q<=0;token_exhausted_q<=0;end
 else begin
  if(i_request_valid&&(state_q!=S_IDLE||!request_legal||!i_enable||token_exhausted_q))protocol_error_q<=1;
  if(i_payload_valid&&!o_payload_ready)protocol_error_q<=1;
  if(i_backend_result_valid&&(state_q!=S_WAIT))duplicate_error_q<=1;
  if(state_q==S_WAIT&&i_backend_result_valid&&i_backend_result_token!=token_q)token_error_q<=1;
  case(state_q)
   S_IDLE:if(request_fire)begin header_q<=i_request_header;port_q<=i_request_port;two_operand_q<=i_two_operand;token_q<=next_token_q;if(next_token_q=={C_TOKEN_WIDTH{1'b1}})token_exhausted_q<=1;else next_token_q<=next_token_q+1'b1;state_q<=S_OP0;end
   S_OP0:if(i_payload_valid&&o_payload_ready)begin operands_q[255:0]<=i_payload_data;state_q<=S_OP1;end
   S_OP1:if(i_payload_valid&&o_payload_ready)begin operands_q[511:256]<=i_payload_data;state_q<=S_BE;end
   S_BE:if(i_payload_valid&&o_payload_ready)begin be_q<=i_payload_data;state_q<=S_ISSUE;end
   S_ISSUE:if(backend_fire)state_q<=S_WAIT;
   S_WAIT:if(i_backend_result_valid&&o_backend_result_ready&&(i_backend_result_token==token_q)&&status_legal&&((header_q[123:118]==6'h30)||(i_backend_result_data==0)))begin status_q<=i_backend_result_status;result_q<=i_backend_result_data;state_q<=S_COMPLETE;end else if(i_backend_result_valid&&o_backend_result_ready&&(!status_legal||((header_q[123:118]==6'h32)&&(i_backend_result_data!=0))))protocol_error_q<=1;
   S_COMPLETE:if(completion_fire)state_q<=S_IDLE;
   default:begin state_q<=S_IDLE;protocol_error_q<=1;end
  endcase
 end
end
endmodule
`default_nettype wire

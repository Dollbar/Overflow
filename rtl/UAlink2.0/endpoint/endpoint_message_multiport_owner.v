`timescale 1ns/1ps
`default_nettype none
// 已解码普通CMD42的多Logical-Port执行owner。每Port拥有独立handler和token序列；
// 全局backend token高两位保存回源Port，低位只由对应handler解释。
module endpoint_message_multiport_owner #(
 parameter integer C_PORTS=4,parameter integer C_TOKEN_WIDTH=16,
 parameter [3:0] C_ACTIVE_PORT_MASK=4'b1111,parameter integer C_RUNTIME_ACTIVE_ENABLE=0
)(
 input wire i_clk,input wire i_rstn,input wire[3:0] i_active_port_mask,input wire[C_PORTS-1:0] i_link_reset,input wire[9:0] i_local_id,
 input wire i_request_valid,output reg o_request_ready,input wire[127:0] i_request_header,
 input wire[1:0] i_request_port,input wire[2047:0] i_request_data,input wire[255:0] i_request_be,input wire i_response_pool,
 output reg o_backend_valid,input wire i_backend_ready,output reg[C_TOKEN_WIDTH-1:0] o_backend_token,
 output reg[127:0] o_backend_header,output reg[1:0] o_backend_port,output reg[2047:0] o_backend_data,output reg[255:0] o_backend_be,
 input wire i_result_valid,output reg o_result_ready,input wire[C_TOKEN_WIDTH-1:0] i_result_token,
 input wire i_result_is_read,input wire[1:0] i_result_num_beats,input wire[3:0] i_result_status,
 input wire[2047:0] i_result_data,input wire[3:0] i_result_poison,
 output wire o_source_valid,output wire[255:0] o_source_control,output wire[1:0] o_source_port,input wire i_source_captured,
 output wire[1:0] o_data_valid,output wire[511:0] o_data,output wire[1:0] o_data_poison,input wire[1:0] i_data_accepted,
 output wire o_busy,output wire o_error,output wire[7:0] o_reason
);
localparam integer C_LOCAL_TOKEN_WIDTH=C_TOKEN_WIDTH-2;
localparam [3:0] C_PORT_MASK_LIMIT=(C_PORTS==1)?4'b0001:(C_PORTS==2)?4'b0011:4'b1111;
localparam [1:0] C_LAST_PORT=(C_PORTS==1)?2'd0:(C_PORTS==2)?2'd1:2'd3;
localparam C_CONFIG_LEGAL=((C_PORTS==1)||(C_PORTS==2)||(C_PORTS==4))&&(C_TOKEN_WIDTH>=3)&&(C_TOKEN_WIDTH<=32)&&
 ((C_ACTIVE_PORT_MASK&~C_PORT_MASK_LIMIT)==0)&&(C_ACTIVE_PORT_MASK!=0)&&((C_RUNTIME_ACTIVE_ENABLE==0)||(C_RUNTIME_ACTIVE_ENABLE==1));
wire[3:0] effective_active_mask=(C_RUNTIME_ACTIVE_ENABLE!=0)?i_active_port_mask:C_ACTIVE_PORT_MASK;
wire active_mask_legal=((effective_active_mask&~C_PORT_MASK_LIMIT)==0)&&(effective_active_mask!=0);
wire active=C_CONFIG_LEGAL&&i_rstn&&!error_q;
wire request_port_range=({30'd0,i_request_port}<C_PORTS);
wire request_port_active=request_port_range&&active_mask_legal&&effective_active_mask[i_request_port];
wire[1:0] result_port=i_result_token[C_TOKEN_WIDTH-1-:2];
wire result_port_range=({30'd0,result_port}<C_PORTS)&&active_mask_legal&&effective_active_mask[result_port];
wire[C_LOCAL_TOKEN_WIDTH-1:0] result_local_token=i_result_token[C_LOCAL_TOKEN_WIDTH-1:0];
wire[3:0] handler_request_ready,handler_backend_valid,handler_result_ready,handler_source_valid,handler_busy,handler_error;
wire[C_PORTS-1:0] handler_backend_ready;
wire[4*C_LOCAL_TOKEN_WIDTH-1:0] handler_backend_token;
wire[4*128-1:0] handler_backend_header;
wire[4*2-1:0] handler_backend_port,handler_data_valid,handler_data_poison,handler_source_port;
wire[4*2048-1:0] handler_backend_data;
wire[4*256-1:0] handler_backend_be,handler_source_control;
wire[4*512-1:0] handler_data;
wire[4*8-1:0] handler_reason;
reg error_q;reg[7:0] reason_q;reg[1:0] backend_rr_q,response_rr_q,response_owner_q;
reg response_locked_q;reg[1:0] backend_select,response_select;reg backend_found,response_found;
reg[7:0] child_reason;reg child_reason_found;
integer backend_scan,backend_candidate,response_scan,response_candidate,reason_scan;

genvar port;
generate for(port=0;port<4;port=port+1)begin:gen_handler
 if(port<C_PORTS)begin:configured
 wire local_request_valid=active&&i_request_valid&&request_port_active&&(i_request_port==port);
 wire local_result_valid=active&&i_result_valid&&result_port_range&&(result_port==port);
 wire local_source_captured=active&&o_source_valid&&(response_select==port)&&i_source_captured;
 wire[1:0] local_data_accepted=(active&&response_found&&(response_select==port))?i_data_accepted:2'b0;
 endpoint_message_handler #(.PORTS(C_PORTS),.TOKEN_WIDTH(C_LOCAL_TOKEN_WIDTH),.LINK_RESET_ENABLE(1))u_handler(
  .i_clk(i_clk),.i_rstn(i_rstn&&!error_q),.i_link_reset(i_link_reset[port]),.i_local_id(i_local_id),
  .i_request_valid(local_request_valid),.o_request_ready(handler_request_ready[port]),.i_request_header(i_request_header),.i_request_port(i_request_port),
  .i_request_data(i_request_data),.i_request_be(i_request_be),.o_backend_valid(handler_backend_valid[port]),
  .i_backend_ready(handler_backend_ready[port]),.o_backend_token(handler_backend_token[port*C_LOCAL_TOKEN_WIDTH+:C_LOCAL_TOKEN_WIDTH]),
  .o_backend_header(handler_backend_header[port*128+:128]),.o_backend_port(handler_backend_port[port*2+:2]),
  .o_backend_data(handler_backend_data[port*2048+:2048]),.o_backend_be(handler_backend_be[port*256+:256]),
  .i_result_valid(local_result_valid),.o_result_ready(handler_result_ready[port]),.i_result_token(result_local_token),
  .i_result_is_read(i_result_is_read),.i_result_num_beats(i_result_num_beats),.i_result_status(i_result_status),
  .i_result_data(i_result_data),.i_result_poison(i_result_poison),.i_response_pool(i_response_pool),
  .o_source_valid(handler_source_valid[port]),.o_source_control(handler_source_control[port*256+:256]),
  .o_source_port(handler_source_port[port*2+:2]),.i_source_captured(local_source_captured),
  .o_data_valid(handler_data_valid[port*2+:2]),.o_data(handler_data[port*512+:512]),
  .o_data_poison(handler_data_poison[port*2+:2]),.i_data_accepted(local_data_accepted),
  .o_busy(handler_busy[port]),.o_error(handler_error[port]),.o_reason(handler_reason[port*8+:8]));
 end else begin:absent
  assign handler_request_ready[port]=1'b0;assign handler_backend_valid[port]=1'b0;assign handler_result_ready[port]=1'b0;
  assign handler_source_valid[port]=1'b0;assign handler_busy[port]=1'b0;assign handler_error[port]=1'b0;
  assign handler_backend_token[port*C_LOCAL_TOKEN_WIDTH+:C_LOCAL_TOKEN_WIDTH]={C_LOCAL_TOKEN_WIDTH{1'b0}};
  assign handler_backend_header[port*128+:128]=128'b0;assign handler_backend_port[port*2+:2]=2'b0;
  assign handler_backend_data[port*2048+:2048]=2048'b0;assign handler_backend_be[port*256+:256]=256'b0;
  assign handler_source_control[port*256+:256]=256'b0;assign handler_source_port[port*2+:2]=2'b0;
  assign handler_data_valid[port*2+:2]=2'b0;assign handler_data[port*512+:512]=512'b0;
  assign handler_data_poison[port*2+:2]=2'b0;assign handler_reason[port*8+:8]=8'b0;
 end
end endgenerate

// 独立backend命令逐次RR；选中handler在ready前保持自身字段稳定。
always @* begin
 backend_select=backend_rr_q;backend_found=1'b0;backend_candidate=0;
 for(backend_scan=0;backend_scan<C_PORTS;backend_scan=backend_scan+1)begin
  backend_candidate={30'd0,backend_rr_q}+backend_scan;if(backend_candidate>=C_PORTS)backend_candidate=backend_candidate-C_PORTS;
  if(!backend_found&&handler_backend_valid[backend_candidate])begin backend_select=backend_candidate[1:0];backend_found=1'b1;end
 end
 o_backend_valid=active&&backend_found;o_backend_token={C_TOKEN_WIDTH{1'b0}};o_backend_header=128'b0;o_backend_port=2'b0;o_backend_data=2048'b0;o_backend_be=256'b0;
 if(active&&backend_found)begin
  o_backend_token={{2{1'b0}},handler_backend_token[backend_select*C_LOCAL_TOKEN_WIDTH+:C_LOCAL_TOKEN_WIDTH]};
  o_backend_token[C_TOKEN_WIDTH-1-:2]=backend_select;
  o_backend_header=handler_backend_header[backend_select*128+:128];o_backend_port=handler_backend_port[backend_select*2+:2];
  o_backend_data=handler_backend_data[backend_select*2048+:2048];o_backend_be=handler_backend_be[backend_select*256+:256];
 end
end
generate for(port=0;port<C_PORTS;port=port+1)begin:gen_backend_ready
 assign handler_backend_ready[port]=active&&backend_found&&(backend_select==port)&&i_backend_ready;
end endgenerate

always @* begin
 o_request_ready=1'b0;if(active&&request_port_active)begin
  case(i_request_port)
   2'd0:o_request_ready=handler_request_ready[0];
   2'd1:if(C_PORTS>1)o_request_ready=handler_request_ready[1];
   2'd2:if(C_PORTS>2)o_request_ready=handler_request_ready[2];
   2'd3:if(C_PORTS>3)o_request_ready=handler_request_ready[3];
  endcase
 end
 // valid拉高前ready保持开放；valid期间只服从token指定Port的独立owner。
 o_result_ready=active;
 if(active&&i_result_valid&&result_port_range)o_result_ready=handler_result_ready[result_port];
end

// Response独立RR，首次展示后锁Port直到该handler整包退休，保留回源port。
always @* begin
 response_select=response_owner_q;response_found=response_locked_q;response_candidate=0;response_scan=0;
 if(!response_locked_q)begin
  response_select=2'd0;
  for(response_scan=0;response_scan<C_PORTS;response_scan=response_scan+1)begin
   response_candidate={30'd0,response_rr_q}+response_scan;if(response_candidate>=C_PORTS)response_candidate=response_candidate-C_PORTS;
   if(!response_found&&handler_source_valid[response_candidate])begin response_select=response_candidate[1:0];response_found=1'b1;end
  end
 end
end
assign o_source_valid=active&&response_found&&handler_source_valid[response_select];
assign o_source_control=o_source_valid?handler_source_control[response_select*256+:256]:256'b0;
assign o_source_port=o_source_valid?handler_source_port[response_select*2+:2]:2'b0;
assign o_data_valid=(active&&response_found)?handler_data_valid[response_select*2+:2]:2'b0;
assign o_data=(active&&response_found)?handler_data[response_select*512+:512]:512'b0;
assign o_data_poison=(active&&response_found)?handler_data_poison[response_select*2+:2]:2'b0;
assign o_busy=i_rstn&&((|handler_busy)||response_locked_q);
assign o_error=i_rstn&&(!C_CONFIG_LEGAL||error_q||(|handler_error));
always @* begin
 child_reason=8'd0;child_reason_found=1'b0;
 for(reason_scan=0;reason_scan<C_PORTS;reason_scan=reason_scan+1)
  if(!child_reason_found&&handler_error[reason_scan])begin child_reason=handler_reason[reason_scan*8+:8];child_reason_found=1'b1;end
end
assign o_reason=error_q?reason_q:child_reason;

always @(posedge i_clk)begin
 if(!i_rstn)begin error_q<=1'b0;reason_q<=8'd0;backend_rr_q<=2'd0;response_rr_q<=2'd0;response_owner_q<=2'd0;response_locked_q<=1'b0;end
 else begin
  if(i_request_valid&&!request_port_active)begin error_q<=1'b1;reason_q<=8'd1;end
  if(i_result_valid&&!result_port_range)begin error_q<=1'b1;reason_q<=8'd2;end
  if(!active_mask_legal)begin error_q<=1'b1;reason_q<=8'd4;end
  if(|handler_error)begin error_q<=1'b1;reason_q<=child_reason;end
  if(o_backend_valid&&i_backend_ready)backend_rr_q<=(backend_select==C_LAST_PORT)?2'd0:backend_select+1'b1;
  if(!response_locked_q&&response_found)begin response_locked_q<=1'b1;response_owner_q<=response_select;end
  else if(response_locked_q&&!handler_busy[response_owner_q])begin
   response_locked_q<=1'b0;response_rr_q<=(response_owner_q==C_LAST_PORT)?2'd0:response_owner_q+1'b1;
  end
 end
end
endmodule
`default_nettype wire

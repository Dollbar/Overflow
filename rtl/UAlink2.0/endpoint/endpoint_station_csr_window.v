`timescale 1ns/1ps
`default_nettype none

// Endpoint多Station管理窗口。该模块只拥有requested mode寄存器和单拍控制命令，
// active状态由Station array返回；一个响应未退休时不会接受第二个请求。
module endpoint_station_csr_window #(
 parameter integer C_NUM_STATIONS=2,
 parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS,
 parameter integer C_STATION_INDEX_WIDTH=(C_NUM_STATIONS<=2)?1:(C_NUM_STATIONS<=4)?2:
  (C_NUM_STATIONS<=8)?3:(C_NUM_STATIONS<=16)?4:(C_NUM_STATIONS<=32)?5:
  (C_NUM_STATIONS<=64)?6:(C_NUM_STATIONS<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,
 input wire i_req_valid,output wire o_req_ready,input wire i_req_write,
 input wire [15:0] i_req_addr,input wire [31:0] i_req_wdata,
 output reg o_rsp_valid,input wire i_rsp_ready,output reg [31:0] o_rsp_rdata,
 output reg o_rsp_error,output reg o_rsp_unsupported,
 output reg [C_FLAT_STATIONS*2-1:0] o_requested_mode,
 output reg [C_FLAT_STATIONS-1:0] o_mode_commit,
 output reg [C_FLAT_STATIONS*4-1:0] o_port_link_reset,
 input wire [C_FLAT_STATIONS*2-1:0] i_active_mode,
 input wire [C_FLAT_STATIONS*4-1:0] i_active_mask,
 input wire [C_FLAT_STATIONS-1:0] i_station_busy,
 input wire [C_FLAT_STATIONS-1:0] i_station_quiescent,
 input wire [C_FLAT_STATIONS-1:0] i_station_error,
 input wire i_global_busy,input wire i_global_quiescent,input wire i_global_error,
 input wire [C_FLAT_STATIONS*4-1:0] i_request_reject_pulse,
 output reg [C_FLAT_STATIONS*4-1:0] o_request_reject_sticky,
 output reg o_error_sticky,output reg o_unsupported_security,
 output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&
  (C_FLAT_STATIONS==C_NUM_STATIONS)&&(C_STATION_INDEX_WIDTH>=1)&&(C_STATION_INDEX_WIDTH<=8)&&
  ((32'd1<<C_STATION_INDEX_WIDTH)>=C_NUM_STATIONS);
 localparam [31:0] C_NUM_STATIONS_32=C_NUM_STATIONS;
 reg [C_STATION_INDEX_WIDTH-1:0] station_index_q;
 reg [31:0] immediate_rdata;
 reg request_legal,request_unsupported;
 reg [1:0] selected_requested_mode,selected_active_mode;
 reg [3:0] selected_active_mask;
 reg selected_busy,selected_quiescent,selected_error;
 reg [7:0] request_reject_count[0:C_FLAT_STATIONS*4-1];
 wire [C_FLAT_STATIONS*32-1:0] request_reject_count_flat;
 integer station_scan;
 integer reject_station_scan,reject_port_scan;
 genvar count_flat_index;
 generate for(count_flat_index=0;count_flat_index<C_FLAT_STATIONS*4;count_flat_index=count_flat_index+1)begin:gen_reject_count_flat
  assign request_reject_count_flat[count_flat_index*8+:8]=request_reject_count[count_flat_index];
 end endgenerate

 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error||o_error_sticky;
 assign o_req_ready=i_rstn&&CONFIG_LEGAL&&!o_rsp_valid;

 // 采用有界扫描形成indexed状态Mux，非法索引不会触发数组动态访问。
 always @(*) begin
  selected_requested_mode=2'd0;selected_active_mode=2'd0;selected_active_mask=4'd0;
  selected_busy=1'b0;selected_quiescent=1'b0;selected_error=1'b0;
  for(station_scan=0;station_scan<C_FLAT_STATIONS;station_scan=station_scan+1)begin
   if(CONFIG_LEGAL&&(station_index_q==station_scan[C_STATION_INDEX_WIDTH-1:0]))begin
    selected_requested_mode=o_requested_mode[station_scan*2+:2];
    selected_active_mode=i_active_mode[station_scan*2+:2];
    selected_active_mask=i_active_mask[station_scan*4+:4];
    selected_busy=i_station_busy[station_scan];
    selected_quiescent=i_station_quiescent[station_scan];
    selected_error=i_station_error[station_scan];
   end
  end
 end

 // 地址解码同时检查访问权限、索引和字段编码；任何错误均返回零且不产生控制副作用。
 always @(*) begin
  immediate_rdata=32'd0;request_legal=CONFIG_LEGAL;request_unsupported=1'b0;
  case(i_req_addr)
   16'h0000:begin immediate_rdata=C_NUM_STATIONS_32;if(i_req_write)request_legal=1'b0;end
   16'h0004:begin immediate_rdata={29'd0,i_global_error,i_global_quiescent,i_global_busy};if(i_req_write)request_legal=1'b0;end
   16'h1000:begin
    immediate_rdata={{(32-C_STATION_INDEX_WIDTH){1'b0}},station_index_q};
    if(i_req_write)begin
     if((i_req_wdata>=C_NUM_STATIONS_32)||(|i_req_wdata[31:C_STATION_INDEX_WIDTH]))request_legal=1'b0;
    end
   end
   16'h1004:begin
    immediate_rdata=i_req_write?{30'd0,i_req_wdata[1:0]}:{30'd0,selected_requested_mode};
    if(i_req_write&&((|i_req_wdata[31:2])||(i_req_wdata[1:0]==2'b11)))request_legal=1'b0;
   end
   16'h1008:begin
    immediate_rdata=32'd0;
    if(i_req_write&&(|i_req_wdata[31:1]))request_legal=1'b0;
   end
   16'h100c:begin
    immediate_rdata=32'd0;
    if(i_req_write&&(|i_req_wdata[31:4]))request_legal=1'b0;
   end
   16'h1010:begin immediate_rdata={30'd0,selected_active_mode};if(i_req_write)request_legal=1'b0;end
   16'h1014:begin immediate_rdata={28'd0,selected_active_mask};if(i_req_write)request_legal=1'b0;end
   16'h1018:begin immediate_rdata={29'd0,selected_error,selected_quiescent,selected_busy};if(i_req_write)request_legal=1'b0;end
   16'h101c:begin
    immediate_rdata={28'd0,o_request_reject_sticky[station_index_q*4+:4]};
    if(i_req_write&&(|i_req_wdata[31:4]))request_legal=1'b0;
   end
   16'h1020:begin immediate_rdata=request_reject_count_flat[station_index_q*32+:32];if(i_req_write)request_legal=1'b0;end
   default:begin request_legal=1'b0;if(i_req_addr[15:12]==4'h8)request_unsupported=1'b1;end
  endcase
 end

 // 响应停顿期间字段保持；写命令仅在请求真实握手沿产生一次。
 always @(posedge i_clk) begin
  if(!i_rstn)begin
   o_rsp_valid<=1'b0;o_rsp_rdata<=32'd0;o_rsp_error<=1'b0;o_rsp_unsupported<=1'b0;
   station_index_q<={C_STATION_INDEX_WIDTH{1'b0}};o_requested_mode<={(C_FLAT_STATIONS*2){1'b0}};
   o_mode_commit<={C_FLAT_STATIONS{1'b0}};o_port_link_reset<={(C_FLAT_STATIONS*4){1'b0}};
   o_error_sticky<=1'b0;o_unsupported_security<=1'b0;
   o_request_reject_sticky<={(C_FLAT_STATIONS*4){1'b0}};
   for(reject_station_scan=0;reject_station_scan<C_FLAT_STATIONS;reject_station_scan=reject_station_scan+1)
    for(reject_port_scan=0;reject_port_scan<4;reject_port_scan=reject_port_scan+1)
     request_reject_count[reject_station_scan*4+reject_port_scan]<=8'd0;
  end else begin
   o_mode_commit<={C_FLAT_STATIONS{1'b0}};
   o_port_link_reset<={(C_FLAT_STATIONS*4){1'b0}};
   if(o_rsp_valid&&i_rsp_ready)o_rsp_valid<=1'b0;
   if(i_req_valid&&o_req_ready)begin
    o_rsp_valid<=1'b1;o_rsp_rdata<=request_legal?immediate_rdata:32'd0;
    o_rsp_error<=!request_legal;o_rsp_unsupported<=request_unsupported;
    if(!request_legal)o_error_sticky<=1'b1;
    if(request_unsupported)o_unsupported_security<=1'b1;
    if(i_req_write&&request_legal)begin
     case(i_req_addr)
      16'h1000:station_index_q<=i_req_wdata[C_STATION_INDEX_WIDTH-1:0];
      16'h1004:o_requested_mode[station_index_q*2+:2]<=i_req_wdata[1:0];
      16'h1008:if(i_req_wdata[0])o_mode_commit[station_index_q]<=1'b1;
      16'h100c:o_port_link_reset[station_index_q*4+:4]<=i_req_wdata[3:0];
      default:begin end
     endcase
    end
   end
   // 每个安全丢弃事务只由上游给出一个pulse。计数饱和；sticky W1C与新事件同沿时事件优先。
   for(reject_station_scan=0;reject_station_scan<C_FLAT_STATIONS;reject_station_scan=reject_station_scan+1)begin
    for(reject_port_scan=0;reject_port_scan<4;reject_port_scan=reject_port_scan+1)begin
     if(i_request_reject_pulse[reject_station_scan*4+reject_port_scan])begin
      o_request_reject_sticky[reject_station_scan*4+reject_port_scan]<=1'b1;
      if(request_reject_count[reject_station_scan*4+reject_port_scan]!=8'hff)
       request_reject_count[reject_station_scan*4+reject_port_scan]<=request_reject_count[reject_station_scan*4+reject_port_scan]+1'b1;
     end else if(i_req_valid&&o_req_ready&&i_req_write&&request_legal&&(i_req_addr==16'h101c)&&
      (station_index_q==reject_station_scan[C_STATION_INDEX_WIDTH-1:0])&&i_req_wdata[reject_port_scan])
      o_request_reject_sticky[reject_station_scan*4+reject_port_scan]<=1'b0;
    end
   end
  end
 end
endmodule
`default_nettype wire

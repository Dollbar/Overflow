`timescale 1ps/1ps // 分域容量及真实完整包所有权组合。
module switch_egress_vc_queues #( // switch_egress_vc_queues模块：出口、请求响应及VC独立资源缓存。
 parameter integer PORTS=4,VCS=4,DATA_WIDTH=544,TOKEN_WIDTH=8,UNIT_WIDTH=4, // 分域容量及真实完整包所有权组合。
 parameter [UNIT_WIDTH-1:0] DEFAULT_CAPACITY=4, // 分域容量及真实完整包所有权组合。
 parameter [2*VCS*PORTS*UNIT_WIDTH-1:0] CAPACITIES={2*VCS*PORTS{DEFAULT_CAPACITY}} // 分域容量及真实完整包所有权组合。
)( // 分域容量及真实完整包所有权组合。
 input wire i_clk,i_rstn, // 分域容量及真实完整包所有权组合。
 input wire [PORTS-1:0] i_header_valid, // 分域容量及真实完整包所有权组合。
 input wire [PORTS*PORTS-1:0] i_route_match, // 分域容量及真实完整包所有权组合。
 input wire [PORTS*UNIT_WIDTH-1:0] i_header_units, // 分域容量及真实完整包所有权组合。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_header_token, // 分域容量及真实完整包所有权组合。
 input wire [PORTS*2-1:0] i_header_vc, // 分域容量及真实完整包所有权组合。
 input wire [PORTS-1:0] i_header_response, // 分域容量及真实完整包所有权组合。
 output wire [PORTS-1:0] o_header_ready, // 分域容量及真实完整包所有权组合。
 input wire [PORTS-1:0] i_body_valid, // 分域容量及真实完整包所有权组合。
 input wire [PORTS*DATA_WIDTH-1:0] i_body_data, // 分域容量及真实完整包所有权组合。
 input wire [PORTS-1:0] i_body_last, // 分域容量及真实完整包所有权组合。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_body_token, // 分域容量及真实完整包所有权组合。
 output wire [PORTS-1:0] o_body_ready, // 分域容量及真实完整包所有权组合。
 input wire [2*VCS*PORTS-1:0] i_ready, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS-1:0] o_valid,o_last, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS*DATA_WIDTH-1:0] o_data, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS*TOKEN_WIDTH-1:0] o_token, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS-1:0] o_release_valid, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS*UNIT_WIDTH-1:0] o_release_units, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS*UNIT_WIDTH-1:0] o_available,o_reserved,o_queue_reserved,o_stored,o_completed, // 分域容量及真实完整包所有权组合。
 output wire [PORTS-1:0] o_source_busy,o_source_error_sticky, // 分域容量及真实完整包所有权组合。
 output wire [PORTS-1:0] o_header_error,o_body_error, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS*PORTS-1:0] o_queue_error_now,o_queue_error_sticky, // 分域容量及真实完整包所有权组合。
 output wire [2*VCS-1:0] o_reservation_error, // 分域容量及真实完整包所有权组合。
 output wire o_error // 分域容量及真实完整包所有权组合。
); // 分域容量及真实完整包所有权组合。
 localparam [31:0] C_PORTS=PORTS,C_DOMAINS=2*VCS; // 分域容量及真实完整包所有权组合。
 localparam integer INDEX_WIDTH=(PORTS<2)?1:(PORTS<3)?1:2; // 分域容量及真实完整包所有权组合。
 localparam [2:0] C_VCS=VCS[2:0]; // 分域容量及真实完整包所有权组合。
 reg [PORTS-1:0] reg_owned,reg_source_error; // 分域容量及真实完整包所有权组合。
 reg [INDEX_WIDTH-1:0] reg_egress[0:PORTS-1]; // 分域容量及真实完整包所有权组合。
 reg [2:0] reg_domain[0:PORTS-1]; // 分域容量及真实完整包所有权组合。
 wire [2*VCS*PORTS-1:0] domain_header_ready,domain_header_error,domain_body_ready,domain_body_error; // 分域容量及真实完整包所有权组合。
 wire [PORTS-1:0] qualified; // 分域容量及真实完整包所有权组合。
 assign o_source_busy=i_rstn?reg_owned:{PORTS{1'b0}}; // 分域容量及真实完整包所有权组合。
 assign o_source_error_sticky=i_rstn?reg_source_error:{PORTS{1'b0}}; // 分域容量及真实完整包所有权组合。
 assign o_error=(|o_header_error)||(|o_body_error)||(|o_source_error_sticky)||(|o_queue_error_now)||(|o_queue_error_sticky)||(|o_reservation_error); // 分域容量及真实完整包所有权组合。
 genvar gs,gd,ge; // 分域容量及真实完整包所有权组合。
 generate // 分域容量及真实完整包所有权组合。
 if(((PORTS!=1)&&(PORTS!=2)&&(PORTS!=4))||((VCS!=1)&&(VCS!=2)&&(VCS!=4)))begin:gen_invalid // 分域容量及真实完整包所有权组合。
  switch_vc_queue_parameters_invalid Invalid_Inst(); // 分域容量及真实完整包所有权组合。
 end // 分域容量及真实完整包所有权组合。
 for(gs=0;gs<C_PORTS;gs=gs+1)begin:gen_source // 分域容量及真实完整包所有权组合。
  assign qualified[gs]=i_rstn&&i_header_valid[gs]&&!reg_owned[gs]&&!reg_source_error[gs]&&!i_body_valid[gs]; // 分域容量及真实完整包所有权组合。
  reg [INDEX_WIDTH-1:0] selected_egress; // 合法唯一route的组合出口编码。
  integer domain_index,egress_index; // 分域容量及真实完整包所有权组合。
  reg selected_header_ready,selected_body_ready,selected_header_error,selected_body_error; // 每源局部组合临时量避免不同always块读改同一packed输出。
  always @* begin // 分域容量及真实完整包所有权组合。
   selected_egress={INDEX_WIDTH{1'b0}}; // 未匹配时默认零，真实接纳仍必须route唯一。
   for(egress_index=0;egress_index<C_PORTS;egress_index=egress_index+1)begin // 组合遍历静态端口集合。
    if(i_route_match[gs*PORTS+egress_index])selected_egress=egress_index[INDEX_WIDTH-1:0]; // 仅编码外部候选，不建立owner。
   end // 结束出口编码。
   selected_header_ready=1'b0;selected_body_ready=1'b0; // 分域容量及真实完整包所有权组合。
   selected_header_error=qualified[gs]&&({1'b0,i_header_vc[gs*2+:2]}>=C_VCS); // 分域容量及真实完整包所有权组合。
   selected_body_error=i_rstn&&!reg_source_error[gs]&&i_body_valid[gs]&&!reg_owned[gs]; // 分域容量及真实完整包所有权组合。
   for(domain_index=0;domain_index<C_DOMAINS;domain_index=domain_index+1)begin // 分域容量及真实完整包所有权组合。
    selected_header_ready=selected_header_ready||domain_header_ready[domain_index*PORTS+gs]; // 分域容量及真实完整包所有权组合。
    selected_header_error=selected_header_error||domain_header_error[domain_index*PORTS+gs]; // 分域容量及真实完整包所有权组合。
    selected_body_ready=selected_body_ready||domain_body_ready[domain_index*PORTS+gs]; // 分域容量及真实完整包所有权组合。
    selected_body_error=selected_body_error||domain_body_error[domain_index*PORTS+gs]; // 分域容量及真实完整包所有权组合。
   end // 分域容量及真实完整包所有权组合。
  end // 分域容量及真实完整包所有权组合。
  assign o_header_ready[gs]=selected_header_ready; // 单一连续驱动本源公开输出。
  assign o_body_ready[gs]=selected_body_ready; // 单一连续驱动本源公开输出。
  assign o_header_error[gs]=selected_header_error; // 单一连续驱动本源公开输出。
  assign o_body_error[gs]=selected_body_error; // 单一连续驱动本源公开输出。
  always @(posedge i_clk)begin // 分域容量及真实完整包所有权组合。
   if(!i_rstn)begin reg_owned[gs]<=1'b0;reg_source_error[gs]<=1'b0;reg_egress[gs]<={INDEX_WIDTH{1'b0}};reg_domain[gs]<=3'd0;end // 同步复位或最后body真实写接纳才清除源所有权。
   else begin // 分域容量及真实完整包所有权组合。
    if(o_body_error[gs])reg_source_error[gs]<=1'b1; // 分域容量及真实完整包所有权组合。
    if(o_header_ready[gs])begin // 分域容量及真实完整包所有权组合。
     reg_owned[gs]<=1'b1; // 分域容量及真实完整包所有权组合。
     reg_domain[gs]<={1'b0,i_header_vc[gs*2+:2]}+(i_header_response[gs]?C_VCS:3'd0); // 首部真实接纳时保存域，后续body不重读当前候选。
     reg_egress[gs]<=selected_egress; // 原子预约后才捕获出口。
    end else if(i_body_valid[gs]&&o_body_ready[gs]&&i_body_last[gs])reg_owned[gs]<=1'b0; // 同步复位或最后body真实写接纳才清除源所有权。
   end // 分域容量及真实完整包所有权组合。
  end // 分域容量及真实完整包所有权组合。
 end // 分域容量及真实完整包所有权组合。
 for(gd=0;gd<C_DOMAINS;gd=gd+1)begin:gen_domain // 分域容量及真实完整包所有权组合。
  localparam [2:0] DOMAIN=gd; // 分域容量及真实完整包所有权组合。
  localparam integer VC_VALUE=gd%VCS; // 先保存常量计算值再明确限制位宽。
  localparam [1:0] VC=VC_VALUE[1:0]; // 分域容量及真实完整包所有权组合。
  localparam RESPONSE=(gd>=VCS); // 分域容量及真实完整包所有权组合。
  wire [PORTS-1:0] header_valid,admit_ready,reserve_valid,write_valid,write_ready,write_last; // 分域容量及真实完整包所有权组合。
  wire [PORTS*PORTS-1:0] grant; // 分域容量及真实完整包所有权组合。
  wire [PORTS*UNIT_WIDTH-1:0] grant_units; // 分域容量及真实完整包所有权组合。
  wire [PORTS*TOKEN_WIDTH-1:0] reserve_token,write_token; // 分域容量及真实完整包所有权组合。
  wire [PORTS*DATA_WIDTH-1:0] write_data; // 分域容量及真实完整包所有权组合。
  wire [PORTS-1:0] unused_release_accepted,unused_release_error,unused_busy; // 分域容量及真实完整包所有权组合。
  wire unused_queue_error; // 分域容量及真实完整包所有权组合。
  for(gs=0;gs<C_PORTS;gs=gs+1)begin:gen_header // 分域容量及真实完整包所有权组合。
   assign header_valid[gs]=qualified[gs]&&(i_header_vc[gs*2+:2]==VC)&&(i_header_response[gs]==RESPONSE); // 分域容量及真实完整包所有权组合。
   reg matched_ready,matched_error; // 分域容量及真实完整包所有权组合。
   integer index; // 分域容量及真实完整包所有权组合。
   always @* begin // 分域容量及真实完整包所有权组合。
    matched_ready=1'b0;matched_error=1'b0; // 分域容量及真实完整包所有权组合。
    for(index=0;index<C_PORTS;index=index+1)begin // 分域容量及真实完整包所有权组合。
     if(i_rstn&&reg_owned[gs]&&!reg_source_error[gs]&&(reg_domain[gs]==DOMAIN)&&(reg_egress[gs]==index[INDEX_WIDTH-1:0]))begin // 分域容量及真实完整包所有权组合。
      matched_ready=write_ready[index]; // 分域容量及真实完整包所有权组合。
      matched_error=i_body_valid[gs]&&o_queue_error_now[gd*PORTS+index]; // 分域容量及真实完整包所有权组合。
     end // 分域容量及真实完整包所有权组合。
    end // 分域容量及真实完整包所有权组合。
   end // 分域容量及真实完整包所有权组合。
   assign domain_body_ready[gd*PORTS+gs]=matched_ready; // 分域容量及真实完整包所有权组合。
   assign domain_body_error[gd*PORTS+gs]=matched_error; // 分域容量及真实完整包所有权组合。
  end // 分域容量及真实完整包所有权组合。
  for(ge=0;ge<C_PORTS;ge=ge+1)begin:gen_mux // 分域容量及真实完整包所有权组合。
   localparam [INDEX_WIDTH-1:0] EGRESS=ge; // 分域容量及真实完整包所有权组合。
   reg [TOKEN_WIDTH-1:0] selected_reserve_token,selected_write_token; // 分域容量及真实完整包所有权组合。
   reg [DATA_WIDTH-1:0] selected_data; // 分域容量及真实完整包所有权组合。
   reg selected_valid,selected_last; // 分域容量及真实完整包所有权组合。
   integer source_index; // 分域容量及真实完整包所有权组合。
   assign reserve_valid[ge]=|grant[ge*PORTS+:PORTS]; // 分域容量及真实完整包所有权组合。
   always @* begin // 分域容量及真实完整包所有权组合。
    selected_reserve_token={TOKEN_WIDTH{1'b0}};selected_write_token={TOKEN_WIDTH{1'b0}};selected_data={DATA_WIDTH{1'b0}};selected_valid=1'b0;selected_last=1'b0; // 分域容量及真实完整包所有权组合。
    for(source_index=0;source_index<C_PORTS;source_index=source_index+1)begin // 分域容量及真实完整包所有权组合。
     if(grant[ge*PORTS+source_index])selected_reserve_token=i_header_token[source_index*TOKEN_WIDTH+:TOKEN_WIDTH]; // 分域容量及真实完整包所有权组合。
     if(reg_owned[source_index]&&!reg_source_error[source_index]&&(reg_domain[source_index]==DOMAIN)&&(reg_egress[source_index]==EGRESS))begin // 分域容量及真实完整包所有权组合。
      selected_write_token=i_body_token[source_index*TOKEN_WIDTH+:TOKEN_WIDTH];selected_data=i_body_data[source_index*DATA_WIDTH+:DATA_WIDTH];selected_valid=i_body_valid[source_index];selected_last=i_body_last[source_index]; // 分域容量及真实完整包所有权组合。
     end // 分域容量及真实完整包所有权组合。
    end // 分域容量及真实完整包所有权组合。
   end // 分域容量及真实完整包所有权组合。
   assign reserve_token[ge*TOKEN_WIDTH+:TOKEN_WIDTH]=selected_reserve_token; // 分域容量及真实完整包所有权组合。
   assign write_token[ge*TOKEN_WIDTH+:TOKEN_WIDTH]=selected_write_token; // 分域容量及真实完整包所有权组合。
   assign write_data[ge*DATA_WIDTH+:DATA_WIDTH]=selected_data; // 分域容量及真实完整包所有权组合。
   assign write_valid[ge]=selected_valid; // 分域容量及真实完整包所有权组合。
   assign write_last[ge]=selected_last; // 分域容量及真实完整包所有权组合。
  end // 分域容量及真实完整包所有权组合。
  switch_credit_reservation #(.PORTS(PORTS),.UNIT_WIDTH(UNIT_WIDTH),.CAPACITIES(CAPACITIES[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH])) Reservation_Inst( // 每域独立预约实例，绝不借其它类别和VC容量。
   .i_clk(i_clk),.i_rstn(i_rstn),.i_request_valid(header_valid),.i_route_match(i_route_match),.i_request_units(i_header_units),.i_admit_ready(admit_ready), // 分域容量及真实完整包所有权组合。
   .i_release_valid(o_release_valid[gd*PORTS+:PORTS]),.i_release_units(o_release_units[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]), // 分域容量及真实完整包所有权组合。
   .o_request_ready(domain_header_ready[gd*PORTS+:PORTS]),.o_grant(grant),.o_grant_units(grant_units),.o_release_accepted(unused_release_accepted), // 分域容量及真实完整包所有权组合。
   .o_available(o_available[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]),.o_reserved(o_reserved[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]), // 分域容量及真实完整包所有权组合。
   .o_request_error(domain_header_error[gd*PORTS+:PORTS]),.o_release_error(unused_release_error),.o_error(o_reservation_error[gd]) // 分域容量及真实完整包所有权组合。
  ); // 分域容量及真实完整包所有权组合。
  switch_egress_packet_queue #(.PORTS(PORTS),.DATA_WIDTH(DATA_WIDTH),.TOKEN_WIDTH(TOKEN_WIDTH),.UNIT_WIDTH(UNIT_WIDTH),.CAPACITIES(CAPACITIES[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH])) Queue_Inst( // 每域实际packet队列实例，出队最后word返回本域信用。
   .i_clk(i_clk),.i_rstn(i_rstn),.i_reserve_valid(reserve_valid),.i_reserve_units(grant_units),.i_reserve_token(reserve_token),.o_reserve_ready(admit_ready), // 分域容量及真实完整包所有权组合。
   .i_write_valid(write_valid),.i_write_data(write_data),.i_write_last(write_last),.i_write_token(write_token),.o_write_ready(write_ready), // 分域容量及真实完整包所有权组合。
   .i_ready(i_ready[gd*PORTS+:PORTS]),.o_valid(o_valid[gd*PORTS+:PORTS]),.o_data(o_data[gd*PORTS*DATA_WIDTH+:PORTS*DATA_WIDTH]),.o_last(o_last[gd*PORTS+:PORTS]),.o_token(o_token[gd*PORTS*TOKEN_WIDTH+:PORTS*TOKEN_WIDTH]), // 分域容量及真实完整包所有权组合。
   .o_release_valid(o_release_valid[gd*PORTS+:PORTS]),.o_release_units(o_release_units[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]), // 分域容量及真实完整包所有权组合。
   .o_reserved(o_queue_reserved[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]),.o_stored(o_stored[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]),.o_completed(o_completed[gd*PORTS*UNIT_WIDTH+:PORTS*UNIT_WIDTH]), // 分域容量及真实完整包所有权组合。
   .o_busy(unused_busy),.o_error_now(o_queue_error_now[gd*PORTS+:PORTS]),.o_error_sticky(o_queue_error_sticky[gd*PORTS+:PORTS]),.o_error(unused_queue_error) // 分域容量及真实完整包所有权组合。
  ); // 分域容量及真实完整包所有权组合。
 end // 分域容量及真实完整包所有权组合。
 endgenerate // 结束逐域与逐源组合结构。
endmodule // 结束独立资源分区缓存模块。
